# R197 — ReShade Ecosystem Review: Findings & Candidates

Repos surveyed: `crosire/reshade-shaders`, `martymcmodding/qUINT`,
`prod80/prod80-ReShade-Repository`, `luluco250/FXShaders`, `BlueSkyDefender/AstrayFX`.

---

## Candidates worth implementing (prioritized)

### 1. Blue-noise temporal dither at final output  [LOW COST / HIGH VALUE]

**Source:** `PD80_00_Noise_Samplers.fxh` (prod80)

**Algorithm:** Tile a 512×512 blue-noise texture. Each frame add the golden ratio
to the noise value: `noise = frac(noise + 0.61803398875 * frame_counter)`.
Apply as signed offset before the final `saturate()`:
`color += noise * (strength / 255.0)`.

**Why:** Our SDR 8-bit swapchain quantizes smooth gradients to visible banding.
Blue noise + golden-ratio temporal accumulation removes it with near-zero perceptual
cost and no GPU budget. One `tex2D` + one `frac()` per pixel.

**Where:** End of `DiffusionPS`, before the `return saturate(result)`.
Could also use the spatial hash from qUINT (`frac(dot(pos, float2(0.06711056, 0.00583715)) * 52.9829189)`)
if we want to avoid adding a texture — free but slightly worse spectral properties.

**Knob:** `DITHER_STRENGTH` (0 = off, 1 = 1 LSB at 8-bit). Default 1.

---

### 2. Per-hue exposure (brightness by hue band)  [MEDIUM COST / MEDIUM VALUE]

**Source:** `qUINT_lightroom.fx` (martymcmodding)

**Algorithm:** For each of the 12 hue bands, apply a luma-dampened exposure shift:
```
float gate = hue_band_weight * sqrt(C) * (1.0 - L) * C;
L_new = L * exp2(HUE_EXPOSURE[band] * gate);
```
The `(1 − L) * C` term makes the effect self-limiting: attenuates near white
(high L) and near gray (low C). Operates in Oklab L-channel only, chroma preserved —
consistent with our R62 Oklab-stable tonal pattern.

**Why:** We have per-hue hue rotation (R21) and saturation (R22/R73), but no
per-hue brightness control. This fills the gap for e.g. "make greens slightly
darker without shifting hue."

**Where:** Inside `ApplyChroma` after R21 hue rotation, before R73 memory ceilings.
12 new floats in `creative_values.fx` (`HUE_EXP_R` … `HUE_EXP_PURPLE`), all default 0.

---

### 3. Invertible piecewise power-law curve  [MEDIUM COST / MEDIUM VALUE]

**Source:** `luluco250/FXShaders / PiecewiseFilmicTonemap.fx`
(adaptation of John Hable's piecewise power curves)

**Algorithm:** Three-segment curve — toe and shoulder use `exp(ln_a + b * log(x))`,
linear mid. Fully invertible via `CurveSegment_eval_inv()` (closed-form).

**Why:** `inverse_grade.fx` currently reconstructs the pre-grade signal by chroma
expansion + per-hue ceiling, but does not exactly invert the FilmCurve. An analytic
inverse of our tone curve would let `inverse_grade` remove the curve before expanding
chroma, then re-apply it — eliminating curve-induced chroma desaturation in shadows.

**Tradeoff:** Our current rational FilmCurve is not a power-law form, so this would
require either (a) replacing FilmCurve with the power-law form, or (b) fitting an
invertible approximation to the existing curve. Option (b) is safer (no visible change
to the grade). Complexity: medium.

---

### 4. "Color" blend mode (hue+sat of source onto luma of destination)  [LOW COST / LOW-MEDIUM VALUE]

**Source:** `PD80_00_Blend_Modes.fxh` (prod80)

**Algorithm:** Convert both images to HSL. Take L from destination, H+S from source.
In Oklab: `result.L = dest.L; result.a = src.a; result.b = src.b`.

**Why:** Absent from our current toolbox. Useful for hue-selective corrections
(e.g. memory color ceilings, R73) that must not shift luminance. Currently we achieve
this via L-substitution (R62), but a named blend mode in a shared header would be
cleaner and reusable.

**Where:** Add to a new `blend_modes.fxh` (included by grade.fx, corrective.fx).
No knob needed — internal building block.

---

### 5. Multi-scale bloom pyramid  [HIGH COST / LOW VALUE FOR TESTBED]

**Source:** `qUINT_bloom.fx` (martymcmodding)

**Algorithm:** 7-scale pyramid (1/2 → 1/128 res). Downsample: 5-tap bilinear or
13-tap high-quality. Upsample merges layers. Per-scale intensity weights.
Bloom source compressed with Reinhard before downsampling to prevent highlight clipping.

**Why:** Our diffusion uses a single-sigma Gaussian (HBM model). A pyramid captures
lower frequencies (glow halos around bright areas) that our Gaussian misses.

**Why not yet:** 7 downsample + 7 upsample = 14 additional passes. The testbed GPU
is already saturated by UE5. Risk of crash. Revisit when testing on a less loaded GPU,
or if we drop another pass elsewhere.

---

## Reviewed and rejected

| Finding | Source | Reason |
|---------|--------|--------|
| Technicolor 2/3-strip simulation | PD80 | Creative effect, not perceptual — low relevance to grade pipeline |
| Hyperbola tone curve | PD80 | Our rational FilmCurve is higher quality; not worth switching |
| ACES fitted | luluco250 | HDR-designed, SDR-incompatible without pipeline restructure |
| Filmic Uncharted 2 + auto-exposure | PD80 | Auto-exposure intentionally excluded from pipeline |
| Selective Color (CMYK) | PD80 | Covered by our 12-band Oklab hue system; HSV-based form is less accurate |
| Color Isolation (desaturate by hue) | PD80 | Diagnostic/creative effect, not grading |
| Clarity (unsharp-mask local contrast) | AstrayFX | Covered by Retinex (R29) |
| Luminance EMA via mip chain | PD80 | Our histogram percentiles are strictly superior |
| Scene-adaptive color gradients | PD80 | Conflicts with no-auto-adaptation rule |
| Kelvin white balance | PD80 | CAT16 removed intentionally (R127); Kelvin conversion not needed |
| Chromatic aberration | PD80 | Aberration simulation, not correction; no depth buffer |
| Vignette | qUINT | Easy to add if ever needed; low priority |
| Perlin film grain | PD80 | Our R136 (PCG3D + Selwyn 2383 + Oklab) is more physically motivated |
| RT color cast removal | PD80 | Our histogram approach is more robust |
| Scene-luma luma fade gate | PD80 | No effects require whole-scene luma gating |

---

## Confirmed approaches (validates existing work)

- **Log2-luma → mip-average EMA** (PD80 FilmicTonemap): same pattern as our `analysis_frame.fx`. Confirms the method.
- **Lorentzian spatial weight** (PD80 CA): same family as our R106 tail. Confirms the choice.
- **Zone-split soft weights** `pow(1−L, 4)` (PD80 SMH): same as our zone masks in corrective. Confirms the approach.
- **Oklab L-only tonal with chroma preservation** (qUINT pattern, F5): matches our R62 pattern.
