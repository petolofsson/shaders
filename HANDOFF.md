# Handoff — 2026-05-14

> **Purpose (for AI context):** Current session state. Read at session start. Update at session end. Changelog entries go in CHANGELOG.md. **Hard limit: 60 lines including this header. Trim aggressively — one fact per line, no prose.**

## Active chain (testbed)
`analysis_frame : inverse_grade : corrective : grade`
grade: 10 passes — LFDownscale1 → LFDownscale2 → NeutralIllum → GuidedCoeff → GuidedBase → ColorTransform → DiffusionDownsample → DiffusionBlurH → DiffusionBlurV → Diffusion

## Known state
- No compile errors. Log: `/tmp/vkbasalt.log`
- **Highway**: HighwayTex 256×1 R16F in `highway.fxh`. BackBuffer pure image — no y=0 guards. `HWY_CHROMA_SLOPE` (was `HWY_SLOPE`), `HWY_MEDIAN_C` (was `HWY_MEAN_CHROMA`). `HWY_STEVENS` removed.
- **inverse_grade**: single-pass. Zone `4·L·(1−L)`. lerp_t = `saturate(INVERSE_STRENGTH × zone_w × c_weight × dir_scale)`.
- **HWY_CHROMA_SLOPE**: `lerp(1.8, 1.15, saturate(median_C / 0.15))` — low chroma → max expansion.
- **EXPOSURE**: stops-based `rgb × exp2(EXPOSURE)`. Luma gate: full below 0.55, rolls off to 1.0 at 0.85.
- **FilmCurve**: rational shoulder + toe. SDR-bounded by construction.
- **Halation**: pre-FilmCurve. G weights modulated by `illum_warm`. R:G:B ≈ 30:3:1.
- **Retinex (R191 P1)**: fires before zone S-curve. `nl_safe = max(luma, 0.001)`.
- **3-way CC (R191 P2)**: fires before `ApplyPrintStock`. SHADOW_TEMP/TINT may need recal.
- **R192 P3**: `ApplyLook` post-chroma. PRINT_STOCK/BLEACH_BYPASS in new LOOK section. **Needs calibration.**
- **R190**: GuidedCoeff+GuidedBase at 1/8-res (r=3 texels). **log2-luma space** (was log10). GuidedCoeffTex (RG16F). BilateralLogTex slot unchanged. BILATERAL_STRENGTH → LOCAL_TONE.
- **Skin tone fix**: ROT_RED 0.00, SAT_RED −0.10, SAT_YELLOW −0.10.
- **HK**: `lerp(0.32, 0.18, zone_log_key / 0.50)` — stronger at low luminance. Abney: `1 + median_C × 0.25`.
- **Mid-shadow off-color**: unverified post-R127/R130. Re-test before vk-colorist Phase 2.

## R192 P3 calibration — pending visual evaluation
- PRINT_STOCK: try 0.25–0.30 (fires on fully-graded signal, feels stronger)
- BLEACH_BYPASS: try 0.03 (shadow desaturation denser; lift no longer softens it)
- SHADOW_TEMP: move toward 0 (was partly compensating print stock warm cast)
- VIBRANCE/SAT_*: may need to come down (calibrated against pre-desaturated signal)

## Next candidates
- ApplyChroma split — still ~80 lines, over Rule 4 limit
- CHROMA_SHOULDER calibration — try 0.35 as starting point
- vk-colorist Phase 0 — Rust/Vulkan layer, independent of shader quality
- Re-test mid-shadow off-color
