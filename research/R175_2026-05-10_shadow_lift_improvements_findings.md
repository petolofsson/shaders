# R175 — Shadow Lift Gate and Bell Improvements: Findings
**Date:** 2026-05-10
**Status:** Implemented

## Problem
Shadow lift was using p25 alone as the scene gate. Bright outdoor scenes with correct deep shadows (p25 low but intentionally so) were being lifted unnecessarily. Pixel bell upper bound at 0.20 was not reaching into lower midtones where lift is most useful.

## Solution
Gate switched from p25 to `(p25 + mode) × 0.5` — mode prevents over-lifting scenes where histogram peak is high (bright outdoor). Bell extended from smoothstep(0.20,0,L) to smoothstep(0.27,0,L), then tuned to 0.23 to reduce lifting of dark particle/schmutz detail.

## Implementation
SceneCtx shadow_lift_str calculation in BuildSceneCtx in grade.fx; mode read from HWY_MODE (x=206).

## Result
Shadow lift no longer fires in correctly-exposed outdoor scenes. Dark detail retains depth.
