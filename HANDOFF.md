# Handoff — 2026-05-19

> **Purpose (for AI context):** Current session state. Read at session start. Update at session end. Changelog entries go in CHANGELOG.md. **Hard limit: 60 lines including this header. Trim aggressively — one fact per line, no prose.**

## Active chain (testbed)
`analysis_frame : inverse_grade : corrective : grade`
grade: 11 passes — LFDownscale1 → LFDownscale2 → NeutralIllum → GuidedCoeff → GuidedBase → ColorTransform → DiffusionDownsample → DiffusionBlurH → DiffusionBlurV → Diffusion → TexHwyWrite

## Known state
- No compile errors. Log: `/tmp/vkbasalt.log`
- **Knob convention**: 0 = passthrough universally. 1 = full designed effect.
- **R204 reverted**: grade.fx, inverse_grade.fx, and both creative_values.fx restored to pre-R204 state via `git checkout 34c794c`. FilmCurveApply, FilmCurveInvCh, and CURVE_R_KNEE/TOE knobs are all back.
- **FILM_CURVE knob** (new this session): added to both creative_values.fx and grade.fx. Gates `fc_w * saturate(FILM_CURVE)` at the FilmCurveApply lerp. 0 = off, 1 = full. `saturate()` guard means values above 1 are clamped.
- **INVERSE_LUMA**: bell weight mu=0.05 sigma=0.18; proportional Oklab. Fires in ColorTransformPS, independent of CORRECTIVE_STRENGTH.
- **INVERSE_STRENGTH**: pure Oklab chroma expansion — zone_w bell + HueCeil natural limiters only.
- **FilmCurveApply**: body_s (upper-mid lift) + sh_comp (rational shoulder) + tc_comp (toe lift). fc_w blend = lerp(1.0, 0.5, sh_w) — half-strength at shoulder. Called in ApplyCorrective.
- **FilmCurveInvCh**: piecewise exact inverse. Applied in inverse_grade.fx before Oklab chroma expansion. Knee/ktoe from highway p25/p50/p75/mode (one-frame delay).
- **BLACKS/WHITES**: lerp-remap at end of ColorTransformPS.
- **CLARITY**: midtone-gated — `smoothstep(0.15,0.40,luma) × (1−smoothstep(0.60,0.85,luma))`.
- **3-way CC**: ±1.0 range. Scale 0.06. Oklab a/b (temp→b, tint→a).
- **R200 slow_key**: dual-rate EMA — K_slow=0.0000346 (T_half=20s), K_fast=0.01034 on scene cut.

## Next
- Confirm FILM_CURVE is the "secret sauce" via A/B (0 vs 1). Dial testbed from there.
- Recalibrate 3-way CC (SHADOW/MID/HIGHLIGHT TEMP/TINT) on both profiles.
- Recalibrate BLEACH_BYPASS on both profiles.
