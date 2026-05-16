# Handoff — 2026-05-16

> **Purpose (for AI context):** Current session state. Read at session start. Update at session end. Changelog entries go in CHANGELOG.md. **Hard limit: 60 lines including this header. Trim aggressively — one fact per line, no prose.**

## Active chain (testbed)
`analysis_frame : inverse_grade : corrective : grade`
grade: 10 passes — LFDownscale1 → LFDownscale2 → NeutralIllum → GuidedCoeff → GuidedBase → ColorTransform → DiffusionDownsample → DiffusionBlurH → DiffusionBlurV → Diffusion

## Known state
- No compile errors. Log: `/tmp/vkbasalt.log`
- **Knob convention**: 0 = passthrough universally. 1 = full designed effect.
- **3-way CC**: ±1.0 range. Scale 0.03 in shader.
- **HueBandWeightW**: width=0.14 used for HUE_*, SAT_*, hw_o*, LUMA_CONTRAST_*. HueCeil/HueBandRollN keep 0.08.
- **above_w**: restored — zone S-curve one-sided again (only lifts above zone median).
- **SHADOW_CAST**: gate smoothstep(0.25, 0.65) — reaches into midtones.
- **LUMA_CONTRAST_***: 6-band hue-selective clarity, ungated, chroma-gated (smoothstep 0.04→0.10). Shares CLARITY's guided filter detail signal.
- **CLARITY**: midtone-gated (0.15→0.40). LUMA_CONTRAST_* uses separate ungated detail path.

## ⚠ Shadow lift — TROUBLESHOOTING IN PROGRESS
- **Problem**: shadow lift not visibly working in GZW jungle at any SHADOWS value.
- **Root cause**: `texture_att` (Retinex scale variance) suppressed lift to ~0 in textured areas. Jungle is all texture.
- **Changes made this session**:
  - `texture_att` removed from shadow lift (still computed, just not applied there)
  - `detail_protect` relaxed: `smoothstep(-4.0, -0.5, log_R)` (was -2.0)
  - `lift_w` bell extended: `smoothstep(0.35, 0.0, new_luma)` (was 0.23)
- **Not yet confirmed working in-game** — needs test at current SHADOWS 2.00.
- **If still broken**: remaining suppressors are `fine_texture_att`, `context_lift`, `specular_att`.

## GZW current values (live — not committed)
- EXPOSURE 0.30 / HALATION 0.10 / INVERSE_LUMA 0.25 / DIR_COUPLER 0.40
- CONTRAST 1.70 / SHADOWS 2.00 / CLARITY 0.5
- LUMA_CONTRAST_GREEN 1.50 / LUMA_CONTRAST_CYAN 1.0 / LUMA_CONTRAST_BLUE 0.0
- CURVE_R_KNEE -0.25 / CURVE_B_KNEE +0.10
- SHADOW_CAST -0.40 / SHADOW_TEMP -0.15 / HUE_GREEN -0.45 / HUE_CYAN +0.12
- SAT_GREEN 0.50 / SAT_CYAN 0.30 / VIBRANCE 1.0
- PRINT_STOCK 0.35 / BLEACH_BYPASS 0.22 / DIFFUSION 0.50 / GRAIN 0.0

## Next
- Test shadow lift in GZW jungle — confirm fix works
- If still broken: investigate fine_texture_att / context_lift / specular_att
- Rebless arc_raiders baselines
- Retune arc_raiders creative_values.fx after 3-way CC rescale
