#!/usr/bin/env python3
"""
tools/compare_frame.py — One-command before/after pipeline analysis.

Renders a reference PNG through the current creative_values.fx pipeline,
captures the result, and reports CIEDE2000 perceptual delta with directional
ΔL*, ΔC*, Δh° breakdown per zone and hue band.

Usage:
    compare_frame <reference.png> [--game gzw] [--delay 3] [--keep]

The reference PNG must be a raw game screenshot (pre-vkBasalt, sRGB).
Auto-detects game from gamespecific/<game>/... path structure.

Controls: move cursor to the monitor where mpv renders before capture runs.
"""

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

import numpy as np

try:
    import OpenEXR
    import Imath
except ImportError:
    sys.exit("Missing: pip install openexr")

# Import cmd_relative from analyze_delta in the same directory
sys.path.insert(0, str(Path(__file__).resolve().parent))
from analyze_delta import compute_relative, print_relative, _de_fmt, _BLD, _RST, HUE_BANDS  # noqa: E402

ROOT   = Path(__file__).resolve().parent.parent
SOCK   = Path("/tmp/mpv-tune.sock")
SCREEN = 0  # KDE Wayland: primary (right, DP-2) = index 0


def _infer_game(png: Path) -> "str | None":
    """Guess game name from gamespecific/<game>/... path structure."""
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
    # sRGB EOTF (IEC 61966-2-1)
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


def _launch_mpv(png: Path, config: Path, delay: int) -> subprocess.Popen:
    SOCK.unlink(missing_ok=True)
    env = os.environ.copy()
    env["ENABLE_VKBASALT"]      = "1"
    env["VKBASALT_CONFIG_FILE"] = str(config)
    cmd = [
        "mpv", "--vo=gpu", "--gpu-api=vulkan",
        "--image-display-duration=inf", "--loop=inf", "--fs",
        f"--screen={SCREEN}", f"--fs-screen={SCREEN}",
        f"--input-ipc-server={SOCK}",
        str(png),
    ]
    proc = subprocess.Popen(
        cmd, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    print(f"  mpv pid {proc.pid} — compiling SPIR-V, waiting {delay}s...")
    time.sleep(delay)
    if proc.poll() is not None:
        sys.exit("mpv exited early — check /tmp/vkbasalt.log")
    return proc


def _run_batch(game: str, config: Path, delay: int, keep: bool) -> None:
    frames_dir = ROOT / "gamespecific" / game / "reference_frames"
    pngs = sorted(frames_dir.glob("*.png"))
    if not pngs:
        sys.exit(f"No PNGs in {frames_dir}")

    print(f"compare_frame --all  game={game}  {len(pngs)} frame(s)")
    print()

    all_stats: list[dict] = []

    for i, png in enumerate(pngs):
        print(f"── [{i+1}/{len(pngs)}] {png.name}")
        before = _load_png_linear(png)
        bh, bw = before.shape[:2]

        tmp       = Path(tempfile.mkdtemp(prefix="compare_frame_"))
        after_png = tmp / f"{png.stem}_after.png"

        proc = _launch_mpv(png, config, delay)
        r = subprocess.run(
            ["spectacle", "-b", "-m", "-n", "-o", str(after_png)],
            capture_output=True,
        )
        proc.terminate()
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            proc.kill()

        if r.returncode != 0 or not after_png.exists() or after_png.stat().st_size == 0:
            print("  SKIP — screen capture failed")
            shutil.rmtree(tmp, ignore_errors=True)
            continue

        after = _load_png_linear(after_png)
        ah, aw = after.shape[:2]

        if before.shape != after.shape:
            print(f"  SKIP — resolution mismatch: ref {bw}×{bh}, capture {aw}×{ah}")
            shutil.rmtree(tmp, ignore_errors=True)
            continue

        if keep:
            _save_exr(before, tmp / f"{png.stem}_before.exr")
            _save_exr(after,  tmp / f"{png.stem}_after.exr")
            print(f"  EXRs kept: {tmp}/")
        else:
            shutil.rmtree(tmp, ignore_errors=True)

        stats = compute_relative(before, after)
        all_stats.append(stats)

        for label in ("shadows", "midtones", "highlights"):
            z = stats["zones"].get(label)
            if z is None:
                continue
            dh_s = f"{z['dh']:+.1f}°" if z["dh"] is not None else "—    "
            print(f"  {label:<12}  ΔL* {z['dL']:+5.1f}  ΔC* {z['dC']:+5.1f}  Δh° {dh_s:<7}  ΔE {_de_fmt(z['mean_de'])}")
        print()

    if not all_stats:
        sys.exit("No frames analysed.")

    n = len(all_stats)
    print("─" * 62)
    print(f"\n{_BLD}AGGREGATE  {n} frame(s){_RST}\n")

    for label in ("shadows", "midtones", "highlights"):
        zones = [s["zones"][label] for s in all_stats if s["zones"].get(label)]
        if not zones:
            continue
        avg_de = sum(z["mean_de"] for z in zones) / len(zones)
        avg_dL = sum(z["dL"]      for z in zones) / len(zones)
        avg_dC = sum(z["dC"]      for z in zones) / len(zones)
        dhs    = [z["dh"] for z in zones if z["dh"] is not None]
        dh_s   = f"{sum(dhs)/len(dhs):+.1f}°" if dhs else "—    "
        print(f"  {label:<12}  ΔL* {avg_dL:+5.1f}  ΔC* {avg_dC:+5.1f}  Δh° {dh_s:<7}  ΔE {_de_fmt(avg_de)}")

    print(f"\n  by hue band (C*>5 chromatic pixels)")
    for entry in HUE_BANDS:
        bname = entry[0]
        bands = [s["hue_bands"][bname] for s in all_stats if s["hue_bands"].get(bname)]
        if not bands:
            continue
        avg_de = sum(b["mean_de"] for b in bands) / len(bands)
        avg_dL = sum(b["dL"]      for b in bands) / len(bands)
        avg_dC = sum(b["dC"]      for b in bands) / len(bands)
        dhs    = [b["dh"] for b in bands if b["dh"] is not None]
        dh_s   = f"{sum(dhs)/len(dhs):+.1f}°" if dhs else "—    "
        print(f"  {bname:<8}      ΔL* {avg_dL:+5.1f}  ΔC* {avg_dC:+5.1f}  Δh° {dh_s:<7}  ΔE {_de_fmt(avg_de)}")
    print()


def main() -> None:
    ap = argparse.ArgumentParser(
        description="One-command before/after pipeline analysis",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Examples:\n"
            "  compare_frame gamespecific/gzw/reference_frames/20260514_133932.png\n"
            "  compare_frame --all --game gzw\n"
            "  compare_frame frame.png --keep   # keep temp EXRs in /tmp\n"
        ),
    )
    ap.add_argument("png",     nargs="?", default=None,
                    help="Reference PNG (pre-vkBasalt game screenshot)")
    ap.add_argument("--all",   action="store_true",
                    help="Batch-analyse all reference frames for the game")
    ap.add_argument("--game",  default=None,
                    help="Game name (auto-inferred from path, required with --all)")
    ap.add_argument("--delay", type=int, default=3,
                    help="Seconds to wait for SPIR-V compile (default: 3)")
    ap.add_argument("--keep",  action="store_true",
                    help="Keep temp EXR files instead of deleting after analysis")
    args = ap.parse_args()

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

    stem       = png.stem
    tmp        = Path(tempfile.mkdtemp(prefix="compare_frame_"))
    before_exr = tmp / f"{stem}_before.exr"
    after_png  = tmp / f"{stem}_after.png"
    after_exr  = tmp / f"{stem}_after.exr"

    try:
        print(f"compare_frame  game={game}  source={png.name}")
        print()

        print("Before: loading reference PNG...")
        before = _load_png_linear(png)
        bh, bw = before.shape[:2]
        print(f"  {bw}×{bh}")
        print()

        print("After: launching mpv + vkBasalt...")
        proc = _launch_mpv(png, config, args.delay)

        print("Capturing screen...")
        r = subprocess.run(
            ["spectacle", "-b", "-m", "-n", "-o", str(after_png)],
            capture_output=True,
        )
        if r.returncode != 0 or not after_png.exists() or after_png.stat().st_size == 0:
            proc.terminate()
            sys.exit("Screen capture failed — is spectacle installed?")

        print("After: linearizing captured frame...")
        after = _load_png_linear(after_png)
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
            _save_exr(before, before_exr)
            _save_exr(after, after_exr)

        stats = compute_relative(before, after)
        print_relative(stats, png.name, after_png.name)

    finally:
        if not args.keep:
            shutil.rmtree(tmp, ignore_errors=True)
        else:
            print(f"Temp files kept in {tmp}/")


if __name__ == "__main__":
    main()
