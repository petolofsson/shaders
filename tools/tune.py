#!/usr/bin/env python3
"""
tools/tune.py — Live shader tuning against representative game frames.

Place PNG screenshots of the game (without vkBasalt) in:
    gamespecific/<game>/analysis/reference/

This tool launches mpv with vkBasalt on all frames as a playlist and
auto-restarts mpv whenever creative_values.fx is saved on disk.

Usage:
    tune [--game arc_raiders] [--delay N] [--no-watch]

Controls in mpv:
    > (Shift+.)    next frame
    < (Shift+,)    previous frame
    q              quit mpv

Workflow:
    1. Run game with ENABLE_VKBASALT=0, take grim screenshots, save as PNG.
    2. Copy PNGs into gamespecific/<game>/analysis/reference/.
    3. Run: tune
    4. Edit creative_values.fx, save — mpv restarts automatically (~3s).
    5. Validate final result in-game.
"""

import argparse
import json
import os
import socket
import subprocess
import sys
import time
from pathlib import Path

ROOT   = Path(__file__).resolve().parent.parent
SOCK   = Path("/tmp/mpv-tune.sock")
SCREEN = 0  # KDE Wayland: primary (right, DP-2) = index 0


def find_frames(game: str) -> list:
    d = ROOT / "gamespecific" / game / "analysis" / "reference"
    if not d.exists():
        sys.exit(
            f"No reference directory: {d}\n"
            f"Create it and add PNG screenshots of the game (without vkBasalt)."
        )
    frames = sorted(d.glob("*.png")) + sorted(d.glob("*.jpg")) + sorted(d.glob("*.exr"))
    if not frames:
        sys.exit(
            f"No frames found in {d}\n"
            f"Add PNG screenshots of the game (run without ENABLE_VKBASALT=1)."
        )
    return frames


def cv_path(game: str) -> Path:
    return ROOT / "gamespecific" / game / "shaders" / "creative_values.fx"


def conf_path(game: str) -> Path:
    return ROOT / "gamespecific" / game / f"{game}.conf"


def mpv_get(prop: str):
    """Query a property from the running mpv IPC socket. Returns None on failure."""
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(0.5)
        s.connect(str(SOCK))
        s.send((json.dumps({"command": ["get_property", prop]}) + "\n").encode())
        data = s.recv(4096)
        s.close()
        return json.loads(data).get("data")
    except Exception:
        return None


def launch(frames: list, config: Path, start: int, delay: int) -> subprocess.Popen:
    SOCK.unlink(missing_ok=True)
    env = os.environ.copy()
    env["ENABLE_VKBASALT"]      = "1"
    env["VKBASALT_CONFIG_FILE"] = str(config)

    cmd = [
        "mpv",
        "--vo=gpu", "--gpu-api=vulkan",
        "--loop-playlist=inf", "--fs",
        f"--screen={SCREEN}",
        f"--fs-screen={SCREEN}",
        f"--input-ipc-server={SOCK}",
        f"--playlist-start={start}",
        "--image-display-duration=inf",
    ] + [str(f) for f in frames]

    proc = subprocess.Popen(cmd, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print(f"  mpv pid {proc.pid} — compiling SPIR-V, waiting {delay}s...")
    time.sleep(delay)
    if proc.poll() is not None:
        sys.exit("mpv exited early — check /tmp/vkbasalt.log")
    print(f"  ready  ({len(frames)} frame(s) in playlist)")
    return proc


def main() -> None:
    ap = argparse.ArgumentParser(description="Live shader tuning with auto-reload on file save")
    ap.add_argument("--game",     default="arc_raiders", help="Game name (default: arc_raiders)")
    ap.add_argument("--delay",    type=int, default=3,   help="Seconds to wait for SPIR-V compile (default: 3)")
    ap.add_argument("--no-watch", action="store_true",   help="Disable file watcher (manual restart only)")
    args = ap.parse_args()

    frames = find_frames(args.game)
    config = conf_path(args.game)
    cv     = cv_path(args.game)

    if not config.exists():
        sys.exit(f"Config not found: {config}")

    print(f"tune — '{args.game}'  {len(frames)} reference frame(s):")
    for f in frames:
        print(f"  {f.name}")
    print()

    if args.no_watch:
        print("Watch disabled — restart tune manually after editing creative_values.fx")
    else:
        print(f"Watching: {cv.relative_to(ROOT)}")
        print("Edit + save → mpv restarts automatically")
    print("In mpv: > / < to cycle frames  |  q to quit")
    print()

    last_mtime = cv.stat().st_mtime if cv.exists() else 0.0
    proc = launch(frames, config, start=0, delay=args.delay)

    if args.no_watch:
        proc.wait()
        return

    try:
        while True:
            time.sleep(0.4)

            if proc.poll() is not None:
                print("mpv exited.")
                break

            if not cv.exists():
                continue

            mtime = cv.stat().st_mtime
            if mtime <= last_mtime:
                continue

            # File saved — remember playlist position and restart
            saved_pos = mpv_get("playlist-pos") or 0
            last_mtime = mtime

            print(f"\ncreative_values.fx saved — restarting at frame {saved_pos}...")
            proc.terminate()
            try:
                proc.wait(timeout=4)
            except subprocess.TimeoutExpired:
                proc.kill()
            time.sleep(0.3)

            proc = launch(frames, config, start=saved_pos, delay=args.delay)

    except KeyboardInterrupt:
        proc.terminate()
        print("\nbye")


if __name__ == "__main__":
    main()
