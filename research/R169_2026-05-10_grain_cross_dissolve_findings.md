# R169 — Grain Temporal Cross-Dissolve: Findings
**Date:** 2026-05-10
**Status:** Implemented (reverted in R172)

## Problem
At >60fps, the discrete snap from grain slot N to slot N+1 was visible as a single-frame flash ("rain" — directional streaks from the slot boundary).

## Solution
Blend between `GrainSlot(slot0)` and `GrainSlot(slot0+1u)` using `frac(FRAME_TIMER/41.667)` as mix factor — continuous cross-dissolve between adjacent grain frames.

## Implementation
GrainSlot() helper extracted from ApplyFilmGrain; DiffusionPS lerps between two adjacent slots using the fractional timer position.

## Result
Snap eliminated at >60fps. Note: root cause was later found to be the luma_scale gradient from R167 (R174), not slot snap — cross-dissolve was treating the symptom. R172 reverted to single-slot for ALU savings.
