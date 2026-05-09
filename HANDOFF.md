# Handoff — 2026-05-09

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
| Stage 2 — Tonal | 96% | 91% |
| Stage 3 — Color + Halation | 98% | 92% |
| Output — Diffusion + Grain | 97% | 91% |

## Known state

- No known compile errors or visual regressions. Debug log: `/tmp/vkbasalt.log`
- **common.fxh migration suspect** — R139 audit listed a `0.001e-10` epsilon variant in `RGBtoHSV` across the three scope/frame files; git diff showed all copies were actually `1e-10` at migration time. If scope or histogram output looks off (hue smearing near achromatic/black), check whether an older `0.001e-10` variant existed and was intentional.
- **R133 Munsell per-hue highlight rolloff** — `hue_bands.fxh` carries 12 `HB_ROLL_N_*` exponents + `HueBandRollN()`. R22 highlight arm (0.45) removed — R133 is now the sole highlight desaturation mechanism. `MUNSELL_HIGHLIGHT_ROLLOFF 0.75` — calibrated on sand map.
- **R134 Print stock shoulder corrected** — Reinhard partial replaces broken `1−(1−ps)²×1.8` shoulder. No longer lifts highlights toward white. `PRINT_STOCK 0.50` stable.
- **Bleach bypass highlight floor** lowered 0.35 → 0.05 — no longer desaturates highlights; shadow/midtone grit character preserved. `BLEACH_BYPASS 0.15` stable.
- **R52 Purkinje** and **R132 Diffusion** polydisperse still warrant calibration (values set at 1.0 and 1.0 respectively).
- **R136 Film grain** — `GRAIN_STRENGTH 0.0` (off by default). Implemented, awaiting testbed calibration. pcg3d hash, Selwyn 2383 envelope, framerate-independent at ~24fps turnover.
- Shadow lift audit complete. Stage 3.5 dissolved.

## Next candidates

- **Calibration pass** — GRAIN_STRENGTH needs testbed dial-in. PURKINJE_STRENGTH, DIFFUSION_STRENGTH, MUNSELL_HIGHLIGHT_ROLLOFF also benefit from a full in-game tuning pass.
- **Stage 0 novelty gap** — at 83%. Input stage has lowest novelty score; candidates include lens distortion, chromatic aberration without UI mask, or sensor noise model.
