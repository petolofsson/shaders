#!/usr/bin/env python3
"""
tools/analyze_delta.py — Perceptual color delta analysis (ΔE_oklab) between EXR captures.

Modes:
    analyze_delta before.exr after.exr        relative: ΔE_oklab per zone + hue band
    analyze_delta --colorchecker [exr]        absolute: ΔE_oklab per patch vs. BabelColor D65
                                              (omit exr to use most recent capture)

ΔE_oklab scale (Euclidean Oklab ×100 — comparable to CIEDE2000):
    < 1     imperceptible to most observers
    1 – 3   acceptable / minor difference
    3 – 6   clearly visible
    > 6     gross error

Hue bands use Oklab hue angle atan2(b,a) in degrees — matches hue_bands.fxh exactly.
Band centers: red ~30°, yellow ~110°, green ~143°, cyan ~195°, blue ~265°, magenta ~329°.

Requires: numpy, openexr
"""

import argparse
import sys
from pathlib import Path

import numpy as np

try:
    import OpenEXR
    import Imath
except ImportError:
    sys.exit("Missing: pip install openexr")

CAPTURES_DIR = Path(__file__).resolve().parent.parent / "captures"

# BabelColor sRGB D65 reference (8-bit) — matches make_test_images.py exactly
CC_PATCHES = [
    ("Dark skin",      115,  82,  68),
    ("Light skin",     194, 150, 130),
    ("Blue sky",        98, 122, 157),
    ("Foliage",         87, 108,  67),
    ("Blue flower",    133, 128, 177),
    ("Bluish green",   103, 189, 170),
    ("Orange",         214, 126,  44),
    ("Purplish blue",   80,  91, 166),
    ("Moderate red",   193,  90,  99),
    ("Purple",          94,  60, 108),
    ("Yellow green",   157, 188,  64),
    ("Orange yellow",  224, 163,  46),
    ("Blue",            56,  61, 150),
    ("Green",           70, 148,  73),
    ("Red",            175,  54,  60),
    ("Yellow",         231, 199,  31),
    ("Magenta",        187,  86, 149),
    ("Cyan",             8, 133, 161),
    ("White 9.5",      243, 243, 242),
    ("Neutral 8",      200, 200, 200),
    ("Neutral 6.5",    160, 160, 160),
    ("Neutral 5",      122, 122, 121),
    ("Neutral 3.5",     85,  85,  85),
    ("Black 2",         52,  52,  52),
]

# ColorChecker layout — must match make_test_images.py
_W, _H          = 2560, 1440
_COLS, _ROWS    = 6, 4
_MARGIN, _GAP   = 80, 20
_PW = (_W - 2 * _MARGIN - (_COLS - 1) * _GAP) // _COLS   # 383 px
_PH = (_H - 2 * _MARGIN - (_ROWS - 1) * _GAP) // _ROWS   # 305 px
_SAMPLE = 40   # center-sample square per patch (pixels)

# 6 hue bands in Oklab hue angle: atan2(b, a) in [0, 360°)
# Centers from hue_bands.fxh: red ~30°, yellow ~110°, green ~143°,
#                              cyan ~195°, blue ~265°, magenta ~329°.
# Boundaries at midpoints between adjacent primaries.
HUE_BANDS = [
    ("red",     350, 360,   0, 70),   # wraps through 0°; pure red ~30°
    ("yellow",   70, 126),            # pure yellow ~110°
    ("green",   126, 169),            # pure green ~143°
    ("cyan",    169, 230),            # pure cyan ~195°
    ("blue",    230, 297),            # pure blue ~265°
    ("magenta", 297, 350),            # pure magenta ~329°
]


# ── Color math (no extra deps) ─────────────────────────────────────────────────

def _srgb_to_linear(v: np.ndarray) -> np.ndarray:
    return np.where(v <= 0.04045, v / 12.92, ((v + 0.055) / 1.055) ** 2.4)


def _linear_rgb_to_oklab(rgb: np.ndarray) -> np.ndarray:
    """Linear sRGB [0, 1] → Oklab scaled ×100. Input: (..., 3) float.

    L in [0, 100]. a, b in approximately [-40, +40].
    Hue angle = atan2(b, a) in degrees, [0, 360°).
    Matches the M1/M2 matrices used in grade.fx / hue_bands.fxh.
    """
    M1 = np.array([
        [0.4122214708, 0.5363325363, 0.0514459929],
        [0.2119034982, 0.6806995451, 0.1073969566],
        [0.0883024619, 0.2817188376, 0.6299787005],
    ], dtype=np.float64)
    M2 = np.array([
        [ 0.2104542553,  0.7936177850, -0.0040720468],
        [ 1.9779984951, -2.4285922050,  0.4505937099],
        [ 0.0259040371,  0.7827717662, -0.8086757660],
    ], dtype=np.float64)
    lms = np.maximum(rgb.astype(np.float64), 0.0) @ M1.T
    lms_c = np.cbrt(lms)
    return (lms_c @ M2.T) * 100.0


def _delta_e_oklab(lab1: np.ndarray, lab2: np.ndarray) -> np.ndarray:
    """Euclidean Oklab distance (×100 scale). Inputs: (..., 3). Returns (...) ΔE."""
    d = lab2 - lab1
    return np.sqrt((d ** 2).sum(axis=-1))


# ── I/O ───────────────────────────────────────────────────────────────────────

def _load(exr_path: Path) -> np.ndarray:
    """Load R/G/B channels as float32 (H, W, 3)."""
    f   = OpenEXR.InputFile(str(exr_path))
    dw  = f.header()["dataWindow"]
    W   = dw.max.x - dw.min.x + 1
    H   = dw.max.y - dw.min.y + 1
    pt  = Imath.PixelType(Imath.PixelType.FLOAT)
    chs = {ch: np.frombuffer(f.channel(ch, pt), dtype=np.float32).reshape(H, W)
           for ch in ("R", "G", "B")}
    return np.stack([chs["R"], chs["G"], chs["B"]], axis=2)


def _latest_capture() -> Path:
    candidates = sorted(CAPTURES_DIR.glob("*.exr"), key=lambda p: p.stat().st_mtime)
    if not candidates:
        sys.exit("No captures found. Run 'capture' first.")
    return candidates[-1]


# ── Terminal helpers ───────────────────────────────────────────────────────────

_GRN = "\033[32m"
_YLW = "\033[33m"
_RED = "\033[31m"
_BLD = "\033[1m"
_RST = "\033[0m"


def _de_fmt(v: float, w: int = 5) -> str:
    s = f"{v:{w}.2f}"
    c = _GRN if v < 1.0 else (_YLW if v < 3.0 else _RED)
    return f"{c}{s}{_RST}"


def _bar(v: float, max_v: float = 6.0, width: int = 20) -> str:
    filled = int(round(min(v / max_v, 1.0) * width))
    c = _GRN if v < 1.0 else (_YLW if v < 3.0 else _RED)
    return f"{c}{'█' * filled}{'░' * (width - filled)}{_RST}"


# ── Mode: relative ─────────────────────────────────────────────────────────────

def compute_relative(before: np.ndarray, after: np.ndarray) -> dict:
    """Compute ΔE_oklab stats between two linear-light frames.

    Returns mean_de, p90, p99, pct_gt1, pct_gt3, zones, hue_bands.
    Zone/band entries: mean_de, max_de, n, dL, dC, dh (dh=None if no chromatic pixels).
    All ΔL/ΔC values are in Oklab ×100 units (L range 0–100, C range ~0–35).
    """
    lab_b = _linear_rgb_to_oklab(before)
    lab_a = _linear_rgb_to_oklab(after)
    de    = _delta_e_oklab(lab_b, lab_a)

    result: dict = {
        "mean_de": float(de.mean()),
        "p90":     float(np.percentile(de, 90)),
        "p99":     float(np.percentile(de, 99)),
        "pct_gt1": float((de > 1.0).mean() * 100),
        "pct_gt3": float((de > 3.0).mean() * 100),
        "zones":   {},
        "hue_bands": {},
    }

    luma = 0.2126 * before[..., 0] + 0.7152 * before[..., 1] + 0.0722 * before[..., 2]
    for label, mask in [
        ("shadows",    luma < 0.18),
        ("midtones",   (luma >= 0.18) & (luma < 0.60)),
        ("highlights", luma >= 0.60),
    ]:
        if not mask.any():
            result["zones"][label] = None
            continue
        z   = de[mask]
        lb  = lab_b[mask]
        la  = lab_a[mask]
        dL  = float((la[:, 0] - lb[:, 0]).mean())
        C_b = np.sqrt(lb[:, 1] ** 2 + lb[:, 2] ** 2)
        C_a = np.sqrt(la[:, 1] ** 2 + la[:, 2] ** 2)
        dC  = float((C_a - C_b).mean())
        chm = C_b > 2.0
        dh  = None
        if chm.any():
            h_b = np.degrees(np.arctan2(lb[chm, 2], lb[chm, 1])) % 360.0
            h_a = np.degrees(np.arctan2(la[chm, 2], la[chm, 1])) % 360.0
            dh  = float((((h_a - h_b + 180.0) % 360.0) - 180.0).mean())
        result["zones"][label] = {
            "mean_de": float(z.mean()), "max_de": float(z.max()),
            "n": int(mask.sum()), "dL": dL, "dC": dC, "dh": dh,
        }

    flat   = lab_b.reshape(-1, 3)
    flat_a = lab_a.reshape(-1, 3)
    de_f   = de.ravel()
    C_flat = np.sqrt(flat[:, 1] ** 2 + flat[:, 2] ** 2)
    hangle = np.degrees(np.arctan2(flat[:, 2], flat[:, 1])) % 360.0
    chroma = C_flat > 3.0   # Oklab C ×100 > 3 ≈ "clearly has a hue"

    for entry in HUE_BANDS:
        bname = entry[0]
        if len(entry) == 5:
            _, lo1, hi1, lo2, hi2 = entry
            mask = chroma & (((hangle >= lo1) & (hangle < hi1)) |
                             ((hangle >= lo2) & (hangle < hi2)))
        else:
            _, lo, hi = entry
            mask = chroma & (hangle >= lo) & (hangle < hi)
        if not mask.any():
            result["hue_bands"][bname] = None
            continue
        bd   = de_f[mask]
        lb_h = flat[mask]
        la_h = flat_a[mask]
        dL   = float((la_h[:, 0] - lb_h[:, 0]).mean())
        C_bh = np.sqrt(lb_h[:, 1] ** 2 + lb_h[:, 2] ** 2)
        C_ah = np.sqrt(la_h[:, 1] ** 2 + la_h[:, 2] ** 2)
        dC   = float((C_ah - C_bh).mean())
        chm  = C_bh > 2.0
        dh   = None
        if chm.any():
            h_b = np.degrees(np.arctan2(lb_h[chm, 2], lb_h[chm, 1])) % 360.0
            h_a = np.degrees(np.arctan2(la_h[chm, 2], la_h[chm, 1])) % 360.0
            dh  = float((((h_a - h_b + 180.0) % 360.0) - 180.0).mean())
        result["hue_bands"][bname] = {
            "mean_de": float(bd.mean()), "max_de": float(bd.max()),
            "n": int(mask.sum()), "dL": dL, "dC": dC, "dh": dh,
        }

    return result


def print_relative(stats: dict, before_name: str, after_name: str) -> None:
    """Print a full ΔE_oklab relative delta report from compute_relative() output."""
    print(f"\n{_BLD}analyze_delta  {before_name} → {after_name}{_RST}")
    print("─" * 62)

    print(f"\n{_BLD}overall{_RST}")
    print(f"  mean {_de_fmt(stats['mean_de'])}  p90 {_de_fmt(stats['p90'])}  p99 {_de_fmt(stats['p99'])}")
    print(f"  pixels >1: {stats['pct_gt1']:.1f}%   pixels >3: {stats['pct_gt3']:.1f}%")

    print(f"\n{_BLD}by zone{_RST}  (luma thresholds from '{before_name}')")
    for label in ("shadows", "midtones", "highlights"):
        z = stats["zones"].get(label)
        if z is None:
            continue
        dh_s = f"{z['dh']:+.1f}°" if z["dh"] is not None else "—"
        print(f"  {label:<12} {_bar(z['mean_de'])}  mean {_de_fmt(z['mean_de'])}  max {_de_fmt(z['max_de'])}  N={z['n']/1e3:.0f}K")
        print(f"               ΔL* {z['dL']:+.1f}  ΔC* {z['dC']:+.1f}  Δh° {dh_s}")

    print(f"\n{_BLD}by hue band{_RST}  (Oklab C>3 chromatic pixels, hue from '{before_name}')")
    for entry in HUE_BANDS:
        bname = entry[0]
        b = stats["hue_bands"].get(bname)
        if b is None:
            print(f"  {bname:<8}  (no chromatic pixels)")
            continue
        dh_s = f"{b['dh']:+.1f}°" if b["dh"] is not None else "—"
        print(f"  {bname:<8}  {_bar(b['mean_de'])}  mean {_de_fmt(b['mean_de'])}  max {_de_fmt(b['max_de'])}  N={b['n']/1e3:.0f}K")
        print(f"            ΔL* {b['dL']:+.1f}  ΔC* {b['dC']:+.1f}  Δh° {dh_s}")

    print()


def cmd_relative(before_path: Path, after_path: Path) -> None:
    print(f"Loading {before_path.name} ...")
    before = _load(before_path)
    print(f"Loading {after_path.name} ...")
    after  = _load(after_path)

    if before.shape != after.shape:
        sys.exit(f"Resolution mismatch: before {before.shape[:2]} vs after {after.shape[:2]}")

    H, W, _ = before.shape
    print(f"Computing ΔE_oklab on {W}×{H} ({W*H/1e6:.1f}M pixels)...")
    stats = compute_relative(before, after)
    print_relative(stats, before_path.name, after_path.name)


# ── Mode: colorchecker ─────────────────────────────────────────────────────────

def cmd_colorchecker(exr_path: Path) -> None:
    print(f"Loading {exr_path.name} ...")
    frame    = _load(exr_path)
    Hf, Wf, _ = frame.shape

    print(f"\n{_BLD}ColorChecker absolute ΔE_oklab — BabelColor D65 reference{_RST}")
    print(f"  source: {exr_path.name}  {Wf}×{Hf}")
    print(f"  {_GRN}green <1{_RST}  {_YLW}yellow 1–3{_RST}  {_RED}red >3{_RST}  (>6 = gross error)")
    print()
    print(f"  {'#':<3} {'Patch':<16} {'ΔE':>5}  {'L ref':>6}  {'L meas':>6}  {'ΔL':>5}  {'ΔC':>5}  {'Δh°':>5}")
    print("  " + "─" * 60)

    des         = []
    neutral_des = []

    for idx, (name, r8, g8, b8) in enumerate(CC_PATCHES):
        col = idx % _COLS
        row = idx // _COLS

        # Sample center of patch
        px = _MARGIN + col * (_PW + _GAP) + (_PW - _SAMPLE) // 2
        py = _MARGIN + row * (_PH + _GAP) + (_PH - _SAMPLE) // 2
        px = max(0, min(px, Wf - _SAMPLE))
        py = max(0, min(py, Hf - _SAMPLE))

        meas_lin = frame[py:py + _SAMPLE, px:px + _SAMPLE, :].mean(axis=(0, 1))
        ref_lin  = _srgb_to_linear(np.array([r8, g8, b8], np.float32) / 255.0)

        lab_ref  = _linear_rgb_to_oklab(ref_lin[None, None]).squeeze()
        lab_meas = _linear_rgb_to_oklab(meas_lin[None, None]).squeeze()

        de   = float(_delta_e_oklab(lab_ref[None], lab_meas[None]).item())
        dL   = float(lab_meas[0] - lab_ref[0])
        Cref = float(np.sqrt(lab_ref[1] ** 2 + lab_ref[2] ** 2))
        Cm   = float(np.sqrt(lab_meas[1] ** 2 + lab_meas[2] ** 2))
        dC   = Cm - Cref
        hr   = float(np.degrees(np.arctan2(lab_ref[2],  lab_ref[1])))
        hm   = float(np.degrees(np.arctan2(lab_meas[2], lab_meas[1])))
        dh   = ((hm - hr + 180.0) % 360.0) - 180.0

        des.append(de)
        if idx >= 18:
            neutral_des.append(de)

        print(f"  {idx+1:<3} {name:<16} {_de_fmt(de)}  "
              f"{lab_ref[0]:6.1f}  {lab_meas[0]:6.1f}  "
              f"{dL:+5.2f}  {dC:+5.2f}  {dh:+5.1f}°")

    print("  " + "─" * 60)
    max_i = int(np.argmax(des))
    print(f"  overall    mean ΔE {_de_fmt(float(np.mean(des)))}  "
          f"max ΔE {_de_fmt(float(np.max(des)))} ({CC_PATCHES[max_i][0]})")
    print(f"  neutral (19–24)    mean ΔE {_de_fmt(float(np.mean(neutral_des)))}")
    print()


# ── Entry ──────────────────────────────────────────────────────────────────────

def main() -> None:
    ap = argparse.ArgumentParser(
        description="Perceptual color delta analysis (ΔE_oklab)",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Examples:\n"
            "  analyze_delta before.exr after.exr\n"
            "  analyze_delta --colorchecker captures/session_foo.exr\n"
            "  analyze_delta --colorchecker          # uses most recent capture"
        ),
    )
    ap.add_argument("--colorchecker", action="store_true",
                    help="Absolute mode: compare vs. BabelColor D65 reference patches")
    ap.add_argument("exr", nargs="*",
                    help="EXR path(s). Relative: before after. Colorchecker: one or none.")
    args = ap.parse_args()

    if args.colorchecker:
        if len(args.exr) == 0:
            p = _latest_capture()
            print(f"Using most recent capture: {p.name}")
        elif len(args.exr) == 1:
            p = Path(args.exr[0])
        else:
            sys.exit("--colorchecker takes zero or one EXR path")
        cmd_colorchecker(p)
    else:
        if len(args.exr) != 2:
            ap.print_help()
            sys.exit("\nRelative mode requires exactly two EXR paths: before after")
        cmd_relative(Path(args.exr[0]), Path(args.exr[1]))


if __name__ == "__main__":
    main()
