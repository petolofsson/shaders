# R179 — Chroma Lift Dead Zones for Tertiary Hues: Findings
**Date:** 2026-05-10
**Status:** Implemented

## Problem
GetBandCenter maps only 6 primaries/secondaries (RED, YELLOW, GREEN, CYAN, BLUE, MAGENTA) with ±0.08 weight width. Tertiary hues (ORANGE at 0.181, AMBER, TEAL, AZURE, VIOLET, ROSE) fell in zero-weight gaps: ORANGE is 0.098 from RED and 0.124 from YELLOW — both > 0.08. Result: total_w≈0 → lifted_C=C → no lift applied to half the hue wheel.

## Solution
Widen pivot weight to ±0.14 inside the chroma lift loop only. No corrective.fx changes — ChromaHistory still tracks 6 bands. All 12 hue regions now interpolate from nearest tracked bands.

## Implementation
grade.fx ApplyChroma loop: `wt = saturate(1 − d_h / 0.14)` (was `/0.08` via HB_BAND_WIDTH).

## Result
Confirmed working. Orange, amber, teal etc. now receive proportional chroma lift.
