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
| Output — Diffusion | 96% | 85% |

## Known state

- No known compile errors or visual regressions. Debug log: `/tmp/vkbasalt.log`
- **R133 Munsell per-hue highlight rolloff** — `hue_bands.fxh` carries 12 `HB_ROLL_N_*` exponents + `HueBandRollN()`. R22 highlight arm (0.45) removed — R133 is now the sole highlight desaturation mechanism. `MUNSELL_HIGHLIGHT_ROLLOFF 0.75` — calibrated on sand map.
- **R134 Print stock shoulder corrected** — Reinhard partial replaces broken `1−(1−ps)²×1.8` shoulder. No longer lifts highlights toward white. `PRINT_STOCK 0.50` stable.
- **Bleach bypass highlight floor** lowered 0.35 → 0.05 — no longer desaturates highlights; shadow/midtone grit character preserved. `BLEACH_BYPASS 0.15` stable.
- **R52 Purkinje** and **R132 Diffusion** polydisperse still warrant calibration (values set at 1.0 and 1.0 respectively).
- Shadow lift audit complete. Stage 3.5 dissolved.

## Next candidates

- **Calibration pass** — PURKINJE_STRENGTH, DIFFUSION_STRENGTH, and MUNSELL_HIGHLIGHT_ROLLOFF all changed; full in-game tuning pass warranted.
- **Output novelty gap** — at 85%. Requires a mechanism distinct from the blur-and-blend chassis (grain, anisotropic diffusion, or similar).
