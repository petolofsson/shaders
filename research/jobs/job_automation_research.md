# Job — Shader Automation Research

**Trigger ID:** trig_01Cm4QTimdKcVX5ZwoiSvhBg
**Schedule:** 0 2 * * * (2 AM UTC)
**Output:** `research/R{next}_{YYYY-MM-DD}_automation.md`

## Summary

Core scene-descriptive automation is complete (R41). This job now focuses on:
1. Adaptive base values — can INVERSE_STRENGTH base, HAL_STRENGTH, ZONE_STRENGTH,
   or CHROMA_STR be auto-derived from scene statistics?
2. Knob count reduction — can rarely-changed knobs be eliminated or merged?
3. New highway slots — HWY_P90, HWY_CHROMA_ANGLE, HWY_ACHROM_FRAC are now available.
   Investigate what pipeline stages could consume them usefully.

## Candidates under investigation

- **INVERSE_STRENGTH base (0.50)** — adapt to IQR compression ratio? p90 now
  available on highway (HWY_P90) for more accurate range measurement.
- **HAL_STRENGTH (0.35)** — current warm_bias feedback loop amplifies red in warm
  scenes (hal_r_gain goes 1.05→1.35 as warm_bias increases). Consider whether this
  is desirable or should be flattened to neutral gains.
- **ZONE_STRENGTH (1.15)** — inverse scale with zone_std?
- **CHROMA_STR (1.0 = 0.04 raw)** — can the 0.04 calibrated constant be derived
  from achromatic fraction (HWY_ACHROM_FRAC)? Gray-heavy scenes might want less lift.
- **Pro-Mist warm scatter** — scatter_r=1.05/scatter_b=0.92 in neutral scenes is a
  baked warm push. Now that R47 is removed, investigate whether this should be
  neutralised or kept as scene-warmth compensation.
- **HWY_CHROMA_ANGLE** — scene colour direction now on highway. Could inverse_grade
  use it to bias expansion toward scene's dominant hue rather than expanding uniformly?

## Locked artistic knobs (do not propose automating)
EXPOSURE, all CC wheels, CURVE_*_KNEE/TOE, ROT_*, PRINT_STOCK, MIST_STRENGTH,
PURKINJE_STRENGTH, VIEWING_SURROUND, LCA_STRENGTH, stage gates.

## Last updated
2026-05-04 — Removed HUNT_LOCALITY (knob removed this session). Added new highway
slot candidates (HWY_P90, HWY_CHROMA_ANGLE, HWY_ACHROM_FRAC). Added halation
warm_bias feedback loop investigation. Added Pro-Mist scatter neutralisation question.
Updated CHROMA_STR to reflect new multiplier convention.
