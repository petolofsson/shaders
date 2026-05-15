# R166 — Grain Size Variety via 3-Octave Value Noise: Findings
**Date:** 2026-05-10
**Status:** Superseded by R172

## Problem
Single-tap pcg3d hash grain looked too uniform spatially — no coarse/fine variation that real film grain has from crystal size distribution.

## Solution
Three-octave value noise: 4px coarse, 2px mid, 1px fine, mixed 0.50:0.30:0.20. New GrainValueNoise() helper introduced in grade.fx.

## Implementation
GrainValueNoise() with 3 octaves; mix weights 0.50/0.30/0.20 for coarse/mid/fine layers.

## Result
More texture variety, but introduced luma-dependent grain size in subsequent R167 which caused directional "rain" artifact. Superseded by R172.
