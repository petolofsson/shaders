# Job — Shader System Stability Audit

**Schedule:** 0 3 * * * (3 AM UTC)
**Output:** `research/R{next}_{YYYY-MM-DD}_stability.md`

## Summary

Nightly code audit — no web search, no source modifications. Five tasks:
A. Register pressure in ColorTransformPS (spill threshold: 128 scalars)
B. Unsafe math sites (log/pow/div-by-zero/sqrt/atan2/exp2)
C. BackBuffer row guard verification (y=0 data highway)
D. Temporal history accumulation (EMA coefficients, format, cold-start safety)
E. Targeted review of most recent additions (see below)

## Files to audit (active chain only)

`general/grade/grade.fx` · `general/corrective/corrective.fx` ·
`general/analysis-frame/analysis_frame.fx` · `general/inverse-grade/inverse_grade.fx` ·
`general/highway.fxh` · `general/hue_bands.fxh`

## Known-good baseline (R116 audit, 2026-05-06)

- **Register pressure**: 59 VGPRs / 87 SGPRs (RADV dump). No spilling. `scratch_en: false`.
- **BackBuffer guards**: all present — grade.fx, corrective.fx, inverse_grade.fx.
  R113 finding: `tex2Dlod(BackBuffer, ...)` always returns zero in vkBasalt; all BackBuffer
  reads now use `tex2D`. Cross-technique render targets only populate mip0 —
  LFDownscale1/2 passes in grade.fx are the fix.
- **EMA coefficients**: all bounded (0,1). History textures use RGBA16F or R16F.
- **Cold-start safety**: `max(slope_enc * 1.5 + 1.0, 1.15)` in inverse_grade.fx (R116 Issue 9)
  prevents uninit x=197 from decoding as slope=1.0. OPT-2/3 guards retained (cold-start
  regression confirmed if removed).
- **Data highway slots**: no write collisions. Slots: 0–128 luma · 130–193 hue ·
  194–196 p25/p50/p75 · 197 R90 slope · 198 median C · 199 scene cut · 200 p90 ·
  201 chroma angle · 202 achromatic fraction · 210 warm bias · 211 zone key · 212 zone std ·
  213 fc_stevens (encoded ÷1.3, decoded ×1.3 — highway UNORM clips at 1.0).
- **ZoneHistoryTex.a**: repurposed from Kalman P (unused) to smoothed intra_std (R116 Issue 3).
  R88 VFF Kalman Q adaptation removed from SmoothZoneLevelsPS; replaced with fixed-K EMA,
  scene-cut reset via HWY_SCENE_CUT.

## Task E — Targeted review: R113–R117 (2026-05-06/07)

**R113 — LFDownscale1/2 passes (grade.fx)**
Verify `LFDownscale1PS` reads `CreativeLowFreqSamp` mip0 and writes `LowFreqMip1Tex` at 1/16-res.
Verify `LFDownscale2PS` reads `LowFreqMip1Samp` and writes `LowFreqMip2Tex` at 1/32-res.
Verify both passes appear before `ColorTransformPS` in the technique definition.
Verify MipLevels=1 on LowFreqMip1Tex and LowFreqMip2Tex (cross-technique, mip0 only).

**R114 — Halation chromatic fringe (grade.fx)**
Verify `hal_b = hal_ring.b * lerp(0.38, 0.22, hal_lore)` is present.
Verify gains: `float3 hal_gains = float3(1.05, 0.30, 0.03)` — not the old `float3(1.05, 0.50, 0.0)`.
Verify `hal_lore` (Lorentzian tail) is computed before `hal_b` is declared.

**R115 — Pro-Mist shimmer model (grade.fx ProMistPS)**
Verify `float3 bloom = max(0.0, blurred - base.rgb)` — not `lerp(base, blurred, strength)`.
Verify `result = base.rgb + bloom * adapt_str`.

**R116 — 9-issue fixes**
- `analysis_frame.fx MeanChromaPS`: verify 32-bin CDF-walk p50, not arithmetic mean.
- `corrective.fx SmoothZoneLevelsPS`: verify `zone_log_key = sum(medians) / 16.0` (linear mean).
- `corrective.fx SmoothZoneLevelsPS`: verify intra-zone variance `E[X²] − E[X]²` per zone.
  Verify `ZoneHistoryTex.a` stores smoothed `intra_std`, not Kalman P.
- `grade.fx ColorTransformPS`: verify `eff_p25 = perc.r` and `eff_p75 = perc.b` — no lerp blend.
- `grade.fx ColorTransformPS`: verify adaptive CAT16 blend `lerp(0.80, 0.60, saturate(illum_dev / 0.3))`.
- `grade.fx ColorTransformPS`: verify chroma ceiling applied to `lifted_C` before vibrance masking.
- `inverse_grade.fx`: verify `max(slope_enc * 1.5 + 1.0, 1.15)` minimum clamp.

**R117 — Stage gap closures (grade.fx, inverse_grade.fx)**
- `inverse_grade.fx`: verify `scene_theta`, `sincos`, `dir_weight` are ABSENT. Expansion is
  `new_C = mean_C + (C - mean_C) * factor` — uniform, no directional bias.
- `grade.fx halation`: verify `hal_broad.r = lerp(0.06, 0.18, hal_bright)` — not fixed 0.12.
  Verify green broad component: `hal_ring.g + hal_broad.g * hal_bright * 0.06`.
- `grade.fx MistDiffuseTex`: verify `MipLevels = 3`. Verify `ProMistPS` samples mip2 as
  `mist_broader` and blends via `broad_w = saturate(MIST_STRENGTH * 0.20 - 0.10)`.

## Important standing notes

- **HUNT_LOCALITY is not missing.** Intentionally removed (commit e155e6c, 2026-05-04). Do not flag.
- **inverse_grade_debug.fx** is not in the active chain. Do not audit.
- **pro_mist.fx** is not in the active chain (merged into grade.fx). Do not audit.
- **`tex2Dlod(BackBuffer, ...)`** always returns zero in vkBasalt — correct form is `tex2D`. Flag any tex2Dlod on BackBuffer sampler as a bug.

## Last updated
2026-05-07 — Full rewrite of Task E for R113–R117. Updated known-good baseline to R116
audit state. Updated highway slots to include 211–213. Updated files list and standing notes.
