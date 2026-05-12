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
- **R186 bilateral local luma** — inverse_grade now 3 passes. INVERSE_STRENGTH=0.30 (tuned). lerp_t clamp + luma_env bell + highlight weight 1.4→0.8 applied. Gamut surface fix (lab.yz /= max_ch) prevents channel clipping. White-out persists at CONTRAST=0.55 — root cause is grade.fx zone S-curve shoulder, not inverse_grade. Pre-R186 had CONTRAST=1.0; investigate there next.
- **Mid-shadow off-color** — unverified post R127/R130. Likely resolved. Re-test before marking closed.

## Next candidates

- **White-out (ongoing)** — inverse_grade code now confirmed under-expanding vs. pre-R186 baseline. Investigate grade.fx zone S-curve shoulder — CONTRAST was 1.0 pre-R186, now 0.55. Also EXPOSURE was 0.17 pre-R186, now 0.23. Try raising CONTRAST toward 0.70–0.80 first.
- **Recalibrate INVERSE_STRENGTH** — R186+luma_env changes effective expansion; current IS=0.30 may need adjustment after CONTRAST is fixed.
- **Re-test mid-shadow off-color** — confirm resolved before vk-colorist Phase 2.
- **vk-colorist Phase 0** — Rust/Vulkan layer infrastructure is independent of shader quality; can start now.
- **ApplyChroma** still ~80 lines — over Rule 4 limit. Split into ApplyChromaLift + ApplyChromaFinish deferred.
- **Testbed re-tune** — rational film curve changes tonal character; EXPOSURE, PRINT_STOCK, CURVE offsets all need calibration from neutral.
