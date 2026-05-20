# Handoff — 2026-05-20

> **Purpose (for AI context):** Current session state. Read at session start. Update at session end. Changelog entries go in CHANGELOG.md. **Hard limit: 60 lines including this header. Trim aggressively — one fact per line, no prose.**

## Active chain (testbed)
`analysis_frame : inverse_grade : corrective : grade`
grade: 11 passes — LFDownscale1 → LFDownscale2 → NeutralIllum → GuidedCoeff → GuidedBase → ColorTransform → DiffusionDownsample → DiffusionBlurH → DiffusionBlurV → Diffusion → TexHwyWrite

## Known state
- No compile errors. Log: `/tmp/vkbasalt.log`
- **R204 reverted; R205 shipped**: FilmCurveApply is back, improved. See research/R205_2026-05-20_filmcurve_improvements.md.
- **FilmCurveApply** (R205): two components — body_s + sh_comp. tc_comp (rational toe) removed: display-referred has no photochemical toe. body_s reparameterized: `t_norm = saturate((xs − 0.5) / max(knee_rgb − 0.5, 0.001))` — peak tracks fc_knee, zero exactly at knee, no overlap with sh_comp. fc_w half-strength blend removed (redundant: sh_comp is already C1 at knee; FILM_CURVE is now sole blend control). Signature: `FilmCurveApply(float3 x, float knee_r, float knee_g, float knee_b)`.
- **hl_taper** (R205): FilmCurve fades to zero at WHITES ceiling. `hl_taper = 1.0 − smoothstep(fc_knee, WHITES, Luma(lin_e))`. Blend: `lerp(lin_e, fc_out, saturate(FILM_CURVE) * hl_taper)`.
- **FilmCurveInvCh** (R205): shoulder-only (toe removed — nothing to invert). `lerp(y, x_sh, step(knee, y))`. Knee per-channel from highway p25/p75 + CURVE_R/B_KNEE. No ktoe params.
- **CURVE_R/B_TOE knobs**: removed from both creative_values.fx. CURVE_R/B_KNEE remain (±1.0 → ±0.10 stop shift).
- **BLACKS/WHITES**: single linear remap at top of ColorTransformPS: `lin = col.rgb * (WHITES − BLACKS) + BLACKS`.
- **ApplyMaskingCoupler**: gated by `lerp(lin, warmed, saturate(print_stock))` — was unconditional warm cast.
- **ApplyDyeMatrix**: gated by `lerp(lin, result, saturate(print_stock))` — was always-on.
- **desat_w** (ApplyPrintStock): fixed. Was shadow-only `(1 − smoothstep(...))`. Now midtone bell: `smoothstep(0, fc_knee_toe, luma_ps) × (1 − smoothstep(fc_knee, 1, luma_ps))`.
- **arc_raiders**: PRINT_STOCK = 1.00 (calibration starting point — likely dial back). FILM_CURVE = 1.0 (corrected from garbage 444.0).

## Next
- A/B and calibrate PRINT_STOCK — first session with correct midtone desaturation. Start at 1.00, dial back to taste.
- Recalibrate EXPOSURE on arc_raiders — BLACKS/WHITES remap shifts tonal position.
- Recalibrate 3-way CC (SHADOW/MID/HIGHLIGHT TEMP/TINT) on both profiles.
