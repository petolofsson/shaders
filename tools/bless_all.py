#!/usr/bin/env python3
"""
tools/bless_all.py — Bless or check all four test images in one go.

For each image: launches mpv with vkBasalt, waits for the pipeline to render,
captures, runs bless/check, then closes mpv and moves to the next image.

Usage:
    bless_all [--delay N]   bless all images (skip already-blessed)
    bless_all --rebless     overwrite existing goldens
    check_all [--delay N]   check all images against their goldens (via --check flag)
"""

import argparse
import os
import subprocess
import sys
import time
from pathlib import Path

ROOT     = Path(__file__).resolve().parent.parent
CAPTURES = ROOT / "captures"
INPUTS   = ROOT / "tests" / "inputs"
CONFIG   = ROOT / "gamespecific" / "arc_raiders" / "arc_raiders.conf"

# Monitor index for the right (game) monitor.
# On KDE Wayland the primary monitor (DP-2, right) is typically index 0.
# Change to 1 if mpv opens on the wrong screen.
GAME_SCREEN = 0

IMAGES = [
    ("gradient",     "test_gradient.png",     "luma ramp + hue bars"),
    ("colorchecker", "test_colorchecker.png",  "24-patch Macbeth ColorChecker"),
    ("highlights",   "test_highlights.png",    "bright patches on dark ground"),
    ("skintones",    "test_skintones.png",     "Fitzpatrick I-VI skin tones"),
]


def latest_exr() -> Path:
    candidates = sorted(CAPTURES.glob("*.exr"), key=lambda p: p.stat().st_mtime)
    if not candidates:
        sys.exit("No captures found after shot.")
    return candidates[-1]


def capture_via_mpv(img_file: str, delay: int) -> Path:
    """Launch mpv on the game monitor, wait, capture, return the EXR path."""
    img_path = INPUTS / img_file
    if not img_path.exists():
        sys.exit(f"Missing: {img_path}\nRun 'make_test_images' first.")

    env = os.environ.copy()
    env["ENABLE_VKBASALT"]      = "1"
    env["VKBASALT_CONFIG_FILE"] = str(CONFIG)

    mpv = subprocess.Popen(
        [
            "mpv",
            "--vo=gpu", "--gpu-api=vulkan",
            "--loop", "--fs",
            f"--screen={GAME_SCREEN}",
            f"--fs-screen={GAME_SCREEN}",
            str(img_path),
        ],
        env=env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    print(f"  mpv pid {mpv.pid} — waiting {delay}s for pipeline to render...")
    time.sleep(delay)

    if mpv.poll() is not None:
        sys.exit("mpv exited early — check /tmp/vkbasalt.log")

    print("  capturing...")
    cap = subprocess.run(
        ["python3", str(ROOT / "tools" / "capture.py"),
         "--game", "test", "--screen", "right"],
        capture_output=True, text=True,
    )
    if cap.returncode != 0:
        mpv.terminate()
        sys.exit(f"capture failed:\n{cap.stderr}")
    for line in cap.stdout.strip().splitlines():
        print(f"  {line}")

    mpv.terminate()
    mpv.wait(timeout=5)
    return latest_exr()


def bless_one(name: str, img_file: str, desc: str, delay: int, rebless: bool) -> None:
    golden_exr = ROOT / "tests" / "golden" / f"{name}.exr"
    if golden_exr.exists() and not rebless:
        print(f"  skip '{name}' — already blessed  (use --rebless to overwrite)")
        return

    print(f"\n── bless {name} {'─' * (44 - len(name))}")
    exr = capture_via_mpv(img_file, delay)

    bless = subprocess.run(
        ["python3", str(ROOT / "tools" / "test_golden.py"),
         "bless", name, str(exr), "--desc", desc],
        capture_output=True, text=True,
    )
    if bless.returncode != 0:
        sys.exit(f"bless failed:\n{bless.stderr}")
    for line in bless.stdout.strip().splitlines():
        print(f"  {line}")


def check_one(name: str, img_file: str, delay: int) -> bool:
    golden_exr = ROOT / "tests" / "golden" / f"{name}.exr"
    if not golden_exr.exists():
        print(f"  skip '{name}' — no golden (run bless_all first)")
        return True

    print(f"\n── check {name} {'─' * (44 - len(name))}")
    exr = capture_via_mpv(img_file, delay)

    result = subprocess.run(
        ["python3", str(ROOT / "tools" / "test_golden.py"),
         "check", name, str(exr)],
        capture_output=True, text=True,
    )
    for line in result.stdout.strip().splitlines():
        print(f"  {line}")
    return result.returncode == 0


def main() -> None:
    ap = argparse.ArgumentParser(description="Bless or check all four test image goldens")
    ap.add_argument("--delay",   type=int,          default=4,     help="Seconds to wait before capture (default: 4)")
    ap.add_argument("--rebless", action="store_true",               help="Overwrite existing goldens (bless mode only)")
    ap.add_argument("--check",   action="store_true",               help="Run checks instead of blessing")
    args = ap.parse_args()

    if not CONFIG.exists():
        sys.exit(f"Config not found: {CONFIG}")

    if args.check:
        print(f"Checking {len(IMAGES)} images  (delay={args.delay}s)")
        passed, failed = [], []
        for name, img_file, _ in IMAGES:
            ok = check_one(name, img_file, args.delay)
            (passed if ok else failed).append(name)
        print(f"\n{'─' * 52}")
        print(f"  PASS {len(passed)}  FAIL {len(failed)}")
        if failed:
            print(f"  failed: {', '.join(failed)}")
            sys.exit(1)
    else:
        print(f"Blessing {len(IMAGES)} images  (delay={args.delay}s, rebless={args.rebless})")
        for name, img_file, desc in IMAGES:
            bless_one(name, img_file, desc, args.delay, args.rebless)

        print(f"\nChecking {len(IMAGES)} images...")
        passed, failed = [], []
        for name, img_file, _ in IMAGES:
            ok = check_one(name, img_file, args.delay)
            (passed if ok else failed).append(name)
        print(f"\n{'─' * 52}")
        print(f"  PASS {len(passed)}  FAIL {len(failed)}")
        if failed:
            print(f"  failed: {', '.join(failed)}")
            sys.exit(1)


if __name__ == "__main__":
    main()
