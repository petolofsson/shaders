# Pipeline Improvement Plan
**Goal:** Reach 90%+ novel on every stage. All stages meet the 90%+ bar. Stage 0 ceiling confirmed at 87% (active testbed too achromatic for further gains). Stage 1 reached 90% via R130. Output reached 90% via R132.
**Created:** 2026-05-03 | **Updated:** 2026-05-08 (R132: polydisperse chromatic scatter radii — per-channel ch_scatter float3 in DiffusionPS, shimmer + midtone overlay)

---

## Plain English Guide

What the pipeline actually does, and why each piece is unusual:

**Stage 0 — Input (inverse_grade)**
The game's tone mapper squashes the original color range into the 0–1 SDR window, compressing vivid colors toward grey. This stage estimates how much compression happened using the scene's own statistics (the IQR — the spread between the 25th and 75th percentile of brightness). It then expands chroma (color saturation) uniformly in Oklab space — a perceptual color model where saturation changes don't shift hue. The C-gate and mid_weight bell protect near-neutrals from over-expansion. A per-hue chroma ceiling (HueCeil from hue_bands.fxh) prevents expansion past the natural gamut boundary for each hue. Novel: no real-time pipeline does IQR-based chroma recovery with Kalman-smoothed slope and per-hue gamut ceilings.

**Stage 1 — Film Stock (corrective + grade)**
Emulates the physical character of Kodak 2383 print stock: a film base that isn't perfectly neutral (chromatic floor), a characteristic density-vs-exposure curve (log-space H&D curve), and the fact that film dyes bleed into adjacent channels (cyan dye absorbs a little green; magenta dye absorbs a little blue). The warm cast and dye coupling are intentional — they come from the print stock knob. CAT16 chromatic adaptation was removed (R127) — game content is display-referred, warm lighting is art direction not a calibration error. Illuminant estimation (NeutralIllumTex) still runs to feed the chromatic floor and ambient shadow tint. Novel: per-channel Beer-Lambert dye absorption, inter-channel dye coupling, and log-density H&D curve in real-time are all first-of-kind.

**Stage 2 — Tonal (grade)**
Adjusts local brightness relationships. A zone-based S-curve (like Ansel Adams' zone system, but computed from the live histogram) pulls shadows down and highlights up. A Retinex normalization reduces the influence of overall scene key on local contrast. A temporal context term adjusts perceived contrast based on the scene's recent brightness history (dark scenes after bright ones look darker than they are — this corrects for that). Novel: the Oklab-stable tonal substitution (changing L without touching chroma) is new in this context; zone statistics use per-zone intra-pixel variance (histogram moments E[X²]−E[X]²) for a true texture/contrast signal rather than measuring spread between zones.

**Stage 3 — Color (grade)**
The large color science block. Purkinje shift (scotopic blue sensitivity at low luminance), Helmholtz-Kohlrausch effect (bright colors look brighter than grey at the same luminance), Abney effect (hue shifts when saturation changes), Hunt effect (adapted-field brightness changes apparent saturation), per-hue rotation, chroma lift with spatial modulation, and MacAdam-calibrated gamut ceilings (each hue has a different maximum chromaticity before it crosses a discrimination threshold). Novel: HELMLAB Fourier hue correction, real-time MacAdam ellipse ceilings, Beer-Lambert absorption, and per-pixel Hunt adaptation are all unique in game post-process.

**Stage 3.5 — Halation (halation block inside grade.fx)**
Film halation is the glow around bright highlights caused by light bouncing off the film base and exposing the emulsion from behind. The model uses a blur-minus-sharp PSF: `max(0, LowFreqMip1 − col)` fires only at dark pixels adjacent to bright sources, producing an annular ring with zero extra texture taps. (True DoG mip2−mip1 doesn't work — mip2 is 4× more diluted than mip1, so the ring is always zero.) A Lorentzian tail function `hal_ring_luma / (hal_ring_luma + HAL_GAMMA + 1e-6)` models the heavier-than-Gaussian falloff of deep emulsion base reflections — `hal_lore` is high for bright ring glow, zero where there's no halation. Red adds a LowFreqMip2 broad component (fixed 0.12 — scatter radius is determined by emulsion geometry, not source brightness). Chromatic gains: red 1.05 (dominant, deepest dye layer), green 0.45 (attenuated by Lorentzian 0.78–0.94×), blue 0.03 (faint — yellow filter blocks most blue, `lerp(0.22, 0.38, hal_lore)`). White sources produce orange/amber fringe. HAL_GAMMA controls the Lorentzian knee. Novel: blur-minus-sharp annular PSF + Lorentzian tail at zero texture taps; chromatic model derived from film emulsion physics (dye layer depth, yellow filter absorption).

**Output — Diffusion (merged into grade.fx)**
Diffusion is a HBM (Hollywood Black Magic) dual-component model. The image is downsampled 4× (4-tap box) to DiffusionTex (1/4-res), then blurred by a separable 9-tap Gaussian (σ=2 output texels ≈ 8px at 1080p) in two sub-res passes (DiffusionBlurH → DiffusionHorizTex → DiffusionBlurV → DiffusionTex). DiffusionPS reads the single fully-blurred source and applies: A) additive shimmer `max(0, blurred − sharp) * src_gate * adapt_str` — highlight scatter only (Reinhard knee 0.08); B) soft midtone overlay `lerp(result, diff_blur, eff_diff * 0.06 * mid_gate)` — bell-gated at luma×(1−luma)×4, zero at blacks/whites. Strength adapts to scene IQR, zone_log_key, and EXPOSURE. Radial vertical oval (xs=1.6, ys=0.08): clarity runs full height at center, diffusion increases left/right (~25% screen width at mid-ramp). Diffusion is passes 5–8 of OlofssonianColorGrade. Novel: statistics-driven adaptive additive shimmer on per-pixel highlight extraction with Gaussian-blurred smooth falloff.

---

## Novelty gap — paths to 90%+

Three stages are below the new 90% target. The non-novel mass in each is identified; candidate additions are listed with estimated novelty delta.

### Stage 0 — Input (87% — ceiling confirmed)

Non-novel mass: uniform chroma boost concept (~10%), mid_weight bell (~3%). The IQR/slope/Kalman/pivot/C-gate/ceilings are all novel — the drag is the base operation itself.

**Cross-band saturation normalisation — ruled out 2026-05-08.** Refined candidate: use per-hue HueCeil as a normaliser to detect which bands are disproportionately compressed (`sat_ratio[b] = pivot[b] / HueCeil(center_b)`), then drive per-band expansion slope from a scene-internal reference ratio. Diagnostically tested via wsum capture: active testbed is ~80% achromatic. All six band wsums ≈ 0 even in the most colorful scene (max wsum=0.015). The technique defaults to global slope every frame — it has nothing to work with. 87% is the real ceiling for this testbed, not a calibration problem. Not viable without content with measurable per-hue chroma (wsum > 0.1 in at least 2 bands).

### Stage 1 — Film Stock (87% → 90%+)

Non-novel mass: basic S-curve shape (~5%), bleach bypass concept (~4%), 3-way CC concept (~4%). R104/R85/R81C/R110 are first-of-kind; they carry the current score.

**R130 — Kodak 2383 spectral dye matrix — Done 2026-05-08.** Replaced R81C Beer-Lambert proxy + R85 empirical coupling with a 3×3 matrix derived from Kodak H-1-2383t spectral dye density curves (agx-emulsion digitization / National Archives 2005 PDF, cross-checked, ±0.001 agreement). Matrix coefficients (normalized per-dye, primary=1.00): Cyan R/G/B = 1.00/0.14/0.09; Magenta = 0.15/1.00/0.09; Yellow = 0.01/0.06/1.00. R85 empirical values (30.8%/33.8% of primary) were 2–4× higher than the actual Kodak data; corrected. Four previously absent cross-channel terms added (Cyan→B, Magenta→R, Yellow→G, Yellow→R). +3% novelty: first real-time post-process to use published Kodak 2383 spectrophotometric data as compile-time constants.

### Output — Diffusion (87% → 90% ✓)

Non-novel mass: bloom/glow concept (~8%), Reinhard knee (~3%), lerp blending (~2%). The additive shimmer + three-scale + scene-adaptive + polydisperse carry the score.

**R132 — chromatic scatter radii — Done 2026-05-08.** Real mist/diffusion filter media are polydisperse — particle size distribution causes longer wavelengths (red) to scatter more broadly than shorter wavelengths (blue). Applied `float3 ch_scatter = float3(1.15, 1.00, 0.85)` to both DiffusionPS components: shimmer `bloom_raw / (bloom_raw + 0.08) * src_gate * ch_scatter` and midtone overlay `eff_diff * 0.06 * mid_gate * ch_scatter`. Analogous to halation chromatic model (R105) but for diffuse scatter rather than specular ring. +3% novelty. Zero new taps, ~3 ALU, no new knobs (physics constant).

---

## Phase status

| Phase | Status | Notes |
|-------|--------|-------|
| 1 — Research | **Done** | R74–R90 all researched, findings docs committed |
| 2 — Quick code | **Done** | R74, R75 shipped; R47 removed (orange source); R72 removed (clarity redundant) |
| 3 — Stage 0 | **Done** | R90 (directional inverse grade) — R76A CAT16 implemented then removed R127 (display-referred content) |
| 4 — Stage 2 | **Skip** | R77 findings: no code changes needed |
| 5 — Stage 3 | **Done** | R78 constant-hue gamut projection |
| 6 — Stage 3.5 | **Done** | R79A/B/C halation |
| 7 — Output | **Done** | R80A/B/C Pro-Mist |
| 8 — Novelty gaps | **Done** | R83 → R84 → R85 |

---

## Current state

| Stage | Finished | Novel | Notes |
|-------|----------|-------|-------|
| Stage 0 — Input | 97% | 87% | R117A: uniform chroma expansion + mean-C pivot; per-hue gamut ceilings; C-gate uniqueness undercounted in prior audit |
| Stage 1 — Film Stock | 97% | 90% | R130: Kodak 2383 spectral dye matrix (3×3 from H-1-2383t); replaces R81C proxy + R85 empirical; +3% novelty |
| Stage 2 — Tonal | 95% | 90% | Intra-zone variance (R116), Oklab-stable tonal (R62), temporal context (R60), R66 ambient tint — all underweighted in prior audit |
| Stage 3 — Chroma | 98% | 93% | Aligned with HANDOFF; R117D memory color attraction + simultaneous contrast counted; Abney coefficient gap remains minor |
| Stage 3.5 — Halation (grade.fx, ColorTransformPS) | 97% | 91% | R114: chromatic fringe (orange/amber); baked into MegaPass — not a separate effect |
| Output — Diffusion (grade.fx, passes 5–8) | 96% | 90% | R132: polydisperse chromatic scatter radii — ch_scatter float3(1.15,1.00,0.85) on shimmer + midtone overlay |

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

**R76B — CIECAM02 viewing condition surround compensation. Removed 2026-05-06.**
Outside environment is not the pipeline's responsibility to compensate for.

GPU cost: CAT16 = matrix multiply (9 MAD). No new taps.

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
bias found during calibration. In content with cool, saturated shadows R47 fought the
explicit grade every frame. Diagnosed by zeroing all knobs then zeroing R47 in shader
code: orange disappeared immediately. Removed entirely from
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

### R81A — Eye LCA (longitudinal chromatic aberration) — **Removed 2026-05-06**
Revised 10+ times across multiple sessions. Fundamental problem: no way to exclude UI text
without a UI mask. Fires on text with any luminance or edge model. Permanently removed.

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
of the persistent orange cast found during calibration. Removal strategy: zeroed all knobs,
confirmed warm push disappeared when R47 was zeroed in shader code. R47 removed from
corrective.fx. ShadowBias pass removed — corrective now 7 passes. PRINT_STOCK warm cast
and R85 dye coupling confirmed as *intentional* film stock character (not part of the orange bug).

### R22 mid_C_boost increased (0.04 → 0.08)
Mid-range saturation bell (`L*(1-L)*4` shape, 0.22–0.70 range) was zeroed during orange
hunt, then restored at 0.04. Further increased to 0.08 — rings did not recur, confirming
R47 was the cause. Internal constant (not a knob).

### CHROMA_STR convention normalized
Raw value 0.03–0.08 was inconsistent with multiplier convention of ZONE_STRENGTH, etc.
Baked 0.04 as internal constant in grade.fx: `float chroma_str = CHROMA_STR * 0.04`.
Knob is now a multiplier (1.0 = calibrated default, 0 = off, 2.0 = aggressive).
Testbed tuned to 1.20.

### R61 HUNT_LOCALITY removed
Per-pixel Hunt adaptation removed (knob count reduction). Global hunt_la from
zone_log_key still drives the Hunt effect — the locality blend is gone.

### R90 directional chroma expansion — **Reversed by R117A**
Was biased toward scene dominant hue via HWY_CHROMA_ANGLE. Removed: multi-hue scenes
(warm practicals + cool fill) were under-expanding colours orthogonal to the dominant hue.
The C-gate and mid_weight bell already protect neutrals — directional constraint was redundant.
`scene_theta`, `sincos`, `dir_weight` removed. Current: `new_C = mean_C + (C - mean_C) * factor` — uniform.
HWY_CHROMA_ANGLE slot 201 still written by analysis_frame but no longer read by inverse_grade.

### Film curve named presets
Documented Vision3 500T, Portra 400, Velvia 50, Ektachrome E100 as named CURVE_* value
sets. Vision3 500T: slight warm lift in R toe, cool rolloff in B toe — characteristic
500T shadow look. Portra 400: warmer toe, more open shadows.

### creative_values.fx restructured
Reordered all knobs in workflow-logical tuning order:
INVERSE → EXPOSURE → FILM → PRINT_STOCK → CURVE → ZONE → SHADOW_LIFT → CC → CHROMA →
HUE → HAL → MIST → VIGN → PURKINJE.

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
- Pro-Mist: additive shimmer from highlights + neutral shadow lift

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
chroma without identifying the specific tone mapper. This is game-agnostic and sufficient
across tested content. R86's ACES hue-shift correction remains a potential future
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
No longer a separate effect in the chain config. OlofssonianColorGrade is a 5-pass technique:
LFDownscale1 → LFDownscale2 → ColorTransform → MistDownsample → ProMist. LFDownscale passes added by R113 to work around vkBasalt cross-technique mip-generation bug.
### Session audit — bugs found and fixed
- **fc_stevens saturate clamp**: highway write was `saturate(fc_s)`, clipping values >1.0 for
  medium-bright scenes. Fixed with ÷1.3 encode / ×1.3 decode.
- **Green halation mip0**: hal_core_g used mip0 (widest ring), inverted from film physics.
  Fixed to mip1 (same as red). hal_g_gain=0.50 attenuated the visual impact but shape was wrong.
- **HAL_GAMMA=0 NaN**: Lorentzian denominator was 0/0 at HAL_GAMMA=0, hal_bright=1.
  Fixed with +1e-6 guard in denominator.

---

## Session 2026-05-06 additions (R114 / R115 / R116)

### R114 — Halation chromatic fringe
Halation was producing purely red/green fringe (blue=0 hardcoded). Added `hal_b` component:
`hal_b = hal_ring.b * lerp(0.22, 0.38, hal_lore)` — stronger toward bright cores (0.38), lighter in the dark annulus (0.22). Gains: `float3(1.05, 0.45, 0.03)`.
White surfaces produce orange/amber fringe (red dominant + faint blue). Red dominance preserved
(deepest emulsion layer; yellow filter layer attenuates blue but passes orange/red).

### R115 — Pro-Mist shimmer model
ProMistPS changed from symmetric lerp diffusion to additive unilateral bloom:
`base + max(0, blurred − base) * strength`. The lerp model muted shadows alongside brightening
highlights — correct for diffusion fog, wrong for a Pro-Mist shimmer filter. New model adds
scatter from highlights only. MIST_STRENGTH 5.0 → 1.5.

### R116 — Color pipeline audit (9 issues)

Full audit of all statistical and logical issues in the pipeline. Research papers in
`research/R116_2026-05-06_color_pipeline_audit.md` and `_findings.md`.

**Implemented fixes (in priority order):**
1. **Chroma ceiling before vibrance** — 1 ALU, zero risk
2. **HWY_SLOPE minimum clamp** — 1 line, eliminates cold-start identity
3. **Adaptive CAT16 blend** — 3 ALU, better correction in neutral scenes
4. **Chroma median (CDF p50)** — replaces arithmetic mean; eliminates outlier bias in shadows
5. **Pure global percentiles for eff_p25/p75** — eliminates incompatible statistics blend
6. **Linear zone log key** — linear mean of zone medians; equal-weight zones
7. **Intra-zone pixel variance** — histogram moments E[X²]−E[X]² per zone; R88 VFF Kalman removed

**What was deliberately NOT changed:**
- Issue 6 (triple highlight compression) — stacking is physically correct; measure before changing
- Issue 7 (black lift documentation) — comment-only; low priority
- Switching to intra-zone std immediately recommended ZONE_STRENGTH retune before finalising

---

## Session 2026-05-06 additions (R117)

### R117 — Stage gap closures (3 changes)

**Stage 0 — Uniform chroma expansion** (`inverse_grade.fx`)
Removed directional bias (`dir_weight` cosine toward HWY_CHROMA_ANGLE). Multi-hue scenes
(warm practicals + cool fill) were under-expanding colours orthogonal to the dominant hue.
The C-gate and mid_weight already protect neutrals — the directional constraint was redundant.
`scene_theta`, `sincos`, `dir_weight` removed. `new_C = mean_C + (C - mean_C) * factor`.
Saves 1 sincos + ~4 ALU. Stage 0: 95/85 → 97/86.

**Stage 3.5 — Halation brightness-scaled PSF** — *REJECTED (R124 research)*
Film halation scatter radius is fixed by emulsion geometry, not source intensity. Brighter
sources produce stronger amplitude, not a wider kernel — amplitude already scales naturally
via `hal_ring = max(0, blur − sharp)`. Fixed broad factor 0.12 is physically correct.

**Output — Pro-Mist three-scale blur** (`grade.fx`) — *DONE (R117C)*
`MistDiffuseTex` MipLevels 2 → 3. vkBasalt auto-generates mip2 within-technique.
`ProMistPS` adds `mist_broader = tex2Dlod(..., LOD 2)`. Blended via
`broad_w = saturate(MIST_STRENGTH * 0.20 − 0.10)` — ramps above ~0.5. Output Pro-Mist: 93/84 → 95/86.

---

## Session 2026-05-08 additions (R127 / R127B / novelty audit)

### R127 — CAT16 removed; chroma lift pivot fixed

**CAT16 pixel correction removed** (`grade.fx`) — Game content is display-referred (sRGB→D65).
CAT16 was treating artistic warm lighting as a calibration error and cooling it. Removed.
`NeutralIllumTex` / `lms_illum_norm` kept to feed R83 (chromatic floor) and R66 (ambient tint).
Highway slot 216 (cat_blend) removed.

**Chroma lift pivot fixed** (`corrective.fx UpdateHistoryPS`) — `MIN_WEIGHT = 1.0` was adding
unconditional weight to every pixel, pulling per-band pivot toward zero and making
`LiftChroma`'s `t = 1 − C/pivot` saturate to 0 for all colored pixels — lift was silently inert.
Fixed: weight = `HueBandWeight * smoothstep(0.03, 0.08, C)`. Achromatic pixels contribute zero;
pivot is now the actual mean chroma of colored pixels. Chroma lift now works as designed.

### R127B — FilmCurve body S-curve revised

R126 formula `x*(1-x)*(1-2x)*0.12` lifted shadows (+9% at x≈0.2) — net image flattening.
Replaced with one-sided midrange-weighted S: `max(0, (x*(1-x))²*(2x-1))*0.65`.
Shadows (x≤0.5) untouched by construction. Upper mids peak +1.2% at x≈0.72, zero at x=1.

### R128 — Specular pings — *ATTEMPTED AND REVERTED*

Design: smooth-space detection of isolated specular hotspots by comparing `ping_local` (1/16-res)
against `ping_broad` (1/32-res). Additive warm lift `float3(1.04, 1.00, 0.92)` at hotspots.
`SPECULAR_PING` knob in `creative_values.fx`. Zero additional texture reads (hoist of duplicate
`lf_mip1` tap). Good in theory — detection logic is sound. Bad in practice: did not hold up
in-game. Research doc: `research/R128_2026-05-08_specular_pings.md`.

### R130 — Kodak 2383 spectral dye absorption matrix
Replaced R50/R81C diagonal Beer-Lambert + R85 two-term empirical coupling with a full 3×3
spectral matrix derived from Kodak H-1-2383t dye density curves. Source: agx-emulsion
digitization of the official Kodak datasheet (National Archives 2005 PDF, Status A
densitometry). Matrix normalized per-dye (primary channel = 1.00). R85's cyan→G (30.8%
of primary) and magenta→B (33.8%) were 2–4× the physical values; corrected to 14% and 9%.
Four absent terms added: Cyan→B (9%), Magenta→R (15%), Yellow→G (6%), Yellow→R (1%).
Zero runtime cost change — compile-time constants. Stage 1 novel: 87% → 90%.

### R129 — Cross-band saturation normalisation — *RULED OUT*

Proposed: use HueCeil as scene-internal chroma normaliser to drive per-hue expansion slopes
in `inverse_grade.fx`. `sat_ratio[b] = pivot[b] / HueCeil(center_b)`. Requires per-band
wsum > 0 to be meaningful. Diagnostic: 3-file wsum capture (slots 220–225 added to highway,
PassthroughPS, capture.py). Result: active testbed ~80% achromatic; all band wsums ≈ 0 even in
most colorful scene (max 0.015). Technique permanently defaults to global slope. Slots removed
after capture. Stage 0 ceiling confirmed at 87% for this testbed.

### Novelty audit — 2026-05-08

Stage scores corrected after cross-referencing code against game post-process state of the art:
- **Stage 0** 86% → 87%: C-gate + mean-C pivot uniqueness undercounted
- **Stage 1** 85% → 87%: R104 DIR couplers + R85 dye coupling + R81C Beer-Lambert all first-of-kind in real-time; undercounted
- **Stage 2** 88% → 90%: Intra-zone variance (histogram moments), Oklab-stable tonal, R60 temporal context, R66 ambient tint all undercounted
- **Stage 3** 94% → 93%: Corrected downward to align with HANDOFF (R117D + simultaneous contrast counted; Abney gap still present)
- **Stage 3.5** finished 96% → 97%: Aligned with HANDOFF (R114 was the closing piece)
- **Output** finished 95% → 96%, novel 86% → 87%: Polydisperse three-scale novelty now counted

---

## Session 2026-05-08 additions (Diffusion blur quality + shadow lift audit)

### Diffusion — Gaussian blur architecture (grade.fx)

Replaced mip-based multi-scale shimmer with a separable Gaussian blur chain:
- **DiffusionTex**: 1/8-res → 1/4-res; MipLevels 3 → 1 (mips no longer needed)
- **DiffusionDownsamplePS**: single tap → 4-tap box filter for proper 4×4 source coverage
- **DiffusionBlurHPS** (new pass): 9-tap horizontal Gaussian, σ=2 output texels, DiffusionTex → DiffusionHorizTex
- **DiffusionBlurVPS** (new pass): 9-tap vertical Gaussian, DiffusionHorizTex → DiffusionTex
- **DiffusionPS**: simplified from 3 mip samples + mip-blend to single `diff_blur` sample. Both shimmer and midtone overlay use the Gaussian-blurred source. Grade now 8 passes (was 6).
- **src_gate**: `smoothstep(0.15, 0.45, Luma(blurred))` — suppresses shimmer on dark blurred regions, preventing spots on ground textures.

### Diffusion — vertical oval radial gradient (grade.fx)

Replaced circular `length(uv - 0.5)` with `length(float2(c.x * 1.6, c.y * 0.08))`. Oval extends past screen top/bottom (y boundary at 5.3× screen height — full clarity top-to-bottom); horizontal ramp ~25% screen width at mid-diffusion. Matches large-format lens character: horizontal softening, vertical clarity.

### Shadow lift audit (grade.fx ColorTransformPS)

Three fixes from a full audit of the shadow lift chain:

1. **detail_protect loosened**: `smoothstep(-0.5, 0.0, log_R)` → `smoothstep(-2.0, -0.5, log_R)`. Old gate closed at log_R = -0.5 (pixel 29% below local illuminant) — suppressing actual shadow pixels. New gate allows lift up to 1.5 stops below local illuminant; only genuine dark materials (2+ stops) are suppressed.

2. **local_range_att removed**: `1.0 - smoothstep(0.20, 0.50, zone_iqr)` was a scene-wide IQR gate suppressing lift globally in contrasty scenes (zone_iqr > 0.35 → lift < 50%). Per-pixel gates (texture_att, fine_texture_att, detail_protect) already provide spatial protection — scene-wide gate was redundant and counterproductive.

3. **lift_w ceiling raised**: `smoothstep(0.25, 0.0, new_luma)` → `smoothstep(0.27, 0.0, new_luma)`. Marginal extension of the shadow luma window (0.25 confirmed appropriate in prior testing; 0.27 adds slight headroom).

---

## Session 2026-05-08 additions (R132 — polydisperse chromatic scatter; R52 Purkinje upgrade)

### Diffusion — per-channel scatter radii (grade.fx DiffusionPS)

**R132:** Added `float3 ch_scatter = float3(1.15, 1.00, 0.85)` to DiffusionPS. Applied to both components:
- **Shimmer**: `bloom_raw / (bloom_raw + 0.08) * src_gate * ch_scatter` — red shimmer 15% stronger, blue 15% weaker.
- **Midtone overlay**: `eff_diff * 0.06 * mid_gate * ch_scatter` — red haze blends more toward diff_blur, blue less.

Physics: polydisperse filter media (polyethylene glycol / glass micro-spheres) have a particle size distribution where longer wavelengths scatter with a broader angular distribution. Mirrors the halation chromatic model (R105) which uses different mip scales per channel. Zero new taps, ~3 ALU, no new knobs. Output stage: 87% → 90%.

### R52 Purkinje — blue-green correction + scotopic desaturation (grade.fx ColorTransformPS)

Two fixes to the existing Purkinje shift:
- **a* component added**: `lab.y -= 0.006 * scotopic_w * C * PURKINJE_STRENGTH` — rod peak is 507nm (blue-green), not pure blue. Previous b*-only shift targeted cyan-blue; adding a* steers correctly toward blue-green.
- **Scotopic desaturation**: `lab.yz *= 1.0 - 0.12 * scotopic_w * PURKINJE_STRENGTH` — rods are achromatic; deep mesopic shadows should lose chroma alongside the hue shift. Applied after hue shift, before `C = length(lab.yz)` recompute. ~3 ALU total, no new knobs.
