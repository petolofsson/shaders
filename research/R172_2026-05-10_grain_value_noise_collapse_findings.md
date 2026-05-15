# R172 — GrainValueNoise Collapse — 3-Channel to 1-Channel: Findings
**Date:** 2026-05-10
**Status:** Implemented

## Problem
R166 introduced 3× per-channel GrainValueNoise calls — 30 pcg3d hash calls per pixel. Performance overhead was significant given the GPU budget constraint.

## Solution
Collapsed to 1× GrainValueNoise call with per-channel luma_scale offset (R×1.00/G×0.90/B×1.15). Hash calls reduced 30→14 per pixel (~53% grain ALU reduction). Per-channel sizing preserved via luma_scale multiplier as additive seed variation.

## Implementation
Single GrainValueNoise() call; channel offsets applied as additive seed variation rather than separate call chains.

## Result
No perceptual change. ~53% grain ALU reduction.
