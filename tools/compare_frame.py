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
from analyze_delta import cmd_relative  # noqa: E402

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


def main() -> None:
    ap = argparse.ArgumentParser(
        description="One-command before/after pipeline analysis",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Examples:\n"
            "  compare_frame gamespecific/gzw/reference_frames/20260514_133932.png\n"
            "  compare_frame frame.png --game gzw --delay 5\n"
            "  compare_frame frame.png --keep   # keep temp EXRs in /tmp\n"
        ),
    )
    ap.add_argument("png",     help="Reference PNG (pre-vkBasalt game screenshot)")
    ap.add_argument("--game",  default=None, help="Game name (auto-inferred from path)")
    ap.add_argument("--delay", type=int, default=3,
                    help="Seconds to wait for SPIR-V compile (default: 3)")
    ap.add_argument("--keep",  action="store_true",
                    help="Keep temp EXR files instead of deleting after analysis")
    args = ap.parse_args()

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
    before_exr = tmp / f"{stem}_before.exr"
    after_png  = tmp / f"{stem}_after.png"
    after_exr  = tmp / f"{stem}_after.exr"

    try:
        print(f"compare_frame  game={game}  source={png.name}")
        print()

        print("Before: loading reference PNG...")
        before = _load_png_linear(png)
        _save_exr(before, before_exr)
        bh, bw = before.shape[:2]
        print(f"  {bw}×{bh} → {before_exr.name}")
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
        _save_exr(after, after_exr)
        ah, aw = after.shape[:2]
        print(f"  {aw}×{ah} → {after_exr.name}")

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

        cmd_relative(before_exr, after_exr)

    finally:
        if not args.keep:
            shutil.rmtree(tmp, ignore_errors=True)
        else:
            print(f"Temp files kept in {tmp}/")


if __name__ == "__main__":
    main()
