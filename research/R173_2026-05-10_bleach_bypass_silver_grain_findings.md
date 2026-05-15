# R173 — BLEACH_BYPASS Silver Grain Coupling: Findings
**Date:** 2026-05-10
**Status:** Implemented

## Problem
Bleach bypass effect desaturates shadows but the grain model was unchanged — bypassed silver should produce additional retained-halide grain texture in shadow areas, which was absent.

## Solution
GrainSlot() accepts a silver_boost param. Blue-noise weight rises from base 0.30 to `0.30 + BLEACH_BYPASS × shadow_mask × 0.30`. Shadow mask `1 − smoothstep(0.0, 0.65, L_g)` matches ApplyBleachBypass rolloff exactly so the grain boost tracks the desaturation region.

## Implementation
silver_boost passed from DiffusionPS through GrainSlot(); shadow_mask computed from L_g at grain application site.

## Result
Bleach bypass scenes have grittier shadow grain — physically matches retained silver halide texture.
