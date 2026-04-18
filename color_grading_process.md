# Color Grading Process: LOG to Rec.709

A reference for understanding the professional grading pipeline and how the shader
stack maps to it.

---

## Why LOG?

Cameras don't record in the color space you watch on screen. They capture in a
**LOG (logarithmic) gamma curve** that compresses a wide dynamic range (14–15 stops)
into the limited range of a video file. The image looks flat and desaturated — that
is intentional. The color information is all there, just compressed.

**Rec.709** is the standard display color space for HD monitors and TV. It has a
narrower dynamic range (~6 stops visible contrast), a specific gamma curve (~2.4),
and a defined color gamut (the triangle of colors the standard can represent).

Going LOG → Rec.709 means: expanding, shaping, and colorizing that flat recording
into something that looks correct and intentional on a display.

---

## Rec.709 — What It Actually Means

Rec.709 (ITU-R BT.709) is the HDTV standard. It defines three things:

**1. Color gamut primaries** (D65 white point, 6500K daylight):
- Red: (0.640, 0.330)
- Green: (0.290, 0.600)
- Blue: (0.150, 0.060)
- Luminance coefficients: Y = 0.2126R + 0.7152G + 0.0722B

**2. Gamma** — Rec.709 does not specify its own display gamma internally.
The standard for professional display is **BT.1886: gamma 2.4**. Consumer
monitors typically use **sRGB: ~gamma 2.2** (piecewise, slightly lighter).
Gamma 2.4 produces a darker, higher-contrast image than 2.2 on the same display.

**3. Encoding domain** — Rec.709 is gamma-compressed (display-referred), NOT
linear light. Working in Rec.709 space means color operations don't behave
linearly — you must linearize first to work correctly.

---

## Color Space Transform (CST)

The CST node in DaVinci Resolve is the technical bridge between color spaces.
It is fundamentally different from a LUT:

| | LUT | CST |
|---|---|---|
| Operation | Fixed table lookup | Mathematical transform |
| Out-of-gamut | Clips or wraps | Intelligent tone mapping |
| Bit depth | Limited by table size | Full 32-bit float |
| Position sensitivity | Order matters destructively | Same result regardless of position |
| Color awareness | None | Knows source colorimetry |

**What CST does technically:**
1. Decodes the source LOG curve (e.g. S-Log3 → linear)
2. Transforms between color gamuts via a 3×3 matrix (e.g. S-Gamut3 → Rec.709 primaries)
3. Applies tone mapping to handle the dynamic range mismatch
4. Re-encodes to the destination gamma (e.g. linear → Rec.709 gamma 2.4)

**Tone mapping methods inside CST:**
- **DaVinci method** — smooth luminance roll-off with controlled desaturation in shadows/highlights
- **Saturation preserving** — luminance roll-off only, no shadow/highlight desaturation; for aggressive color pushing
- **Simple** — basic curve compression, no desaturation

CSTs act as bookends:

```
Input CST: S-Log3/S-Gamut3 → DaVinci Wide Gamut Intermediate
    [all grading happens here]
Output CST: DaVinci Wide Gamut → Rec.709 Gamma 2.4
```

---

## DaVinci Wide Gamut Intermediate

When using Resolve Color Management, all grading happens in **DaVinci Wide Gamut
Intermediate** — a working space that is:
- Larger than BT.2020, ARRI Wide Gamut, and ACES combined
- Scene-referred (based on actual light energy)
- Designed so no color information is lost before the output transform

This is why grading in a wide gamut space is preferred: you have the full color
volume available, and the gamut compression/mapping happens in the output CST
where it can be done intelligently, once.

---

## The Professional Pipeline (DaVinci Resolve)

```
Camera footage (e.g. S-Log3 / S-Gamut3.Cine)
     │
     ▼  Input CST — technical, not creative
        S-Log3 → linear → DaVinci Wide Gamut Intermediate
     │
     ▼  Primary Correction — correction, not creative
        White balance (Offset wheel)
        Exposure (Gain wheel)
        Contrast shaping (Gamma/Lift/Gain)
        Black and white points
     │
     ▼  Secondary Corrections — targeted correction
        HSL qualifiers (isolate skin tones, sky, etc.)
        Power windows (spatial masks)
        Hue vs. Hue / Hue vs. Sat curves
        Noise reduction
     │
     ▼  Creative Look — artistic intent
        Tonal style (lift/gamma/gain for look)
        Film emulation (LUT or plugin like Dehancer)
        Color separation (teal/orange, etc.)
     │
     ▼  Output CST — technical, not creative
        Wide Gamut → linear → Rec.709 Gamma 2.4
        Gamut mapping happens here (intelligent compression)
     │
     ▼  Film effects — MUST be last
        Halation (before grain)
        Grain (very last — responds to final luminance values)
     │
Display (Rec.709 gamma 2.4)
```

**Why grain must be last:** Grain structure is luminosity-dependent — it must see
the final luminance after all color and contrast work. Glows and halations go before
grain because they affect luminance that grain will then respond to.

---

## Gamut Mapping vs. Saturation Limiting

These are different operations that serve different purposes:

**Saturation limiting** (creative):
- Caps HSV/HSL saturation so colors don't become garish
- Applied during the creative grade
- Uniform reduction across hues
- Operated in HSV space

**Gamut mapping** (technical):
- Brings out-of-gamut RGB values back inside the displayable Rec.709 triangle
- Applied in the output CST, as part of the color space conversion
- Perceptually aware — preserves hue while compressing chroma magnitude
- DaVinci's implementation: saturation compression with a user-adjustable knee;
  desaturates peaks so they fit within Rec.709 limits
- Operated in RGB/XYZ space

The distinction matters for pipeline order: saturation limiting is a creative
choice made during grading; gamut mapping is a technical step done at output.
Doing gamut mapping in the middle of a grade means subsequent operations can
push colors back out of gamut again.

---

## Film Emulation — How It Actually Works

DaVinci Resolve has no native film emulation. Professionals use plugins:
- **Dehancer Pro** — 60+ researched film stocks (used in high-end productions)
- **EMUL8** — real-time film emulation with bloom/halation/grain

These are technically more sophisticated than a print matrix:

**Negative density curves** — maps digital linear light to film negative response.
Each stock has a unique non-linear tonal response. Shadows and highlights respond
differently to exposure based on the stock's latitude and dye chemistry.

**Print film transform** — the negative is printed onto print stock, which has its
own color response. This is where the characteristic color palette of a stock comes
from. A separate LUT or matrix for the print stage on top of the negative stage.

**Halation** — NOT a glow. A physical phenomenon:
1. Light exposes the emulsion from the front
2. Bright light passes through and bounces off the camera back
3. The bounced light re-exposes primarily the red layer, secondarily the green layer
4. Result: reddish/orange halo around bright objects, localized to highlights
Different from bloom (which is optical, not photochemical).

**Grain** — NOT uniform noise:
- Grain size and intensity varies by tonal density (shadows ≠ highlights)
- Each color channel (RGB of the negative) has independent grain
- Real film grain is temporally coherent frame-to-frame (unlike digital noise)
- Grain interacts with edge transitions differently than digital noise

**In our stack**: The FILM_* matrix in ColorGrade approximates the print matrix
stage (dye bleed between layers). It does not model the negative curve, halation,
or grain.

---

## How Our Stack Maps (Honest Assessment)

```
Game engine output (Rec.709 gamma-encoded)
     │
     ▼
┌─────────────────────────────────────────────────────┐
│  OlofssonianZoneContrast                            │
│  ≈ Contrast shaping (stage 4 in Resolve)            │
│  Adaptive S-curve around local luminance mean       │
│  PROBLEM: operates in gamma space, not linear       │
└─────────────────────────────────────────────────────┘
     │
     ▼
┌─────────────────────────────────────────────────────┐
│  OlofssonianChromaLift                          │
│  ≈ Secondary corrections (stage 5 in Resolve)       │
│  Per-band HSV S-curve + green hue rotation          │
│  PROBLEM: saturation limiting and gamut mapping     │
│  are conflated (SAT_MAX does both jobs)             │
└─────────────────────────────────────────────────────┘
     │
     ▼
┌─────────────────────────────────────────────────────┐
│  ColorGrade                                         │
│  ≈ Creative look (stage 6 in Resolve)               │
│  Lift/Gamma/Gain tinting, film matrix, white cast   │
│  PROBLEM: gamut compression is before film matrix   │
│  (matrix can push out of gamut with nothing to fix) │
└─────────────────────────────────────────────────────┘
     │
     ▼
Display (Rec.709)
```

---

## What We're Missing vs. a Full Resolve Grade

| Professional stage | Our stack | Gap |
|---|---|---|
| Input CST (log decode) | — | Not needed — game is post-tonemap |
| Linearization | — | **Missing — we grade in gamma space** |
| Primary correction (WB, exposure) | — | **Missing entirely** |
| Contrast shaping | ZoneContrast | Present, but in gamma space |
| Secondary corrections (per-hue) | ChromaContrast | Present |
| Hue rotation (all bands) | ChromaContrast | Only green band done |
| Creative tinting | ColorGrade | Present |
| Film print matrix | ColorGrade | Present (approx.) |
| White point warm cast | ColorGrade | Present |
| Output CST with gamut mapping | — | **Missing — we clip at saturate()** |
| Negative density curve | — | Not implemented |
| Halation | — | Not implemented |
| Grain | — | Not implemented |
| Scopes (waveform, vectorscope) | debug indicators | Debug only, no measurement |
| Per-node isolation / masking | — | Not possible in linear shader chain |

**Most impactful missing pieces for quality:**
1. **Linearization** — grading in gamma space causes disproportionate shadow crushing
   and saturation artifacts in highlights. A linearize → grade → re-gamma bookend
   would fix this.
2. **Primary correction** — no white balance or exposure normalization means the grade
   depends on the game rendering consistent output (it often doesn't).
3. **Proper gamut mapping at output** — currently we clip with `saturate()`. A proper
   gamut compression pass at the very end (after all creative work) would prevent
   harsh clipping artifacts on oversaturated colors.

---

## Key Terms

| Term | Meaning |
|---|---|
| LOG | Logarithmic gamma curve that compresses dynamic range |
| Rec.709 | Standard HD display color space (gamut + gamma 2.4) |
| BT.1886 | Standard specifying gamma 2.4 for professional HDTV displays |
| sRGB | Consumer display gamma (~2.2); lighter than BT.1886 |
| CDL | ASC Color Decision List — Slope/Offset/Power per channel |
| LUT | Look-Up Table — pre-computed color transform |
| CST | Color Space Transform — mathematical, gamut-aware color conversion |
| IDT | Input Device Transform — LOG decode for a specific camera |
| ODT | Output Device Transform — encode for a specific display |
| ACES | Academy Color Encoding System — standardized color pipeline |
| DWG | DaVinci Wide Gamut — Resolve's internal working color space |
| Gamut | The triangle of colors a color space can represent |
| Gamut mapping | Intelligent compression of out-of-gamut colors at output |
| Saturation limiting | Creative cap on color vividness during grade |
| Halation | Reddish photochemical halo around bright objects in film |
| Dye bleed | Inter-channel contamination in film dye layers (→ print matrix) |
| D65 | Standard daylight white point (6500K) used by Rec.709 |
| Scene-referred | Values represent actual light energy (linear) |
| Display-referred | Values represent encoded display signal (gamma-compressed) |
