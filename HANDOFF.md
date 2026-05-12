# Handoff — 2026-05-12

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
- R159–R180 complete. R161/R164/R176-autochroma permanently dropped.
- **EXPOSURE** now stops-based `rgb * pow(2, EXPOSURE)`. Both profiles at 0.0 neutral; testbed at 0.15 EV.
- **FilmCurve** rational shoulder + toe. `fc_factor`, `fc_toe_fac`, `fc_stevens`, `shoulder_w`, `toe_w` all removed. Asymptotically SDR-bounded by construction.
- **body_s bug** (R126, latent since 2026-05-07) fixed — clamped to `saturate(x)` before xw computation.
- CURVE_B_KNEE +0.008, CURVE_B_TOE −0.005 (rebalanced after shoulder_w/toe_w removal).
- **Current creative_values** — read live from `creative_values.fx` files; do not cache here.
- **R185 HCHROMA_ROLLOFF** — implemented, default 0.0 in both profiles. Start at 0.35 to calibrate.
- **R186 bilateral local luma** — inverse_grade now 3 passes. INVERSE_STRENGTH needs recalibration (shadows get less expansion than before, highlights more).
- **Mid-shadow off-color** — unverified post R127/R130. Likely resolved. Re-test before marking closed.

## Next candidates

- **Recalibrate INVERSE_STRENGTH** — R186 zone weights change effective expansion; old value likely needs a small pull-down.
- **Re-test mid-shadow off-color** — confirm resolved before vk-colorist Phase 2.
- **vk-colorist Phase 0** — Rust/Vulkan layer infrastructure is independent of shader quality; can start now.
- **ApplyChroma** still ~80 lines — over Rule 4 limit. Split into ApplyChromaLift + ApplyChromaFinish deferred.
- **Testbed re-tune** — rational film curve changes tonal character; EXPOSURE, PRINT_STOCK, CURVE offsets all need calibration from neutral.
