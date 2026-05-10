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
| Stage 0 — Input | 98% | 90% |
| Stage 1 — Film Stock | 98% | 91% |
| Stage 2 — Tonal | 97% | 91% |
| Stage 3 — Color + Halation | 98% | 92% |
| Output — Diffusion + Grain | 97% | 91% |

## Known state

- No known compile errors. Debug log: `/tmp/vkbasalt.log`
- R147–R165 complete: statistical signal correctness, grain timer fix, hue-aware expansion, highway audit (R161–R164), illuminant warmth CCT proxy (R165). Full audit: analysis_frame ✓ corrective ✓ grade ✓ inverse_grade ✓.
- R159: luma expansion removed from inverse_grade (zone S-curve owns luma). R145 zone coupling removed — ZONE_STRENGTH is now a clean knob.
- R160 adaptive print stock: black lift backs off when p25 elevated, shoulder softens when p75 high.
- R161–R164 highway wiring: ACHROM_FRAC→chroma_str, P90→shadow lift suppression, CHROMA_ANGLE→expansion alignment bias, LUMA_MEAN_PRE→slope cap.
- R165 slot 220 (HWY_ILLUM_WARM): CAT16 LMS warmth scalar written by ColorTransformPS, read one-frame-delayed by inverse_grade to scale back warm-hue bias in warm-lit scenes.
- creative_values.fx (arc_raiders): PURKINJE_STRENGTH 0.70, CHROMA_STR 1.05, ZONE_STRENGTH 1.00.
- **Mid-shadow off-color** — unverified post R127/R130. Likely resolved. Re-test before marking closed.

## Next candidates

- **Re-test mid-shadow off-color** — confirm resolved before vk-colorist Phase 2.
- **Second game calibration** — GZW profile is an uncalibrated copy. Validate game-agnosticism on different content.
- **vk-colorist Phase 0** — Rust/Vulkan layer infrastructure is independent of shader quality; can start now.
- **ApplyChroma** still ~80 lines — over Rule 4 limit. Split into ApplyChromaLift + ApplyChromaFinish deferred.
