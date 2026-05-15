#!/usr/bin/env python3
"""
tools/test_golden.py — Golden image regression tests.

Commands:
    bless <name> <exr>   Promote a capture EXR to golden reference.
    check <name> <exr>   Compare a capture EXR against its golden.
    list                 List all golden references.

Comparison uses two metrics computed from the linear-light R/G/B frame channels:
  - Per-channel MAE in [0,1] linear light
  - Luma histogram chi-squared (BT.709 luma, 128 bins)

On failure: diff PNG written to /tmp/golden_diff_<name>.png

Thresholds are stored per-scene in the JSON sidecar alongside each golden EXR.
Default MAE 0.005 (0.5%) tolerates minor NPC/particle movement while catching
tone and color shifts. Raise per-scene with --mae if the scene has heavy motion.

Requires: numpy, openexr
"""

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path

import numpy as np

try:
    import OpenEXR
    import Imath
except ImportError:
    sys.exit("Missing: pip install openexr")

GOLDEN_DIR = Path(__file__).resolve().parent.parent / "tests" / "golden"
DEFAULT_MAE  = 0.005   # 0.5% linear light
DEFAULT_CHI2 = 0.05    # luma histogram shape distance


def _git_commit() -> str:
    try:
        return subprocess.run(
            ["git", "rev-parse", "--short", "HEAD"],
            capture_output=True, text=True,
            cwd=Path(__file__).resolve().parent.parent,
        ).stdout.strip() or "unknown"
    except Exception:
        return "unknown"


def load_frame(exr_path: Path) -> np.ndarray:
    """Load R/G/B channels as float32 (H, W, 3). Exits on missing channels."""
    f = OpenEXR.InputFile(str(exr_path))
    header = f.header()
    dw = header["dataWindow"]
    W = dw.max.x - dw.min.x + 1
    H = dw.max.y - dw.min.y + 1
    pt = Imath.PixelType(Imath.PixelType.FLOAT)
    chs = {}
    for ch in ("R", "G", "B"):
        if ch not in header["channels"]:
            sys.exit(f"{exr_path}: missing channel '{ch}' — captured with --no-frame?")
        chs[ch] = np.frombuffer(f.channel(ch, pt), dtype=np.float32).reshape(H, W)
    return np.stack([chs["R"], chs["G"], chs["B"]], axis=2)


def luma_histogram(frame: np.ndarray, bins: int = 128) -> np.ndarray:
    """Normalized BT.709 luma histogram in linear light."""
    luma = 0.2126 * frame[:, :, 0] + 0.7152 * frame[:, :, 1] + 0.0722 * frame[:, :, 2]
    hist, _ = np.histogram(luma.ravel(), bins=bins, range=(0.0, 1.0))
    total = hist.sum()
    return hist.astype(np.float64) / max(total, 1)


def chi_squared(a: np.ndarray, b: np.ndarray) -> float:
    return float(np.sum((a - b) ** 2 / (a + b + 1e-12)))


def write_diff_png(golden_path: Path, current_path: Path, name: str) -> Path:
    out = Path(f"/tmp/golden_diff_{name}.png")
    subprocess.run(
        ["compare", "-metric", "MAE", str(golden_path), str(current_path), str(out)],
        capture_output=True,
    )
    return out


# ── Commands ──────────────────────────────────────────────────────────────────

def cmd_bless(name: str, exr_path: Path, desc: str, mae: float, chi2: float) -> None:
    GOLDEN_DIR.mkdir(parents=True, exist_ok=True)
    frame = load_frame(exr_path)
    H, W, _ = frame.shape
    commit = _git_commit()

    dst = GOLDEN_DIR / f"{name}.exr"
    shutil.copy2(exr_path, dst)

    meta = {
        "name":        name,
        "description": desc,
        "git_commit":  commit,
        "source":      exr_path.name,
        "resolution":  [W, H],
        "thresholds":  {"mae": mae, "hist_chi2": chi2},
    }
    (GOLDEN_DIR / f"{name}.json").write_text(json.dumps(meta, indent=2))

    print(f"Blessed '{name}'  {W}×{H}  commit {commit}")
    print(f"  thresholds: MAE ≤ {mae:.4f}  hist χ² ≤ {chi2:.4f}")
    print(f"  → {dst}")


def cmd_check(name: str, exr_path: Path) -> bool:
    golden_exr  = GOLDEN_DIR / f"{name}.exr"
    golden_json = GOLDEN_DIR / f"{name}.json"
    if not golden_exr.exists():
        sys.exit(f"No golden for '{name}'. Run: test_golden bless {name} <exr>")

    meta     = json.loads(golden_json.read_text()) if golden_json.exists() else {}
    thr      = meta.get("thresholds", {})
    mae_thr  = thr.get("mae",       DEFAULT_MAE)
    chi2_thr = thr.get("hist_chi2", DEFAULT_CHI2)

    print(f"check '{name}'")
    print(f"  golden:  {golden_exr.name}  [{meta.get('git_commit', '?')}]")
    print(f"  current: {exr_path.name}")

    g = load_frame(golden_exr)
    c = load_frame(exr_path)

    if g.shape != c.shape:
        print(f"  FAIL  resolution mismatch: golden {g.shape[1]}×{g.shape[0]}  current {c.shape[1]}×{c.shape[0]}")
        return False

    diff  = np.abs(g - c)
    mae   = float(diff.mean())
    mae_r = float(diff[:, :, 0].mean())
    mae_g = float(diff[:, :, 1].mean())
    mae_b = float(diff[:, :, 2].mean())
    px_ok = mae <= mae_thr

    chi2    = chi_squared(luma_histogram(g), luma_histogram(c))
    hist_ok = chi2 <= chi2_thr

    px_tag   = "PASS" if px_ok   else "FAIL"
    hist_tag = "PASS" if hist_ok else "FAIL"

    print(f"  pixel MAE  {mae:.5f}  (R {mae_r:.5f}  G {mae_g:.5f}  B {mae_b:.5f})  thr {mae_thr:.5f}  [{px_tag}]")
    print(f"  hist  χ²   {chi2:.5f}  thr {chi2_thr:.5f}  [{hist_tag}]")

    passed = px_ok and hist_ok
    if not passed:
        diff_path = write_diff_png(golden_exr, exr_path, name)
        print(f"  diff → {diff_path}")
    print(f"  {'PASS' if passed else 'FAIL'}")
    return passed


def cmd_list() -> None:
    jsons = sorted(GOLDEN_DIR.glob("*.json")) if GOLDEN_DIR.exists() else []
    if not jsons:
        print("No golden references. Run: test_golden bless <name> <exr>")
        return
    print(f"{'name':<24} {'resolution':<13} {'commit':<9} {'mae_thr':<9} description")
    print("─" * 76)
    for jp in jsons:
        m    = json.loads(jp.read_text())
        W, H = m.get("resolution", ["?", "?"])
        print(
            f"{m.get('name', jp.stem):<24} {W}×{H!s:<10} "
            f"{m.get('git_commit', '?'):<9} "
            f"{m.get('thresholds', {}).get('mae', DEFAULT_MAE):<9.4f} "
            f"{m.get('description', '')}"
        )


# ── Entry ─────────────────────────────────────────────────────────────────────

def main() -> None:
    ap = argparse.ArgumentParser(description="Golden image regression tests")
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("bless", help="Promote a capture EXR to golden reference")
    p.add_argument("name")
    p.add_argument("exr", nargs="?",  help="Capture EXR path (omit to use most recent capture)")
    p.add_argument("--desc",      default="",         help="Scene description")
    p.add_argument("--mae",       type=float,          default=DEFAULT_MAE,  help="Pixel MAE threshold [0,1]")
    p.add_argument("--hist-chi2", type=float,          default=DEFAULT_CHI2, help="Luma histogram χ² threshold")

    p = sub.add_parser("check", help="Compare a capture EXR against its golden")
    p.add_argument("name")
    p.add_argument("exr", nargs="?", help="Capture EXR path (omit to use most recent capture)")

    sub.add_parser("list", help="List all golden references")

    args = ap.parse_args()
    if args.cmd == "bless":
        if args.exr:
            exr_path = Path(args.exr)
        else:
            candidates = sorted(
                (Path(__file__).resolve().parent.parent / "gamespecific").glob("*/captures/*.exr"),
                key=lambda p: p.stat().st_mtime,
            )
            if not candidates:
                sys.exit("No captures found. Run 'capture' first.")
            exr_path = candidates[-1]
            print(f"Using most recent capture: {exr_path.name}")
        cmd_bless(args.name, exr_path, args.desc, args.mae, args.hist_chi2)
    elif args.cmd == "check":
        if args.exr:
            exr_path = Path(args.exr)
        else:
            candidates = sorted(
                (Path(__file__).resolve().parent.parent / "gamespecific").glob("*/captures/*.exr"),
                key=lambda p: p.stat().st_mtime,
            )
            if not candidates:
                sys.exit("No captures found. Run 'capture' first.")
            exr_path = candidates[-1]
            print(f"Using most recent capture: {exr_path.name}")
        sys.exit(0 if cmd_check(args.name, exr_path) else 1)
    elif args.cmd == "list":
        cmd_list()


if __name__ == "__main__":
    main()
