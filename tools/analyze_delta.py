#!/usr/bin/env python3
"""
tools/analyze_delta.py — Perceptual color delta analysis (CIEDE2000) between EXR captures.

Modes:
    analyze_delta before.exr after.exr        relative: ΔE2000 per zone + hue band
    analyze_delta --colorchecker [exr]        absolute: ΔE2000 per patch vs. BabelColor D65
                                              (omit exr to use most recent capture)

ΔE2000 scale:
    < 1     imperceptible to most observers
    1 – 3   acceptable / minor difference
    3 – 6   clearly visible
    > 6     gross error

Requires: numpy, openexr
No extra packages needed — CIEDE2000 implemented inline from CIE 142:2001.
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

# 6 broad hue bands in CIE Lab hue angle: atan2(b*, a*) in [0, 360)
# Red=0°, Yellow=90°, Green=180°, Blue=270° in Lab
HUE_BANDS = [
    ("red",     340, 360, 0,  30),   # wraps: 340-360 + 0-30
    ("yellow",   30,  90),
    ("green",    90, 150),
    ("cyan",    150, 210),
    ("blue",    210, 290),
    ("magenta", 290, 340),
]


# ── Color math (no extra deps) ─────────────────────────────────────────────────

def _srgb_to_linear(v: np.ndarray) -> np.ndarray:
    return np.where(v <= 0.04045, v / 12.92, ((v + 0.055) / 1.055) ** 2.4)


def _linear_rgb_to_lab(rgb: np.ndarray) -> np.ndarray:
    """Linear sRGB [0, 1] → CIE L*a*b* (D65 2°). Input: (..., 3) float."""
    M = np.array([
        [0.4124564, 0.3575761, 0.1804375],
        [0.2126729, 0.7151522, 0.0721750],
        [0.0193339, 0.1191920, 0.9503041],
    ], dtype=np.float64)
    xyz = rgb.astype(np.float64) @ M.T
    xyz_n = xyz / np.array([0.95047, 1.00000, 1.08883])
    k = 6.0 / 29.0
    f = np.where(xyz_n > k ** 3, np.cbrt(xyz_n), xyz_n / (3.0 * k ** 2) + 4.0 / 29.0)
    L = 116.0 * f[..., 1] - 16.0
    a = 500.0 * (f[..., 0] - f[..., 1])
    b = 200.0 * (f[..., 1] - f[..., 2])
    return np.stack([L, a, b], axis=-1)


def _delta_e_2000(lab1: np.ndarray, lab2: np.ndarray) -> np.ndarray:
    """CIEDE2000 per CIE 142:2001. Inputs: (..., 3) L*a*b*. Returns (...) ΔE."""
    L1, a1, b1 = lab1[..., 0], lab1[..., 1], lab1[..., 2]
    L2, a2, b2 = lab2[..., 0], lab2[..., 1], lab2[..., 2]

    # a' adjustment
    C1 = np.sqrt(a1 ** 2 + b1 ** 2)
    C2 = np.sqrt(a2 ** 2 + b2 ** 2)
    Cavg7 = ((C1 + C2) / 2.0) ** 7
    G = 0.5 * (1.0 - np.sqrt(Cavg7 / (Cavg7 + 25.0 ** 7)))
    a1p = a1 * (1.0 + G)
    a2p = a2 * (1.0 + G)

    C1p = np.sqrt(a1p ** 2 + b1 ** 2)
    C2p = np.sqrt(a2p ** 2 + b2 ** 2)
    h1p = np.degrees(np.arctan2(b1, a1p)) % 360.0
    h2p = np.degrees(np.arctan2(b2, a2p)) % 360.0

    dLp = L2 - L1
    dCp = C2p - C1p

    dh_abs = np.abs(h2p - h1p)
    dhp = np.where(dh_abs <= 180.0, h2p - h1p,
          np.where(h2p - h1p > 180.0, h2p - h1p - 360.0,
                                       h2p - h1p + 360.0))
    dhp  = np.where((C1p == 0) | (C2p == 0), 0.0, dhp)
    dHp  = 2.0 * np.sqrt(C1p * C2p) * np.sin(np.radians(dhp / 2.0))

    Lpavg = (L1 + L2) / 2.0
    Cpavg = (C1p + C2p) / 2.0

    both  = (C1p > 0) & (C2p > 0)
    hsum  = h1p + h2p
    hpavg = np.where(~both, hsum,
            np.where(dh_abs <= 180.0, hsum / 2.0,
            np.where(hsum < 360.0, (hsum + 360.0) / 2.0,
                                   (hsum - 360.0) / 2.0)))

    T  = (1.0
          - 0.17 * np.cos(np.radians(hpavg - 30.0))
          + 0.24 * np.cos(np.radians(2.0 * hpavg))
          + 0.32 * np.cos(np.radians(3.0 * hpavg + 6.0))
          - 0.20 * np.cos(np.radians(4.0 * hpavg - 63.0)))

    SL = 1.0 + 0.015 * (Lpavg - 50.0) ** 2 / np.sqrt(20.0 + (Lpavg - 50.0) ** 2)
    SC = 1.0 + 0.045 * Cpavg
    SH = 1.0 + 0.015 * Cpavg * T

    Cpavg7 = Cpavg ** 7
    RC     = 2.0 * np.sqrt(Cpavg7 / (Cpavg7 + 25.0 ** 7))
    dtheta = 30.0 * np.exp(-((hpavg - 275.0) / 25.0) ** 2)
    RT     = -np.sin(np.radians(2.0 * dtheta)) * RC

    return np.sqrt(
        (dLp / SL) ** 2 +
        (dCp / SC) ** 2 +
        (dHp / SH) ** 2 +
        RT * (dCp / SC) * (dHp / SH)
    )


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

def cmd_relative(before_path: Path, after_path: Path) -> None:
    print(f"Loading {before_path.name} ...")
    before = _load(before_path)
    print(f"Loading {after_path.name} ...")
    after  = _load(after_path)

    if before.shape != after.shape:
        sys.exit(f"Resolution mismatch: before {before.shape[:2]} vs after {after.shape[:2]}")

    H, W, _ = before.shape
    print(f"Computing ΔE2000 on {W}×{H} ({W*H/1e6:.1f}M pixels)...")
    lab_b = _linear_rgb_to_lab(before)
    lab_a = _linear_rgb_to_lab(after)
    de    = _delta_e_2000(lab_b, lab_a)

    print(f"\n{_BLD}analyze_delta  {before_path.name} → {after_path.name}{_RST}")
    print("─" * 62)

    mean_de = float(de.mean())
    p90     = float(np.percentile(de, 90))
    p99     = float(np.percentile(de, 99))
    pct1    = float((de > 1.0).mean() * 100)
    pct3    = float((de > 3.0).mean() * 100)

    print(f"\n{_BLD}overall{_RST}")
    print(f"  mean {_de_fmt(mean_de)}  p90 {_de_fmt(p90)}  p99 {_de_fmt(p99)}")
    print(f"  pixels >1: {pct1:.1f}%   pixels >3: {pct3:.1f}%")

    # Per-zone (classified from 'before' luma)
    luma  = (0.2126 * before[..., 0] + 0.7152 * before[..., 1] + 0.0722 * before[..., 2])
    zones = [
        ("shadows",    luma < 0.18),
        ("midtones",   (luma >= 0.18) & (luma < 0.60)),
        ("highlights", luma >= 0.60),
    ]
    print(f"\n{_BLD}by zone{_RST}  (luma thresholds from '{before_path.name}')")
    for label, mask in zones:
        if not mask.any():
            continue
        z    = de[mask]
        n    = mask.sum()
        mean = float(z.mean())
        mx   = float(z.max())
        print(f"  {label:<12} {_bar(mean)}  mean {_de_fmt(mean)}  max {_de_fmt(mx)}  N={n/1e3:.0f}K")
        lb   = lab_b[mask]
        la   = lab_a[mask]
        dL   = float((la[:, 0] - lb[:, 0]).mean())
        C_b  = np.sqrt(lb[:, 1] ** 2 + lb[:, 2] ** 2)
        C_a  = np.sqrt(la[:, 1] ** 2 + la[:, 2] ** 2)
        dC   = float((C_a - C_b).mean())
        chm  = C_b > 2.0
        if chm.any():
            h_b  = np.degrees(np.arctan2(lb[chm, 2], lb[chm, 1])) % 360.0
            h_a  = np.degrees(np.arctan2(la[chm, 2], la[chm, 1])) % 360.0
            dh   = float((((h_a - h_b + 180.0) % 360.0) - 180.0).mean())
            dh_s = f"{dh:+.1f}°"
        else:
            dh_s = "—"
        print(f"               ΔL* {dL:+.1f}  ΔC* {dC:+.1f}  Δh° {dh_s}")

    # Per-hue-band (chromatic pixels only, Lab C* > 5)
    flat   = lab_b.reshape(-1, 3)
    flat_a = lab_a.reshape(-1, 3)
    de_f   = de.ravel()
    Cstar  = np.sqrt(flat[:, 1] ** 2 + flat[:, 2] ** 2)
    hangle = np.degrees(np.arctan2(flat[:, 2], flat[:, 1])) % 360.0
    chroma = Cstar > 5.0

    print(f"\n{_BLD}by hue band{_RST}  (C*>5 chromatic pixels, hue from '{before_path.name}')")
    for entry in HUE_BANDS:
        name = entry[0]
        if len(entry) == 5:  # wrapping band (red)
            _, lo1, hi1, lo2, hi2 = entry
            mask = chroma & (((hangle >= lo1) & (hangle < hi1)) |
                             ((hangle >= lo2) & (hangle < hi2)))
        else:
            _, lo, hi = entry
            mask = chroma & (hangle >= lo) & (hangle < hi)

        if not mask.any():
            print(f"  {name:<8}  (no chromatic pixels)")
            continue
        bd   = de_f[mask]
        mean = float(bd.mean())
        mx   = float(bd.max())
        print(f"  {name:<8}  {_bar(mean)}  mean {_de_fmt(mean)}  max {_de_fmt(mx)}  N={mask.sum()/1e3:.0f}K")
        lb_h = flat[mask]
        la_h = flat_a[mask]
        dL   = float((la_h[:, 0] - lb_h[:, 0]).mean())
        C_bh = np.sqrt(lb_h[:, 1] ** 2 + lb_h[:, 2] ** 2)
        C_ah = np.sqrt(la_h[:, 1] ** 2 + la_h[:, 2] ** 2)
        dC   = float((C_ah - C_bh).mean())
        chm  = C_bh > 2.0
        if chm.any():
            h_b  = np.degrees(np.arctan2(lb_h[chm, 2], lb_h[chm, 1])) % 360.0
            h_a  = np.degrees(np.arctan2(la_h[chm, 2], la_h[chm, 1])) % 360.0
            dh   = float((((h_a - h_b + 180.0) % 360.0) - 180.0).mean())
            dh_s = f"{dh:+.1f}°"
        else:
            dh_s = "—"
        print(f"            ΔL* {dL:+.1f}  ΔC* {dC:+.1f}  Δh° {dh_s}")

    print()


# ── Mode: colorchecker ─────────────────────────────────────────────────────────

def cmd_colorchecker(exr_path: Path) -> None:
    print(f"Loading {exr_path.name} ...")
    frame    = _load(exr_path)
    Hf, Wf, _ = frame.shape

    print(f"\n{_BLD}ColorChecker absolute ΔE2000 — BabelColor D65 reference{_RST}")
    print(f"  source: {exr_path.name}  {Wf}×{Hf}")
    print(f"  {_GRN}green <1{_RST}  {_YLW}yellow 1–3{_RST}  {_RED}red >3{_RST}  (>6 = gross error)")
    print()
    print(f"  {'#':<3} {'Patch':<16} {'ΔE':>5}  {'L*ref':>6}  {'L*meas':>6}  {'ΔL*':>5}  {'ΔC*':>5}  {'Δh°':>5}")
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

        lab_ref  = _linear_rgb_to_lab(ref_lin[None, None]).squeeze()
        lab_meas = _linear_rgb_to_lab(meas_lin[None, None]).squeeze()

        de   = float(_delta_e_2000(lab_ref[None], lab_meas[None]).item())
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
        description="Perceptual color delta analysis (CIEDE2000)",
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
