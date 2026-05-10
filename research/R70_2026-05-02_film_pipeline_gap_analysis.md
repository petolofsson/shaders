# R70 — Film/Creative Pipeline Gap Analysis

**Date:** 2026-05-02
**Status:** Analysis — spawns R71+

---

## Reference pipeline

Professional film color correction chain (DaVinci Resolve / Baselight / ACES):

```
IDT → Scene-linear primaries correction → Tone mapping (LMT+RRT)
    → Primary CC (wheels/curves) → Secondary CC (HSL qualifier + power windows)
    → Creative looks → ODT
```

For this analysis we exclude: grain, power windows/masks (not feasible real-time without
mask generation), HDR/WCG (SDR-only pipeline), spectral rendering.

---

## What we have — full inventory

| Stage | What's implemented |
|-------|--------------------|
| Input | FILM_FLOOR/CEILING, EXPOSURE (power), R54 |
| Stage 1 | FilmCurve (per-channel knee/toe, percentile-anchored), Kodak 2383 R51, dye secondary absorption R50, 3-way color corrector R19 (shadow/mid/hl temp+tint) |
| Stage 2 | Zone S-curve (CLAHE-limited, auto), MSR illumination norm, shadow lift (ISL, texture-gated R58/R59, Retinex-gated, temporal context R60), chroma-stable tonal R62, Hunt coupling R65, ambient shadow tint R66 |
| Stage 3 | HELMLAB Fourier hue correction, Purkinje R52, saturation rolloff by luminance R22, per-band hue rotation R21, mean_chroma → adaptive chroma/density R36, spatial chroma modulation R68A, per-band chroma lift (PivotedSCurve ×6), Abney R12/R69, green-hue cool correction, H-K R15, density darkening, gamut pre-knee R68B, gclip |
| Stage 3.5 | Film halation R56 |
| Output | Pro-Mist R55 |

---

## Gap table

| Gap | Film equivalent | Impact | Impl cost | GPU cost | Verdict |
|-----|----------------|--------|-----------|----------|---------|
| Vibrance / chroma self-masking | Resolve Saturation curves + Color Boost | **H** | L | L | **Pursue R71** |
| Local contrast / output sharpening | Resolve Detail, Sharpen | **H** | M | L | **Pursue R72** |
| Memory color protection | Secondary CC hue qualifier | **H** | M | L | **Pursue R73** |
| Highlight desaturation | Film shoulder chroma rolloff | M | L | L | Pursue R74 |
| Hue-by-luminance rotation | Creative LUT / color wheels per zone | M | M | L | Pursue R75 |
| Creative 3D LUT slot | LUT node | L | L | M | Dismiss |
| HSL smooth curves | Hue qualifier with spline | L | H | L | Dismiss |
| RGB arbitrary curves | Custom curve per channel | L | H | L | Dismiss |
| Surround adaptation (CIECAM viewing conditions) | Display calibration | L | M | L | Dismiss |

---

## Gap analysis — detail

### Gap 1: Vibrance / chroma self-masking (PURSUE)

**What film tools do:** "Color Boost" / "Vibrance" applies higher lift to desaturated colors
and less (or zero) to already-saturated ones. The standard formulation: `lift = f(C) * (1 - C/Cmax)`.
In Resolve this is the "Saturation" curve with a custom envelope.

**What we do:** `PivotedSCurve(C, band_mean_chroma, chroma_str)` applied per band. The pivot
shifts per scene mean_chroma, but the per-pixel response is symmetric — a C=0.05 pixel and
a C=0.25 pixel in the same band get proportional treatment. There is no self-masking.

**Effect of the gap:** In scenes with a mix of saturated primaries (neon UI, energy effects)
and muted naturals (skin, stone, foliage), the lift pushes the already-saturated primaries
toward gamut boundary while the muted naturals barely move. The result reads as over-processed
primaries and flat naturals simultaneously. This is the most common complaint about automatic
chroma enhancement in game post-process.

**Fix:** Add a per-pixel descending weight `(1 - C / C_ceiling)` multiplied into the chroma
lift delta. `delta_C = lifted_C - C`. Attenuated delta: `delta_C * (1 - C / C_sat)`. This
preserves saturated colors exactly at their input value and maximally lifts achromatic ones.
C_ceiling can be 0.20–0.25 (well within sRGB gamut). Zero new taps.

---

### Gap 2: Local contrast / adaptive sharpening (PURSUE)

**What film tools do:** Resolve `Detail` / Baselight spatial `Clarity` applies
luminance-channel unsharp mask with a soft luminance gate (fires less in highlights to
avoid halation-like artifacts). Every professional grade includes some form of local
contrast enhancement.

**What we have:** R30 (wavelet clarity) was removed due to illuminant bleed (the
illumination component was being sharpened alongside reflectance, causing bloom).

**The Retinex separation already solves the old problem.** `log_R = log2(new_luma / illum_s0)`
is the reflectance component with illumination removed. Sharpening `log_R` and
reconstructing from it would boost micro-contrast on surfaces and geometry without
touching the illumination layer. This is precisely the technique behind "reflectance-based
sharpening" in computational photography (ECCV 2018, illuminant-invariant sharpening).

**Effect of the gap:** The pipeline has no perceptual acuity enhancement. Fine surface
detail (pores, weave, lettering, edge definition) looks slightly soft compared to a
graded reference. Pro-Mist actually softens further. Local contrast is the single most
visible difference between a graded and ungraded image in game content.

**Fix:** Derive a detail signal `d = log_R - gaussian_smooth(log_R)`. `illum_s0` is already
the "gaussian_smooth" approximation. So `d = log_R` (already computed) relative to a
lower-mip anchor. Boost `new_luma` proportional to `d`, gated by highlights. This is
essentially: `new_luma += CLARITY_STR * d * (1 - new_luma)`. Zero new taps (reuses
existing Retinex reads).

---

### Gap 3: Memory color protection (PURSUE)

**What film tools do:** Secondary CC with hue qualifier protects "memory colors" — the
perceptual anchors an observer uses to judge naturalness: sky (~BAND_CYAN/BLUE),
foliage (~BAND_GREEN/YELLOW-GREEN), skin (orange, ~h=0.22). These regions are isolated
and their saturation is capped or steered toward the remembered anchor.

**What we have:** Chroma lift is uniform across bands with only band mean_chroma as
context. No ceiling on any hue region. No skin protection.

**Effect of the gap:** When mean_chroma is low (pale, muted scene), chroma_str is high.
If a small region of cyan sky is present in an otherwise low-chroma scene, it gets the
same high chroma_str as everything else — sky turns neon. The pipeline has no mechanism
to say "this hue is already at its perceptual optimum, don't push further."

**Fix:** Per-band chroma ceiling. Each band has a `hist_cache[bi].r` (mean band chroma)
already. Cap `final_C` per-band at `C_target[band]` where target is perceptually calibrated
per hue. Sky: 0.18 (Oklab C, corresponds to vivid but not neon cyan). Skin: 0.14. Foliage:
0.16. Outside memory color hues: no cap. Implementation: replace the `max(lifted_C, C)`
identity limit with a soft ceiling per band.

---

### Gap 4: Highlight desaturation (PURSUE)

**What film does:** Print stocks naturally desaturate as density approaches paper white.
Kodak 2383 measured response shows chroma falls to ~20% of peak at D-min (the paper base).
The current R51 print stock model applies a midrange desat (line 269: `desat_w` fires
between luma 0 and 0.3, and 0.6 and 1.0) but it's symmetric — it also applies in shadows.

**What we're missing:** A chroma rolloff that specifically targets high-luma highlights
(luma > 0.8), independent of the shadow behavior, tied to the approach-white phenomenon.
R22 handles shadows (−20% chroma rolloff at luma < 0.25). The mirror effect in highlights
is missing.

**Fix:** Extend R22 to include an independent highlight rolloff arm:
```hlsl
C *= 1.0 - 0.30 * saturate((lab.x - 0.80) / 0.20);  // highlights desat on approach to white
```
This is two extra ALU ops. Visually: warm specular highlights stay orange/gold rather
than clipping to white with unnatural saturation at the boundary.

---

### Gap 5: Hue-by-luminance rotation (PURSUE)

**What film does:** Print stock dye response is not hue-neutral at extreme densities.
Shadows acquire a slight blue-green cast (silver halide base visible through thin dye
layer). Highlights acquire a slight warm cast (dye color at low density is warm-shifted).
This is distinct from R19 (3-way corrector) which applies uniform hue shifts per
luminance zone to all pixels.

**What we're missing:** Hue *rotation* that varies by luminance. Currently `r21_delta` is
hue-dependent but luminance-agnostic. In film, a red highlight shifts slightly more
toward orange than a red midtone does. This is a very subtle effect — 2–3° of hue
rotation across the luma range — but it contributes to the warmth differentiation
that makes a graded image feel "finished" vs. processed.

**Fix:** Multiply `r21_delta` by a luminance-dependent weight, or add a separate luma-driven
Abney-style per-band rotation. The magnitude is small (±0.01 in Oklab hue normalised units)
and the GPU cost is zero.

---

## Ranked implementation order

| Priority | ID | Topic | Gain/cost ratio |
|----------|----|-------|----------------|
| 1 | R71 | Vibrance chroma self-masking | Highest — fixes over-saturated primaries |
| 2 | R72 | Reflectance-based local contrast | Highest — fills clarity void post-R30 removal |
| 3 | R73 | Memory color protection | High — prevents neon sky/foliage |
| 4 | R74 | Highlight desaturation | Medium — completes R22 |
| 5 | R75 | Hue-by-luminance rotation | Medium — finishing detail |

R71 and R74 operate on the same chroma variables — can be implemented together.
R72 operates in Stage 2 (tonal), independent of all others.
R73 modifies the per-band loop — dependent on final_C computation in R71.
