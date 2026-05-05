# Job — Shader Research Nightly

**Trigger ID:** trig_01X6LEJt3G5xvjUqGiaokRFh
**Schedule:** 0 1 * * * (1 AM UTC)
**Output:** `research/R{next}_{YYYY-MM-DD}_{slug}.md`

## Summary

Domain-rotation literature search. Finds novel findings from adjacent fields and
filters them for architectural viability. Writes a dated findings file to alpha.

## Domain rotation (date +%u)
1 Mon — Tone mapping & film sensitometry
2 Tue — Perceptual chroma (HK, Hunt, Abney)
3 Wed — Temporal filtering & state estimation
4 Thu — Zone/histogram analysis
5 Fri — Film stock spectral emulation
6 Sat — Color appearance models
7 Sun — Wild card

## Key exclusions (permanent, no exceptions)
- Clarity / sharpening / local contrast / mid-frequency boost / CLARITY_STRENGTH
- Film grain
- Lateral chromatic aberration
- Any HDR-only technique
- OPT-2/3 (zone_log_key guard removal, saturate(lin) removal) — cold-start
  regression confirmed; do not re-propose without cold-start frame proof

## Already implemented — do not re-propose (Tuesday/chroma domain)
- **R101 F1 — Bezold-Brücke** (2026-05-05): Replaces R75 uniform hue-by-luminance lerp.
  Unique-yellow-anchored `-sin(2π(h−0.27))` model using `sh_h`/`ch_h` from HELMLAB.
  Single-harmonic — slightly over-corrects cyan; two-harmonic extension is a future candidate.
- **R101 F2 — H-K exponent scene-adaptation** (2026-05-05): `pow(final_C, 0.587)` →
  `pow(final_C, lerp(0.52, 0.64, saturate(zone_log_key / 0.50)))`. Nayatani 1997 backed.
- **R101 F3 — Abney C_stim** (2026-05-05): Abney coefficients scale by pre-lift stimulus
  chroma `C_stim`, not post-lift `final_C`. Burns et al. 1984.

## Pipeline state as of 2026-05-05
- Chain: analysis_frame → inverse_grade → inverse_grade_debug → corrective (7 passes) → grade → pro_mist → analysis_scope
- Active knobs: INVERSE_STRENGTH, EXPOSURE, FILM_FLOOR/CEILING, PRINT_STOCK,
  CURVE_R/B_KNEE/TOE, ZONE_STRENGTH, SHADOW_LIFT_STRENGTH, 3-way CC (6 values),
  CHROMA_STR, ROT_* (6 values), HAL_STRENGTH, MIST_STRENGTH, VEIL_STRENGTH,
  VIGN_* (3 values), PURKINJE_STRENGTH, LCA_STRENGTH, VIEWING_SURROUND
- HUNT_LOCALITY: intentionally removed (e155e6c, 2026-05-04) — not a regression
- New highway slots: HWY_P90 (200), HWY_CHROMA_ANGLE (201), HWY_ACHROM_FRAC (202)

## Last updated
2026-05-05 — Added R101 F1/F2/F3 to implemented list. Updated pipeline state.
