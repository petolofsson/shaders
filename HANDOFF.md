# Handoff — 2026-05-17

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
- **3-way CC**: ±1.0 range. Scale 0.08 in shader.
- **DIR_COUPLER**: removed as knob, hardcoded 0.30 in shader.
- **CONTRAST**: scale 1.00 (was 0.30).

## Shadow lift — fixed 2026-05-16
- **Root cause resolved**: `fine_texture_att` zeroed lift in all textured areas.
- **Formula now**: `shadow_lift_str × detail_protect × context_lift × specular_att × 0.25 × lift_w × SHADOWS`
- **Needs in-game test**: confirm SHADOWS=1.0 gives visible lift in GZW jungle.

## Next
- Test shadow lift in GZW jungle — confirm fix works
- Rebless arc_raiders baselines (all stage gates 000 during INVERSE_LUMA debug — restore to 100)
- Retune arc_raiders creative_values.fx (3-way CC scale change, CONTRAST scale change affect output)
