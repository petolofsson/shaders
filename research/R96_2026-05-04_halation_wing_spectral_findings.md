# R96 Findings — Halation Wing Spectral Correction (2026-05-04)

## Status: Original framing incorrect — revised proposal

## Original framing (from proposal doc)

"Multi-scatter spectral broadening → pull wing toward luma by 25%."

## Why this is physically wrong

Web research confirms the real mechanism is the *opposite* of desaturation:

Anti-halation dyes absorb blue/green selectively on the return light path — blue is
nearly completely absorbed (~97%), green is heavily absorbed (~84% at 550nm based on
OD 0.80), red passes at ~50% (OD 0.30). Light that reaches the base and scatters back
is therefore strongly red-biased, not neutral/desaturated.

Pulling wing toward luma (neutral grey) would make it *less* physically correct.

## What R93B already captures

R93B (implemented) corrects the red:green blend ratio to 2:1 (0.20/0.10 base) from
the anti-halation OD data. This accounts for the *amount* of wing each channel uses.

## Revised framing: spectral warm-tilt on the wing source

R93B corrects how much wing. R96 should correct the *colour* of the wing — the RGB
values of `hal_wing = lf_mip2.rgb` are the scene colours blurred, not the scene colours
after anti-halation filtering. On the return scatter path, the wing light is further
filtered. A modest warm tilt on the wing source before blending is physically motivated:

```hlsl
float3 hal_wing_w = float3(hal_wing.r, hal_wing.g * 0.88, hal_wing.b * 0.75);
// use hal_wing_w in place of hal_wing in both lerp calls
```

Coefficients: green attenuated 12%, blue 25% — conservative fractions of the full
anti-halation OD ratio (which would give ~84% and ~97%). Conservative because R93B
already handles the larger part of the imbalance at the blend level.

## Risk

The gain vector `float3(1.2 * hal_gate_r, 0.45 * hal_gate_g, 0.0)` already aggressively
suppresses green (0.45). Stacking a 12% green reduction on the wing source on top of
this may over-suppress green halation on warm-coloured light sources. Needs visual
validation before shipping.

## Cost

~3 ALU (float3 multiply of hal_wing). 0 new taps.

## Recommendation

Implement after R95 is stable. Test on a scene with both neutral white and coloured
light sources. If green halation disappears on warm lights, back off the `0.88`
coefficient toward `0.94`.
