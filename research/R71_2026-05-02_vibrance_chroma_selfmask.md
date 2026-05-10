# R71 — Vibrance / Chroma Self-Masking

**Date:** 2026-05-02
**Status:** Proposed

## Problem

`chroma_str` drives a `PivotedSCurve` lift per band. The lift is proportional to current C
but contains no self-masking: a pixel at C=0.04 (nearly achromatic) and a pixel at C=0.20
(near sRGB primary) in the same hue band receive the same lift multiplier. In scenes that
mix dull naturals (stone, skin, shadow) with saturated primaries (UI, energy effects,
specular), the result is simultaneous over-saturation of primaries and under-saturation
of naturals — both in the same frame.

Every professional color tool (Resolve "Saturation" curve / "Color Boost", Lightroom
"Vibrance") implements self-masking as the standard chroma enhancement mode precisely
to avoid this artifact.

## Solution

Attenuate the lift delta by input saturation. Let `delta_C = lifted_C - C`. Apply:

```hlsl
float vib_mask = saturate(1.0 - C / 0.22);
float final_C  = C + delta_C * vib_mask;
```

`vib_mask`:
- C = 0.00 (achromatic): 1.0 — full lift
- C = 0.11 (muted):      0.5 — half lift
- C = 0.22 (saturated):  0.0 — no lift

`0.22` ceiling: sRGB primary C in Oklab ranges ~0.26–0.30. Setting the ceiling at 0.22
means already-vivid colors receive zero additional lift; everything below scales linearly.

## GPU cost

2 ALU ops (div, saturate). No new taps, no new knobs.

## Success criterion

Muted naturals (skin, stone, shadow, foliage) lift visibly. Already-saturated primaries
(neon UI, energy effects) are unchanged. No over-saturation artifacts in mixed-content
scenes.
