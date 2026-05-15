# R174 — Grain Rain Artifact Root Cause and Fix: Findings
**Date:** 2026-05-10
**Status:** Implemented

## Problem
Diagonal streaks ("rain") visible during camera movement. Initially attributed to grain slot snap, leading to R169 cross-dissolve. Cross-dissolve helped slightly but did not eliminate the artifact.

## Solution
Root cause: `luma_scale = lerp(2.5, 1.5, L_g)` in GrainValueNoise created smooth spatial variation in grain cell size. During camera movement this gradient read as directed motion — grain cells appeared to stream diagonally. Fix: constant `luma_scale = 2.5`. Single 24fps slot snap. Restored 3× per-channel GrainValueNoise with physically correct Kodak 2383 dye sizing: cyan(R)×1.15, magenta(G)×1.00, yellow(B)×0.85.

## Implementation
luma_scale set to constant 2.5 in GrainValueNoise(); slot = `uint(FRAME_TIMER / 41.667)` (single slot, no cross-dissolve).

## Result
Rain artifact eliminated. 14 hash calls total. Per-channel dye sizing physically correct.
