# R76 Findings — Perceptual Input Normalization

**Date:** 2026-05-03
**Status:** Implement — R76A confirmed; R76B confirmed with design note

Sources: Li et al. 2017 (CAT16), CIE 159:2004 (CIECAM02), colour-science/colour
library (M16 matrix verification).

---

## R76A — CAT16 Scene-Illuminant Chromatic Adaptation

### M16 matrix (XYZ → CAT16 LMS)

```
M16 = [[ 0.401288,  0.650173, -0.051461],
       [-0.250268,  1.204414,  0.045854],
       [-0.002079,  0.048952,  0.953127]]
```

M16_inv (LMS → XYZ, numerically inverted):
```
M16_inv ≈ [[ 1.862068, -1.011255,  0.149791],
            [ 0.387526,  0.621447, -0.008973],
            [-0.015842, -0.034123,  1.049765]]
```

### Pipeline: sRGB → XYZ → LMS

sRGB linear is not XYZ. Must apply sRGB primaries matrix first:
```
sRGB_to_XYZ_D65 = [[0.4124564, 0.3575761, 0.1804375],
                    [0.2126729, 0.7151522, 0.0721750],
                    [0.0193339, 0.1191920, 0.9503041]]
```

Full per-pixel transform:
1. `lms_pixel = M16 * sRGB_to_XYZ_D65 * lin` (combined as one 3×3 matrix pre-multiplied)
2. Compute illuminant LMS: `lms_illum = M16 * sRGB_to_XYZ_D65 * illum_rgb`
3. D65 LMS: `lms_d65 = M16 * [0.9505, 1.0000, 1.0890]` = M16 * XYZ_D65
4. Per-channel gains: `gain = lms_d65 / max(lms_illum, 0.001)` (with D = 1.0)
5. Adapted LMS: `lms_adapted = lms_pixel * gain`
6. Back to linear sRGB: `lin = XYZ_to_sRGB * M16_inv * lms_adapted`

Steps 1, 2, 6 can each be pre-collapsed to a single 3×3 multiply. The per-pixel
cost is three 3×3 matrix multiplies, reduced by pre-multiplying pairs:
`M_cat = (XYZ_to_sRGB * M16_inv) * diag(gain) * (M16 * sRGB_to_XYZ_D65)`
= one combined matrix per frame, applied per pixel as one 3×3 multiply (~9 MAD).

### Degree of adaptation: D = 1.0

At typical monitor luminance with full scene-illuminant adaptation, D = 1.0 is
correct (ICC colour management convention). Partial D would only be needed to model
incomplete von Kries adaptation in psychophysical experiments.

### Illuminant estimate from CreativeLowFreqTex mip 2

`illum_s2_rgb` (already sampled in R66) is the scene spatial average at 1/32-res.
This is a reliable proxy for scene illuminant chromaticity — 256-pixel spatial
average, Kalman-smoothed, already validated in R66 research (temporal stability
confirmed). Mip 2 is in scope and free.

### CAT16 vs CAT02

CAT16 preferred: no negative LMS gamut issues that affect CAT02 on high-chroma inputs.
Symmetric and transitive at D=1. Better prediction accuracy on non-white illuminants.
CAT02's M matrix can produce negative LMS for saturated sRGB values — would cause
artefacts in the pipeline.

### Interaction with R19 (3-way CC)

After R76A, R19 SHADOW/MID/HIGHLIGHT TEMP/TINT become artistic deviations from
the CAT16-neutralised signal, not scene corrections. No conflict — clear separation
of purposes.

### Blend factor

Full D=1.0 CAT16 may be too strong for scenes with intentional warm grades (Arc
Raiders has fire, lava, torchlight that should remain warm). Apply at partial blend:
`lin = lerp(lin, cat16_corrected, 0.60)`. This retains 40% of the original scene
cast, preventing over-correction of artistically intended warm environments while
still normalising strong unintended illuminant deviations.

---

## R76B — CIECAM02 Surround Compensation

### Surround parameters (CIE 159:2004)

| Surround | c | c × z (z≈1.927) |
|---------|---|----------------|
| Average | 0.69 | 1.330 |
| Dim | 0.59 | 1.137 |
| Dark | 0.525 | 1.012 |

### Correction formula

Surround correction reduces to a power function on luminance. To view content
authored for average surround correctly on a dark-surround display:

```
L_out = L_in^(c_src_z / c_dst_z) = L_in^(1.330 / 1.012) = L_in^1.314
```

Applied to linear light input (before FilmCurve), approximated per-pixel:

```hlsl
lin = pow(max(lin, 0.0), 1.314);  // average → dark
```

Or parameterised by surround selection (dim to dark = L_in^(1.137/1.012) = L_in^1.123).

### Perceptual significance

Psychophysical validation (CIC21, Gao et al. 2025) confirms a ~10–20% contrast
difference between dim and dark surround viewing conditions. This is perceptually
noticeable in dark-room playtesting — shadow detail compresses, highlights flatten
without correction.

### Design note: source surround assumption

Arc Raiders / UE5 targets "typical living room or desktop" (dim surround). Applying
average→dark correction (exponent 1.314) would over-correct. The appropriate
correction for gaming content is **dim→dark: L_in^1.123**. A `VIEWING_SURROUND`
knob with three presets (dim→dark = 1.123, average→dark = 1.314, off = 1.0)
correctly handles both cases.

### Interaction with FilmCurve

Apply BEFORE FilmCurve. FilmCurve shapes the tonal response; surround correction
adjusts the input luminance distribution that FilmCurve operates on. Applying after
FilmCurve would distort the carefully calibrated knee/toe positions.

---

## Implementation order

1. R76A (CAT16): computed from illuminant in corrective stage, applied before Stage 1
2. R76B (surround): applied immediately after, before FilmCurve
3. Blend at 0.60 for R76A to preserve artistic warm casts
