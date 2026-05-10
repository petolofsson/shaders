# R156 — Hue-Aware Inverse-Grade Expansion Bias: Findings
**Date:** 2026-05-10
**Status:** Implemented

## Problem
R90 adaptive inverse tonemap applied a uniform expansion slope across all hues. ACES and similar tonemappers compress warm hues (orange, red-orange) more than cool hues — uniform expansion over-corrects cool and under-corrects warm.

## Solution
`HueSlopeBias(hue)` 12-band lookup encoding ACES warm-hue excess compression: orange +0.20, teal/cyan −0.05. Applied as `slope_eff = clamp(slope × (1 + bias), 1.0, 2.2)`.

## Implementation
New `HueSlopeBias()` function in hue_bands.fxh, called in InverseGradePS to modulate per-pixel slope before chroma expansion.

## Result
Warm skin and orange tones recover more chroma; already-open cool tones not over-saturated.
