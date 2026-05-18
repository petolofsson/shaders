# Handoff — 2026-05-18

> **Purpose (for AI context):** Current session state. Read at session start. Update at session end. Changelog entries go in CHANGELOG.md. **Hard limit: 60 lines including this header. Trim aggressively — one fact per line, no prose.**

## Active chain (testbed)
`analysis_frame : inverse_grade : corrective : grade`
grade: 10 passes — LFDownscale1 → LFDownscale2 → NeutralIllum → GuidedCoeff → GuidedBase → ColorTransform → DiffusionDownsample → DiffusionBlurH → DiffusionBlurV → Diffusion

## Known state
- No compile errors. Log: `/tmp/vkbasalt.log`
- **Knob convention**: 0 = passthrough universally. 1 = full designed effect.
- **INVERSE_LUMA**: Mertens bell weight mu=0.05 sigma=0.18; proportional Oklab (L,a,b). mu range 0.05–0.20.
- **Halation**: luma-neutral orange `float3(0.316,−0.064,−0.294)`; sky_w exp gate (B>R factor 7.0).
- **CLARITY**: fully midtone-gated — `smoothstep(0.15,0.40,luma) × (1−smoothstep(0.60,0.85,luma))`.
- **LUMA_CONTRAST_***: 6-band hue-selective clarity, ungated, chroma-gated (smoothstep 0.04→0.10).
- **above_w**: restored — zone S-curve one-sided again (only lifts above zone median).
- **SHADOW_CAST**: gate smoothstep(0.40, 0.70) — tighter than previous (was 0.25→0.65).
- **3-way CC**: ±1.0 range. Scale 0.06 in shader. Zones: sh full<BT.709 0.11, hl full>0.80.
- **DIR_COUPLER**: removed as knob, hardcoded 0.30 in shader.
- **CONTRAST**: scale 1.00 (was 0.30).
- **R200 slow_key**: dual-rate EMA — K_slow=0.0000346 (T_half=20s), K_fast=0.01034 (T_half=67ms on scene cut); framerate-independent via FRAME_TIME.
- **R202 M_neg**: Kodak Vision3 500T sensitivity matrix in linear sRGB, after EXPOSURE+halation, before FilmCurve. No knobs. Completes negative+print two-stock chain.

## Shadow lift — confirmed 2026-05-17
- **Root cause resolved**: `fine_texture_att` zeroed lift in all textured areas.
- **Formula now**: `shadow_lift_str × detail_protect × context_lift × specular_att × 0.25 × lift_w × SHADOWS`
- **GZW jungle test**: confirmed working.

## Color system changes — 2026-05-18
- **3-way CC**: now Oklab a/b. temp→b-axis, tint→a-axis. Zone gates: sh smoothstep(0.35,0.55,L), hl smoothstep(0.70,0.90,L). Scale 0.06.
- **Bleach bypass**: linear sRGB luma desaturation. Moved before PrintStock in ApplyLook.
- **Temporal dither**: FRAME_COUNT→FRAME_TIMER slot. No visual impact on static images.

## Next
- Dial SHADOW/MID/HIGHLIGHT TEMP/TINT on both profiles (zones recalibrated; knobs still at zero).
- Recalibrate BLEACH_BYPASS on both profiles (new space + new order).
