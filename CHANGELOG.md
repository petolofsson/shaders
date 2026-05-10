# Changelog

> **Purpose (for AI context):** Chronological record of code changes, one compacted entry per day. Keep only the last 3–4 days. Older history lives in git log. Do not duplicate entries from HANDOFF.md or PLAN.md here.

## 2026-05-10

- **R144 luma inverse tonemapping** (`inverse_grade.fx`) — Extends R90 to expand Oklab L alongside C using the same IQR-derived slope, restoring the joint luma+chroma signal the game's tonemapper compressed. Pivot is `cbrt(p50_linear)` (not raw p50_linear) — Oklab L is perceptual/cube-root, so using linear p50 as pivot would place the zero-crossing at L≈0.50 (linear Y≈0.125, deep shadow). c_weight excluded from luma_factor: tonemapper compressed every pixel's luma equally including near-neutrals. mid_weight bell gate preserves L=0 and L=1 exactly. +5 lines to InverseGradePS. INVERSE_STRENGTH retuned 0.50→0.40 (joint expansion is stronger than chroma-only).
- **R143 reverted** (`inverse_grade.fx`) — Highlight reconstruction removed. Caused sun desaturation: near-clip warm light sources have Oklab C≈0.05 which falls below any viable C gate. Problem it targeted (orange clipping artifacts) is already resolved by R138/R130/R133. R90 mid_weight gate (≈0 at high L) also means near-clip pixels are barely touched by expansion — pre-correction was solving a non-issue.

- **R143 reverted** (`inverse_grade.fx`) — Highlight reconstruction removed. Caused sun desaturation: near-clip warm light sources have Oklab C≈0.05 which falls below any viable C gate. Problem it targeted (orange clipping artifacts) is already resolved by R138/R130/R133. R90 mid_weight gate (≈0 at high L) also means near-clip pixels are barely touched by expansion — pre-correction was solving a non-issue.
- **R142 ColorTransformPS stage split** (`grade.fx`) — F4-A implemented. `BuildSceneCtx()` collects all scene-uniform texture fetches + derived scalars into a `SceneCtx` struct (~35 lines). `ApplyCorrective()` owns EXPOSURE→FilmCurve→halation→print stock→dye matrix→bleach bypass→3-way CC (~25 lines). `ApplyTonal()` owns zone S-curve→Retinex→shadow lift→R62/R65→R66 tint, returns `TonalOut {lin, new_luma, local_var}` (~55 lines). `ApplyChroma()` owns HELMLAB→Purkinje→R22→R133→R21→chroma lift→memory colors→HK→Abney→induction→density→gamut (~80 lines). ColorTransformPS becomes a 47-line orchestrator calling the three stages. Zero output change — compiler inlines all helpers.
- **`code_rules.md` → `CODE_RULES.md`** — renamed to match uppercase convention of other root docs.
- **R139 code rules audit — low/medium items resolved** (`all effect files`) — All remaining R139 open items closed: F4-B/C/D/E/F (function-length refactors: ScopePS→DrawLumaPost/Pre/HuePanel, UpdateHistoryPS→ComputeZoneStats/ComputeSlowKey/UpdateChromaKalman, DiffusionPS→ApplyDiffusionBloom+ApplyFilmGrain, ScopeCapturePS→CaptureLumaHistPixel+CaptureHueHistPixel, MeanChromaPS→ComputeMedianC); F5-B/C (bounds: P_new saturated, RGBtoOklab clamps input); F6-A (lms_illum_norm declared inline); F7-A/B (HueBandWeight self-defending frac(hue), GetBandCenter clamped); F1-B (conditional→lerp/step). F4-A (MegaPass) and F1-A (if-ladder) deferred; F6-B and F10-C documented as intentional/note-only.

## 2026-05-09

- **R139 common.fxh migration** (`general/common.fxh`, all effect files) — Consolidated 6 duplicate utility functions into a shared header: `PostProcessVS`, `Luma`, `RGBtoOklab`, `OklabToRGB`, `OklabHueNorm`, `RGBtoHSV`. `GetBandCenter` (Oklab 6-band) moved to `hue_bands.fxh` alongside its constants. `analysis_frame.fx` HSV-space variants renamed `GetHSVBandCenter`/`HSVBandWeight` to distinguish from Oklab counterparts. Resolves F8-A/B/C, F10-A, F2-A, F5-A from the R139 audit.

- **R137 print stock shoulder** (`grade.fx R51`) — Additive `−ps⁶×0.06` correction on the original `1−(1−ps)²×1.8` formula. Preserves shadow/midtone character exactly (ps⁶≈0 below 0.70); progressively compresses highlights above 0.75 (ps=0.85: 0.960→0.937, ps=0.90: 0.982→0.950). Reinhard partial (R134) reverted — it lost midtone body punch. R137 is a targeted correction, not a formula replacement.
- **R136 film grain** (`grade.fx DiffusionPS`) — Selwyn 2383 granularity model. pcg3d hash gives three fully decorrelated RGB noise streams per pixel. Amplitude envelope `σ = GRAIN_STRENGTH × 0.018 × sqrt(1 − L_gamma)` peaks at Oklab L≈0.50 (upper shadows), falls toward black and highlight extremes. Channel ratios R:G:B = 1.00:0.80:1.50. Framerate-independent: `grain_slot = uint(FRAME_COUNT × (FRAME_TIME/41.667))` — ~24fps turnover at any display fps. Zero new passes. `GRAIN_STRENGTH 0.0` (off, awaiting calibration).
- **creative_values.fx reordered** (arc_raiders + gzw) — Sections ordered by tuning frequency: EXPOSURE → ZONE → SHADOW_LIFT → 3-WAY CC → CHROMA → PRINT_STOCK → BLEACH_BYPASS → DIFFUSION → GRAIN → HALATION → MUNSELL → PURKINJE → INVERSE → HUE_ROT → CAMERA_RANGE → FILM_CURVE → COUPLERS → STAGE_GATES. gzw: MUNSELL_HIGHLIGHT_ROLLOFF added (was missing).
- **Shadow lift gate** (`grade.fx`) — `lift_w` ceiling 0.27→0.25→0.20. Lift now gates off at L=0.20, leaving lower mids untouched.
- **Bleach bypass highlight floor fixed** (`grade.fx`) — Lowered `lerp(0.35, 0.72, bb_dark)` floor 0.35→0.05. Physical bypass has near-zero effect in highlights.
- **R22 highlight arm removed** (`grade.fx`) — Removed `−0.45×saturate((L−0.75)/0.25)`. Superseded by R133.

## 2026-05-08

- **R133 Munsell per-hue highlight chroma rolloff** (`hue_bands.fxh`, `grade.fx`) — Replaces R74 linear ramp (`0.30*sat((L−0.80)/0.20)`) which had a hard gate at L=0.80 and never reached C=0 at L=1.0. New form: `f=(4(1-L))^n` per hue, f=1 at L≤0.75, f=0 at L=1.0. Twelve per-hue exponents in `hue_bands.fxh` from Munsell Renotation V=8→9→10 C_max ratios: yellow n=0.22 (peaks at V=9 — late onset), yellow-green n=0.27 (slowest), orange n=0.81 (fastest). `MUNSELL_HIGHLIGHT_ROLLOFF` knob added to `creative_values.fx`.
- **R132 polydisperse chromatic scatter** (`grade.fx DiffusionPS`) — `float3 ch_scatter = float3(1.15, 1.00, 0.85)` applied to both shimmer and midtone overlay. Red scatters more broadly, blue less — polydisperse filter media physics. DIFFUSION_STRENGTH 1.2 → 1.0.
- **R52 Purkinje improved** (`grade.fx`) — Added a* component toward 507nm blue-green (rod peak, not pure blue). Added scotopic desaturation `lab.yz *= 1 − 0.12 × scotopic_w × PURKINJE_STRENGTH` — rods are achromatic.
- **R131 HBM Gaussian blur** (`grade.fx`) — Replaced mip-based shimmer with separable 9-tap Gaussian chain (DiffusionDownsample → DiffusionBlurH → DiffusionBlurV → Diffusion). DiffusionTex 1/8→1/4-res; MipLevels 3→1. Grade now 8 passes.
- **R130 Kodak 2383 dye matrix** (`grade.fx`) — Replaced Beer-Lambert proxy + empirical coupling with 3×3 matrix from H-1-2383t spectral dye density data. R85 empirical values were 2–4× too high; corrected. Four absent cross-channel terms added.
- **Shadow lift audit** (`grade.fx`) — detail_protect widened `smoothstep(-0.5, 0.0)` → `(-2.0, -0.5)`; local_range_att removed (scene-wide gate redundant vs. per-pixel gates); lift_w ceiling 0.25 → 0.27.
- **CAT16 removed** (`grade.fx`) — Display-referred content; CAT16 was cooling deliberate warm lighting. NeutralIllumTex + lms_illum_norm kept for chromatic floor and ambient tint.
- **Chroma lift pivot fixed** (`corrective.fx`) — MIN_WEIGHT removed; weight now chroma-gated via `smoothstep(0.03, 0.08, C)`. Chroma lift was silently inert before this fix.
- **Diffusion radial oval** (`grade.fx`) — Replaced circular radial with `length(float2(c.x * 1.6, c.y * 0.08))`. Full clarity top-to-bottom; diffusion increases left/right.

## 2026-05-07

- **R124B NeutralIllumPS** (`grade.fx`) — New pass: 144-sample neutral-pixel-weighted illuminant estimate (16×9 grid, Oklab C-weighted). Replaces grey world mean for R83 chromatic floor and R66 ambient tint.
- **R126 FilmCurve body S** (`grade.fx`) — Linear body replaced with one-sided S: `max(0, (x*(1-x))²*(2x-1))*0.65`. Shadows untouched; upper mids peak +1.2% at x≈0.72.
- **R125/R126 Bezold-Brücke** (`grade.fx`) — Anchor fixed to h=0.25 (unique yellow) / h=0.75 (unique blue). Three-harmonic model gives correct teal > orange asymmetry (1.6×, per Kurtenbach 1994).
- **Zone_std thresholds recalibrated** — Intra-zone variance peaks ~0.15, not ~0.25+. Smoothstep bounds tightened.

## 2026-05-06

- **R113 mip fix** (`grade.fx`) — Cross-technique mip generation bug: CreativeLowFreqTex mip1/mip2 were zero everywhere. Fix: LFDownscale1 + LFDownscale2 explicit downscale passes within OlofssonianColorGrade.
- **R114 halation chromatic** (`grade.fx`) — Added blue component via Lorentzian attenuation. Gains `float3(1.05, 0.50, 0.0)` → `float3(1.05, 0.45, 0.03)`. White surfaces now produce correct orange/amber fringe.
- **R115 diffusion shimmer** (`grade.fx`) — Changed symmetric lerp to additive `base + max(0, blurred − base) * strength`. Previous model muted shadows; new model adds only from highlights.
- **R116 pipeline audit** — 9 issues resolved: chroma ceiling order, HWY_SLOPE minimum, adaptive CAT16 blend, chroma median → CDF p50, pure global percentiles, zone log key linear mean, intra-zone pixel variance, Bezold-Brücke anchor, R119 fine-texture gate.
- **LCA / R81A permanently removed** — No viable solution without a UI mask.
- **VIEWING_SURROUND / R76B removed** — Outside environment not pipeline's responsibility.

## 2026-05-05

- **R101 F1 Bezold-Brücke** (`grade.fx`) — `−sin(2π(h − 0.27))` unique-yellow-anchored model replaces uniform hue-by-luminance lerp. Reuses HELMLAB sincos — zero new trig.
- **R101 F2 H-K scene-adaptation** (`grade.fx`) — Fixed exponent 0.587 → `lerp(0.52, 0.64, saturate(zone_log_key / 0.50))`. Dim scenes get stronger H-K effect.
- **R101 F3 Abney C_stim** (`grade.fx`) — Coefficients now scale by pre-lift stimulus chroma (Burns et al. 1984). Zero ALU change.
- **OPT-1/2/3/4** — Eliminated third sincos (small-angle approx); tex2D → tex2Dlod for 4 reads in ColorTransformPS; removed dead `lin_pre_tonal` register and `CORRECTIVE_STRENGTH` lerp.
