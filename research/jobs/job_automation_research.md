# Job — Shader Automation Research

**Trigger ID:** trig_01Cm4QTimdKcVX5ZwoiSvhBg
**Schedule:** 0 2 * * * (2 AM UTC)
**Output:** `research/R{next}_{YYYY-MM-DD}_automation.md`

## Summary

Core scene-descriptive automation is complete (R41). This job now focuses on:
1. Adaptive base values — can HUNT_LOCALITY, INVERSE_STRENGTH base, HAL_STRENGTH,
   or ZONE_STRENGTH be auto-derived from scene statistics?
2. Knob count reduction — can rarely-changed knobs be eliminated or merged?
3. Automation robustness — does existing automation hold up post R88/R89/R90/R61?

## Candidates under investigation
- HUNT_LOCALITY (0.35) — adapt to zone_std?
- INVERSE_STRENGTH base (0.50) — adapt to IQR compression ratio?
- HAL_STRENGTH (0.00) — auto-enable from highlight mass?
- ZONE_STRENGTH (1.2) — inverse scale with zone_std?

## Locked artistic knobs (do not propose automating)
EXPOSURE, all CC wheels, CURVE_*_KNEE/TOE, ROT_*, PRINT_STOCK, MIST_STRENGTH,
PURKINJE_STRENGTH, VIEWING_SURROUND, LCA_STRENGTH, stage gates.

## Last updated
2026-05-04 — Complete rewrite. Removed stale candidates (CLARITY_STRENGTH,
DENSITY_STRENGTH, CHROMA_STRENGTH — none exist in creative_values.fx).
Updated HANDOFF.md reference. Refocused on R61/R90 adaptive calibration.
