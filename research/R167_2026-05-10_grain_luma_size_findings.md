# R167 — Grain Luma-Dependent Size: Findings
**Date:** 2026-05-10
**Status:** Superseded by R172

## Problem
R166 had uniform grain size across luma. Real film: shadow crystals are larger than highlight crystals (smaller exposed area = larger effective grain in shadows).

## Solution
`luma_scale = lerp(2.5, 1.5, L_g)` — shadows get 2.5× effective size, highlights 1.5×. Per-channel dye sizing: R×1.00, G×0.90, B×1.15.

## Implementation
luma_scale computed from L_g per pixel inside GrainValueNoise(); per-channel multipliers applied to sample offsets.

## Result
Root cause of R174 rain artifact — smooth spatial gradient in luma_scale read as directional motion during camera movement. Fixed in R174 by removing luma-dependence.
