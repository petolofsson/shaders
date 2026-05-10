# R157 — Achromatic Fraction Gate for Inverse-Grade c_gate: Findings
**Date:** 2026-05-10
**Status:** Implemented

## Problem
In scenes dominated by grey/neutral pixels (fog, overcast, concrete), inverse-grade chroma expansion was applying full slope to the few coloured pixels present, over-saturating them.

## Solution
`c_gate` lerps 0.10→0.06 as HWY_ACHROM_FRAC rises 0.60→0.85. Colored pixels in achromatic scenes see a slightly reduced expansion ceiling, preventing over-pop without affecting normal mixed scenes.

## Implementation
Single lerp in InverseGradePS: `c_gate = lerp(0.10, 0.06, saturate((achrom - 0.60) / 0.25))` using `ReadHWY(HWY_ACHROM_FRAC)`.

## Result
Fog scenes and overcast environments no longer over-pop the few coloured objects present.
