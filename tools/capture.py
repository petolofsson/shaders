#!/usr/bin/env python3
"""
tools/capture.py — Pipeline session capture.

Takes a screenshot, decodes the data highway (BackBuffer y=0), and writes a
structured EXR. All analysis tools read from this shared format instead of
re-implementing PNG parsing and highway decoding independently.

EXR channels (all float16):
    R, G, B              linearized sRGB frame (omitted with --no-frame)
    hwy.*                decoded highway scalars (constant across image)
    luma.hist.NNN        128-bin luma histogram (x=0..127, analysis_scope_pre)
    hue.hist.NN          64-bin hue histogram (x=130..193, analysis_scope_pre)

EXR header attributes:
    game, timestamp, git_commit, note

Usage:
    python3 tools/capture.py [--game NAME] [--note TEXT] [--no-frame] [--dump] [OUT.exr]

    --no-frame   write 1×1 EXR (scalars + histograms only, no full-res image)
    --dump       print decoded highway to stdout, skip EXR write

Requires:
    pip install openexr numpy
    grim (Wayland) or scrot (X11)
"""

import argparse
import math
import struct
import subprocess
import sys
import zlib
from datetime import datetime
from pathlib import Path

try:
    import numpy as np
except ImportError:
    sys.exit("Missing: pip install numpy")

try:
    import OpenEXR
    import Imath
except ImportError:
    sys.exit("Missing: pip install openexr")


# ── Highway slot table ────────────────────────────────────────────────────────
# (x_pixel, channel_name, decode_fn)
# decode_fn: raw sRGB-linearized [0,1] float → physical value
# Encoding convention documented in general/highway.fxh.

SCALAR_SLOTS = [
    (128, "hwy.luma_mean_pre",   lambda v: v),
    (129, "hwy.luma_mean_post",  lambda v: v),
    (194, "hwy.p25",             lambda v: v),
    (195, "hwy.p50",             lambda v: v),
    (196, "hwy.p75",             lambda v: v),
    (197, "hwy.slope",           lambda v: v * 1.5 + 1.0),           # encode (v-1)/1.5, range [1.15, 1.80]
    (198, "hwy.chroma_med",      lambda v: v),                        # Oklab C, raw [0, 0.4]
    (199, "hwy.scene_cut",       lambda v: v),
    (200, "hwy.p90",             lambda v: v),
    (201, "hwy.chroma_angle",    lambda v: v * 2.0 * math.pi - math.pi),  # encode (atan2+π)/2π
    (202, "hwy.achrom_frac",     lambda v: v),
    (203, "hwy.zone_key",         lambda v: v),
    (204, "hwy.zone_std",         lambda v: v),
    (205, "hwy.slow_key",         lambda v: v),
    (210, "hwy.warm_bias",        lambda v: v),
    (213, "hwy.fc_stevens",       lambda v: v * 1.3),                  # encode v/1.3, range [0.72, 1.22]
    (214, "hwy.fc_knee",          lambda v: v),
    (215, "hwy.zone_str",         lambda v: v * 0.30),                 # encode v/0.30
    (217, "hwy.shadow_lift_str",  lambda v: v * 1.5),                  # encode v/1.5, range [0, 1.5]
    (218, "hwy.chroma_str",       lambda v: v * 0.10),                 # encode v/0.10, range [0, 0.10]
    (219, "hwy.mist_str",         lambda v: v * 0.10),                 # encode v/0.10, range [0, 0.10]
]

LUMA_HIST_START = 0
LUMA_HIST_BINS  = 128   # x=0..127, written by analysis_scope_pre

HUE_HIST_OFFSET = 130
HUE_HIST_BINS   = 64    # x=130..193, written by analysis_scope_pre


# ── Screenshot ────────────────────────────────────────────────────────────────

def take_screenshot(path: Path) -> None:
    for cmd in [
        ["grim",      str(path)],
        ["grimblast", "save", "screen", str(path)],
        ["wayshot",   "-f", str(path)],
        ["spectacle", "--background", "--fullscreen", "--output", str(path)],
        ["scrot",     str(path)],
        ["import",    "-window", "root", str(path)],
    ]:
        try:
            if subprocess.run(cmd, capture_output=True).returncode == 0:
                return
        except FileNotFoundError:
            continue
    sys.exit("No screenshot tool found. Install grim (Wayland) or scrot (X11).")


# ── PNG loading ───────────────────────────────────────────────────────────────

def _srgb_to_linear(arr: np.ndarray) -> np.ndarray:
    return np.where(
        arr <= 0.04045,
        arr / 12.92,
        ((arr + 0.055) / 1.055) ** 2.4,
    )


def _apply_filter(ftype: int, row: np.ndarray, prev: np.ndarray, bpp: int) -> np.ndarray:
    if ftype == 0:
        return row.copy()
    if ftype == 1:
        out = row.copy()
        for i in range(bpp, len(out)):
            out[i] = (int(out[i]) + int(out[i - bpp])) & 0xFF
        return out
    if ftype == 2:
        return ((row.astype(np.int16) + prev.astype(np.int16)) & 0xFF).astype(np.uint8)
    if ftype == 3:
        out = row.copy()
        for i in range(len(out)):
            left = int(out[i - bpp]) if i >= bpp else 0
            out[i] = (int(out[i]) + (left + int(prev[i])) // 2) & 0xFF
        return out
    if ftype == 4:
        out = row.copy()
        for i in range(len(out)):
            a = int(out[i - bpp]) if i >= bpp else 0
            b = int(prev[i])
            c = int(prev[i - bpp]) if i >= bpp else 0
            p = a + b - c
            pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
            pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
            out[i] = (int(out[i]) + pr) & 0xFF
        return out
    return row.copy()


def load_png(data: bytes):
    """
    Parse PNG, return (width, height, linear_rgb) where linear_rgb is
    float32 ndarray (H, W, 3) in linear light.
    """
    pos, idat = 8, b""
    width = height = 0
    bpp = 3

    while pos < len(data):
        length     = struct.unpack(">I", data[pos:pos+4])[0]
        chunk_type = data[pos+4:pos+8]
        chunk_data = data[pos+8:pos+8+length]
        if chunk_type == b"IHDR":
            width, height = struct.unpack(">II", chunk_data[:8])
            bpp = 4 if chunk_data[9] in (4, 6) else 3
        elif chunk_type == b"IDAT":
            idat += chunk_data
        pos += 12 + length

    raw    = zlib.decompress(idat)
    stride = 1 + width * bpp
    rows   = np.zeros((height, width * bpp), dtype=np.uint8)
    prev   = np.zeros(width * bpp, dtype=np.uint8)

    for y in range(height):
        ftype = raw[y * stride]
        raw_row = np.frombuffer(raw[y * stride + 1:(y + 1) * stride], dtype=np.uint8).copy()
        decoded = _apply_filter(ftype, raw_row, prev, bpp)
        rows[y] = decoded
        prev    = decoded

    pixels   = rows.reshape(height, width, bpp)[:, :, :3].astype(np.float32) / 255.0
    return width, height, _srgb_to_linear(pixels)


# ── Highway decode ────────────────────────────────────────────────────────────

def decode_scalars(linear_rgb: np.ndarray) -> dict:
    """Decode named scalar slots from row y=0, R channel."""
    row = linear_rgb[0, :, 0]
    out = {}
    for x, name, fn in SCALAR_SLOTS:
        if x < row.shape[0]:
            out[name] = fn(float(row[x]))
    return out


def decode_luma_hist(linear_rgb: np.ndarray) -> list:
    """128 normalized luma histogram bins from x=0..127, row y=0."""
    row = linear_rgb[0, :, 0]
    n   = min(LUMA_HIST_BINS, row.shape[0] - LUMA_HIST_START)
    return [float(row[LUMA_HIST_START + i]) for i in range(n)]


def decode_hue_hist(linear_rgb: np.ndarray) -> list:
    """64 normalized hue histogram bins from x=130..193, row y=0."""
    row = linear_rgb[0, :, 0]
    n   = min(HUE_HIST_BINS, row.shape[0] - HUE_HIST_OFFSET)
    return [float(row[HUE_HIST_OFFSET + i]) for i in range(n)]


# ── EXR write ─────────────────────────────────────────────────────────────────

def write_exr(
    path: Path,
    linear_rgb: np.ndarray,
    scalars: dict,
    luma_hist: list,
    hue_hist: list,
    metadata: dict,
    no_frame: bool,
) -> None:
    import json

    H, W  = (1, 1) if no_frame else linear_rgb.shape[:2]
    half  = Imath.PixelType(Imath.PixelType.HALF)

    # Build channel definitions
    ch_def = {}
    if not no_frame:
        for name in ("R", "G", "B"):
            ch_def[name] = Imath.Channel(half)
    for name in scalars:
        ch_def[name] = Imath.Channel(half)
    for i in range(len(luma_hist)):
        ch_def[f"luma.hist.{i:03d}"] = Imath.Channel(half)
    for i in range(len(hue_hist)):
        ch_def[f"hue.hist.{i:02d}"] = Imath.Channel(half)

    header = OpenEXR.Header(W, H)
    header["channels"] = ch_def

    # Float scalars duplicated as header attributes for quick exrheader inspection
    for name, value in scalars.items():
        header[name.replace(".", "_")] = float(value)

    out = OpenEXR.OutputFile(str(path), header)

    pixels = {}
    if not no_frame:
        pixels["R"] = linear_rgb[:, :, 0].astype(np.float16).tobytes()
        pixels["G"] = linear_rgb[:, :, 1].astype(np.float16).tobytes()
        pixels["B"] = linear_rgb[:, :, 2].astype(np.float16).tobytes()
    for name, value in scalars.items():
        pixels[name] = np.full((H, W), np.float16(value), dtype=np.float16).tobytes()
    for i, v in enumerate(luma_hist):
        pixels[f"luma.hist.{i:03d}"] = np.full((H, W), np.float16(v), dtype=np.float16).tobytes()
    for i, v in enumerate(hue_hist):
        pixels[f"hue.hist.{i:02d}"] = np.full((H, W), np.float16(v), dtype=np.float16).tobytes()

    out.writePixels(pixels)
    out.close()

    # JSON sidecar for string metadata (game, timestamp, note, git_commit)
    path.with_suffix(".json").write_text(json.dumps(metadata, indent=2))


# ── Dump (human-readable stdout) ──────────────────────────────────────────────

def _bar(v: float, peak: float, width: int = 36) -> str:
    return "█" * int(v / max(peak, 1e-9) * width)


def dump_highway(scalars: dict, luma_hist: list, hue_hist: list) -> None:
    print(f"\n  {'channel':<24} {'value':>12}   note")
    print(f"  {'-'*60}")
    notes = {
        "hwy.slope":           "R90 chroma expansion slope, range [1.15, 1.80]",
        "hwy.fc_stevens":      "Stevens exponent curve, range [0.72, 1.22]",
        "hwy.chroma_angle":    lambda v: f"{math.degrees(v):.1f}° dominant hue",
        "hwy.p25":             "scene p25 luma",
        "hwy.p75":             "scene p75 luma",
        "hwy.achrom_frac":     "fraction of pixels with Oklab C < 0.05",
        "hwy.zone_key":        "linear mean of zone medians [0,1]",
        "hwy.zone_std":        "mean intra-zone pixel variance [0,1]",
        "hwy.slow_key":        "slow ambient key EMA [0,1]",
        "hwy.fc_knee":         "FilmCurve knee position [0,1]",
        "hwy.zone_str":        "zone contrast strength (effective) [0,0.30]",
        "hwy.shadow_lift_str": "shadow lift strength (effective) [0,1.5]",
        "hwy.chroma_str":      "chroma lift base (pre-spatial-mod) [0,0.10]",
        "hwy.mist_str":        "pro-mist adapt_str (effective) [0,0.10]",
    }
    for name, value in scalars.items():
        note = notes.get(name, "")
        if callable(note):
            note = note(value)
        print(f"  {name:<24} {value:>12.5f}   {note}")

    print(f"\n  Luma histogram (128 bins, pre-correction):")
    peak = max(luma_hist) if luma_hist else 1.0
    for i, v in enumerate(luma_hist):
        print(f"    [{i:03d}] {v:.4f}  {_bar(v, peak)}")

    print(f"\n  Hue histogram (64 bins, pre-correction):")
    peak = max(hue_hist) if hue_hist else 1.0
    hue_labels = ["Red", "Yellow", "Green", "Cyan", "Blue", "Magenta"]
    for i, v in enumerate(hue_hist):
        label = hue_labels[round(i / HUE_HIST_BINS * 6) % 6] if i % 11 == 5 else ""
        print(f"    [{i:02d}] {v:.4f}  {_bar(v, peak, 24)}  {label}")


# ── Main ──────────────────────────────────────────────────────────────────────

def _screen_offset(screen_arg: str, total_width: int) -> int:
    """Return the x pixel offset for the requested screen."""
    if screen_arg in ("left",  "0"): return 0
    if screen_arg in ("right", "1"): return total_width // 2
    try:
        return int(screen_arg)   # explicit pixel offset
    except ValueError:
        return 0


def main() -> None:
    ap = argparse.ArgumentParser(description="vkBasalt pipeline capture → EXR")
    ap.add_argument("out",        nargs="?",           help="output .exr path (default: auto-named)")
    ap.add_argument("--game",     default="unknown",   help="game label")
    ap.add_argument("--note",     default="",          help="free-text session note")
    ap.add_argument("--screen",   default="left",      help="which monitor the game is on: left|right|0|1|<pixel offset>")
    ap.add_argument("--no-frame", action="store_true", help="1×1 scalars-only output, no frame image")
    ap.add_argument("--dump",     action="store_true", help="print highway to stdout, skip EXR write")
    args = ap.parse_args()

    ts  = datetime.now().strftime("%Y%m%d_%H%M%S")
    tmp = Path(f"/tmp/pipeline_capture_{ts}.png")

    print("Capturing screenshot...", end=" ", flush=True)
    take_screenshot(tmp)
    print("ok")

    print("Decoding...", end=" ", flush=True)
    png_data          = tmp.read_bytes()
    width, height, lr = load_png(png_data)

    # Crop to the monitor the game is on
    x_off = _screen_offset(args.screen, width)
    if x_off > 0 or width > 2600:
        half_w = width // 2 if args.screen in ("left", "right", "0", "1") else width
        x_end  = x_off + half_w if x_off + half_w <= width else width
        lr     = lr[:, x_off:x_end, :]

    scalars   = decode_scalars(lr)
    luma_hist = decode_luma_hist(lr)
    hue_hist  = decode_hue_hist(lr)
    tmp.unlink(missing_ok=True)
    crop_w = lr.shape[1]
    print(f"{width}×{height} → cropped to {crop_w}×{height} (screen={args.screen})")

    try:
        commit = subprocess.run(
            ["git", "rev-parse", "--short", "HEAD"],
            capture_output=True, text=True,
            cwd=Path(__file__).resolve().parent.parent,
        ).stdout.strip() or "unknown"
    except Exception:
        commit = "unknown"

    if args.dump:
        dump_highway(scalars, luma_hist, hue_hist)
        return

    default_dir = Path(__file__).resolve().parent.parent / "captures"
    default_dir.mkdir(exist_ok=True)
    out_path = Path(args.out) if args.out else default_dir / f"session_{ts}_{args.game}.exr"
    metadata = {
        "game":       args.game,
        "timestamp":  ts,
        "git_commit": commit,
        "note":       args.note,
        "scalars":    scalars,
        "luma_hist":  luma_hist,
        "hue_hist":   hue_hist,
    }

    print(f"Writing {out_path}...", end=" ", flush=True)
    write_exr(out_path, lr, scalars, luma_hist, hue_hist, metadata, args.no_frame)
    print("ok")

    n_ch = len(scalars) + len(luma_hist) + len(hue_hist)
    frame_note = "1×1 scalars-only" if args.no_frame else f"{width}×{height} RGB frame"
    print(f"  {n_ch} data channels + {frame_note}  [{commit}]")


if __name__ == "__main__":
    main()
