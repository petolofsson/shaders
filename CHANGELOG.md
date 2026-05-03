# Changelog

## 2026-05-03 — session (R83–R89 + LCA tuning)

### Implemented
- **R83** Chromatic FILM_FLOOR (`grade.fx`): per-channel black pedestal from Kodak 2383
  D-min ratios (1.02/1.00/0.97), modulated by CAT16 `lms_illum_norm`. Zero new taps.
- **R84** Log-density FilmCurve (`grade.fx`): `CURVE_*` knobs reinterpreted as log₂-density
  offsets (`fc_knee * exp2(CURVE_R_KNEE)`). exp2 folds at compile time. CURVE_* values
  recalibrated for both Arc Raiders and GZW.
- **R85** Inter-channel dye masking (`grade.fx`): cyan→green 2.0% and magenta→blue 2.2%
  bleed inside Beer-Lambert block. First real-time implementation of inter-channel dye coupling.
- **R88** Sage-Husa Q adaptation (`corrective.fx`): Kalman Q in `SmoothZoneLevelsPS` and
  `UpdateHistoryPS` now driven by posterior P (accumulated uncertainty) rather than
  instantaneous innovation. Single-frame flashes no longer spike the filter gain.
- **R89** IGN blue-noise dither (`grade.fx`): Jimenez IGN replaces `sin(dot)·43758` white
  noise. Spectrally blue — banding in gradients reduced.
- **LCA** displacement halved (base scale 0.004→0.002); Arc Raiders `LCA_STRENGTH` 0.4→0.8.

### Research committed
- **R86** ACES analytical inverse — exact quadratic formula (4 ALU, float32 epsilon).
  Microsoft MiniEngine formula bug identified (wrong root). ACES confidence fingerprint
  designed from PercTex (zero new taps). Empirical calibration still needed.
- **R87** Lateral research (Telecommunications domain) — Sage-Husa Q and IGN dither
  identified as high-ROI candidates.

---

## 2026-05-03 — session (R78 + R79 + R80 + R76 + brightness fix)

### Implemented
- **R78** Constant-hue gamut projection (`grade.fx`): `gclip` now applied to Oklab
  `(f_oka, f_okb)` before `OklabToRGB` instead of projecting `chroma_rgb` toward grey
  in RGB space. Same formula, same cost, hue-accurate. Uses existing `rgb_probe` —
  one fewer float in registers. Note: correctness improvement, not a novelty gain.
- **R79** Halation dual-PSF + gate + warm wing (`grade.fx`): gate onset `0.80→0.70`
  (R79A); mip 2 extended wing tap added, 70% core / 30% wing per channel (R79B);
  green wing blend reduced to 20% for warm bias — red penetrates deeper in emulsion
  (R79C). +1 tex tap total.
- **R80** Pro-Mist spectral scatter model (`pro_mist.fx`): warm scatter tint
  `[1.05, 1.0, 0.92]` folded into existing R46 channel weights (R80A); scene-key
  adaptive `lerp(1.30, 0.80, smoothstep(0.05, 0.25, zone_log_key))` on `adapt_str`
  (R80B); aperture proxy `lerp(1.10, 0.90, ...)` via `EXPOSURE` (R80C). No new taps.

---

## 2026-05-03 — session (brightness fix + R76)

### Fixed
- **Brightness regression** diagnosed and resolved. Root cause: R72 clarity coefficient
  (`0.10`) created a systematic net brightness lift — `log_R` is positive for any pixel
  brighter than its local illuminant (the common case on lit surfaces), so the effect
  was one-sided upward. R72 removed entirely: game engines bake in sharpening/clarity,
  making it redundant.
- **FILM_CEILING** restored to `1.00` (passthrough). Ceiling/floor are now both
  passthrough (`FILM_FLOOR 0.000`, `FILM_CEILING 1.00`). Brightness is correct without
  requiring input headroom clamping.

### Implemented
- **R76A** CAT16 chromatic adaptation — normalises scene illuminant toward D65 using
  `CreativeLowFreqTex` mip 2 as illuminant estimate. Implemented as purely chromatic:
  adapted pixel is re-normalised to its original luma (`cat16 *= luma_in / Luma(cat16)`)
  before the 60% blend. Zero luminance impact — shadow lift, Retinex, zone contrast all
  see the same luma as without R76A. Illuminant normalised to unit luminance before gain
  computation, preventing absolute-brightness lift from scene-darker-than-D65 illuminants.
- **R76B** CIECAM02 surround compensation — `VIEWING_SURROUND` knob added to
  `creative_values.fx`. Default `1.00` = off. `dim→dark` (gaming): `1.123`.
  Applied as `pow(col.rgb, VIEWING_SURROUND)` before FilmCurve.

### Removed
- **R72** Reflectance local contrast (`new_luma += coeff * log_R * clarity_gate * (1-new_luma)`).
  Redundant with game sharpening. Net brightness bias regardless of coefficient sign.

---

## 2026-05-03 — commit `50c1cc4`

### Implemented
- **R47** Shadow warm bias (scene-adaptive shadow temperature): enabled with `zone_std`
  gate `smoothstep(0.06, 0.15, zone_std)` to suppress in flat/UI scenes. Was fully
  implemented in corrective.fx but never sampled in grade.fx; the ShadowBiasSamp tap
  and gated `sh_temp_auto` computation added to the R19 block.
- **R71** Vibrance self-masking: `vib_mask = saturate(1 - C / 0.22)` attenuates chroma
  lift delta on already-saturated pixels. Prevents over-saturating primaries while
  lifting flat naturals.
- **R72** Reflectance local contrast: `new_luma += 0.10 * log_R * clarity_gate * (1 - new_luma)`
  after Retinex normalisation. `log_R = log2(luma / illum_s0)` is illumination-free,
  so this sharpens surface detail without illuminant bleed (the fault that killed R30).
- **R73** Memory color protection: per-band Oklab C ceiling interpolated from
  `hw_o0–hw_o5` band weights (0.28 red / 0.22 yellow / 0.16 green / 0.18 cyan /
  0.26 blue / 0.22 magenta). `final_C = min(vib_C, max(C_ceil, C))` — never pushes
  below the input chroma.
- **R74** Munsell-calibrated highlight desaturation: R22 highlight arm coefficient
  `0.25 → 0.45`. Munsell data shows 50–60% chroma reduction at Value 9 for most hues;
  25% was ~2× too gentle.
- **R75** Hue-by-luminance (2383 tonal): `r21_delta += lerp(-0.003, +0.003, lab.x)`.
  ±1.1° hue rotation — cool shadows, warm highlights. Primarily affects neutral axis
  (achromatic pixels); below perceptual threshold on saturated colors.
- **creative_values.fx**: EXPOSURE 1.03→1.00, FILM_FLOOR 0.005→0.000, FILM_CEILING 0.95→1.00

### Research committed
R65–R80: 32 research documents (proposals + findings) covering Hunt chroma coupling,
ambient shadow tint, pipeline gap analysis, gamut knee, Abney validation, film pipeline
gap, vibrance, reflectance contrast, memory color, highlight desaturation, hue-by-luminance,
perceptual input normalization (CAT16 + CIECAM02), Stage 2 calibration validation, constant-hue
gamut projection, halation dual-PSF, and Pro-Mist spectral scatter.

### Removed
- `research/CHANGELOG_2026-05-01_session.md` — replaced by this file

---

## 2026-05-02 — commit `ceeb214`

- **R60** Temporal context: `context_lift = exp2(log2(slow_key / zk_safe) * 0.4)`
  boosts shadow lift during dark scene transitions, suppresses on re-entry.
- **R62 OPT-3** Chroma-stable tonal: zone S-curve applied in Oklab L space
  (`lab_t.x *= exp2(log2(r_tonal) / 3)`) to prevent S-curve from shifting chroma.
- HELMLAB Fourier hue correction: 2-harmonic correction
  `h_perc = h + (0.008 sin θ + 0.004 sin 2θ) / 2π` aligns Oklab hue toward perceptual.
- Shadow lift auto-range widened: max 1.30 → 1.50.
- SHADOW_LIFT / CHROMA_STRENGTH automation (R63).
- OPT-1/2/3: zero-error perf wins in ColorTransformPS.

---

## Attempted and reverted (no commit)

### 2026-05-03 — R76 first attempt (all-white failure, then fixed)
R76A first attempt caused all-white screen — root cause was R72's net brightness lift
inflating LMS values before the CAT16 gain calculation, spiking the blue gain channel.
Fixed in same session: R72 removed, R76A re-implemented with per-pixel luma
re-normalization for guaranteed luminance neutrality. Stable.
