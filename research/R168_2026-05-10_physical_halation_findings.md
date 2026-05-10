# R168 — Physical Halation Rewrite — Dual-Scale DoG PSF: Findings
**Date:** 2026-05-10
**Status:** Implemented

## Problem
Previous halation used a single-scale blur with a uniform warm tint. Real film halation has two physical components: a tight ring (rem-jet AH layer attenuation) and a broad tail (base scatter). These have different spectral profiles and the single-scale model could not reproduce both.

## Solution
Two-scale DoG PSF using existing LowFreqMip1 (tight ring = lf_mip1 − lin) and LowFreqMip2 (broad ring = lf_mip2 − lf_mip1). AH layer attenuates tight ring ~40%. Spectral weights: tight `col=(0.63, 0.27×g, 0.02×b)`, broad `col=(1.05, 0.45×g, 0.03×b)`. Lorentzian crossover `tight_luma / (tight_luma + HAL_GAMMA)` per ring.

## Implementation
ApplyHalation in grade.fx reads LowFreqMip1Samp and LowFreqMip2Samp; replaces previous single-scale halation path.

## Result
Physically correct orange/amber fringe around specular sources, inner ring spectrally balanced, outer tail orange-dominant.
