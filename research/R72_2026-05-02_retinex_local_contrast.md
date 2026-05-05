# R72 — Reflectance-Based Local Contrast

**Date:** 2026-05-02
**Status:** Proposed

## Problem

R30 (wavelet clarity) was removed because illuminant bleed caused bloom — the
illumination low-frequency component was sharpened alongside the reflectance
high-frequency signal. After removal, the pipeline has no local contrast or detail
enhancement. Fine surface detail (geometry, lettering, material surface variation)
appears softer than a graded reference; Pro-Mist further reduces acuity.

## Solution

`log_R = log2(luma / illum_s0)` is already computed in Stage 2 (line 318). It is the
Retinex reflectance estimate: the per-pixel log-ratio to the local spatial average.
Illumination is divided out — the signal is illumination-free by construction. This
resolves the exact root cause that killed R30.

Adding a fraction of `log_R` back to `new_luma` after Retinex normalisation is an
illumination-decoupled unsharp mask:

```hlsl
float clarity_gate = smoothstep(0.06, 0.25, new_luma);
new_luma = saturate(new_luma + 0.10 * log_R * clarity_gate * (1.0 - new_luma));
```

- `clarity_gate`: zero below luma 0.06 (deep shadow fully protected), full above 0.25
- `(1.0 - new_luma)`: natural highlight rolloff — no blowout near white
- Coefficient 0.10: empirical start point — should be tuned visually

## Why this won't bleed

R30 sharpened `luma - illum`, which includes edge halos from the illumination component.
`log_R` = `log2(luma) - log2(illum_s0)`. `illum_s0` is the mip-1 low-frequency average —
subtracting it in log space removes DC + low-frequency illumination variation completely.
Sharpening the residual amplifies only surface reflectance contrast.

## GPU cost

1 smoothstep + 3 ALU ops. No new taps (log_R already computed). No new knobs.

## Success criterion

Edge definition improves vs. unprocessed — lettering, geometry silhouettes, material
boundaries are crisper. No blooming around light sources or illumination boundaries.
Pro-Mist + R72 combined should match or exceed the perceived sharpness of the old
pre-R30-removal state.
