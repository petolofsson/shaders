#!/usr/bin/env python3
"""
tools/auto_capture.py — Automated reference frame collection during gameplay.

Runs in the background. Every --interval seconds it screenshots the current
monitor, rejects loading screens and near-duplicate scenes, and saves keepers
to gamespecific/<game>/reference_frames/ as autof_<timestamp>.png.

Stop with Ctrl-C.

Note: spectacle captures what is on screen, so frames will include the active
vkBasalt pass. For pre-pipeline frames use Steam F12 (captured by the game
process before the Vulkan layer) and copy from
~/.local/share/Steam/userdata/*/760/remote/*/screenshots/.

Usage:
    auto_capture [--game arc_raiders] [--interval 20] [--max-frames 24] [--min-diff 12]
"""

import argparse
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(Path(__file__).resolve().parent))
from capture import take_screenshot as _take_screenshot  # noqa: E402


def crop_to_monitor(png: Path, screen: str) -> None:
    """Crop png in-place to the target monitor using ImageMagick."""
    r = subprocess.run(
        ["identify", "-format", "%wx%h", str(png)], capture_output=True, text=True
    )
    if r.returncode != 0:
        return
    try:
        total_w, total_h = map(int, r.stdout.strip().split("x"))
    except (ValueError, AttributeError):
        return

    half_w = total_w // 2
    if screen in ("left", "0"):
        x_off, crop_w = 0, half_w
    elif screen in ("right", "1"):
        x_off, crop_w = half_w, half_w
    else:
        try:
            x_off = int(screen)
            crop_w = total_w - x_off
        except ValueError:
            return

    if x_off == 0 and crop_w >= total_w:
        return  # nothing to crop

    tmp_out = png.with_suffix(".crop.png")
    r2 = subprocess.run(
        ["convert", str(png),
         "-crop", f"{crop_w}x{total_h}+{x_off}+0", "+repage", str(tmp_out)],
        capture_output=True,
    )
    if r2.returncode == 0:
        tmp_out.replace(png)


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


def take_screenshot(tmp: Path) -> bool:
    _take_screenshot(tmp)
    return tmp.exists() and tmp.stat().st_size > 0


def make_thumb(png: Path) -> "np.ndarray | None":
    """Downscale to 160×90 uint8 via ImageMagick. Returns None on failure."""
    r = subprocess.run(
        ["convert", str(png), "-resize", "160x90!", "-depth", "8", "RGB:-"],
        capture_output=True,
    )
    expected = 160 * 90 * 3
    if r.returncode != 0 or len(r.stdout) != expected:
        return None
    return np.frombuffer(r.stdout, dtype=np.uint8).reshape(90, 160, 3)


def is_interesting(t: np.ndarray) -> tuple:
    """
    Returns (keep: bool, reason: str).
    Rejects near-black (loading), near-white (splash), and near-uniform frames.
    """
    mean = float(t.mean()) / 255.0
    if mean < 0.06:
        return False, f"too dark (mean={mean:.2f})"
    if mean > 0.93:
        return False, f"too bright (mean={mean:.2f})"
    std = float(t.std()) / 255.0
    if std < 0.04:
        return False, f"too uniform (std={std:.2f})"
    return True, ""


def mean_diff(a: np.ndarray, b: np.ndarray) -> float:
    return float(np.abs(a.astype(np.int16) - b.astype(np.int16)).mean())


def prune(dest: Path, max_frames: int) -> None:
    """Delete oldest auto-captured frames if over the limit."""
    frames = sorted(dest.glob("autof_*.png"), key=lambda p: p.stat().st_mtime)
    for p in frames[:-max_frames]:
        p.unlink(missing_ok=True)
        print(f"  pruned  {p.name}")


def main() -> None:
    ap = argparse.ArgumentParser(
        description="Automated reference frame collection during gameplay",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Examples:\n"
            "  auto_capture                  # 20s interval, saves to arc_raiders/reference_frames/\n"
            "  auto_capture --interval 10    # faster capture\n"
            "  auto_capture &                # run in background\n"
        ),
    )
    ap.add_argument("--game",       default=None,
                    help="Game name — auto-detected from SHADER_GAME env var if omitted")
    ap.add_argument("--interval",   type=int, default=20,
                    help="Seconds between capture attempts (default: 20)")
    ap.add_argument("--max-frames", type=int, default=24,
                    help="Max frames to keep in analysis/reference/ — oldest pruned (default: 24)")
    ap.add_argument("--min-diff",   type=int, default=12,
                    help="Min mean pixel diff (0–255) required to save a frame (default: 12)")
    ap.add_argument("--screen",     default="right",
                    help="which monitor the game is on: left|right|0|1|<pixel offset> (default: right)")
    args = ap.parse_args()

    game = args.game or detect_game()
    if not game:
        sys.exit("Could not detect game. Set SHADER_GAME=<name> in Steam launch options or pass --game.")
    if args.game is None:
        print(f"Detected game: {game}")
    args.game = game

    dest = ROOT / "gamespecific" / args.game / "analysis" / "reference"
    dest.mkdir(parents=True, exist_ok=True)
    tmp  = Path("/tmp/auto_capture_shot.png")

    # Seed similarity baseline from most recent auto-frame if any exist
    last_thumb = None
    existing   = sorted(dest.glob("autof_*.png"), key=lambda p: p.stat().st_mtime)  # noqa
    if existing:
        t = make_thumb(existing[-1])
        if t is not None:
            last_thumb = t
            print(f"Seeded from: {existing[-1].name}")

    print(f"auto_capture  game={args.game}  interval={args.interval}s  "
          f"min_diff={args.min_diff}  max_frames={args.max_frames}")
    print(f"Saving to {dest.relative_to(ROOT)}/")
    print("Ctrl-C to stop.\n")

    saved = skipped = 0

    try:
        while True:
            ts = time.strftime("%Y%m%d_%H%M%S")

            if not take_screenshot(tmp):
                print(f"  [{ts}] screenshot failed — is spectacle installed?")
                time.sleep(args.interval)
                continue

            crop_to_monitor(tmp, args.screen)

            t = make_thumb(tmp)
            if t is None:
                print(f"  [{ts}] thumbnail failed")
                time.sleep(args.interval)
                continue

            keep, reason = is_interesting(t)
            if not keep:
                skipped += 1
                print(f"  [{ts}] skip — {reason}")
                time.sleep(args.interval)
                continue

            if last_thumb is not None:
                diff = mean_diff(t, last_thumb)
                if diff < args.min_diff:
                    skipped += 1
                    print(f"  [{ts}] skip — similar to last (diff={diff:.1f} < {args.min_diff})")
                    time.sleep(args.interval)
                    continue

            out = dest / f"autof_{ts}.png"
            shutil.copy2(tmp, out)
            last_thumb = t
            saved += 1
            prune(dest, args.max_frames)
            print(f"  [{ts}] saved  {out.name}  (total saved: {saved})")

            time.sleep(args.interval)

    except KeyboardInterrupt:
        tmp.unlink(missing_ok=True)
        print(f"\nDone. {saved} saved, {skipped} skipped.")


if __name__ == "__main__":
    main()
