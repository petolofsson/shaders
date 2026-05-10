# Changelog

> **Purpose (for AI context):** Chronological record of code changes, one compacted entry per day. Keep only the last 3–4 days. Older history lives in git log. Do not duplicate entries from HANDOFF.md or PLAN.md here.

## 2026-05-10

- **R159 luma expansion removal + R145 decoupling** (`inverse_grade.fx`, `grade.fx`) — Removed R144 pivot-based luma expansion from inverse_grade (cbrt(p50_linear) Oklab L pivot caused texture smoothing on bright surfaces in dark scenes; zone S-curve owns luma). Removed R145 zone coupling (ZONE_STRENGTH was divided by inv slope — workaround for R144 redundancy). ZONE_STRENGTH is now a clean standalone knob. INVERSE_STRENGTH tuned to 0.40.

- **R160 adaptive print stock** (`grade.fx`) — ApplyPrintStock now receives p25 and p75. Black lift `0.025 × saturate(1 − p25/0.06)` backs off when scene shadows already elevated; shoulder exponent lerps 1.8→1.2 and cubic correction lerps 0.06→0.02 as p75 rises 0.40→0.70.

- **R161–R164 highway audit** (`inverse_grade.fx`, `grade.fx`, `corrective.fx`) — Four previously-unread slots wired to processing decisions: R161 ACHROM_FRAC multiplier on chroma_str_base (desaturated scenes get less chroma lift); R162 P90-derived specular_contrast in SceneCtx suppresses shadow lift 35% max (eliminates duplicate halation ReadHWY); R163 CHROMA_ANGLE alignment bias in inverse_grade `dir_scale = 1 − alignment × 0.15` (complementary hues get ±15% expansion bias); R164 LUMA_MEAN_PRE slope cap `lerp(2.2, 1.5, saturate((mean_pre − 0.25)/0.35))` in inverse_grade (bright raw scenes get tighter expansion ceiling).

- **R161 + R164 permanently dropped** (`grade.fx`, `inverse_grade.fx`) — R161 achrom_frac multiplier on chroma_str_base flattened simultaneous contrast and degraded blacks character (mean_C inverse already handles scene desaturation). R164 LUMA_MEAN_PRE slope cap `lerp(2.2,1.5,...)` degraded colour richness and blacks; print stock shoulder already owns that tonal compression. Both reverted to baseline logic.

- **R166 grain size variety** (`grade.fx`) — Added `pcg3d_hash()` helper and `GrainValueNoise()` three-octave value noise (4px coarse, 2px mid, 1px fine). Replaces single-octave pcg3d. Coarse:mid:fine = 0.50:0.30:0.20.

- **R167 grain luma-size + dye scaling** (`grade.fx`) — Dropped 4px coarse octave (visible banding on flat areas). Luma-dependent grain size `lerp(2.5, 1.5, L_g)` — shadows get larger grains, highlights finer. Per-channel dye sizing: R×1.00, G×0.90, B×1.15 (matches 2383 dye layer physical depth ordering). Blue-noise high-frequency octave mixed at 0.30 weight. Two-octave final: value noise coarse + blue noise fine.

- **R168 physical halation** (`grade.fx`) — ApplyHalation rewritten. Two-scale DoG PSF: tight ring = `lf_mip1 − lin`, broad ring = `lf_mip2 − lf_mip1`. AH layer (rem-jet) attenuates tight ring ~40%: col_tight = `(0.63, 0.27×lore_g, 0.02×lore_b)`, col_broad = `(1.05, 0.45×lore_g, 0.03×lore_b)`. Lorentzian chromatic crossover `tight_luma / (tight_luma + hal_gamma)` per ring.

- **R169 grain temporal cross-dissolve** (`grade.fx`) — GrainSlot() helper extracted. ApplyFilmGrain blends `GrainSlot(slot0)` → `GrainSlot(slot0+1u)` using `frac(FRAME_TIMER/41.667)` — eliminates screen-space snap ("rain" artifact) visible at >60 FPS when grain slot advances by one full frame. 28 hash calls, arithmetic-only, no extra texture samples.

- **GZW jungle movie grade** (`gzw/creative_values.fx`) — Synced from arc_raiders base; colour grade tuned for jungle movie aesthetic: teal-green shadows (SHADOW_TEMP −10, TINT −6), green ambient mids (MID_TINT −3), golden highlights (HIGHLIGHT_TEMP +15, TINT +2). Hue rotations: reds warm toward orange (+0.04), greens deep toward cyan (−0.04). HAL_STRENGTH 0.30, HAL_GAMMA 0.02.

- **Halation recalibration** (both profiles) — GZW: HAL_STRENGTH 0.30 / HAL_GAMMA 0.02 (jungle diffuse-dominant, tight ring denser). arc_raiders: HAL_STRENGTH 0.20 / HAL_GAMMA 0.05 reverted (reverted to pre-R168 calibration after user comparison).

- **R165 illuminant warmth CCT proxy** (`grade.fx`, `inverse_grade.fx`, `highway.fxh`) — New slot 220 (HWY_ILLUM_WARM). ColorTransformPS reads NeutralIllumTex, converts to CAT16 LMS, writes `warmth = saturate(L_norm − S_norm + 0.5)` (D65≈0.39, warm>0.5, cool<0.5). InverseGradePS reads one-frame-delayed (acceptable — illuminant changes slowly; frame 0 default 0 → no change). warm_scene gate at 0.45, positive HueSlopeBias reduced up to 50% at very warm illuminant — prevents over-saturating warm hues that are correct for the illuminant.

- **Retune** (arc_raiders creative_values) — PURKINJE_STRENGTH 0.90→0.70, CHROMA_STR →1.05, ZONE_STRENGTH →1.00.

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
