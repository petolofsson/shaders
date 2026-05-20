# Changelog

> **Purpose (for AI context):** Chronological record of code changes, one compacted entry per day. Keep only the last 3–4 days. Older history lives in git log. Do not duplicate entries from HANDOFF.md or PLAN.md here.

## 2026-05-20

- **R205: FilmCurve audit + improvements** (`grade.fx`, `inverse_grade.fx`, both `creative_values.fx`, `research/R205_2026-05-20_filmcurve_improvements.md`) — Three changes: (1) **tc_comp removed**: rational toe modeled a photochemical process that has no basis in display-referred space; `ApplyPrintStock` owns shadow density. FilmCurveApply is now `x + body_s − sh_comp`. (2) **body_s reparameterized**: peak no longer fixed at x≈0.724 — normalized via `t_norm = saturate((xs−0.5)/max(knee_rgb−0.5, 0.001))`; peak tracks fc_knee, body_s is exactly zero at fc_knee (no overlap with sh_comp in bright scenes). (3) **fc_w removed**: half-strength shoulder blend was empirical compensation for a non-existent discontinuity (sh_comp is C1 at knee); FILM_CURVE knob is now the sole blend gate. Signature simplified: `FilmCurveApply(float3 x, float knee_r, float knee_g, float knee_b)`. CURVE_R/B_TOE knobs removed from both creative_values.fx (nothing to offset). `FilmCurveInvCh` simplified to shoulder-only (no toe to invert). `hl_taper` added: FilmCurve fades to zero at WHITES ceiling via `1.0 − smoothstep(fc_knee, WHITES, Luma(lin_e))`.

- **BLACKS/WHITES linear remap** (`grade.fx`) — Replaced separate floor/ceiling clips at different pipeline positions with a single coordinated linear remap at the top of ColorTransformPS: `lin = col.rgb * (WHITES − BLACKS) + BLACKS`. Matches how film labs and DaVinci Resolve handle black/white point — gain×offset, C1 by construction, no joint between clips.

- **Print stock fixes** (`grade.fx`) — Three correctness fixes: (1) `ApplyMaskingCoupler` now gated by `lerp(lin, warmed, saturate(print_stock))` — was unconditional warm cast that grew regardless of PRINT_STOCK. (2) `ApplyDyeMatrix` now gated by `lerp(lin, result, saturate(print_stock))` — was always-on at full strength. (3) `desat_w` in `ApplyPrintStock` was shadow-only: `(1 − smoothstep(0, fc_knee_toe, luma_ps))` inverted the gate, desaturating only luma < fc_knee_toe ≈ 0.20. Fixed to midtone bell: `smoothstep(0, fc_knee_toe, luma_ps) × (1 − smoothstep(fc_knee, 1, luma_ps))`. Arc_raiders PRINT_STOCK set to 1.00 as calibration starting point.

## 2026-05-18 (session 2)

- **Dead code removal + doc sync** — Removed `CreativeZoneHistTex`/`CreativeZoneHistSamp` from `grade.fx` (declared, never sampled). Fixed 6 stale comments across `grade.fx` and `analysis_frame.fx` referencing removed textures (`CreativeLowFreqTex`, `CreativeLowFreqSamp`, `CorrectiveSrcTex`). Removed `analysis_scope.fx` and `analysis_scope_pre.fx` (old BackBuffer y=0 histogram scope, incompatible with current TexHwyTex data highway). Updated CLAUDE.md: chain, grade pass count (8→11), corrective pass count (8→7), all `CreativeLowFreqTex`/`CreativeLowFreqSamp` references, analysis texture list in `ColorTransformPS` section.

## 2026-05-18

- **3-way CC → Oklab** (`grade.fx`) — `Apply3WayCC` rewritten in Oklab a/b space. temp → b-axis (warm=positive, cool=negative); tint → a-axis (magenta=positive, green=negative). Axes are orthogonal — temp and tint no longer cross-contaminate. Zone gates moved from `sqrt(BT.709 luma)` to Oklab L (sh: 0.35→0.55, hl: 0.70→0.90), consistent with shadow cast and other ApplyChroma gates. Scale 0.06 (was 0.08 additive sRGB vector). **SHADOW/MID/HIGHLIGHT TEMP/TINT require recalibration on both profiles.**

- **Bleach bypass: fix order + fix space** (`grade.fx`) — Two physical-model fixes. (1) `ApplyBleachBypass` moved to first in `ApplyLook`, before `ApplyPrintStock` — development stage precedes printing stage (bleach bypass is film development, print stock is contact printing). (2) Rewritten in linear sRGB luma desaturation: `lerp(lin, luma.xxx, desat)` — retained silver is spectrally neutral (luminance-domain), not a perceptual chroma effect. Bell midtone darkening also switches to linear luma (peaks at luma=0.5 vs. old Oklab L=0.5 which was luma≈0.125). **BLEACH_BYPASS requires recalibration.**

- **Temporal dither: FRAME_COUNT → FRAME_TIMER** (`grade.fx`) — `source = "framecount"` returns 0 in vkBasalt (same issue as R158 grain fix). `dither_phase` was always 0 — IGN temporal rotation was inactive. Now uses `uint(FRAME_TIMER / 41.667)` matching the grain slot counter; rotates at 24fps. No calibration impact.

- **Dead code removal** (`common.fxh`) — `RGBtoHSV` removed; unused since Oklab adoption, never called in the chain.

## 2026-05-17

- **INVERSE_LUMA: Mertens bell weight** (`grade.fx`, `creative_values.fx`) — Replaced flat proportional ACES luma inverse with per-pixel bell-weighted correction: `exp(-0.5*((col_luma−mu)/0.18)²)`, mu=0.05. Peaks at near-black zone; glow penumbra (0.40+) barely touched — diffusion reach preserved. Applied proportionally in Oklab (L,a,b) → no chroma density change. mu tuning range 0.05–0.20 documented in code: lower = more diffusion reach, higher = more smoke/fog correction; above 0.35 causes blob expansion.

- **Halation: luma-neutral tint + sky suppression** (`grade.fx`) — (1) Orange tint changed from additive `float3(0.63,0.25,0.02)` to luma-neutral `float3(0.316,−0.064,−0.294)` (original minus its luma 0.314) — hue shift only, no brightness blooming. (2) Sky suppression: `sky_w = exp(−max(0, lin_p.b − lin_p.r) × 7.0)` — warm/neutral sources unaffected, blue/cool sky pixels suppressed smoothly.

- **CLARITY upper highlight rolloff** (`grade.fx`) — Upper gate was documented in `creative_values.fx` but missing from code. Now fully implemented: `clarity_gate = smoothstep(0.15,0.40,luma) × (1−smoothstep(0.60,0.85,luma))`. Fades to zero at L=0.85 — highlights unaffected as documented.

- **DIR_COUPLER knob removed** (`grade.fx`, `gzw/creative_values.fx`) — Hardcoded to 0.30 in shader; knob removed from GZW profile. Effect is always-on at designed calibration.

- **3-way CC scale 0.03→0.08** (`grade.fx`) — Increased range to match revised knob convention.

- **CONTRAST scale 0.30→1.00** (`grade.fx`) — Zone S-curve now responds at full knob range.

- **SHADOW_CAST gate 0.25→0.65 shifted to 0.40→0.70** (`grade.fx`) — Tighter gate, pushes full cast strength to deeper shadows.

## 2026-05-16

- **Shadow lift redesign** (`grade.fx`) — Removed `fine_texture_att` (4-tap sub-pixel neighbourhood gate) and dead `texture_att`; both zeroed lift in all textured areas (jungle = all texture). Also dropped the Retinex inverse-illuminant term `0.149169/(illum_s0²+0.003)` which gave only ≈1× amplification in bright outdoor scenes (calibrated for dark interiors with illum_s0 < 0.10). New formula: `shadow_lift_str × detail_protect × context_lift × specular_att × 0.25 × lift_w × SHADOWS` — scene-adaptive gate preserved via `shadow_lift_str`, direct scale works consistently across bright and dark scenes. Four BackBuffer taps removed.

- **DEHAZE removed** (`grade.fx`, both `creative_values.fx`, `tools/stage_isolate.py`) — Guided filter shadow lift (`LOCAL_CONTRAST` → `DEHAZE`) removed entirely. Lift reference (p75) never reliably fired across scene types; complexity without consistent benefit. `CLARITY` now owns the guided-filter block solo.

- **Fix CLARITY constant** (`grade.fx`) — Reverted `0.08306 → 0.025`. The 0.08306 = 0.025 × log2(10) was a direction error introduced 2026-05-14: guided passes already write log2-luma, so 0.025 is the correct log2-space constant. The prior multiplication by log2(10) was wrongly applied (divide, not multiply).

- **CLARITY midtone gate** (`grade.fx`) — `clarity_gate = smoothstep(0.15, 0.40, luma) × (1 − smoothstep(0.60, 0.85, luma))`. Full effect 0.40–0.60, fades to zero at 0.15 (noise) and 0.85 (highlight blowout). Game-agnostic by construction.

- **Halation fixes** (`grade.fx`) — Three changes: (1) DoG threshold 0.04 inserted before ×luma_p — diffuse areas (sky, clouds, DoG < 0.03) no longer tint; isolated sources (lamps, speculars, DoG > 0.10) fire normally. Self-limiting, no knob. (2) Color corrected from R:G:B = 0.63:0.07:0.02 (red) to 0.63:0.25:0.02 (orange-amber) — green was severely underweighted. (3) `HALATION_CROSSOVER` knob removed; threshold baked in.

