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

## Pipeline state as of 2026-05-04 (for context)
- Chain: analysis_frame → inverse_grade → corrective (7 passes) → grade → pro_mist
- Active knobs: INVERSE_STRENGTH, EXPOSURE, FILM_FLOOR/CEILING, PRINT_STOCK,
  CURVE_R/B_KNEE/TOE, ZONE_STRENGTH, SHADOW_LIFT_STRENGTH, 3-way CC (6 values),
  CHROMA_STR, ROT_* (6 values), HAL_STRENGTH, MIST_STRENGTH, VEIL_STRENGTH,
  VIGN_* (3 values), PURKINJE_STRENGTH, LCA_STRENGTH, VIEWING_SURROUND
- Removed this session: R47 shadow auto-temp, HUNT_LOCALITY, ShadowBias pass
- New highway slots: HWY_P90 (200), HWY_CHROMA_ANGLE (201), HWY_ACHROM_FRAC (202)

## Last updated
2026-05-04 — Added pipeline state snapshot, OPT-2/3 exclusion, updated chain
pass count to 7 (ShadowBias removed).
