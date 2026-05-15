# Handoff — 2026-05-16

> **Purpose (for AI context):** Current session state. Read at session start. Update at session end. Changelog entries go in CHANGELOG.md. **Hard limit: 60 lines including this header. Trim aggressively — one fact per line, no prose.**

## Active chain (testbed)
`analysis_frame : inverse_grade : corrective : grade`
grade: 10 passes — LFDownscale1 → LFDownscale2 → NeutralIllum → GuidedCoeff → GuidedBase → ColorTransform → DiffusionDownsample → DiffusionBlurH → DiffusionBlurV → Diffusion

## Known state
- No compile errors. Log: `/tmp/vkbasalt.log`
- **Knob convention**: 0 = passthrough universally. 1 = full designed effect. Compensation factors live in grade.fx — not in creative_values.fx values.
- **Removed knobs**: `DEHAZE` (was LOCAL_CONTRAST — guided lift unreliable across scene types). `HALATION_CROSSOVER` — replaced by baked DoG threshold 0.04.
- **BLACKS**: direct linear floor. 0.00 = passthrough. 0.005 = ARRI LogC3 black point.
- **CURVE_***: ×0.10 in shader. ±1.0 user range = ±0.10 stop knee/toe shift.
- **PRINTER_R/G/B**: 0 = neutral (was 25). Shader drops −25 offset.
- **DIFFUSION_STRENGTH**: ×1.40 in shader. 1.0 = HBM 1/2 grade.
- **Highway**: HighwayTex 256×1 R16F. `HWY_CHROMA_SLOPE`, `HWY_MEDIAN_C`. BackBuffer pure image.
- **inverse_grade**: single-pass. Zone `4·L·(1−L)`. **R198**: FilmCurve pre-inverse (`FilmCurveInvCh`) applied before Oklab conversion — chroma expansion in post-curve domain. `HWY_CHROMA_SLOPE = lerp(1.8, 1.15, saturate(median_C / 0.15))`.
- **EXPOSURE**: stops-based `rgb × exp2(EXPOSURE)`. Luma gate: full below 0.55, rolls off to 1.0 at 0.85.
- **FilmCurve**: rational shoulder + toe. SDR-bounded by construction.
- **Halation**: pre-FilmCurve. DoG threshold 0.04 filters diffuse areas (sky/clouds). Orange: R:G:B = 0.63:0.25:0.02. Self-limiting by construction.
- **CLARITY**: midtone-only. Shadow rolloff `smoothstep(0.15,0.40)`, highlight rolloff `1−smoothstep(0.60,0.85)`. Constant 0.025 (log2-space).
- **Retinex (R191 P1)**: fires before zone S-curve.
- **3-way CC (R191 P2)**: fires before `ApplyPrintStock`.
- **ApplyLook (R192 P3)**: PRINT_STOCK/BLEACH_BYPASS post-chroma. Needs retune.
- **R190**: GuidedCoeff+GuidedBase at 1/8-res. log2-luma space. CLARITY only (DEHAZE removed).
- **Analysis tools**: Oklab/ΔE_oklab metric. `stage_isolate`, `compare_frame --all`, `check_all`.
- **Baselines**: INVALID — halation + CLARITY changes since last bless.

## Next
- Continue arc_raiders retune: enable CHROMA then LOOK stages
- Rebless baselines with `check_all --bless` after full retune
- Retune GZW `creative_values.fx` from new 0=passthrough baseline
- ApplyChroma split — still ~80 lines, over Rule 4 limit
