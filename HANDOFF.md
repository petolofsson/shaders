# Handoff — 2026-05-10

> **Purpose (for AI context):** Current session state. Read at session start to orient. Update at session end. Changelog entries go in CHANGELOG.md.

## Active chain (testbed)

```
analysis_frame : inverse_grade : corrective : grade
```

grade is an **8-pass technique**: LFDownscale1 → LFDownscale2 → NeutralIllum → ColorTransform → DiffusionDownsample → DiffusionBlurH → DiffusionBlurV → Diffusion

## Pipeline state

| Stage | Finished | Novel |
|-------|----------|-------|
| Stage 0 — Input | 98% | 92% |
| Stage 1 — Film Stock | 98% | 94% |
| Stage 2 — Tonal | 97% | 91% |
| Stage 3 — Color + Halation | 98% | 90% |
| Output — Diffusion + Grain | 97% | 94% |

## Known state

- No known compile errors. Debug log: `/tmp/vkbasalt.log`
- R159–R179 complete. R161/R164 permanently dropped.
- R174: grain rain fixed — root cause was luma-dependent lerp in luma_scale, not temporal slot rate. Fixed luma_scale=2.5, 24fps slot snap, correct 2383 per-channel dye layer sizing (R×1.15/G×1.00/B×0.85).
- R175: shadow lift gate now (p25+mode)×0.5 — prevents over-lift in bright outdoor scenes; pixel bell extended to smoothstep(0.27,0,luma).
- R176: chroma_str_base gamut expansion + Hunt effect — `lerp(1.25, 0.85, smoothstep(0.04, 0.18, mean_C))` replaces R151's one-sided boost. Vibrant scenes now back off to ×0.85; achromatic scenes up to ×1.25.
- R177: MeanChroma EMA slowed to ~1s τ (`frametime*0.001`), scene-cut reset. Was visibly tracking camera movement along walls.
- R178: Shadow lift gated on zone_std — high-contrast scenes (intentional dark interior) suppress lift to zero via `smoothstep(0.05,0.13,zone_std)`.
- R179: Chroma lift dead zones fixed — tertiary hues (orange/amber/teal/azure/violet/rose) were getting zero lift due to ±0.08 band width gaps. Widened to ±0.14 in pivot loop only. Confirmed working.
- Diffusion center: 0% (was 20%) — eliminated center haze. Ramp now starts at r=0.30.
- **arc_raiders** current values: EXPOSURE 0.85, FILM_CEILING 0.97, PRINT_STOCK 0.50, BLEACH_BYPASS 0.10, ZONE_STRENGTH 1.10, SHADOW_LIFT_STRENGTH 1.0, CHROMA_STR 1.10, PURKINJE_STRENGTH 0.75, HAL_STRENGTH 0.30, HAL_GAMMA 0.05, DIFFUSION_STRENGTH 0.70, GRAIN_STRENGTH 1.1.
- **GZW** current values: EXPOSURE 0.80, FILM_CEILING 0.97, PRINT_STOCK 0.50, BLEACH_BYPASS 0.15, ZONE_STRENGTH 1.15, SHADOW_LIFT_STRENGTH 0.80, PURKINJE_STRENGTH 0.65, HAL_STRENGTH 0.30, HAL_GAMMA 0.02, DIFFUSION_STRENGTH 0.65.
- **Mid-shadow off-color** — unverified post R127/R130. Likely resolved. Re-test before marking closed.

## Next candidates

- **Re-test mid-shadow off-color** — confirm resolved before vk-colorist Phase 2.
- **vk-colorist Phase 0** — Rust/Vulkan layer infrastructure is independent of shader quality; can start now.
- **ApplyChroma** still ~80 lines — over Rule 4 limit. Split into ApplyChromaLift + ApplyChromaFinish deferred.
