# Changelog

> **Purpose (for AI context):** Chronological record of code changes, one compacted entry per day. Keep only the last 3–4 days. Older history lives in git log. Do not duplicate entries from HANDOFF.md or PLAN.md here.

## 2026-05-10

- **R158 grain timer fix** (`grade.fx`, `corrective.fx`) — `source = "framecount"` returns 0 in vkBasalt, freezing grain to a static pattern (invisible to human perception). Replaced with `FRAME_TIMER` (`source = "timer"`, ms since app start). Grain slot: `uint(FRAME_TIMER / 41.667)` — correct ~24fps turnover. Same fix for Halton `base_idx` in `UpdateChromaKalman`. `GRAIN_STRENGTH` reset 2.0→1.0 (was inflated to compensate for static grain).

- **creative_values.fx reorder + retune** (both profiles) — Sections reordered by pipeline stage: INPUT → CORRECTIVE → TONAL → CHROMA → OUTPUT → STAGE GATES. Values: `SHADOW_LIFT_STRENGTH` 1.2→0.85 (R144 luma expansion lifts shadows passively — was double-lifting), `PURKINJE_STRENGTH` 1.3/1.4→0.90 (above 1.0 pushes scotopic desaturation past physical calibration), `CURVE_B_TOE` −0.0218→−0.010 (was excessively compressing blue at toe), `FILM_FLOOR` 0.01→0.005 (arc_raiders only).

- **R156–R157 inverse_grade hue-aware expansion** (`hue_bands.fxh`, `inverse_grade.fx`) — R156: `HueSlopeBias(hue)` — 12-band blended bias encoding ACES warm-hue compression excess (orange +0.20, teal/cyan −0.05); applied as `slope_eff = clamp(slope × (1 + bias), 1.0, 2.2)`. R157: `c_gate` lerps 0.10→0.06 as `HWY_ACHROM_FRAC` rises 0.60→0.85 — colored pixels in achromatic scenes see full expansion.

- **R147–R155 statistical signal correctness** (`analysis_frame.fx`, `corrective.fx`, `grade.fx`, `highway.fxh`, `inverse_grade.fx`) — Added histogram mode (`CDFWalkModePS`, `HWY_MODE=206`) and Bowley skewness to `SceneCtx`. Wrong signals corrected: fc_stevens→mode (was zone_log_key), halation→p90−p50 gap (was Bowley), chroma lift→mean_C inverse (was Bowley), Purkinje→mode-gated. Dead code removed: WarmBias, sat histogram (4 passes), zmin/zmax, k_med/k_ema. Zone CDF intra-bin interpolation added.

- **R142–R145** (`grade.fx`) — ColorTransformPS split into BuildSceneCtx/ApplyCorrective/ApplyTonal/ApplyChroma. Zone strength coupled to inverse-grade slope (×1/slope). R144 luma inverse tonemapping (cbrt(p50_linear) pivot in Oklab L space).

## 2026-05-09

- **R139 common.fxh** — Consolidated `PostProcessVS`, `Luma`, `RGBtoOklab`, `OklabToRGB`, `OklabHueNorm`, `RGBtoHSV` into shared header. `GetBandCenter` moved to `hue_bands.fxh`.
- **R137 print stock shoulder** — Additive `−ps⁶×0.06` correction on shoulder formula. Preserves shadows exactly, progressively compresses above L=0.75.
- **R136 film grain** — Selwyn 2383 pcg3d model: σ = GRAIN_STRENGTH × 0.018 × sqrt(1−L_gamma), R:G:B decorrelated at 1.00:0.80:1.50. (Timer source broken until R158.)
- **R142 ColorTransformPS split** — BuildSceneCtx / ApplyCorrective / ApplyTonal / ApplyChroma extracted. Zero output change.

## 2026-05-08

- **R130–R133** — Kodak 2383 3×3 spectral dye matrix (H-1-2383t data). R131 HBM Gaussian blur chain (4 passes). R132 polydisperse chromatic scatter (R:G:B = 1.15:1.00:0.85). R133 Munsell per-hue highlight rolloff `f=(4(1−L))^n` from Renotation V=8→10 C_max ratios.
- **R52 Purkinje** — a*+b* shift toward 507nm + scotopic desaturation `lab.yz *= 1−0.12×w×PURKINJE_STRENGTH`.
- **CAT16 removed** — display-referred content; warm lighting is art direction. NeutralIllumTex kept for R83 + R66.
- **Chroma lift pivot fixed** (`corrective.fx`) — MIN_WEIGHT removed; weight now chroma-gated. Lift was silently inert before this fix.

## 2026-05-07

- **R124B NeutralIllumPS** — 144-sample neutral-pixel-weighted illuminant estimate. Replaces grey world for R83 + R66.
- **R125–R126 Bezold-Brücke + FilmCurve body** — Three-harmonic BB anchored to unique yellow/blue. Body: one-sided S `max(0,(x(1−x))²(2x−1))×0.65`.
- **Zone_std thresholds recalibrated** — Intra-zone variance peaks ~0.15. Smoothstep bounds tightened.
