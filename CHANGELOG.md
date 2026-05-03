# Changelog

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

### 2026-05-03 — R76 all-white failure
R76A (CAT16 chromatic adaptation) + R76B (CIECAM02 surround compensation) caused
all-white screen on load. Reverted to `50c1cc4`. See HANDOFF.md for root cause
analysis and recommended debug strategy.
