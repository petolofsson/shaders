# Handoff — 2026-05-03

## Current branch
`alpha` — HEAD `50c1cc4`
Clean working tree. Pushed to origin.

## What happened this session

### Completed and shipped (in commit `50c1cc4`)
- **R65** — Hunt C/L coupling during shadow lift (prevents grey/ashy lift)
- **R66** — Ambient shadow tint injection (scene-ambient hue into achromatic shadows)
- **R68A/B** — Spatial chroma modulation + gamut pre-knee (Reinhard rolloff)
- **R69** — Abney green hue calibration validated
- **R71** — Vibrance self-masking (saturated pixels get less chroma lift)
- **R72** — Reflectance local contrast via illumination-free `log_R`
- **R73** — Memory color protection — per-band Oklab C ceilings (sky/foliage/skin)
- **R74** — Munsell-calibrated highlight desaturation: `0.25 → 0.45` in R22
- **R75** — Hue-by-luminance: `r21_delta += lerp(-0.003, +0.003, lab.x)` (2383 tonal)
- **R47** — Shadow warm bias enabled with `zone_std` gate (was always-off, UI contamination)
- **Research R65–R80** — All findings docs written and committed
- **PLAN.md** — Full phased plan written

### Attempted and reverted (NOT in any commit)
- **R76A** — CAT16 chromatic adaptation caused all-white screen. Reverted.
- **R76B** — CIECAM02 surround compensation (depended on R76A). Reverted with it.

---

## R76 failure — known issue

**Symptom:** Full white screen immediately on load.

**Likely causes (in priority order):**
1. The B-matrix inverse has large values (row 0: `[5.45, -4.22, -0.026]`). For any
   pixel where `lms * gain` overshoots, the dot products produce >> 1.0 before
   `saturate` can clamp. The 60% lerp blend does not help if the un-blended value
   is +inf or NaN.
2. `gain = lms_d65 / max(lms_ill, 0.001)` — if the `CreativeLowFreqTex` mip 2
   channel values have any zeros or near-zeros on first frame before Kalman warms
   up, `lms_ill` hits the 0.001 floor and `gain` spikes to ~1000. This would white
   out the frame.
3. `pow(max(col.rgb, 0.0), VIEWING_SURROUND)` — the `max` guard handles negatives,
   but if R76A already produced inf/NaN, R76B's pow propagates it.

**Recommended fix strategy for next session:**
- Debug R76A in isolation: temporarily set the lerp blend to 0.05 (almost identity)
  and add a `gain = clamp(gain, 0.5, 2.0)` safety clamp to verify the shader loads.
- Then confirm whether mip 2 is valid on frame 0 vs. warm state — check
  `/tmp/vkbasalt.log` for SPIR-V compile errors which would also cause white screen.
- R76B is independent — it can be skipped until R76A is stable.

---

## What's next (PLAN phases)

| Phase | Status | Items |
|-------|--------|-------|
| 1 — Research | **Done** | R74–R80 all researched |
| 2 — Quick code | **Done** | R74, R75, R47 shipped |
| 3 — Stage 0 | **Blocked** | R76A white-screen failure; needs debug |
| 4 — Stage 2 | Ready | R77 — findings say no code changes needed |
| 5 — Stage 3 | Ready | R78 — constant-hue gamut projection, zero extra cost |
| 6 — Stage 3.5 | Ready | R79A/B/C — halation gate + dual PSF + chromatic |
| 7 — Output | Ready | R80A/B/C — Pro-Mist warm scatter, adaptive, aperture proxy |

Phases 4–7 are independent of Phase 3 (R76) and can proceed while R76 is blocked.

---

## Key file locations

| File | Role |
|------|------|
| `general/grade/grade.fx` | All color work — `ColorTransformPS` |
| `gamespecific/arc_raiders/shaders/creative_values.fx` | Only tuning surface |
| `general/corrective/corrective.fx` | Analysis passes |
| `research/R76_2026-05-03_perceptual_input_normalization_findings.md` | R76 full derivation |
| `research/R78_2026-05-03_constant_hue_gamut_projection_findings.md` | R78 implementation |
| `research/R79_2026-05-03_halation_dual_psf_findings.md` | R79 implementation |
| `research/R80_2026-05-03_promist_spectral_scatter_findings.md` | R80 implementation |

## Debug log
`/tmp/vkbasalt.log` — always check this first for SPIR-V compile errors.
