#!/usr/bin/env python3
"""
tools/compare_frame.py — One-command before/after pipeline analysis.

Renders a reference PNG through the current creative_values.fx pipeline,
captures the result, and reports ΔE_oklab with directional ΔL*, ΔC*, Δh°
breakdown per zone and hue band.

Usage:
    compare_frame <reference.png> [--game gzw] [--delay 3] [--keep]
    compare_frame --all --game gzw [--delay 3]

The reference PNG must be a raw game screenshot (pre-vkBasalt, sRGB).
Auto-detects game from gamespecific/<game>/... path structure.

--all launches mpv once for all frames (single SPIR-V compile) and
navigates via IPC socket — much faster than per-frame restarts.
Saves aggregate to gamespecific/<game>/compare_agg.json for call sheet.
"""

import argparse
import json
import os
import re
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import time
from datetime import date, datetime
from pathlib import Path

import numpy as np

try:
    import OpenEXR
    import Imath
except ImportError:
    sys.exit("Missing: pip install openexr")

sys.path.insert(0, str(Path(__file__).resolve().parent))
from analyze_delta import compute_relative, print_relative, _de_fmt, _BLD, _RST, HUE_BANDS  # noqa: E402
from capture import take_screenshot  # noqa: E402

ROOT         = Path(__file__).resolve().parent.parent
SOCK         = Path("/tmp/mpv-tune.sock")
SCREEN       = 0        # KDE Wayland: primary (right, DP-2) = index 0
GAME_MONITOR = "right"  # which half of a dual-monitor grim capture to use


def _infer_game(png: Path) -> "str | None":
    parts = png.resolve().parts
    try:
        idx = list(parts).index("gamespecific")
        return parts[idx + 1]
    except (ValueError, IndexError):
        return None


def _load_png_linear(path: Path) -> np.ndarray:
    """sRGB PNG → linear float32 (H, W, 3) via ImageMagick."""
    r = subprocess.run(
        ["identify", "-format", "%wx%h", str(path)], capture_output=True
    )
    if r.returncode != 0:
        sys.exit(f"Cannot identify {path.name} — is imagemagick installed?")
    w, h = map(int, r.stdout.decode().strip().split("x"))

    r = subprocess.run(
        ["convert", str(path), "-depth", "8", "RGB:-"],
        capture_output=True,
    )
    if r.returncode != 0 or len(r.stdout) != w * h * 3:
        sys.exit(f"ImageMagick conversion failed for {path.name}")

    arr = (np.frombuffer(r.stdout, dtype=np.uint8)
             .reshape(h, w, 3)
             .astype(np.float32) / 255.0)
    return np.where(arr <= 0.04045, arr / 12.92, ((arr + 0.055) / 1.055) ** 2.4)


def _save_exr(arr: np.ndarray, path: Path) -> None:
    """Save linear float32 (H, W, 3) as EXR."""
    h, w = arr.shape[:2]
    header = OpenEXR.Header(w, h)
    pt = Imath.PixelType(Imath.PixelType.FLOAT)
    header["channels"] = {c: Imath.Channel(pt) for c in "RGB"}
    out = OpenEXR.OutputFile(str(path), header)
    out.writePixels({
        "R": arr[:, :, 0].astype(np.float32).tobytes(),
        "G": arr[:, :, 1].astype(np.float32).tobytes(),
        "B": arr[:, :, 2].astype(np.float32).tobytes(),
    })
    out.close()


def _launch_mpv(pngs: "list[Path]", config: Path, delay: int) -> subprocess.Popen:
    """Launch mpv with a playlist. Single SPIR-V compile; navigate with _goto_frame."""
    SOCK.unlink(missing_ok=True)
    env = os.environ.copy()
    env["ENABLE_VKBASALT"]      = "1"
    env["VKBASALT_CONFIG_FILE"] = str(config)
    cmd = [
        "mpv", "--vo=gpu", "--gpu-api=vulkan",
        "--image-display-duration=inf", "--loop-playlist=inf", "--fs",
        f"--screen={SCREEN}", f"--fs-screen={SCREEN}",
        f"--input-ipc-server={SOCK}",
    ] + [str(p) for p in pngs]
    proc = subprocess.Popen(
        cmd, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    print(f"  mpv pid {proc.pid} — compiling SPIR-V, waiting {delay}s...")
    time.sleep(delay)
    if proc.poll() is not None:
        sys.exit("mpv exited early — check /tmp/vkbasalt.log")
    return proc


def _mpv_cmd(cmd_list: list) -> None:
    """Send a command to the running mpv via IPC socket."""
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(1.0)
        s.connect(str(SOCK))
        s.send((json.dumps({"command": cmd_list}) + "\n").encode())
        s.recv(4096)
        s.close()
    except Exception:
        pass


def _goto_frame(idx: int, settle: float = 0.25) -> None:
    """Navigate mpv playlist to frame idx and wait for it to render."""
    _mpv_cmd(["set_property", "playlist-pos", idx])
    time.sleep(settle)


# ── All-effects mode ──────────────────────────────────────────────────────────

_AE_GATE_NAMES = ["CORRECTIVE_STRENGTH", "TONAL_STRENGTH", "CHROMA_STRENGTH", "LOOK_STRENGTH"]

# Per-effect passthrough values. Each entry: (label, {knob: passthrough_value}).
# passthrough_value = the value that makes the effect do nothing (0.0 for almost all;
# WHITES=1.0 is the exception because it is a ceiling, not a floor).
# Skip logic: if all knobs are already at their passthrough values, the effect is
# inactive and the run is skipped (would produce ΔE=0 anyway).
_EFFECTS: "list[tuple[str, dict]]" = [
    # ── INPUT ──────────────────────────────────────────────────────────────────
    ("INVERSE_STRENGTH",  {"INVERSE_STRENGTH": 0.0}),
    ("INVERSE_LUMA",      {"INVERSE_LUMA":     0.0}),
    # ── CORRECTIVE ─────────────────────────────────────────────────────────────
    ("EXPOSURE",          {"EXPOSURE":         0.0}),
    ("BLACKS_WHITES",     {"BLACKS": 0.0, "WHITES": 1.0}),
    ("DIR_COUPLER",       {"DIR_COUPLER":      0.0}),
    ("HALATION",          {"HALATION":         0.0}),
    ("FILM_CURVE",        {"CURVE_R_KNEE": 0.0, "CURVE_B_KNEE": 0.0,
                           "CURVE_R_TOE":  0.0, "CURVE_B_TOE":  0.0}),
    ("3WAY_CC",           {"SHADOW_TEMP": 0.0, "SHADOW_TINT": 0.0,
                           "MID_TEMP":    0.0, "MID_TINT":    0.0,
                           "HIGHLIGHT_TEMP": 0.0, "HIGHLIGHT_TINT": 0.0}),
    # ── TONAL ──────────────────────────────────────────────────────────────────
    ("CLARITY",           {"CLARITY":          0.0}),
    ("LUMA_CONTRAST",     {"LUMA_CONTRAST_RED": 0.0, "LUMA_CONTRAST_YELLOW": 0.0,
                           "LUMA_CONTRAST_GREEN": 0.0, "LUMA_CONTRAST_CYAN": 0.0,
                           "LUMA_CONTRAST_BLUE":  0.0, "LUMA_CONTRAST_MAG":  0.0}),
    ("CONTRAST",          {"CONTRAST":         0.0}),
    ("SHADOWS",           {"SHADOWS":          0.0}),
    ("HIGHLIGHTS",        {"HIGHLIGHTS":       0.0}),
    # ── CHROMA ─────────────────────────────────────────────────────────────────
    ("SHADOW_CAST",       {"SHADOW_CAST":      0.0}),
    ("HUE_ROTATION",      {"HUE_RED": 0.0, "HUE_YELLOW": 0.0, "HUE_GREEN": 0.0,
                           "HUE_CYAN": 0.0, "HUE_BLUE":  0.0, "HUE_MAG":   0.0}),
    ("VIBRANCE",          {"VIBRANCE":         0.0}),
    ("SATURATION",        {"SAT_RED": 0.0, "SAT_YELLOW": 0.0, "SAT_GREEN": 0.0,
                           "SAT_CYAN": 0.0, "SAT_BLUE":  0.0, "SAT_MAG":   0.0}),
    # ── LOOK ───────────────────────────────────────────────────────────────────
    ("PRINT_STOCK",       {"PRINT_STOCK":      0.0}),
    ("BLEACH_BYPASS",     {"BLEACH_BYPASS":    0.0}),
    ("PRINTER_LIGHTS",    {"PRINTER_R": 0.0, "PRINTER_G": 0.0, "PRINTER_B": 0.0}),
    # ── OUTPUT ─────────────────────────────────────────────────────────────────
    ("DIFFUSION",         {"DIFFUSION":        0.0}),
    ("GRAIN",             {"GRAIN":            0.0}),
]


def _ae_cv_path(game: str) -> Path:
    p = ROOT / "gamespecific" / game / "shaders" / "creative_values.fx"
    if not p.exists():
        sys.exit(f"Not found: {p}")
    return p


def _ae_write_knobs(cv: Path, knobs: dict) -> None:
    """Write knob values into creative_values.fx using regex replacement.

    Handles both integer gate knobs (100/0) and float effect knobs.
    Uses multiline \S+ to match the existing value token regardless of format
    (handles +0.10, -0.20, 0.005, 100, 1.0, etc.).
    """
    text = cv.read_text()
    for name, val in knobs.items():
        if isinstance(val, int):
            valstr = str(val)
        elif val == 0.0:
            valstr = "0.0"
        elif val == 1.0:
            valstr = "1.0"
        else:
            valstr = f"{val:g}"
        text = re.sub(
            rf"^(#define\s+{re.escape(name)}\s+)\S+",
            rf"\g<1>{valstr}",
            text,
            flags=re.MULTILINE,
        )
    cv.write_text(text)


def _ae_knobs_at_passthrough(cv: Path, passthrough: dict) -> bool:
    """True if every knob in passthrough is already at its passthrough value.

    Used to skip effects whose knobs haven't been dialled in — they would
    produce ΔE≈0 anyway, so there is nothing to measure.
    """
    text = cv.read_text()
    for name, pval in passthrough.items():
        m = re.search(rf"^#define\s+{re.escape(name)}\s+(\S+)", text, re.MULTILINE)
        if not m:
            return False
        try:
            cur = float(m.group(1))
        except ValueError:
            return False
        if abs(cur - float(pval)) > 1e-6:
            return False
    return True


def _capture_pipeline_output(
    pngs: "list[Path]", ref_images: "list[np.ndarray]", config: Path, delay: int
) -> "list[np.ndarray | None]":
    """Launch mpv and capture pipeline output for each PNG.

    Returns a list of the same length as pngs. Entries are None for frames that
    failed to capture or had a resolution mismatch — keeps indices aligned across
    multiple calls so frame i from one config can be compared to frame i of another.
    """
    outputs: "list[np.ndarray | None]" = [None] * len(pngs)
    proc = _launch_mpv(pngs, config, delay)
    try:
        for i, (png, before) in enumerate(zip(pngs, ref_images)):
            print(f"    [{i+1}/{len(pngs)}] {png.name}", end="", flush=True)
            _goto_frame(i)

            tmp       = Path(tempfile.mkdtemp(prefix="compare_ae_"))
            after_png = tmp / f"{png.stem}_after.png"
            take_screenshot(after_png)

            if not after_png.exists() or after_png.stat().st_size == 0:
                print("  SKIP (capture failed)")
                shutil.rmtree(tmp, ignore_errors=True)
                continue

            after = _load_png_linear(after_png)
            bh, bw = before.shape[:2]
            if after.shape[1] > bw:
                x = after.shape[1] // 2 if GAME_MONITOR == "right" else 0
                after = after[:, x:x + bw, :]
            shutil.rmtree(tmp, ignore_errors=True)

            if before.shape != after.shape:
                print("  SKIP (resolution mismatch)")
                continue

            outputs[i] = after
            print("  ok")
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=3)
        except Exception:
            proc.kill()

    return outputs


def _ae_aggregate(all_stats: "list[dict]") -> dict:
    n = len(all_stats)

    def avg_zone(label):
        zones = [s["zones"][label] for s in all_stats if s["zones"].get(label)]
        if not zones:
            return None
        return {
            "mean_de": sum(z["mean_de"] for z in zones) / len(zones),
            "dL":      sum(z["dL"]      for z in zones) / len(zones),
            "dC":      sum(z["dC"]      for z in zones) / len(zones),
        }

    def avg_band(bname):
        bands = [s["hue_bands"][bname] for s in all_stats if s["hue_bands"].get(bname)]
        if not bands:
            return None
        return {
            "mean_de": sum(b["mean_de"] for b in bands) / len(bands),
            "dL":      sum(b["dL"]      for b in bands) / len(bands),
            "dC":      sum(b["dC"]      for b in bands) / len(bands),
        }

    return {
        "mean_de":   sum(s["mean_de"] for s in all_stats) / n,
        "zones":     {lbl: avg_zone(lbl) for lbl in ("shadows", "midtones", "highlights")},
        "hue_bands": {e[0]: avg_band(e[0]) for e in HUE_BANDS},
    }


def _run_all_effects(game: str, config: Path, delay: int, max_frames: int = 12,
                     only: "list[str] | None" = None) -> None:
    cv            = _ae_cv_path(game)
    original_text = cv.read_text()

    frames_dir = ROOT / "gamespecific" / game / "analysis" / "reference"
    pngs       = sorted(frames_dir.glob("*.png"))[:max_frames]
    if not pngs:
        sys.exit(f"No PNGs in {frames_dir}")

    effects = _EFFECTS
    if only:
        valid = {label for label, _ in _EFFECTS}
        unknown = [n for n in only if n not in valid]
        if unknown:
            sys.exit(f"Unknown effect(s): {', '.join(unknown)}\nValid: {', '.join(sorted(valid))}")
        effects = [(label, pt) for label, pt in _EFFECTS if label in only]

    print(f"compare_frame --all-effects  game={game}  {len(pngs)} frame(s)")
    print(f"Mode: incremental subtraction — ΔE(full pipeline) vs ΔE(full minus effect)")
    print(f"Effects: {', '.join(label for label, _ in effects)}\n")

    def _restore(sig=None, frame=None):
        cv.write_text(original_text)
        print("\ncreative_values.fx restored.")
        if sig is not None:
            sys.exit(1)
    signal.signal(signal.SIGINT, _restore)

    ref_images = [_load_png_linear(p) for p in pngs]
    results: "list[tuple[str, dict | None]]" = []
    full_agg: "dict | None" = None

    try:
        # Phase 1 — FULL pipeline (gates must all be 100)
        print("── FULL  (reference)")
        _ae_write_knobs(cv, {k: 100 for k in _AE_GATE_NAMES})
        time.sleep(0.1)
        full_out = _capture_pipeline_output(pngs, ref_images, config, delay)
        # restore after FULL capture so cv is back to original state for subtraction runs
        cv.write_text(original_text)
        n_ok = sum(1 for o in full_out if o is not None)
        print(f"  {n_ok}/{len(pngs)} frames ok\n")
        if n_ok == 0:
            print("FULL capture failed — aborting.")
            return

        full_raw_stats = [
            compute_relative(ref_images[i], full_out[i])
            for i in range(len(pngs))
            if full_out[i] is not None and ref_images[i].shape == full_out[i].shape
        ]
        if full_raw_stats:
            full_agg = _ae_aggregate(full_raw_stats)

        # Phase 2 — WITHOUT each effect; compare to FULL
        for label, passthrough in effects:
            if _ae_knobs_at_passthrough(cv, passthrough):
                print(f"── without {label}  (skipped — already at passthrough)\n")
                results.append((label, None))
                continue

            print(f"── without {label}")
            _ae_write_knobs(cv, passthrough)
            time.sleep(0.1)
            wo_out = _capture_pipeline_output(pngs, ref_images, config, delay)
            cv.write_text(original_text)   # restore before next iteration

            frame_stats = [
                compute_relative(wo_out[i], full_out[i])
                for i in range(len(pngs))
                if full_out[i] is not None and wo_out[i] is not None
                and full_out[i].shape == wo_out[i].shape
            ]
            if not frame_stats:
                print(f"  No valid frame pairs — skipping.\n")
                results.append((label, None))
                continue

            agg = _ae_aggregate(frame_stats)
            results.append((label, agg))
            print(f"  {label} contribution ΔE {agg['mean_de']:.2f}\n")

    finally:
        cv.write_text(original_text)
        print("creative_values.fx restored.\n")

    if not results and full_agg is None:
        return

    DEAD = 0.5

    print("─" * 72)
    print(f"\n{_BLD}EFFECT ATTRIBUTION  (incremental — full pipeline minus that effect){_RST}")
    print(f"  ΔE = how much the output changes when that effect is zeroed")
    print(f"  ΔE < {DEAD} flagged as silent — effect may be broken or knobs at passthrough\n")

    hdr = f"  {'Effect':<18}  {'ΔE':>5}  {'shadows ΔL*/ΔC*':>18}  {'mids ΔL*/ΔC*':>14}  {'highs ΔL*/ΔC*':>14}"
    sep_line = "  " + "─" * 74
    print(hdr)
    print(sep_line)

    def _zone_row(label: str, agg: "dict | None", flag_dead: bool = True) -> None:
        if agg is None:
            print(f"  {label:<18}  (skipped — at passthrough)")
            return
        de   = agg["mean_de"]
        sh   = agg["zones"].get("shadows")
        mi   = agg["zones"].get("midtones")
        hi   = agg["zones"].get("highlights")
        sh_s = f"{sh['dL']:+.1f}/{sh['dC']:+.1f}" if sh else "    —    "
        mi_s = f"{mi['dL']:+.1f}/{mi['dC']:+.1f}" if mi else "    —    "
        hi_s = f"{hi['dL']:+.1f}/{hi['dC']:+.1f}" if hi else "    —    "
        flag = "  ← silent?" if flag_dead and de < DEAD else ""
        print(f"  {label:<18}  {_de_fmt(de)}  {sh_s:>18}  {mi_s:>14}  {hi_s:>14}{flag}")

    for label, agg in results:
        _zone_row(label, agg)

    if full_agg is not None:
        print(sep_line)
        _zone_row("FULL (raw→graded)", full_agg, flag_dead=False)

    # Hue band table
    band_names = [e[0] for e in HUE_BANDS]
    print(f"\n  by hue band  (ΔL*/ΔC*, chromatic pixels C*>3)")
    print(f"  {'Effect':<18}  " + "  ".join(f"{b:<12}" for b in band_names))
    print("  " + "─" * (20 + 14 * len(band_names)))

    def _band_row(label: str, agg: "dict | None") -> None:
        if agg is None:
            print(f"  {label:<18}  (skipped)")
            return
        cells = [
            (f"{agg['hue_bands'][b]['dL']:+.1f}/{agg['hue_bands'][b]['dC']:+.1f}"
             if agg["hue_bands"].get(b) else "   —   ")
            for b in band_names
        ]
        print(f"  {label:<18}  " + "  ".join(f"{c:<12}" for c in cells))

    for label, agg in results:
        _band_row(label, agg)
    if full_agg is not None:
        _band_row("FULL", full_agg)
    print()

    # ── Persist to full_analysis/ ─────────────────────────────────────────────
    now      = datetime.now()
    cv_path  = ROOT / "gamespecific" / game / "shaders" / "creative_values.fx"
    out_dir  = ROOT / "gamespecific" / game / "full_analysis"
    out_dir.mkdir(parents=True, exist_ok=True)

    payload = {
        "date":            str(now.date()),
        "time":            now.strftime("%H:%M:%S"),
        "game":            game,
        "n_frames":        len(pngs),
        "creative_values": cv_path.read_text() if cv_path.exists() else None,
        "effects": {
            label: agg
            for label, agg in results
        },
        "full": full_agg,
    }

    ts       = now.strftime("%Y-%m-%d_%H%M%S")
    run_path = out_dir / f"effects_{ts}.json"
    run_path.write_text(json.dumps(payload, indent=2))

    latest = out_dir / "latest.json"
    latest.write_text(json.dumps(payload, indent=2))

    print(f"  saved → {run_path.relative_to(ROOT)}")
    print(f"  latest → {latest.relative_to(ROOT)}")


def _run_batch(game: str, config: Path, delay: int, keep: bool) -> None:
    frames_dir = ROOT / "gamespecific" / game / "analysis" / "reference"
    pngs = sorted(frames_dir.glob("*.png"))
    if not pngs:
        sys.exit(f"No PNGs in {frames_dir}")

    print(f"compare_frame --all  game={game}  {len(pngs)} frame(s)")
    print()

    analysis_dir = ROOT / "gamespecific" / game / "analysis" / str(date.today())
    frames_out: "Path | None" = None
    if keep:
        frames_out = analysis_dir / "frames"
        frames_out.mkdir(parents=True, exist_ok=True)

    all_stats: list[dict] = []
    all_channels: list[dict] = []
    proc = _launch_mpv(pngs, config, delay)

    try:
        for i, png in enumerate(pngs):
            print(f"── [{i+1}/{len(pngs)}] {png.name}")
            before = _load_png_linear(png)
            bh, bw = before.shape[:2]

            _goto_frame(i)

            tmp       = Path(tempfile.mkdtemp(prefix="compare_frame_"))
            after_png = tmp / f"{png.stem}_after.png"
            take_screenshot(after_png)

            if not after_png.exists() or after_png.stat().st_size == 0:
                print("  SKIP — screen capture failed")
                shutil.rmtree(tmp, ignore_errors=True)
                continue

            after = _load_png_linear(after_png)
            ah, aw = after.shape[:2]
            if aw > bw:
                x = aw // 2 if GAME_MONITOR == "right" else 0
                after = after[:, x:x + bw, :]
                ah, aw = after.shape[:2]

            if before.shape != after.shape:
                print(f"  SKIP — resolution mismatch: ref {bw}×{bh}, capture {aw}×{ah}")
                shutil.rmtree(tmp, ignore_errors=True)
                continue

            if keep and frames_out:
                _save_exr(before, frames_out / f"{png.stem}_before.exr")
                _save_exr(after,  frames_out / f"{png.stem}_after.exr")
            shutil.rmtree(tmp, ignore_errors=True)

            stats = compute_relative(before, after)
            all_stats.append(stats)

            frame_ch = {}
            for ch, ci in (("R", 0), ("G", 1), ("B", 2)):
                frame_ch[ch] = {
                    "raw":  [float(v) for v in np.percentile(before[:, :, ci], [5, 50, 95])],
                    "grad": [float(v) for v in np.percentile(after[:, :, ci],  [5, 50, 95])],
                }
            all_channels.append(frame_ch)

            for label in ("shadows", "midtones", "highlights"):
                z = stats["zones"].get(label)
                if z is None:
                    continue
                dh_s = f"{z['dh']:+.1f}°" if z["dh"] is not None else "—    "
                print(f"  {label:<12}  ΔL* {z['dL']:+5.1f}  ΔC* {z['dC']:+5.1f}  Δh° {dh_s:<7}  ΔE {_de_fmt(z['mean_de'])}")
            print()
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            proc.kill()

    if not all_stats:
        sys.exit("No frames analysed.")

    n = len(all_stats)
    print("─" * 62)
    print(f"\n{_BLD}AGGREGATE  {n} frame(s){_RST}\n")

    agg_zones: dict = {}
    for label in ("shadows", "midtones", "highlights"):
        zones = [s["zones"][label] for s in all_stats if s["zones"].get(label)]
        if not zones:
            agg_zones[label] = None
            continue
        dhs = [z["dh"] for z in zones if z["dh"] is not None]
        agg_zones[label] = {
            "mean_de": sum(z["mean_de"] for z in zones) / len(zones),
            "dL":      sum(z["dL"]      for z in zones) / len(zones),
            "dC":      sum(z["dC"]      for z in zones) / len(zones),
            "dh":      sum(dhs) / len(dhs) if dhs else None,
        }
        z = agg_zones[label]
        dh_s = f"{z['dh']:+.1f}°" if z["dh"] is not None else "—    "
        print(f"  {label:<12}  ΔL* {z['dL']:+5.1f}  ΔC* {z['dC']:+5.1f}  Δh° {dh_s:<7}  ΔE {_de_fmt(z['mean_de'])}")

    agg_bands: dict = {}
    print(f"\n  by hue band (C*>5 chromatic pixels)")
    for entry in HUE_BANDS:
        bname = entry[0]
        bands = [s["hue_bands"][bname] for s in all_stats if s["hue_bands"].get(bname)]
        if not bands:
            agg_bands[bname] = None
            continue
        dhs = [b["dh"] for b in bands if b["dh"] is not None]
        agg_bands[bname] = {
            "mean_de": sum(b["mean_de"] for b in bands) / len(bands),
            "dL":      sum(b["dL"]      for b in bands) / len(bands),
            "dC":      sum(b["dC"]      for b in bands) / len(bands),
            "dh":      sum(dhs) / len(dhs) if dhs else None,
        }
        b = agg_bands[bname]
        dh_s = f"{b['dh']:+.1f}°" if b["dh"] is not None else "—    "
        print(f"  {bname:<8}      ΔL* {b['dL']:+5.1f}  ΔC* {b['dC']:+5.1f}  Δh° {dh_s:<7}  ΔE {_de_fmt(b['mean_de'])}")
    print()

    # Save aggregate JSON for call sheet
    agg_channels: dict = {}
    if all_channels:
        for ch in ("R", "G", "B"):
            agg_channels[ch] = {
                "raw":  [sum(f[ch]["raw"][i]  for f in all_channels) / len(all_channels) for i in range(3)],
                "grad": [sum(f[ch]["grad"][i] for f in all_channels) / len(all_channels) for i in range(3)],
            }

    agg_data = {
        "date":     str(date.today()),
        "game":     game,
        "n_frames": n,
        "zones":    agg_zones,
        "hue_bands": agg_bands,
        "channels": agg_channels,
    }
    agg_path = ROOT / "gamespecific" / game / "compare_agg.json"
    agg_path.write_text(json.dumps(agg_data, indent=2))
    print(f"  aggregate → {agg_path.relative_to(ROOT)}")

    analysis_dir.mkdir(parents=True, exist_ok=True)
    arch_path = analysis_dir / "compare_agg.json"
    arch_path.write_text(json.dumps(agg_data, indent=2))
    if keep and frames_out:
        print(f"  EXRs      → {frames_out.relative_to(ROOT)}/")
    print(f"  archive   → {arch_path.relative_to(ROOT)}")


def main() -> None:
    ap = argparse.ArgumentParser(
        description="One-command before/after pipeline analysis",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Examples:\n"
            "  compare_frame gamespecific/gzw/reference_frames/frame.png\n"
            "  compare_frame --all --game gzw\n"
            "  compare_frame frame.png --keep\n"
        ),
    )
    ap.add_argument("png",     nargs="?", default=None,
                    help="Reference PNG (pre-vkBasalt game screenshot)")
    ap.add_argument("--all",         action="store_true",
                    help="Batch-analyse all reference frames for the game")
    ap.add_argument("--all-effects", action="store_true",
                    help="Measure each pipeline stage individually (not cumulative) — shows silent effects")
    ap.add_argument("--game",  default=None,
                    help="Game name (auto-inferred from path, required with --all / --all-effects)")
    ap.add_argument("--delay", type=int, default=3,
                    help="Seconds to wait for SPIR-V compile (default: 3)")
    ap.add_argument("--keep",  action="store_true",
                    help="Keep temp EXR files instead of deleting after analysis")
    ap.add_argument("--max-frames", type=int, default=None,
                    help="Cap number of reference frames (default: 12 for --all-effects, unlimited for --all)")
    ap.add_argument("--only", nargs="+", default=None, metavar="EFFECT",
                    help="Test only these effects (space-separated, e.g. --only INVERSE_LUMA EXPOSURE)")
    args = ap.parse_args()

    if args.all_effects:
        game = args.game
        if not game:
            sys.exit("--all-effects requires --game <name>")
        config = ROOT / "gamespecific" / game / f"{game}.conf"
        if not config.exists():
            sys.exit(f"Config not found: {config}")
        max_frames = args.max_frames if args.max_frames is not None else 12
        _run_all_effects(game, config, args.delay, max_frames, args.only)
        return

    if args.all:
        game = args.game
        if not game:
            sys.exit("--all requires --game <name>")
        config = ROOT / "gamespecific" / game / f"{game}.conf"
        if not config.exists():
            sys.exit(f"Config not found: {config}")
        _run_batch(game, config, args.delay, args.keep)
        return

    if not args.png:
        ap.print_help()
        sys.exit(1)

    png = Path(args.png)
    if not png.exists():
        sys.exit(f"Not found: {png}")

    game = args.game or _infer_game(png)
    if not game:
        sys.exit("Cannot infer game from path. Pass --game <name>.")

    config = ROOT / "gamespecific" / game / f"{game}.conf"
    if not config.exists():
        sys.exit(f"Config not found: {config}")

    stem      = png.stem
    tmp       = Path(tempfile.mkdtemp(prefix="compare_frame_"))
    after_png = tmp / f"{stem}_after.png"

    try:
        print(f"compare_frame  game={game}  source={png.name}")
        print()

        print("Before: loading reference PNG...")
        before = _load_png_linear(png)
        bh, bw = before.shape[:2]
        print(f"  {bw}×{bh}")
        print()

        print("After: launching mpv + vkBasalt...")
        proc = _launch_mpv([png], config, args.delay)

        print("Capturing screen...")
        take_screenshot(after_png)
        if not after_png.exists() or after_png.stat().st_size == 0:
            proc.terminate()
            sys.exit("Screen capture failed.")

        print("After: linearizing captured frame...")
        after = _load_png_linear(after_png)
        ah, aw = after.shape[:2]
        if aw > bw:
            x = aw // 2 if GAME_MONITOR == "right" else 0
            after = after[:, x:x + bw, :]
            ah, aw = after.shape[:2]
        print(f"  {aw}×{ah}")

        proc.terminate()
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            proc.kill()
        print("mpv closed.")
        print()

        if before.shape != after.shape:
            sys.exit(
                f"Resolution mismatch: reference {bw}×{bh}, capture {aw}×{ah}.\n"
                f"Ensure the reference PNG matches the display resolution ({aw}×{ah})."
            )

        if args.keep:
            _save_exr(before, tmp / f"{stem}_before.exr")
            _save_exr(after,  tmp / f"{stem}_after.exr")

        stats = compute_relative(before, after)
        print_relative(stats, png.name, after_png.name)

    finally:
        if not args.keep:
            shutil.rmtree(tmp, ignore_errors=True)
        else:
            print(f"Temp files kept in {tmp}/")


if __name__ == "__main__":
    main()
