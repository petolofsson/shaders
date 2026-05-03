# Handoff — 2026-05-03

## Current branch
`alpha` — HEAD `427820e`
Clean working tree. Pushed to origin.

---

## Pipeline state

All phases of the original plan are complete. Every stage is at or above target:

| Stage | Finished | Novel |
|-------|----------|-------|
| Stage 0 — Input | 92% | 75% |
| Stage 1 — Corrective | 90% | 75% |
| Stage 2 — Tonal | 90% | 88% |
| Stage 3 — Chroma | 95% | 90% |
| Stage 3.5 — Halation | 90% | 78% |
| Output — Pro-Mist | 90% | 72% |

---

## What shipped this session

- **R83** Chromatic FILM_FLOOR — per-channel black pedestal from illuminant chromaticity
- **R84** Log-density FilmCurve — `CURVE_*` as log₂-density offsets, exp2 folds at compile time
- **R85** Inter-channel dye masking — cyan→green 2%, magenta→blue 2.2% in Beer-Lambert block
- **R86** Research (Angle 0) — exact ACES analytical inverse (4 ALU, float32 epsilon), confidence fingerprint designed
- **R87** Lateral research (Telecomms) — Sage-Husa Q adaptation + IGN dither identified
- **R88** Sage-Husa Q — P-driven Kalman Q in both corrective passes, no spike misfires
- **R89** IGN dither — blue-noise-like, analytical, replaces white-noise sin hash
- **LCA** displacement halved (0.004→0.002); Arc Raiders strength adjusted to 0.8 to compensate

---

## R86 — Scene Reconstruction (next big track)

**What's done:** Analytical ACES inverse derived and validated (R86 research file). Exact quadratic formula. ACES confidence fingerprint designed using existing PercTex (zero new taps).

**What's needed before prototype:**
1. Empirically read actual `PercTex` p25/p50/p75/IQR values from Arc Raiders and GZW using the debug overlay or `/tmp/vkbasalt.log`. Confirm Arc Raiders scores `aces_conf > 0.7`, GZW scores `< 0.3`.
2. Research ACES hue distortions (Angle 1 — not yet run). Red→orange push, cyan→blue shift, yellow highlight desaturation. Need magnitude in Oklab degrees per hue band.
3. Once both: write prototype to `unused/general/inverse-grade/inverse_grade_aces.fx`. Do NOT touch live `grade.fx` until validated on both games.

**Key research file:** `research/R86_2026-05-03_R86_Scene_Reconstruction.md`

---

## No known regressions

No brightness issues, no white screens, no compile errors.
Debug log: `/tmp/vkbasalt.log` — check first for any SPIR-V issues.
