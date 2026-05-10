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
- R147–R158 complete: statistical signal correctness pass, dead-code removal (4 passes), grain timer fix, inverse_grade hue-aware expansion. Full audit: analysis_frame ✓ corrective ✓ grade ✓ inverse_grade ✓ (analysis_scope/pre are display tools, not transformative).
- creative_values.fx reordered (INPUT→CORRECTIVE→TONAL→CHROMA→OUTPUT→STAGE GATES) and retuned: SHADOW_LIFT 0.85, PURKINJE 0.90, CURVE_B_TOE −0.010, FILM_FLOOR 0.005, GRAIN_STRENGTH 1.0.
- **Mid-shadow off-color** — unverified post R127/R130. Likely resolved. Re-test before marking closed.
- **Grain** — now animated (R158). GRAIN_STRENGTH 1.0 = calibrated 2383 amplitude; tune up if too subtle.

## Next candidates

- **Re-test mid-shadow off-color** — confirm resolved before vk-colorist Phase 2.
- **Second game calibration** — GZW profile is an uncalibrated copy. Validate game-agnosticism on different content.
- **vk-colorist Phase 0** — Rust/Vulkan layer infrastructure is independent of shader quality; can start now.
- **ApplyChroma** still ~80 lines — over Rule 4 limit. Split into ApplyChromaLift + ApplyChromaFinish deferred.
