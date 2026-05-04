# Handoff — 2026-05-04 (stable)

## Current branch
`alpha` — active development.

---

## Pipeline state

| Stage | Finished | Novel |
|-------|----------|-------|
| Stage 0 — Input | 93% | 80% |
| Stage 1 — Corrective | 90% | 75% |
| Stage 2 — Tonal | 90% | 88% |
| Stage 3 — Chroma | 95% | 90% |
| Stage 3.5 — Halation | 90% | 78% |
| Output — Pro-Mist | 90% | 72% |

---

## Active chain (Arc Raiders)

```
analysis_frame : inverse_grade : inverse_grade_debug : analysis_scope_pre : corrective : grade : pro_mist : analysis_scope
```

---

## What shipped this session (latest first)

### R61 — Per-pixel Hunt adaptation (grade.fx)
CAM16 local-field Hunt effect. `hunt_la = lerp(zone_log_key, lab.x, HUNT_LOCALITY)`.
Highlights get stronger chroma boost, shadows get less. `HUNT_LOCALITY 0.35` knob added.

### F1–F3 — Film sensitometry + Stevens (grade.fx)
- **F1** Print stock `desat_w` bounds now track `fc_knee_toe`/`fc_knee` — scene-adaptive desaturation window
- **F2** +6% midtone chroma bell at L≈0.47 in R22 — cinema SDR mastering data (Žaganeli et al. 2026)
- **F3** Stevens exponent sqrt→cbrt in `fc_stevens`, denominator 2.03→2.04 — psychophysically correct

### R90 — Adaptive inverse tone mapping

- **R90** — `general/inverse-grade/inverse_grade.fx` — game-agnostic adaptive inverse tone mapping
  - Oklab chroma-only expansion: luma unchanged, brightness neutral
  - `mid_weight = L*(1-L)*4` protects black/white
  - `c_weight = saturate((C-0.10)/0.15)` protects near-neutrals/warm whites
  - Slope from highway x=197 (Kalman-smoothed, computed in analysis_frame from float16 PercTex)
  - `INVERSE_STRENGTH 0.50` in `creative_values.fx`
- **R86 retired** — `inverse_grade_aces.fx`, `aces_debug.fx` moved to `unused/`
- **Oklab bug fixed** — wrong b-row in inverse_grade.fx caused systematic yellow cast.
  Correct b-row: `[0.0259040371, 0.7827717662, -0.8086757660]` (matches grade.fx)

---

## Current creative_values.fx (Arc Raiders)

| Knob | Value |
|------|-------|
| EXPOSURE | 0.90 |
| FILM_FLOOR | 0.01 |
| FILM_CEILING | 0.95 |
| ZONE_STRENGTH | 1.2 |
| SHADOW_LIFT_STRENGTH | 1.2 |
| PRINT_STOCK | 0.40 |
| HAL_STRENGTH | 0.00 |
| VEIL_STRENGTH | 0.00 |
| MIST_STRENGTH | 0.25 |
| PURKINJE_STRENGTH | 1.3 |
| VIEWING_SURROUND | 1.123 |
| LCA_STRENGTH | 0.0 |
| HUNT_LOCALITY | 0.35 |
| INVERSE_STRENGTH | 0.50 |

---

## Known state

- HAL and VEIL zeroed — both competed with inverse grade highlight expansion; restore
  cautiously if needed (start HAL at 0.15, VEIL at 2.0).
- `inverse_grade_debug.fx` in chain — can be removed once tuning is stable.
- Register pressure verified via RADV shader dump: 59 VGPRs / 87 SGPRs, no spilling.
- No known compile errors or visual regressions.

Debug log: `/tmp/vkbasalt.log` — check first for SPIR-V issues.
