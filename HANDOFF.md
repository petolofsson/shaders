# Handoff — 2026-05-19

> **Purpose (for AI context):** Current session state. Read at session start. Update at session end. Changelog entries go in CHANGELOG.md. **Hard limit: 60 lines including this header. Trim aggressively — one fact per line, no prose.**

## Active chain (testbed)
`analysis_frame : inverse_grade : corrective : grade`
grade: 11 passes — LFDownscale1 → LFDownscale2 → NeutralIllum → GuidedCoeff → GuidedBase → ColorTransform → DiffusionDownsample → DiffusionBlurH → DiffusionBlurV → Diffusion → **TexHwyWrite**

## Known state
- No compile errors. Log: `/tmp/vkbasalt.log`
- **Knob convention**: 0 = passthrough universally. 1 = full designed effect.
- **INVERSE_LUMA**: bell weight mu=0.05 sigma=0.18; proportional Oklab. Fires in ColorTransformPS, independent of CORRECTIVE_STRENGTH.
- **INVERSE_STRENGTH**: pure Oklab chroma expansion — zone_w bell + HueCeil natural limiters only. No illum_gate, no c_weight, no FilmCurveInvCh.
- **ApplyCorrective**: now only EXPOSURE × lerp-to-3WayCC. FilmCurveApply removed (R204).
- **FilmCurveApply removed (R204)**: toe was physically unjustified in display-referred space; shoulder redundant given WHITES; per-channel knee was film stock territory. All shadow/highlight character owned by PRINT_STOCK + BLACKS/WHITES.
- **BLACKS/WHITES**: lerp-remap at end of ColorTransformPS. `lerp(BLACKS, WHITES, saturate(result))`. Not in ApplyCorrective.
- **DIR_COUPLER**: knob 0–1. Formula: `exp2(log_c − cpl × DIR_COUPLER × 20)`. Fires in ColorTransformPS before CORRECTIVE_STRENGTH lerp.
- **M_NEG**: knob 0–1. Off-diagonal scaled: `lin + off_diag × M_NEG × 20`. Fires in ColorTransformPS.
- **DiffusionPS floor fixed**: was `(0.10 + eff_diff × 0.09)` — hardcoded 0.10 blurred shadows even at DIFFUSION=0. Now `eff_diff × 0.19`.
- **PRINT_STOCK desat_w fixed**: fires midtones (0→fc_knee_toe×2), not shadows. Range capped via `saturate(print_stock)`.
- **CLARITY**: midtone-gated — `smoothstep(0.15,0.40,luma) × (1−smoothstep(0.60,0.85,luma))`.
- **3-way CC**: ±1.0 range. Scale 0.06. Oklab a/b (temp→b, tint→a).
- **R200 slow_key**: dual-rate EMA — K_slow=0.0000346 (T_half=20s), K_fast=0.01034 on scene cut.
- **R202 M_neg**: Kodak Vision3 500T matrix. Off-diagonal max 2.45%; ×20 knob scaling.
- **Halation**: removed. Requires engine-side light source data.

## Removed knobs (both profiles)
`CURVE_R_KNEE`, `CURVE_B_KNEE`, `CURVE_R_TOE`, `CURVE_B_TOE` — all dead after FilmCurveApply removal.

## Research
- **R204** (2026-05-19): FilmCurve toe audit. Verdict: tc_comp unjustified in display-referred space. fc_knee/body_s/sh_comp also removed — highlight treatment via WHITES, shadow via PRINT_STOCK.

## Next
- Dial SHADOW/MID/HIGHLIGHT TEMP/TINT on both profiles.
- Recalibrate BLEACH_BYPASS on both profiles.
