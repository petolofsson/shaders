#!/usr/bin/env python3
"""
tools/capture.py — Pipeline session capture.

Captures a linearized RGB EXR from the desktop. HighwayTex is offscreen;
screenshots contain no scalar or histogram telemetry. The obsolete --dump
and --no-frame modes fail explicitly.

Usage:
    python3 tools/capture.py [--game NAME] [--note TEXT] [OUT.exr]

Requires:
    pip install openexr numpy
    grim (Wayland) or scrot (X11)
"""

import argparse
import os
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


# ── Game auto-detection ───────────────────────────────────────────────────────

def detect_game() -> "str | None":
    """Scan /proc for a running process with SHADER_GAME set in its environment."""
    needle = b"SHADER_GAME="
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            for entry in Path(f"/proc/{pid}/environ").read_bytes().split(b"\0"):
                if entry.startswith(needle):
                    return entry[len(needle):].decode(errors="replace").strip()
        except (PermissionError, FileNotFoundError, ProcessLookupError):
            continue
    return None


# ── Screenshot ────────────────────────────────────────────────────────────────

def take_screenshot(path: Path) -> None:
    import time
    for cmd in [
        ["grim",      str(path)],
        ["grimblast", "save", "screen", str(path)],
        ["wayshot",   "-f", str(path)],
        ["spectacle", "--background", "--fullscreen", "--output", str(path)],
        ["scrot",     str(path)],
        ["import",    "-display", ":0", str(path)],
    ]:
        try:
            if subprocess.run(cmd, capture_output=True).returncode == 0:
                # Poll up to 1s — some tools (spectacle on KDE Wayland) return 0
                # before the file is flushed, or silently fail to write it.
                for _ in range(20):
                    if path.exists() and path.stat().st_size > 0:
                        return
                    time.sleep(0.05)
                # File still absent after 1s — tool lied about success, try next.
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
    raise RuntimeError("HighwayTex is offscreen; screenshots contain no highway telemetry")


def decode_luma_hist(linear_rgb: np.ndarray) -> list:
    """128 normalized luma histogram bins from x=0..127, row y=0."""
    raise RuntimeError("HighwayTex is offscreen; screenshots contain no highway telemetry")


def decode_hue_hist(linear_rgb: np.ndarray) -> list:
    """64 normalized hue histogram bins from x=130..193, row y=0."""
    raise RuntimeError("HighwayTex is offscreen; screenshots contain no highway telemetry")


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
    ap.add_argument("out",           nargs="?",          help="output .exr path (default: auto-named)")
    ap.add_argument("--game",        default=None,       help="game name (auto-detected from SHADER_GAME if omitted)")
    ap.add_argument("--note",        default="",         help="free-text session note")
    ap.add_argument("--screen",      default="left",     help="which monitor the game is on: left|right|0|1|<pixel offset>")
    ap.add_argument("--no-frame",    action="store_true", help="unsupported: telemetry requires GPU readback")
    ap.add_argument("--dump",        action="store_true", help="unsupported: telemetry requires GPU readback")
    ap.add_argument("--detect-game", action="store_true", help="print detected game name and exit")
    args = ap.parse_args()
    if args.dump or args.no_frame:
        ap.error("HighwayTex is offscreen: screenshot telemetry is unavailable. Capture RGB instead.")

    if args.detect_game:
        game = detect_game()
        if game:
            print(game)
            sys.exit(0)
        sys.exit(1)

    if not args.game:
        args.game = detect_game() or "unknown"
        if args.game != "unknown":
            print(f"Detected game: {args.game}")

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

    scalars, luma_hist, hue_hist = {}, [], []
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

    ROOT = Path(__file__).resolve().parent.parent
    if args.game != "unknown":
        default_dir = ROOT / "gamespecific" / args.game / "captures"
    else:
        default_dir = ROOT / "captures"
    default_dir.mkdir(parents=True, exist_ok=True)
    out_path = Path(args.out) if args.out else default_dir / f"session_{ts}_{args.game}.exr"
    metadata = {
        "game":       args.game,
        "timestamp":  ts,
        "git_commit": commit,
        "note":       args.note,
        "telemetry":  "unavailable: offscreen render targets are not in screenshots",
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
