# Handoff — 2026-05-10

> **Purpose (for AI context):** Current session state. Read at session start to orient. Update at session end. Changelog entries go in CHANGELOG.md.

## Active chain (testbed)

```
analysis_frame : inverse_grade : analysis_scope_pre : corrective : grade : analysis_scope
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
- R159–R169 complete. R161 (achrom_frac chroma gate) and R164 (LUMA_MEAN_PRE slope cap) permanently dropped — degraded blacks character, redundant with existing signals.
- R165 (HWY_ILLUM_WARM slot 220) and R163 (CHROMA_ANGLE alignment bias) active.
- R166/R167: three-octave grain replaced with two-octave (2px smooth + 1px blue noise) + luma-dependent size + per-channel dye layer scaling.
- R168: physical halation — two-scale DoG PSF (tight 1/16−sharp, broad 1/32−1/16), AH layer attenuation on tight ring (2383 rem-jet ~40%), per-layer color weights.
- R169: grain temporal cross-dissolve — `frac(FRAME_TIMER/41.667)` sub-frame blend between grain slots eliminates screen-space snap at high FPS (>60fps rain artifact).
- GZW jungle movie grade complete: teal-green shadows, green ambient mids, golden highlights, deep-cyan greens.
- **arc_raiders** current values: INVERSE_STRENGTH 0.50, SHADOW_LIFT_STRENGTH 1.00, CHROMA_STR 1.10, HAL_STRENGTH 0.20, HAL_GAMMA 0.05, GRAIN_STRENGTH 1.15.
- **GZW** current values: SHADOW_LIFT_STRENGTH 1.15, DIFFUSION_STRENGTH 0.60, HAL_STRENGTH 0.30, HAL_GAMMA 0.02.
- **Mid-shadow off-color** — unverified post R127/R130. Likely resolved. Re-test before marking closed.

## Next candidates

- **Re-test mid-shadow off-color** — confirm resolved before vk-colorist Phase 2.
- **vk-colorist Phase 0** — Rust/Vulkan layer infrastructure is independent of shader quality; can start now.
- **ApplyChroma** still ~80 lines — over Rule 4 limit. Split into ApplyChromaLift + ApplyChromaFinish deferred.
