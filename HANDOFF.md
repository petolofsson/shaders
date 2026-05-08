# Handoff — 2026-05-08

> **Purpose (for AI context):** Current session state — active chain, known issues, and next candidates. Read this at the start of a session to orient quickly. Update known state and next candidates at the end of each session. Do not add changelog entries here; those go in CHANGELOG.md.

## Active chain (testbed)

```
analysis_frame : inverse_grade : analysis_scope_pre : corrective : grade : analysis_scope
```

grade is an **8-pass technique**: LFDownscale1 → LFDownscale2 → NeutralIllum → ColorTransform → DiffusionDownsample → DiffusionBlurH → DiffusionBlurV → Diffusion

Diffusion is merged inside grade — not a separate effect in the chain.

## Pipeline state

| Stage | Finished | Novel |
|-------|----------|-------|
| Stage 0 — Input | 97% | 83% |
| Stage 1 — Film Stock | 97% | 90% |
| Stage 2 — Tonal | 95% | 87% |
| Stage 3 — Color + Halation | 98% | 92% |
| Output — Diffusion | 96% | 85% |

## Known state

- No known compile errors or visual regressions. Debug log: `/tmp/vkbasalt.log`
- **R52 Purkinje** now shifts both a* (green) + b* (blue) toward 507nm rod peak and adds scotopic desaturation (`lab.yz *= 1 − 0.12 × w`). PURKINJE_STRENGTH 1.0 — recalibration pass warranted.
- **R132 Diffusion** polydisperse: red ×1.15, green ×1.00, blue ×0.85. DIFFUSION_STRENGTH 1.0 (red effective ~1.15 vs. old 1.2 baseline). May need tuning.
- Shadow lift audit complete (detail_protect, local_range_att removed, lift_w ceiling). Lift chain is clean.
- Stage 3.5 dissolved — halation is part of Stage 3 (same MegaPass, same novelty accounting).

## Next candidates

- **Calibration pass** — PURKINJE_STRENGTH and DIFFUSION_STRENGTH both changed this session; in-game tuning warranted before further code work.
- **Stage 2 novelty gap** — at 87% with critical eyes. Retinex and zone system carry non-novel mass. R74 Munsell highlight desaturation arm (chroma rolloff approaching white) is unimplemented and would add a genuinely absent physical term.
- **Output novelty gap** — at 85%. To move the score requires a mechanism distinct from the blur-and-blend chassis, not further parameter refinement.
