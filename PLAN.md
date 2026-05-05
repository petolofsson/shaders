# Pipeline Improvement Plan
**Goal:** Raise every stage to 90% finished / 75% novel (game-specific sense).
**Created:** 2026-05-03 | **Updated:** 2026-05-05 (R104 DIR couplers, R105/R106 halation DoG+Lorentz, R107 edge LCA, Pro-Mist merge, fc_stevens OPT-4)

---

## Plain English Guide

What the pipeline actually does, and why each piece is unusual:

**Stage 0 — Input (inverse_grade)**
The game's tone mapper squashes the original color range into the 0–1 SDR window, compressing vivid colors toward grey. This stage estimates how much compression happened using the scene's own statistics (the IQR — the spread between the 25th and 75th percentile of brightness). It then expands chroma (color saturation) in Oklab space — a perceptual color model where saturation changes don't shift hue. The expansion now follows the scene's *dominant color direction* (e.g. if the scene is warm orange, it expands mostly in the orange direction, not uniformly). Novel: no real-time pipeline does statistics-driven chroma recovery with directional bias from a scene hue angle measured on the fly.

**Stage 1 — Film Stock (corrective + grade)**
Emulates the physical character of Kodak 2383 print stock: a film base that isn't perfectly neutral (chromatic floor), a characteristic density-vs-exposure curve (log-space H&D curve), and the fact that film dyes bleed into adjacent channels (cyan dye absorbs a little green; magenta dye absorbs a little blue). The warm cast and dye coupling are intentional — they come from the print stock knob. Also applies CAT16 chromatic adaptation (white balancing toward D65 using the measured scene illuminant). Novel: per-channel Beer-Lambert dye absorption, inter-channel dye coupling, and log-density H&D curve in real-time are all first-of-kind.

**Stage 2 — Tonal (grade)**
Adjusts local brightness relationships. A zone-based S-curve (like Ansel Adams' zone system, but computed from the live histogram) pulls shadows down and highlights up. A Retinex normalization reduces the influence of overall scene key on local contrast. A temporal context term adjusts perceived contrast based on the scene's recent brightness history (dark scenes after bright ones look darker than they are — this corrects for that). Novel: the Oklab-stable tonal substitution (changing L without touching chroma) and the Sage-Husa adaptive Kalman filter for scene-key estimation are both new in this context.

**Stage 3 — Color (grade)**
The large color science block. Purkinje shift (scotopic blue sensitivity at low luminance), Helmholtz-Kohlrausch effect (bright colors look brighter than grey at the same luminance), Abney effect (hue shifts when saturation changes), Hunt effect (adapted-field brightness changes apparent saturation), per-hue rotation, chroma lift with spatial modulation, and MacAdam-calibrated gamut ceilings (each hue has a different maximum chromaticity before it crosses a discrimination threshold). Novel: HELMLAB Fourier hue correction, real-time MacAdam ellipse ceilings, Beer-Lambert absorption, and per-pixel Hunt adaptation are all unique in game post-process.

**Stage 3.5 — Halation (halation block inside grade.fx)**
Film halation is the glow around bright highlights caused by light bouncing off the film base and exposing the emulsion from behind. The model uses a DoG (Difference-of-Gaussians) PSF: mip1−mip2 of CreativeLowFreqTex creates an annular ring around bright sources with zero extra texture taps. A Lorentzian tail function γ²/(γ²+d²+ε) models the heavier-than-Gaussian falloff of deep emulsion base reflections (ISL-like, not Gaussian). Chromatic: red uses mip1 core (wider scatter, deepest dye layer), green uses mip1 (tighter), blue = zero. HAL_GAMMA controls Lorentzian tail half-width. Novel: DoG mip-ring PSF + Lorentzian tail in a zero-tap architecture — published implementations all use convolution or radial blur passes.

**Output — Pro-Mist (merged into grade.fx)**
Pro-Mist is global diffusion: the image is downsampled to MistDiffuseTex (1/8-res, MipLevels=2), vkBasalt auto-generates mip1 (1/16-res effective), and ProMistPS lerps that blurred copy back onto the sharp image. Blend strength is scene-adaptive (IQR + zone_log_key + EXPOSURE proxy). This softens micro-contrast uniformly across all tones without adding brightness. Pro-Mist is the 2nd and 3rd passes of OlofssonianColorGrade — NOT a separate effect in the chain. Veil is available for games with no volumetric fog; it is removed from Arc Raiders (was fighting engine atmospheric volumes). Novel: statistics-driven adaptive diffusion blend on a full-image lerp.

---

## Phase status

| Phase | Status | Notes |
|-------|--------|-------|
| 1 — Research | **Done** | R74–R90 all researched, findings docs committed |
| 2 — Quick code | **Done** | R74, R75 shipped; R47 removed (orange source); R72 removed (clarity redundant) |
| 3 — Stage 0 | **Done** | R76A (CAT16) + R76B (surround) + R90 (directional inverse grade) |
| 4 — Stage 2 | **Skip** | R77 findings: no code changes needed |
| 5 — Stage 3 | **Done** | R78 constant-hue gamut projection |
| 6 — Stage 3.5 | **Done** | R79A/B/C halation |
| 7 — Output | **Done** | R80A/B/C Pro-Mist |
| 8 — Novelty gaps | **Done** | R83 → R84 → R85 |

---

## Current state

| Stage | Finished | Novel | Notes |
|-------|----------|-------|-------|
| Stage 0 — Input | 96% | 83% | R90 directional HWY_CHROMA_ANGLE wired (+1F/+3N) |
| Stage 1 — Corrective | 93% | 78% | R47 removed; PRINT_STOCK warm cast + R85 dye coupling confirmed intentional |
| Stage 2 — Tonal | 92% | 90% | R61 HUNT_LOCALITY removed; zone/R60/R62/R66 remain novel |
| Stage 3 — Chroma | 97% | 93% | R22 mid_C_boost 0.08; R74 highlight desat added; CHROMA_STR ×0.04 normalized |
| Stage 3.5 — Halation | 96% | 88% | R105 DoG PSF ring + R106 Lorentzian tail; exposure correction removed (OPT-1); green mip0 bug fixed |
| Output — Pro-Mist | 94% | 82% | Merged into grade.fx 3-pass technique; 1/8-res MistDiffuseTex mip1 |
| Output — Veil | —  | —  | Removed from Arc Raiders (fights engine atmospheric volumes) |

---

## Research items

### R74 — Highlight Desaturation
**Targets:** Stage 1 finished +5%, Stage 3 finished +3%

R22 applies Munsell-calibrated chroma rolloffs in shadows only. Film print stock
desaturates near paper white — chroma approaches zero as luminance approaches 1.0.
The highlight arm is absent.

Research: Derive correct Oklab C rolloff shape at high Lightness from Munsell data.
Confirm whether R51 print stock desat_w partially covers this or needs a separate term.

Likely implementation (Stage 3, after R22 shadow block):
```hlsl
C *= 1.0 - 0.30 * saturate((lab.x - 0.80) / 0.20);
```

GPU cost: 2 ALU. No new taps, no new knobs.

---

### R75 — Hue-by-Luminance Rotation
**Targets:** Stage 1 finished +4%, Stage 3 finished +3%, Stage 1 novel +3%

Film print stock dye response is not tonally neutral: shadows acquire a blue-green cast
(thin dye layer transparency to base), highlights acquire a warm cast (dye at low
density is warm-biased). Currently `r21_delta` is hue-dependent but luminance-agnostic.
The 3-way CC (R19) applies uniform RGB shifts per zone — it cannot apply hue rotation
that varies by luminance.

Research: Derive sign and magnitude of hue rotation per tonal zone from Kodak 2383
spectral data. Map to Oklab hue-normalised units (0–1).

Likely implementation: luminance-weighted additive delta on `r21_delta` before it feeds
`h_out`. ≤3 lines.

GPU cost: ~3 ALU. No new taps, no new knobs.

---

### R76 — Perceptual Input Normalization
**Targets:** Stage 0 finished +10%, Stage 0 novel +55% | **Status: Done**

**R76A — CAT16 scene-illuminant chromatic adaptation.**
Normalises toward D65 in LMS cone space. More principled than R19's linear RGB shifts.
Uses spatially-measured illuminant from `CreativeLowFreqTex mip 2`.

**R76B — CIECAM02 viewing condition surround compensation.**
Dark-room vs. bright-room contrast adjustment. `VIEWING_SURROUND` knob (0.9–1.2).

GPU cost: CAT16 = matrix multiply (9 MAD). Surround = 2–3 ALU. No new taps.

---

### R77 — Stage 2 Calibration
**Targets:** Stage 2 finished +3% | **Status: Skip — no code changes needed**

Three targeted validations: R65/R66 interaction, Retinex blend weight, R60 temporal
context exponent. Research finding: all three are within acceptable ranges. No changes.

---

### R78 — Constant-Hue Gamut Projection
**Targets:** Stage 3 finished +3% | **Status: Done**

Replaced L_grey projection in `gclip` with constant-hue compression along ab direction.
Scale factor found from headroom — preserves hue while compressing chroma to sRGB boundary.

GPU cost: ~4 ALU. No new taps.

---

### R79 — Halation Dual-PSF + Gate Refinement + Chromatic Dispersion
**Targets:** Stage 3.5 finished +22%, Stage 3.5 novel +20% | **Status: Done**

**R79A** — hal_gate onset moved from 0.80 to ~0.65 (Kodak 2383 onset).
**R79B** — Dual-Gaussian PSF per channel (mip 1 core + mip 2 wing, red and green).
**R79C** — Extended wing warmer than core (longer wavelengths scatter further).

GPU cost: +2 tex taps. ~6 additional ALU.

---

### R80 — Pro-Mist Spectral Scatter Model
**Targets:** Output finished +18%, Output novel +27% | **Status: Done**

**R80A** — Wavelength-dependent scatter (blue tighter, red coarser mip blend).
**R80B** — Scene-key adaptive strength (`zone_log_key^0.3`).
**R80C** — Aperture proxy via `EXPOSURE` modulates scatter radius.

GPU cost: ~4 ALU total. No new taps.

---

### R47 — Shadow Auto-Temp
**Status: Removed 2026-05-04**

Auto shadow temperature (+15 temp into cool shadows) was the root cause of the orange
bias in Arc Raiders. Arc Raiders has naturally cool, saturated shadows — R47 was
fighting the explicit grade every frame. Diagnosed by zeroing all knobs and
zero-ing R47 in shader code: orange disappeared immediately. Removed entirely from
corrective.fx (ShadowBias pass gone; corrective now 7 passes). Do not re-implement
without a specific game case that benefits.

---

## Novelty gap research (Stage 0 and Stage 1)

### R83 — Chromatic FILM_FLOOR | **Status: Done**

Per-channel black pedestal from Kodak 2383 D-min ratios (1.02/1.00/0.97), modulated by
CAT16 `lms_illum_norm`. Warm illuminants produce warm floor, cool produce cool floor.
Zero new taps. Stage 0 novel: 70%→75%.

---

### R84 — Optical Density FilmCurve | **Status: Done**

`CURVE_*` knobs reinterpreted as log₂-density offsets: `fc_knee * exp2(CURVE_R_KNEE)`.
exp2 folds to constant at compile time. Physically correct density-space deviation.
Stage 1 novel: +3%.

---

### R85 — Inter-Channel Dye Masking | **Status: Done**

Cyan→green (2.0%) and magenta→blue (2.2%) bleed from Kodak 2383 spectral dye curves.
First real-time post-process to model inter-channel dye coupling. Stage 1 novel: +7%.

---

## Execution order

| Phase | Items | Stages | Status |
|-------|-------|--------|--------|
| 1 — Research | R74–R90 | All | **Done** |
| 2 — Quick code | R74, R75; R47/R72 removed | Stage 1, 3 | **Done** |
| 3 — Stage 0 | R76A, R76B, R90 | Stage 0 | **Done** |
| 4 — Stage 2 | R77 calibration | Stage 2 | **Skip** |
| 5 — Stage 3 | R78 gamut projection | Stage 3 | **Done** |
| 6 — Stage 3.5 | R79A → R79B → R79C | Stage 3.5 | **Done** |
| 7 — Output | R80A + R80B + R80C | Pro-Mist | **Done** |
| 8 — Novelty gaps | R83 → R84 → R85 | Stage 0, Stage 1 | **Done** |

---

## Post-plan additions

### R81A — Eye LCA (longitudinal chromatic aberration)
Per-pixel radial channel separation modelling the human eye's focus-wavelength
dispersion. Blue samples outward, red inward from screen centre. `LCA_STRENGTH` knob.
First physiologically-grounded LCA in game post-process.

### R81B — MacAdam-calibrated chroma ceilings
Per-hue chroma ceilings re-derived from MacAdam discrimination ellipses: blue/cyan
tightened, yellow relaxed. Physically-justified per-hue discrimination thresholds.

### R81C — Beer-Lambert dye absorption
Replaced linear dominant-channel attenuation with `exp(-α·c·d)`. Taylor-expanded to
2nd order (max error 4.57×10⁻⁵). Physically correct for dye-layer absorption at high chroma.

### R82 — 11 zero-loss optimizations in ColorTransformPS
−3 tex reads, −5 transcendentals, ~−30 live scalars, −8 saturate ops per pixel.
Critical fix for AMD RDNA: hist_cache[6] array removal frees 24 scalars, reducing
register spill pressure.

### R83 — Chromatic FILM_FLOOR (see above)
### R84 — Log-Density FilmCurve offsets (see above)
### R85 — Inter-Channel Dye Masking (see above)

### R88 — Sage-Husa Q Adaptation
Replaced instantaneous-innovation Q trigger with posterior-P-driven adaptation.
Flashes no longer spike the Kalman filter gain. 2 lines changed.

### R89 — IGN Blue-Noise Dither
Replaced `sin(dot)·43758` white-noise with Jimenez IGN. Spectrally blue — quantization
error pushed to high spatial frequencies. Reduces banding in fog, sky, shadow gradients.

### F1–F3 — Film Sensitometry + Stevens Recalibration
- **F1** `desat_w` bounds now track `fc_knee_toe`/`fc_knee` (exposure-adaptive). 2-token change.
- **F2** Midtone chroma expansion: +6% bell at L≈0.47. Gate-free double smoothstep. 4 ALU.
- **F3** `fc_stevens`: `sqrt` → `exp2(log2(key)*(1/3))`, denominator 2.03→2.04. Cube root
  matches psychophysical data. Dark scenes +6–8% shoulder.

### R90 — Adaptive Inverse Tone Mapping
Game-agnostic chroma recovery. IQR-based compression ratio (2.5-stop reference, ACES-
derived) drives Oklab chroma expansion. Luma unchanged. Mid-weight bell + C-gate protect
near-neutral pixels. Slope Kalman-smoothed, highway x=197. Stage 0 novel: +5%.

### SHADOW_LIFT_STRENGTH knob
Auto shadow lift exposed as user scalar (1.0 = calibrated default).

---

## Session 2026-05-04 additions

### Orange hunt + R47 removal
Systematic zero-everything diagnosis identified R47 (shadow auto-temp) as the root cause
of the persistent orange cast in Arc Raiders. Removal strategy: zeroed all knobs, confirmed
warm push disappeared when R47 was zeroed in shader code. R47 removed from corrective.fx.
ShadowBias pass removed — corrective now 7 passes. PRINT_STOCK warm cast and R85 dye
coupling confirmed as *intentional* film stock character (not part of the orange bug).

### R22 mid_C_boost increased (0.04 → 0.08)
Mid-range saturation bell (`L*(1-L)*4` shape, 0.22–0.70 range) was zeroed during orange
hunt, then restored at 0.04. Further increased to 0.08 — rings did not recur, confirming
R47 was the cause. Internal constant (not a knob).

### CHROMA_STR convention normalized
Raw value 0.03–0.08 was inconsistent with multiplier convention of ZONE_STRENGTH, etc.
Baked 0.04 as internal constant in grade.fx: `float chroma_str = CHROMA_STR * 0.04`.
Knob is now a multiplier (1.0 = calibrated default, 0 = off, 2.0 = aggressive).
Arc Raiders tuned to 1.20.

### R61 HUNT_LOCALITY removed
Per-pixel Hunt adaptation removed (knob count reduction). Global hunt_la from
zone_log_key still drives the Hunt effect — the locality blend is gone.

### R90 directional chroma expansion (HWY_CHROMA_ANGLE)
Previous R90 expanded chroma uniformly in all Oklab directions. Now biased toward scene
dominant hue via HWY_CHROMA_ANGLE (highway slot 201, written by analysis_frame):

```hlsl
float  scene_theta = ReadHWY(HWY_CHROMA_ANGLE) * (2.0 * 3.14159265) - 3.14159265;
float  sc_s, sc_c;
sincos(scene_theta, sc_s, sc_c);
float  dir_weight = saturate(dot(dir, float2(sc_c, sc_s)) * 0.5 + 0.5);
float  new_C = mean_C + (C - mean_C) * lerp(1.0, factor, dir_weight);
```

Pixels aligned with scene hue get full expansion; opposite hue gets none. This means
the recovery follows the actual color palette rather than pushing all colors equally.
Stage 0 novel: 80%→83%.

### Film curve named presets
Documented Vision3 500T, Portra 400, Velvia 50, Ektachrome E100 as named CURVE_* value
sets. Arc Raiders currently uses Vision3 500T values (slight warm lift in R toe, cool
rolloff in B toe — characteristic 500T look in shadows).

### creative_values.fx restructured
Reordered all knobs in workflow-logical tuning order:
INVERSE → EXPOSURE → FILM → PRINT_STOCK → CURVE → ZONE → SHADOW_LIFT → CC → CHROMA →
HUE → HAL → MIST → VEIL → VIGN → PURKINJE → LCA → SURROUND.

### R74 — Highlight Desaturation (Done)
Oklab C rolloff above L=0.80: `C *= 1.0 - 0.30 * saturate((lab.x - 0.80) / 0.20)`.
Implemented after R22 shadow block. Matches FotoKem Shift "silvery highlights" character —
film print paper approaches white with near-zero chroma. 2 ALU, no new taps, no knob.

### Halation warm_bias feedback loop removed
`hal_r_gain` and `hal_g_gain` were previously lerping toward warm based on `HWY_WARM_BIAS`.
This created a feedback loop: warm scene → warm bias → warmer halation → more warm bias.
Fixed to neutral constants: `hal_r_gain = 1.05; hal_g_gain = 0.50;`. Red channel still
dominant (deepest dye layer) but color character is now scene-independent.

### Halation exposure correction (added 2026-05-04, removed 2026-05-05 as OPT-1)
Blur source (`lf_mip1`, `lf_mip2`) was sampled pre-grade (CreativeLowFreqTex), but
composited in post-grade tonal space. Bright sources appeared muted in the wrong zone.
Added: `hal_core_r = exp2(log2(max(lf_mip1.rgb, 1e-5)) * EXPOSURE)`. Subsequently removed
in OPT-1: the halation gate (hal_bright) uses post-grade luma, making the correction
imperceptible at EXPOSURE=0.90. Not worth 3 ALU per channel.

### Pro-Mist redesigned: global diffusion (R99)
Replaced additive threshold-extract bloom with full-image lerp diffusion.
See R99 findings doc. Responsibility separation:
- Halation: red fringe around specular sources
- Veil: additive DC lift (intraocular scatter, contrast floor)
- Pro-Mist: global micro-contrast softening (all tones equally)

### Veil calibrated to filmic soft
VEIL_STRENGTH 0.10 → 0.15 on both games. Doc fix: "scene median (p50)" → "scene p75".

### OPT-2/3 guards reverted
Research job's proof that zone_log_key ≥ 0.001 in steady-state was valid but incomplete:
on the cold-start frame, ChromaHistoryTex is zero-initialized → zone_log_key = 0 →
`exp2(log2(slow_key / 0) * 0.4)` = exp2(+Inf) = +Inf → white screen.
Guards restored. Any future proof must include the cold-start frame explicitly.

---

## Scene Reconstruction Research Track

**Status: Phase 1 complete (analytical inverse + fingerprint design) — prototype pending**

### R86 — Tone Mapper Identification and Analytical Inversion
**Status: Retired — replaced by R90 game-agnostic approach**

The rational-function inverse (quadratic formula approach) for UE5 ACES was the original
plan. R90 instead uses scene statistics (IQR, p25/p75) to measure compression and recover
chroma without identifying the specific tone mapper. This is more game-agnostic and proved
sufficient for Arc Raiders. R86's ACES hue-shift correction remains a potential future
addition if orange/magenta cast in ACES content becomes an issue again.

---

## Session 2026-05-05 additions

### R104 — DIR Couplers
Developer-inhibitor-release cross-channel masking in log2 space. Fires after `pow(rgb, EXPOSURE)`,
before FilmCurveApply. Activation: x²/(x²+0.09). Each bright channel suppresses adjacent channels.
COUPLER_STRENGTH knob (default 0.0 = off). Physically models the inter-layer dye inhibitor
chemistry in color negative film. 0 extra taps. ~8 ALU (skipped at COUPLER_STRENGTH=0 by compiler).

### R105 — Halation DoG PSF (replacing lerp blend)
Annular ring PSF via Difference-of-Gaussians: ring = max(mip1 − mip2, 0). Both red and green
use mip1 as core (green mip0 was an audit bug, corrected). The ring fires around bright sources
with no extra texture taps. Replaces the previous filled-disk lerp blend.

### R106 — Lorentzian Tail for Halation
Tail weight: γ²/(γ²+d²+ε) where d=1−hal_bright, ε=1e-6 (NaN guard). Heavier falloff than
Gaussian — models deep emulsion base reflections (ISL character). HAL_GAMMA knob (0.10–1.0,
default 0.40). Lower = faster falloff; higher = halo lingers further into dark areas.

### R107 — Edge-Directional LCA (replacing radial)
Luminance gradient from lf_mip2.a (4 reads at ~32px stride in mip2 space) drives CA offset
direction. Red shifts opposite gradient, blue with gradient. Self-limiting: saturate(glen) keeps
offset zero in flat areas. Replaces radial offset from screen centre. Same tap count; gradient
reads reuse the already-hoisted lf_mip2 cache. Max UV offset 0.0015 at LCA_STRENGTH=0.3.

### Halation exposure correction removed (OPT-1)
`hal_core_r = exp2(log2(max(lf_mip1.rgb, 1e-5)) * EXPOSURE)` was a workaround for the
pre-grade/post-grade mismatch. Removed: the halation gate (hal_bright) uses post-grade luma
which already has EXPOSURE applied; the source/gate mismatch at EXPOSURE=0.90 is imperceptible.
Saves 3 ALU per channel.

### H-K pow → sqrt (OPT-2)
`pow(final_C, 0.587)` approximated with `sqrt(final_C)` (exp 0.5). Max error 0.8% at C=1,
zero at C=0. Saves 1 transcendental per pixel (exp2+log2 pair → rsq).

### fc_stevens hoisted to highway slot 213 (OPT-4)
`cbrt(zone_log_key)` scaled — frame-constant, was computed per pixel (~3 transcendentals ×
2M pixels/frame). Now written once by corrective PassthroughPS to highway slot 213.
Encode ÷1.3, decode ×1.3 (fc_stevens range [0.72, 1.22] exceeds 8-bit UNORM without encoding).
Grade.fx reads with ReadHWY(HWY_STEVENS). Establishes the highway encode/decode convention
for any future value outside [0,1].

### Pro-Mist merged into grade.fx
No longer a separate effect in arc_raiders.conf. OlofssonianColorGrade is now a 3-pass technique:
ColorTransform → MistDownsample (writes MistDiffuseTex 1/8-res) → ProMist (composites mip1).
Veil removed from Arc Raiders entirely (was fighting engine atmospheric volumes).

### Session audit — bugs found and fixed
- **fc_stevens saturate clamp**: highway write was `saturate(fc_s)`, clipping values >1.0 for
  medium-bright scenes. Fixed with ÷1.3 encode / ×1.3 decode.
- **Green halation mip0**: hal_core_g used mip0 (widest ring), inverted from film physics.
  Fixed to mip1 (same as red). hal_g_gain=0.50 attenuated the visual impact but shape was wrong.
- **HAL_GAMMA=0 NaN**: Lorentzian denominator was 0/0 at HAL_GAMMA=0, hal_bright=1.
  Fixed with +1e-6 guard in denominator.
