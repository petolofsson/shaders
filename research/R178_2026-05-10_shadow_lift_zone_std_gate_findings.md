# R178 — Shadow Lift zone_std Gate for Intentional Dark Interiors: Findings
**Date:** 2026-05-10
**Status:** Implemented

## Problem
Ceiling fan scene: bright window + dark room. Shadow lift was firing aggressively, lifting the dark interior as underexposure. But this was intentional atmospheric lighting — zone_std was high (large intra-zone variance = intentional contrast), not low (flat underexposure).

## Solution
`_std_suppress = smoothstep(0.05, 0.13, zone_std)`. shadow_lift_str multiplied by `(1 − _std_suppress)`. At zone_std ≥ 0.13, lift is fully off. Flat underexposed scenes (low zone_std) are unchanged.

## Implementation
grade.fx BuildSceneCtx; reads HWY_ZONE_STD from highway and applies suppression before writing shadow_lift_str to SceneCtx.

## Result
Intentional dark interiors no longer lifted. Underexposed flat scenes still corrected.
