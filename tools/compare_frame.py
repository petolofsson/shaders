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
from datetime import date
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

EFFECTS = [
    ("CORRECTIVE", {"CORRECTIVE_STRENGTH": 100, "TONAL_STRENGTH":   0, "CHROMA_STRENGTH":   0, "LOOK_STRENGTH":   0}),
    ("TONAL",      {"CORRECTIVE_STRENGTH":   0, "TONAL_STRENGTH": 100, "CHROMA_STRENGTH":   0, "LOOK_STRENGTH":   0}),
    ("CHROMA",     {"CORRECTIVE_STRENGTH":   0, "TONAL_STRENGTH":   0, "CHROMA_STRENGTH": 100, "LOOK_STRENGTH":   0}),
    ("LOOK",       {"CORRECTIVE_STRENGTH":   0, "TONAL_STRENGTH":   0, "CHROMA_STRENGTH":   0, "LOOK_STRENGTH": 100}),
    ("FULL",       {"CORRECTIVE_STRENGTH": 100, "TONAL_STRENGTH": 100, "CHROMA_STRENGTH": 100, "LOOK_STRENGTH": 100}),
]


def _ae_cv_path(game: str) -> Path:
    p = ROOT / "gamespecific" / game / "shaders" / "creative_values.fx"
    if not p.exists():
        sys.exit(f"Not found: {p}")
    return p


def _ae_read_gates(cv: Path) -> dict:
    text = cv.read_text()
    out = {}
    for name in _AE_GATE_NAMES:
        m = re.search(rf"#define\s+{name}\s+(\d+)", text)
        if not m:
            sys.exit(f"Gate '{name}' not found in {cv}")
        out[name] = int(m.group(1))
    return out


def _ae_write_gates(cv: Path, gates: dict) -> None:
    text = cv.read_text()
    for name, val in gates.items():
        text = re.sub(rf"(#define\s+{name}\s+)\d+", rf"\g<1>{val}", text)
    cv.write_text(text)


def _capture_frames(game: str, config: Path, delay: int) -> "list[dict] | None":
    """Capture all reference frames with current creative_values; return per-frame stats."""
    frames_dir = ROOT / "gamespecific" / game / "analysis" / "reference"
    pngs = sorted(frames_dir.glob("*.png"))
    if not pngs:
        sys.exit(f"No PNGs in {frames_dir}")

    all_stats = []
    proc = _launch_mpv(pngs, config, delay)
    try:
        for i, png in enumerate(pngs):
            print(f"    [{i+1}/{len(pngs)}] {png.name}", end="", flush=True)
            before = _load_png_linear(png)
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

            stats = compute_relative(before, after)
            all_stats.append(stats)
            print(f"  ΔE {stats['mean_de']:.2f}")
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=3)
        except Exception:
            proc.kill()

    return all_stats if all_stats else None


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


def _run_all_effects(game: str, config: Path, delay: int) -> None:
    cv       = _ae_cv_path(game)
    original = _ae_read_gates(cv)
    print(f"compare_frame --all-effects  game={game}  {len(EFFECTS)} effects")
    print(f"Saved gates: {original}\n")

    def _restore(sig=None, frame=None):
        _ae_write_gates(cv, original)
        print("\nGates restored.")
        if sig is not None:
            sys.exit(1)
    signal.signal(signal.SIGINT, _restore)

    results: list[tuple[str, dict]] = []
    try:
        for label, gates in EFFECTS:
            print(f"── {label}  {gates}")
            _ae_write_gates(cv, gates)
            time.sleep(0.1)
            stats = _capture_frames(game, config, delay)
            if stats is None:
                print(f"  No frames captured — skipping.\n")
                continue
            agg = _ae_aggregate(stats)
            results.append((label, agg))
            print(f"  aggregate ΔE {agg['mean_de']:.2f}\n")
    finally:
        _ae_write_gates(cv, original)
        print("Gates restored.\n")

    if not results:
        return

    DEAD = 0.5   # ΔE threshold below which an effect is flagged as silent

    print("─" * 72)
    print(f"\n{_BLD}EFFECT ATTRIBUTION  (each stage isolated from baseline){_RST}")
    print(f"  ΔE < {DEAD} flagged as silent — effect may be miscalibrated or broken\n")

    # Zone table
    print(f"  {'Effect':<14}  {'ΔE':>5}  {'shadows ΔL*/ΔC*':>18}  {'mids ΔL*/ΔC*':>14}  {'highs ΔL*/ΔC*':>14}")
    print("  " + "─" * 70)
    for label, agg in results:
        de   = agg["mean_de"]
        sh   = agg["zones"].get("shadows")
        mi   = agg["zones"].get("midtones")
        hi   = agg["zones"].get("highlights")
        sh_s = f"{sh['dL']:+.1f}/{sh['dC']:+.1f}" if sh else "    —    "
        mi_s = f"{mi['dL']:+.1f}/{mi['dC']:+.1f}" if mi else "    —    "
        hi_s = f"{hi['dL']:+.1f}/{hi['dC']:+.1f}" if hi else "    —    "
        flag = "  ← silent?" if de < DEAD else ""
        sep  = "  ════" if label == "FULL" else ""
        print(f"{sep}  {label:<14}  {_de_fmt(de)}  {sh_s:>18}  {mi_s:>14}  {hi_s:>14}{flag}")

    # Hue band table
    band_names = [e[0] for e in HUE_BANDS]
    print(f"\n  by hue band  (ΔL*/ΔC* per effect, chromatic pixels C*>3)")
    print(f"  {'Effect':<14}  " + "  ".join(f"{b:<12}" for b in band_names))
    print("  " + "─" * (16 + 14 * len(band_names)))
    for label, agg in results:
        cells = []
        for bname in band_names:
            b = agg["hue_bands"].get(bname)
            cells.append(f"{b['dL']:+.1f}/{b['dC']:+.1f}" if b else "   —   ")
        print(f"  {label:<14}  " + "  ".join(f"{c:<12}" for c in cells))
    print()


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
    args = ap.parse_args()

    if args.all_effects:
        game = args.game
        if not game:
            sys.exit("--all-effects requires --game <name>")
        config = ROOT / "gamespecific" / game / f"{game}.conf"
        if not config.exists():
            sys.exit(f"Config not found: {config}")
        _run_all_effects(game, config, args.delay)
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
