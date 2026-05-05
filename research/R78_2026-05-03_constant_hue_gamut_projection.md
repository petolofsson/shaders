# R78 — Constant-Hue Gamut Projection

**Date:** 2026-05-03
**Status:** Proposed

## Problem

The `gclip` safety net projects out-of-gamut pixels toward `L_grey`:
```hlsl
float gclip = saturate((1.0 - L_grey) / max(rmax - L_grey, 0.001));
chroma_rgb  = L_grey + gclip * (chroma_rgb - L_grey);
```

Projection toward `L_grey` (achromatic) does not follow constant-hue lines in Oklab.
As `gclip < 1`, the ab components are scaled uniformly but the RGB reconstruction
shifts hue because sRGB primaries are not uniformly distributed in Oklab. Visible
as a magenta→gray or cyan→white hue shift on over-range chromatic highlights.

R68B (pre-knee) reduces how often gclip fires but it remains the safety net.

## Research task

Find a closed-form or low-iteration constant-hue projection:
given `float3(density_L, f_oka, f_okb)` where `OklabToRGB` returns rmax > 1,
find the largest scalar `s ≤ 1` such that `max(OklabToRGB(density_L, f_oka*s, f_okb*s)) = 1`.

This preserves the Oklab ab direction (hue angle) exactly while compressing chroma.

### Approach options to evaluate

1. **Direct headroom-based approximation**: `headroom` already approximates proximity
   to the sRGB boundary. Derive `s` as a function of `headroom` and `C` analytically.

2. **2-iteration bisection**: start at s=gclip (current value), test OklabToRGB,
   refine once. Two extra OklabToRGB calls.

3. **Linear-in-C approximation**: in Oklab, the gamut boundary in any constant-L,
   constant-hue slice is approximately linear in C. Use the ratio `C_boundary / C`
   derived from `headroom` and the current `rgb_probe`.

Research: derive which approximation is most accurate vs. least GPU cost. The existing
`rgb_probe` call is already made for density computation — can be reused.

## GPU cost

Target: same or fewer ALU than current gclip block. No new texture taps.
