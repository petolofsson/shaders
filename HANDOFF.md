# Handoff — 2026-05-15

> **Purpose (for AI context):** Current session state. Read at session start. Update at session end. Changelog entries go in CHANGELOG.md. **Hard limit: 60 lines including this header. Trim aggressively — one fact per line, no prose.**

## Active chain (testbed)
`analysis_frame : inverse_grade : corrective : grade`
grade: 10 passes — LFDownscale1 → LFDownscale2 → NeutralIllum → GuidedCoeff → GuidedBase → ColorTransform → DiffusionDownsample → DiffusionBlurH → DiffusionBlurV → Diffusion

## Known state
- No compile errors. Log: `/tmp/vkbasalt.log`
- **Knob convention**: 0 = passthrough universally. 1 = full designed effect. Compensation factors live in grade.fx — not in creative_values.fx values.
- **Renamed**: `HAL_GAMMA` → `HALATION_CROSSOVER`. Knobs use industry vernacular: `WHITES`, `HALATION`, `CLARITY`, `PURKINJE`, `HUE_*`, `DIFFUSION`, `GRAIN`, `LOCAL_CONTRAST`.
- **BLACKS**: ×0.005 in shader. 1.0 = ARRI LogC3 black point.
- **CURVE_***: ×0.10 in shader. ±1.0 user range = ±0.10 stop knee/toe shift.
- **PRINTER_R/G/B**: 0 = neutral (was 25). Shader drops −25 offset.
- **DIFFUSION_STRENGTH**: ×1.40 in shader. 1.0 = HBM 1/2 grade.
- **Highway**: HighwayTex 256×1 R16F. `HWY_CHROMA_SLOPE`, `HWY_MEDIAN_C`. BackBuffer pure image.
- **inverse_grade**: single-pass. Zone `4·L·(1−L)`. `HWY_CHROMA_SLOPE = lerp(1.8, 1.15, saturate(median_C / 0.15))`.
- **EXPOSURE**: stops-based `rgb × exp2(EXPOSURE)`. Luma gate: full below 0.55, rolls off to 1.0 at 0.85.
- **FilmCurve**: rational shoulder + toe. SDR-bounded by construction.
- **Halation**: pre-FilmCurve. G weights modulated by `illum_warm`. R:G:B ≈ 30:3:1.
- **Retinex (R191 P1)**: fires before zone S-curve.
- **3-way CC (R191 P2)**: fires before `ApplyPrintStock`.
- **ApplyLook (R192 P3)**: PRINT_STOCK/BLEACH_BYPASS post-chroma. Needs retune.
- **R190**: GuidedCoeff+GuidedBase at 1/8-res. log2-luma space. LOCAL_TONE/CLARITY preserved.
- **Analysis tools**: Oklab/ΔE_oklab metric. `stage_isolate`, `compare_frame --all`, `check_all`.
- **Baselines**: VALID — check_all PASS 4/4 (5a78cdb). Oklab compare_frame baseline established 2026-05-15.

## Next
- Retune GZW `creative_values.fx` from new 0=passthrough baseline
- Rebless baselines with `check_all --bless` after retune
- ApplyChroma split — still ~80 lines, over Rule 4 limit
