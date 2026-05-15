#!/usr/bin/env python3
"""
tools/stage_isolate.py — Additive stage-isolation analysis.

Runs compare_frame --all four times, enabling stages cumulatively:
  1. CORRECTIVE only
  2. +TONAL
  3. +CHROMA
  4. +LOOK  (full pipeline)

Prints a side-by-side attribution table so you can see exactly what each
stage contributes in the context of the stages that precede it.

Usage:
    stage_isolate --game gzw [--delay 5]

The stage gate values in creative_values.fx are saved and fully restored
after the run, even if the script is interrupted.
"""

import argparse
import re
import signal
import sys
from pathlib import Path

import numpy as np

try:
    import OpenEXR  # noqa: F401 — validates dep before any work starts
except ImportError:
    sys.exit("Missing: pip install openexr")

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(Path(__file__).resolve().parent))

from compare_frame import _load_png_linear, _launch_mpv, _save_exr  # noqa: E402
from analyze_delta import compute_relative, _de_fmt, _BLD, _RST, HUE_BANDS  # noqa: E402

import subprocess
import tempfile
import shutil
import time

# ── Stage gate definitions ────────────────────────────────────────────────────

STAGES = [
    ("CORRECTIVE", {"CORRECTIVE_STRENGTH": 100, "TONAL_STRENGTH": 0,   "CHROMA_STRENGTH": 0,   "LOOK_STRENGTH": 0}),
    ("+TONAL",     {"CORRECTIVE_STRENGTH": 100, "TONAL_STRENGTH": 100,  "CHROMA_STRENGTH": 0,   "LOOK_STRENGTH": 0}),
    ("+CHROMA",    {"CORRECTIVE_STRENGTH": 100, "TONAL_STRENGTH": 100,  "CHROMA_STRENGTH": 100, "LOOK_STRENGTH": 0}),
    ("+LOOK",      {"CORRECTIVE_STRENGTH": 100, "TONAL_STRENGTH": 100,  "CHROMA_STRENGTH": 100, "LOOK_STRENGTH": 100}),
]

GATE_NAMES = ["CORRECTIVE_STRENGTH", "TONAL_STRENGTH", "CHROMA_STRENGTH", "LOOK_STRENGTH"]
_GATE_RE   = re.compile(r"(#define\s+({gates})\s+)\d+".format(gates="|".join(GATE_NAMES)))


# ── creative_values.fx gate manipulation ─────────────────────────────────────

def _cv_path(game: str) -> Path:
    p = ROOT / "gamespecific" / game / "shaders" / "creative_values.fx"
    if not p.exists():
        sys.exit(f"Not found: {p}")
    return p


def _read_gates(cv: Path) -> dict:
    text = cv.read_text()
    out = {}
    for name in GATE_NAMES:
        m = re.search(rf"#define\s+{name}\s+(\d+)", text)
        if not m:
            sys.exit(f"Gate '{name}' not found in {cv}")
        out[name] = int(m.group(1))
    return out


def _write_gates(cv: Path, gates: dict) -> None:
    text = cv.read_text()
    for name, val in gates.items():
        text = re.sub(rf"(#define\s+{name}\s+)\d+", rf"\g<1>{val}", text)
    cv.write_text(text)


# ── Batch capture for one stage configuration ─────────────────────────────────

def _run_stage(game: str, config: Path, delay: int) -> "list[dict] | None":
    frames_dir = ROOT / "gamespecific" / game / "reference_frames"
    pngs = sorted(frames_dir.glob("*.png"))
    if not pngs:
        sys.exit(f"No PNGs in {frames_dir}")

    all_stats = []
    for i, png in enumerate(pngs):
        print(f"    [{i+1}/{len(pngs)}] {png.name}", end="", flush=True)
        before = _load_png_linear(png)

        tmp      = Path(tempfile.mkdtemp(prefix="stage_isolate_"))
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
            print("  SKIP (capture failed)")
            shutil.rmtree(tmp, ignore_errors=True)
            continue

        after = _load_png_linear(after_png)
        shutil.rmtree(tmp, ignore_errors=True)

        if before.shape != after.shape:
            print(f"  SKIP (resolution mismatch)")
            continue

        stats = compute_relative(before, after)
        all_stats.append(stats)
        print(f"  ΔE {stats['mean_de']:.2f}")

    return all_stats if all_stats else None


def _aggregate(all_stats: "list[dict]") -> dict:
    """Average stats across frames."""
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
        "mean_de": sum(s["mean_de"] for s in all_stats) / n,
        "zones":   {lbl: avg_zone(lbl) for lbl in ("shadows", "midtones", "highlights")},
        "hue_bands": {e[0]: avg_band(e[0]) for e in HUE_BANDS},
    }


# ── Report ────────────────────────────────────────────────────────────────────

def _print_report(results: "list[tuple[str, dict]]") -> None:
    print()
    print("─" * 72)
    print(f"\n{_BLD}STAGE ISOLATION REPORT{_RST}\n")

    # Overall ΔE row
    print(f"  {'Stage':<14}  {'Overall ΔE':>10}  {'shadows ΔL*/ΔC*':>17}  {'mids ΔL*/ΔC*':>14}  {'highs ΔL*/ΔC*':>14}")
    print("  " + "─" * 72)
    prev_de = 0.0
    for label, agg in results:
        de  = agg["mean_de"]
        inc = de - prev_de
        inc_s = f"(+{inc:.2f})" if prev_de > 0 else ""
        prev_de = de

        sh = agg["zones"].get("shadows")
        mi = agg["zones"].get("midtones")
        hi = agg["zones"].get("highlights")
        sh_s = f"{sh['dL']:+.1f}/{sh['dC']:+.1f}" if sh else "  —  "
        mi_s = f"{mi['dL']:+.1f}/{mi['dC']:+.1f}" if mi else "  —  "
        hi_s = f"{hi['dL']:+.1f}/{hi['dC']:+.1f}" if hi else "  —  "

        print(f"  {label:<14}  {_de_fmt(de)} {inc_s:<8}  {sh_s:>17}  {mi_s:>14}  {hi_s:>14}")

    # Hue band table
    print(f"\n  {_BLD}by hue band  (ΔL* / ΔC*){_RST}")
    band_names = [e[0] for e in HUE_BANDS]
    header = f"  {'Stage':<14}  " + "  ".join(f"{b:<13}" for b in band_names)
    print(header)
    print("  " + "─" * (16 + 15 * len(band_names)))
    for label, agg in results:
        cells = []
        for bname in band_names:
            b = agg["hue_bands"].get(bname)
            cells.append(f"{b['dL']:+.1f}/{b['dC']:+.1f}" if b else "  —  ")
        print(f"  {label:<14}  " + "  ".join(f"{c:<13}" for c in cells))

    print()


# ── Main ──────────────────────────────────────────────────────────────────────

def main() -> None:
    ap = argparse.ArgumentParser(
        description="Additive stage-isolation analysis across all reference frames",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="Example:\n  stage_isolate --game gzw --delay 5",
    )
    ap.add_argument("--game",  required=True, help="Game name (e.g. gzw)")
    ap.add_argument("--delay", type=int, default=3,
                    help="Seconds to wait for SPIR-V compile per frame (default: 3)")
    args = ap.parse_args()

    cv     = _cv_path(args.game)
    config = ROOT / "gamespecific" / args.game / f"{args.game}.conf"
    if not config.exists():
        sys.exit(f"Config not found: {config}")

    original_gates = _read_gates(cv)
    print(f"stage_isolate  game={args.game}  {len(STAGES)} stages")
    print(f"Original gates: { {k: original_gates[k] for k in GATE_NAMES} }")

    # Restore on Ctrl-C or normal exit
    def _restore(sig=None, frame=None):
        _write_gates(cv, original_gates)
        print("\nGates restored.")
        if sig is not None:
            sys.exit(1)
    signal.signal(signal.SIGINT, _restore)

    results = []
    try:
        for stage_label, gates in STAGES:
            print(f"\n── {stage_label}  gates={gates}")
            _write_gates(cv, gates)
            time.sleep(0.1)  # let filesystem flush before mpv picks it up

            all_stats = _run_stage(args.game, config, args.delay)
            if all_stats is None:
                print(f"  No frames captured for {stage_label} — aborting.")
                break
            agg = _aggregate(all_stats)
            results.append((stage_label, agg))
            print(f"  aggregate ΔE {agg['mean_de']:.2f}  ({len(all_stats)} frames)")
    finally:
        _write_gates(cv, original_gates)
        print(f"\nGates restored to original values.")

    if results:
        _print_report(results)


if __name__ == "__main__":
    main()
