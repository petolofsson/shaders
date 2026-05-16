# Handoff — 2026-05-16

> **Purpose (for AI context):** Current session state. Read at session start. Update at session end. Changelog entries go in CHANGELOG.md. **Hard limit: 60 lines including this header. Trim aggressively — one fact per line, no prose.**

## Active chain (testbed)
`analysis_frame : inverse_grade : corrective : grade`
grade: 10 passes — LFDownscale1 → LFDownscale2 → NeutralIllum → GuidedCoeff → GuidedBase → ColorTransform → DiffusionDownsample → DiffusionBlurH → DiffusionBlurV → Diffusion

## Known state
- No compile errors. Log: `/tmp/vkbasalt.log`
- **Knob convention**: 0 = passthrough universally. 1 = full designed effect. Compensation factors live in grade.fx — not in creative_values.fx values.
- **BLACKS**: `max(col.rgb, cfilm_floor)` floor lift in ColorTransformPS, before ApplyCorrective.
- **WHITES**: `min(lin_e, WHITES)` ceiling clip inside ApplyCorrective, after EXPOSURE+HALATION, before FilmCurve.
- **EXPOSURE**: uniform `lin_e *= exp2(EXPOSURE)` — no luma gate. Fires after INVERSE_LUMA.
- **INVERSE_LUMA**: scene-median (p50) ACES quadratic inverse. Uniform scalar — no per-pixel luma variation. Shadow gate smoothstep(0.005, 0.04) only.
- **HALATION**: post-EXPOSURE. DoG `pixel − lf_mip1`, smoothstep(0.25, 0.40) threshold, `dog² × luma_p`. Orange R:G:B = 0.63:0.25:0.02. Global warm highlight character is intentional.
- **CLARITY**: lower shadow gate only (smoothstep 0.15→0.40). Upper gate removed. Large-scale gradient suppression via `log_base − log_lf1` (cloud/sky boundary scale suppressed; fine texture unaffected).
- **VIBRANCE**: scale `×0.40` (was ×0.04). Pivot = `HueCeil(h_out) × 0.5` — no Kalman dependency. vib_mask ceiling = `HueCeil` (was hardcoded 0.22).
- **SHADOW_CAST**: bipolar. Positive = warm amber (×4 scale: 0.080/0.048 ab). Negative = Purkinje desaturate+bias (0.60 desat, 0.032/0.088 ab). Gate smoothstep(0.25, 0.55). Purkinje standalone block removed — folded in here.
- **SATURATION knob**: removed from creative_values.fx and grade.fx. Use per-band SAT_* uniformly instead.
- **DIR_COUPLER**: guarded with `if (DIR_COUPLER > 0.0)`, lerp-blended by value. 0 = true passthrough.
- **FilmCurve**: shoulder softened — `lerp(lin_e, fc_out, fc_w)` where fc_w rolls off to 0.5 in shoulder region.
- **Zone S-curve**: `above_w` gate removed — zone_adj now fires uniformly.
- **CURVE_***: ×0.10 in shader. ±1.0 user range = ±0.10 stop knee/toe shift.
- **Highway**: HighwayTex 256×1 R16F. Slots documented in highway.fxh.
- **Baselines**: INVALID — needs rebless after this session's changes.
- **tools/capture.py**: `import` fixed to `-display :0` (was `-window root`). Polls 1s after tool exit before trying next — fixes spectacle silent-success on KDE Wayland with mpv fullscreen.

## Next
- Run `stage_isolate --game arc_raiders` to generate callsheet (capture fix now in)
- Rebless baselines with `bless_all --game arc_raiders` after callsheet review
- Retune GZW `creative_values.fx` from new 0=passthrough baseline
