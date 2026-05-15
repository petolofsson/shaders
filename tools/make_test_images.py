#!/usr/bin/env python3
"""
tools/make_test_images.py — Generate synthetic test images for golden regression tests.

Writes to tests/inputs/:
  test_gradient.png / .exr      vertical luma ramp + saturated hue bars
  test_colorchecker.png / .exr  24-patch Macbeth ColorChecker on 18% grey (BabelColor sRGB D65)
  test_highlights.png / .exr    bright patches on dark ground
  test_skintones.png / .exr     Fitzpatrick I–VI patches on 18% grey

PNGs are the sRGB source images fed to vkBasalt via mpv.
EXRs are the linearised equivalents — the exact signal the pipeline sees as input.
Both are needed: PNGs for display, EXRs for delta analysis alongside the goldens.
"""

import struct
import subprocess
import sys
import zlib
from pathlib import Path

import numpy as np

try:
    import OpenEXR
    import Imath
except ImportError:
    sys.exit("Missing: pip install openexr")

OUT = Path(__file__).resolve().parent.parent / "tests" / "inputs"
W, H = 2560, 1440


def im(*args: str) -> None:
    r = subprocess.run(["convert"] + list(args), capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit(f"ImageMagick convert failed:\n{r.stderr}")


# ── Reference data ────────────────────────────────────────────────────────────

# BabelColor sRGB D65 reference values, 8-bit
CC_PATCHES = [
    # Row 1 — natural
    ("Dark skin",      115,  82,  68),
    ("Light skin",     194, 150, 130),
    ("Blue sky",        98, 122, 157),
    ("Foliage",         87, 108,  67),
    ("Blue flower",    133, 128, 177),
    ("Bluish green",   103, 189, 170),
    # Row 2 — colorful
    ("Orange",         214, 126,  44),
    ("Purplish blue",   80,  91, 166),
    ("Moderate red",   193,  90,  99),
    ("Purple",          94,  60, 108),
    ("Yellow green",   157, 188,  64),
    ("Orange yellow",  224, 163,  46),
    # Row 3 — primaries / secondaries
    ("Blue",            56,  61, 150),
    ("Green",           70, 148,  73),
    ("Red",            175,  54,  60),
    ("Yellow",         231, 199,  31),
    ("Magenta",        187,  86, 149),
    ("Cyan",             8, 133, 161),
    # Row 4 — neutral steps
    ("White 9.5",      243, 243, 242),
    ("Neutral 8",      200, 200, 200),
    ("Neutral 6.5",    160, 160, 160),
    ("Neutral 5",      122, 122, 121),
    ("Neutral 3.5",     85,  85,  85),
    ("Black 2",         52,  52,  52),
]

# sRGB values roughly matching Fitzpatrick scale midpoints
SKIN_PATCHES = [
    ("Fitzpatrick I",   255, 220, 196),
    ("Fitzpatrick II",  241, 194, 167),
    ("Fitzpatrick III", 224, 172, 140),
    ("Fitzpatrick IV",  198, 134, 101),
    ("Fitzpatrick V",   141,  85,  36),
    ("Fitzpatrick VI",   72,  37,  14),
]

# Saturated primaries / secondaries for hue bar strip
HUE_BARS = [
    (255,   0,   0),  # Red
    (255, 220,   0),  # Yellow
    (  0, 200,   0),  # Green
    (  0, 220, 220),  # Cyan
    (  0,   0, 255),  # Blue
    (220,   0, 220),  # Magenta
]

GREY18 = "rgb(118,118,118)"   # 18% linear grey in sRGB ≈ 118
DARK   = "rgb(30,30,30)"      # ~1% linear — dark ground for highlights test


# ── Generators ────────────────────────────────────────────────────────────────

def make_gradient() -> None:
    """Vertical luma ramp (top=black, bottom=white) with saturated hue bars across the bottom quarter."""
    out = str(OUT / "test_gradient.png")
    bar_h = H // 4
    bar_w = W // len(HUE_BARS)

    args = ["-depth", "8", "-size", f"{W}x{H}", "gradient:black-white"]
    for i, (r, g, b) in enumerate(HUE_BARS):
        x0, y0 = i * bar_w,        H - bar_h
        x1, y1 = x0 + bar_w - 1,  H - 1
        args += ["-fill", f"rgb({r},{g},{b})", "-draw", f"rectangle {x0},{y0} {x1},{y1}"]
    args.append(out)
    im(*args)
    print(f"  {out}")


def make_colorchecker() -> None:
    """24-patch Macbeth ColorChecker on 18% grey background."""
    out = str(OUT / "test_colorchecker.png")

    cols, rows = 6, 4
    margin, gap = 80, 20
    pw = (W - 2 * margin - (cols - 1) * gap) // cols
    ph = (H - 2 * margin - (rows - 1) * gap) // rows

    args = ["-size", f"{W}x{H}", f"xc:{GREY18}"]
    for idx, (_, r, g, b) in enumerate(CC_PATCHES):
        col, row = idx % cols, idx // cols
        x0 = margin + col * (pw + gap)
        y0 = margin + row * (ph + gap)
        args += [
            "-fill", f"rgb({r},{g},{b})",
            "-draw", f"rectangle {x0},{y0} {x0+pw-1},{y0+ph-1}",
        ]
    args.append(out)
    im(*args)
    print(f"  {out}")


def make_highlights() -> None:
    """Bright patches of varying size and colour on a dark background.

    Patch sizes span from 500px down to 40px — the halation DoG PSF uses
    LowFreqMip1 (1/16-res, ~160px at 2560) and LowFreqMip2 (1/32-res, ~80px),
    so patches at those scales stress the two halo rings independently.
    """
    out = str(OUT / "test_highlights.png")

    patches = [
        # (x_center, y_center, w, h, r, g, b)
        # Large pure-white — both rings active
        ( 480,  400, 480, 480, 255, 255, 255),
        # Near-white — tests shoulder of halation gate
        ( 480,  1050, 260, 260, 242, 242, 242),
        # Warm specular — tests rem-jet G-channel modulation
        (1100,  360, 320, 320, 255, 228, 190),
        # Cool specular
        (1100,  900, 320, 320, 190, 218, 255),
        # Tall bar — tests vertical PSF spread
        (1700,  500, 200, 600, 255, 255, 255),
        # Wide bar — tests horizontal PSF spread
        (1700, 1100, 600, 160, 255, 255, 255),
        # Small — ~1/16-res scale, stresses inner ring only
        (2200,  380, 160, 160, 255, 255, 255),
        # Tiny — below 1/32-res scale
        (2200,  700,  70,  70, 255, 255, 255),
        # Very tiny
        (2200,  900,  40,  40, 255, 255, 255),
        # Medium grey — diffusion midtone gate
        (2200, 1150, 200, 200, 180, 180, 180),
    ]

    args = ["-size", f"{W}x{H}", f"xc:{DARK}"]
    for xc, yc, pw, ph, r, g, b in patches:
        x0, y0 = xc - pw // 2, yc - ph // 2
        args += [
            "-fill", f"rgb({r},{g},{b})",
            "-draw", f"rectangle {x0},{y0} {x0+pw-1},{y0+ph-1}",
        ]
    args.append(out)
    im(*args)
    print(f"  {out}")


def make_skintones() -> None:
    """Fitzpatrick I–VI skin tone patches on 18% grey — the pipeline's known sensitive area."""
    out = str(OUT / "test_skintones.png")

    n = len(SKIN_PATCHES)
    margin, gap = 120, 30
    pw = (W - 2 * margin - (n - 1) * gap) // n
    ph = H - 2 * margin

    args = ["-size", f"{W}x{H}", f"xc:{GREY18}"]
    for idx, (_, r, g, b) in enumerate(SKIN_PATCHES):
        x0 = margin + idx * (pw + gap)
        y0 = margin
        args += [
            "-fill", f"rgb({r},{g},{b})",
            "-draw", f"rectangle {x0},{y0} {x0+pw-1},{y0+ph-1}",
        ]
    args.append(out)
    im(*args)
    print(f"  {out}")


def _srgb_to_linear(arr: np.ndarray) -> np.ndarray:
    return np.where(arr <= 0.04045, arr / 12.92, ((arr + 0.055) / 1.055) ** 2.4)


def png_to_linear_exr(png_path: Path, exr_path: Path) -> None:
    """Read an sRGB PNG and write a linear-light float16 EXR (R, G, B channels only)."""
    # Decode PNG via ImageMagick → raw RGB bytes
    r = subprocess.run(
        ["convert", str(png_path), "-depth", "16", "-colorspace", "sRGB", "RGB:-"],
        capture_output=True,
    )
    if r.returncode != 0:
        sys.exit(f"convert failed for {png_path}: {r.stderr.decode()}")

    raw = np.frombuffer(r.stdout, dtype=">u2").astype(np.float32) / 65535.0
    H, W = 1440, 2560
    rgb_srgb = raw.reshape(H, W, 3)
    rgb_lin  = _srgb_to_linear(rgb_srgb).astype(np.float16)

    half = Imath.PixelType(Imath.PixelType.HALF)
    header = OpenEXR.Header(W, H)
    header["channels"] = {ch: Imath.Channel(half) for ch in ("R", "G", "B")}
    out = OpenEXR.OutputFile(str(exr_path), header)
    out.writePixels({
        "R": rgb_lin[:, :, 0].tobytes(),
        "G": rgb_lin[:, :, 1].tobytes(),
        "B": rgb_lin[:, :, 2].tobytes(),
    })
    out.close()


def make_originals() -> None:
    """Convert each PNG to a linear-light EXR — the exact input the pipeline receives."""
    names = ["gradient", "colorchecker", "highlights", "skintones"]
    for name in names:
        png = OUT / f"test_{name}.png"
        exr = OUT / f"test_{name}.exr"
        png_to_linear_exr(png, exr)
        print(f"  {exr}")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    print(f"Writing to {OUT}/")
    make_gradient()
    make_colorchecker()
    make_highlights()
    make_skintones()
    print("Linearising to EXR...")
    make_originals()
    print("Done.")


if __name__ == "__main__":
    main()
