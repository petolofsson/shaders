#!/usr/bin/env python3
"""
tools/stage_isolate.py — Additive stage-isolation analysis.

Runs four cumulative stage configurations:
  1. CORRECTIVE only
  2. +TONAL
  3. +CHROMA
  4. +LOOK  (full pipeline)

Each stage launches mpv once for all frames (single SPIR-V compile) and
navigates via IPC — much faster than per-frame restarts.

At the end, writes grade_callsheet.txt to gamespecific/<game>/ combining
creative_values.fx, compare_frame aggregate (if available), and stage data.

Usage:
    stage_isolate --game gzw [--delay 5]

Gate values in creative_values.fx are saved and fully restored after the
run, even if interrupted.
"""

import argparse
import json
import re
import signal
import sys
from datetime import date
from pathlib import Path

import numpy as np

try:
    import OpenEXR  # noqa: F401
except ImportError:
    sys.exit("Missing: pip install openexr")

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(Path(__file__).resolve().parent))

from compare_frame import (  # noqa: E402
    _load_png_linear, _launch_mpv, _mpv_cmd, _goto_frame,
    _save_exr, GAME_MONITOR,
)
from analyze_delta import compute_relative, _de_fmt, _BLD, _RST, HUE_BANDS  # noqa: E402
from capture import take_screenshot  # noqa: E402

import shutil
import tempfile
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

            tmp       = Path(tempfile.mkdtemp(prefix="stage_isolate_"))
            after_png = tmp / f"{png.stem}_after.png"
            take_screenshot(after_png)

            if not after_png.exists() or after_png.stat().st_size == 0:
                print("  SKIP (capture failed)")
                shutil.rmtree(tmp, ignore_errors=True)
                continue

            after = _load_png_linear(after_png)
            bh, bw = before.shape[:2]
            ah, aw = after.shape[:2]
            if aw > bw:
                x = aw // 2 if GAME_MONITOR == "right" else 0
                after = after[:, x:x + bw, :]
            shutil.rmtree(tmp, ignore_errors=True)

            if before.shape != after.shape:
                print(f"  SKIP (resolution mismatch)")
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


def _aggregate(all_stats: "list[dict]") -> dict:
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


# ── Report ────────────────────────────────────────────────────────────────────

def _print_report(results: "list[tuple[str, dict]]") -> None:
    print()
    print("─" * 72)
    print(f"\n{_BLD}STAGE ISOLATION REPORT{_RST}\n")

    print(f"  {'Stage':<14}  {'Overall ΔE':>10}  {'shadows ΔL*/ΔC*':>17}  {'mids ΔL*/ΔC*':>14}  {'highs ΔL*/ΔC*':>14}")
    print("  " + "─" * 72)
    prev_de = 0.0
    for label, agg in results:
        de    = agg["mean_de"]
        inc   = de - prev_de
        inc_s = f"(+{inc:.2f})" if prev_de > 0 else ""
        prev_de = de
        sh = agg["zones"].get("shadows")
        mi = agg["zones"].get("midtones")
        hi = agg["zones"].get("highlights")
        sh_s = f"{sh['dL']:+.1f}/{sh['dC']:+.1f}" if sh else "  —  "
        mi_s = f"{mi['dL']:+.1f}/{mi['dC']:+.1f}" if mi else "  —  "
        hi_s = f"{hi['dL']:+.1f}/{hi['dC']:+.1f}" if hi else "  —  "
        print(f"  {label:<14}  {_de_fmt(de)} {inc_s:<8}  {sh_s:>17}  {mi_s:>14}  {hi_s:>14}")

    print(f"\n  {_BLD}by hue band  (ΔL* / ΔC*){_RST}")
    band_names = [e[0] for e in HUE_BANDS]
    print(f"  {'Stage':<14}  " + "  ".join(f"{b:<13}" for b in band_names))
    print("  " + "─" * (16 + 15 * len(band_names)))
    for label, agg in results:
        cells = []
        for bname in band_names:
            b = agg["hue_bands"].get(bname)
            cells.append(f"{b['dL']:+.1f}/{b['dC']:+.1f}" if b else "  —  ")
        print(f"  {label:<14}  " + "  ".join(f"{c:<13}" for c in cells))

    print()


# ── Call sheet ────────────────────────────────────────────────────────────────

def _write_callsheet(game: str, results: "list[tuple[str, dict]]") -> None:
    data_dir = ROOT / "gamespecific" / game
    cv_path  = data_dir / "shaders" / "creative_values.fx"
    agg_path = data_dir / "compare_agg.json"

    agg = json.loads(agg_path.read_text()) if agg_path.exists() else None

    sep = "=" * 72
    lines = [
        f"GRADE CALL SHEET — {game} — {date.today()}",
        sep,
        "",
        "Paste into a web AI with: 'make this look more like [director / film / stock]'",
        "The knob comments explain every parameter. The analysis shows what the grade",
        "is currently doing. The AI can suggest specific value changes.",
        "",
        sep,
        "SCENE DESCRIPTION  (fill in before sharing with an AI)",
        sep,
        "",
        "# Lighting: [e.g. 'overcast jungle canopy, dappled midday light through leaves']",
        "# Raw palette: [e.g. 'warm orange midtones, desaturated foliage, deep blue shadows']",
        "# Subject: [e.g. 'dense jungle canopy, player character at midground, distant village']",
        "",
        sep,
        "REFERENCE LOOK  (fill in before sharing with an AI)",
        sep,
        "",
        "# Reference still: [filename or URL — e.g. 'gzw_frame_001.png' or a film still]",
        "# Film reference: [e.g. 'Sicario (2015) — Deakins — golden dust, cool blue shadows']",
        "# Target descriptors: [e.g. 'lifted blacks / warm midtone rolloff / desaturated highlights / visible grain']",
        "",
        sep,
        "CREATIVE VALUES  (knob comments explain units, ranges, and physical meaning)",
        sep,
        "",
        cv_path.read_text().rstrip(),
    ]

    if agg:
        lines += [
            "",
            sep,
            f"ANALYSIS — raw game vs graded ({agg['n_frames']} frames, Oklab ΔE_oklab)",
            sep,
            "",
            "ΔL* = luma shift  ΔC* = chroma shift  Δh° = hue rotation  ΔE = perceptual distance",
            "Scale: <1 imperceptible  1–3 minor  3–6 visible  >6 gross",
            "",
            "TONAL ZONES:",
        ]
        for zone in ("shadows", "midtones", "highlights"):
            z = agg["zones"].get(zone)
            if not z:
                continue
            dh_s = f"  Δh° {z['dh']:+.1f}°" if z.get("dh") is not None else ""
            lines.append(f"  {zone:<12}  ΔL* {z['dL']:+.1f}  ΔC* {z['dC']:+.1f}{dh_s}  ΔE {z['mean_de']:.2f}")

        lines += ["", "HUE BANDS (chromatic pixels only, Oklab C* > 3):"]
        for bname, b in agg["hue_bands"].items():
            if not b:
                continue
            dh_s = f"  Δh° {b['dh']:+.1f}°" if b.get("dh") is not None else ""
            lines.append(f"  {bname:<8}  ΔL* {b['dL']:+.1f}  ΔC* {b['dC']:+.1f}{dh_s}  ΔE {b['mean_de']:.2f}")

        ch = agg.get("channels", {})
        if ch:
            lines += [
                "",
                f"CHANNEL PERCENTILES  (linear light 0–1, averaged {agg['n_frames']} frames)",
                "  Warm cast = R.p50 > B.p50.  Cool = B.p50 > R.p50.  Balanced = R ≈ G ≈ B.",
                "",
                f"  {'Ch':<3}  {'p5':>6}  {'p50':>6}  {'p95':>6}    {'p5':>6}  {'p50':>6}  {'p95':>6}  {'Δp50':>6}",
                f"  {'':3}  {'── Raw ──':>20}    {'── Graded ──':>20}",
            ]
            for c in ("R", "G", "B"):
                r, g = ch[c]["raw"], ch[c]["grad"]
                lines.append(
                    f"  {c:<3}  {r[0]:6.3f}  {r[1]:6.3f}  {r[2]:6.3f}    {g[0]:6.3f}  {g[1]:6.3f}  {g[2]:6.3f}  {g[1]-r[1]:+6.3f}"
                )

    lines += [
        "",
        sep,
        "DELTA LEGEND",
        sep,
        "",
        "  ΔL* > 0 = brighter in that zone    → SHADOWS / HIGHLIGHTS / EXPOSURE / LOCAL_CONTRAST",
        "  ΔL* < 0 = darker                   → same knobs, opposite direction",
        "  ΔC* > 0 = more saturated            → SATURATION / SAT_* / VIBRANCE",
        "  Δh° > 0 = hue shifted toward yellow → HUE_* / PRINTER_R/G/B / SHADOW_TEMP",
        "  ΔE < 1.0 imperceptible   1–3 subtle   3–6 visible   > 6 strong",
        "  Channel p5 = shadow floor   p50 = midtone anchor   p95 = highlight ceiling",
        "",
        sep,
        "WHAT THE GRADE IS DOING  (plain language per stage)",
        sep,
        "",
    ]

    prev_de = 0.0
    contribs = []
    for label, agg_s in results:
        inc = agg_s["mean_de"] - prev_de
        contribs.append((label, inc, agg_s))
        prev_de = agg_s["mean_de"]

    largest_label = max(contribs, key=lambda x: x[1])[0]

    for label, inc, agg_s in contribs:
        sh = agg_s["zones"].get("shadows")
        mi = agg_s["zones"].get("midtones")
        hi = agg_s["zones"].get("highlights")
        if inc > 0.05:
            tag = f"+{inc:.2f} ΔE"
            if label == largest_label:
                tag += "  ← largest contributor, most tuning headroom here"
        elif inc < -0.05:
            tag = f"−{abs(inc):.2f} ΔE, reduces perceptual distance (correction working)"
        else:
            tag = f"{inc:+.2f} ΔE, minimal change"
        zone_parts = []
        for zlabel, z in (("shadows", sh), ("mids", mi), ("highs", hi)):
            if z:
                zone_parts.append(f"{zlabel} {z['dL']:+.1f} ΔL*")
        lines.append(f"  {label:<14}  {tag}")
        if zone_parts:
            lines.append(f"  {'':14}  tonal: {' / '.join(zone_parts)}")
        lines.append("")

    lines += [
        "",
        sep,
        "STAGE ATTRIBUTION  (cumulative — each row adds one stage to the previous)",
        sep,
        "",
        "Format: ΔL* / ΔC* per zone. (+increment) shows each stage's added ΔE.",
        "",
        f"  {'Stage':<14}  {'ΔE':>5}           {'shadows ΔL*/ΔC*':>17}  {'mids ΔL*/ΔC*':>14}  {'highs ΔL*/ΔC*':>14}",
        "  " + "─" * 68,
    ]
    prev_de = 0.0
    for label, agg_s in results:
        de    = agg_s["mean_de"]
        inc   = de - prev_de
        inc_s = f"(+{inc:.2f})" if prev_de > 0 else "      "
        prev_de = de
        sh = agg_s["zones"].get("shadows")
        mi = agg_s["zones"].get("midtones")
        hi = agg_s["zones"].get("highlights")
        sh_s = f"{sh['dL']:+.1f}/{sh['dC']:+.1f}" if sh else "  —  "
        mi_s = f"{mi['dL']:+.1f}/{mi['dC']:+.1f}" if mi else "  —  "
        hi_s = f"{hi['dL']:+.1f}/{hi['dC']:+.1f}" if hi else "  —  "
        lines.append(f"  {label:<14}  {de:5.2f} {inc_s}  {sh_s:>17}  {mi_s:>14}  {hi_s:>14}")

    band_names = [e[0] for e in HUE_BANDS]
    lines += [
        "",
        "BY HUE BAND  (ΔL* / ΔC* per stage):",
        f"  {'Stage':<14}  " + "  ".join(f"{b:<12}" for b in band_names),
        "  " + "─" * (16 + 14 * len(band_names)),
    ]
    for label, agg_s in results:
        cells = []
        for bname in band_names:
            b = agg_s["hue_bands"].get(bname)
            cells.append(f"{b['dL']:+.1f}/{b['dC']:+.1f}" if b else "  —  ")
        lines.append(f"  {label:<14}  " + "  ".join(f"{c:<12}" for c in cells))

    out = data_dir / "grade_callsheet.txt"
    out.write_text("\n".join(lines) + "\n")
    print(f"  call sheet → {out.relative_to(ROOT)}")

    analysis_dir = data_dir / "analysis" / str(date.today())
    analysis_dir.mkdir(parents=True, exist_ok=True)
    arch = analysis_dir / "grade_callsheet.txt"
    arch.write_text("\n".join(lines) + "\n")
    print(f"  archive    → {arch.relative_to(ROOT)}")


# ── Main ──────────────────────────────────────────────────────────────────────

def main() -> None:
    ap = argparse.ArgumentParser(
        description="Additive stage-isolation analysis across all reference frames",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="Example:\n  stage_isolate --game gzw --delay 5",
    )
    ap.add_argument("--game",  required=True, help="Game name (e.g. gzw)")
    ap.add_argument("--delay", type=int, default=2,
                    help="Seconds to wait for SPIR-V compile per stage (default: 2)")
    args = ap.parse_args()

    cv     = _cv_path(args.game)
    config = ROOT / "gamespecific" / args.game / f"{args.game}.conf"
    if not config.exists():
        sys.exit(f"Config not found: {config}")

    original_gates = _read_gates(cv)
    print(f"stage_isolate  game={args.game}  {len(STAGES)} stages")
    print(f"Original gates: { {k: original_gates[k] for k in GATE_NAMES} }")

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
            time.sleep(0.1)

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
        _write_callsheet(args.game, results)


if __name__ == "__main__":
    main()
