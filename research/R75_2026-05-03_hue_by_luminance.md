# R75 — Hue-by-Luminance Rotation

**Date:** 2026-05-03
**Status:** Proposed

## Problem

`r21_delta` is hue-dependent but luminance-agnostic — a red shadow and a red highlight
receive the same hue rotation. Film print stock dye response is tonally non-uniform:

- Shadows: thin dye layer, transparency to base — slight blue-green cast
- Highlights: dye at low density — warm bias (orange/amber lean)

This is distinct from R19's 3-way CC which applies uniform RGB shifts per zone.
What's missing is a hue *rotation* (not a tint) that varies continuously across the
luminance range.

## Research task

1. Obtain Kodak 2383 spectral dye sensitivity data at multiple density levels (D-min,
   D-0.5, D-1.0, D-max). Convert density-domain spectral shifts to Oklab hue rotation.
2. Derive the per-tonal-zone hue rotation magnitude in Oklab hue-normalised units.
3. Determine which hue bands are most affected (typically red/orange in highlights,
   cyan/blue in shadows) and whether the rotation is uniform across hue or band-selective.

## Likely implementation

An additive luminance-weighted delta applied before h_out is finalised:
```hlsl
float lum_hue_rot = lerp(-0.003, +0.004, lab.x);  // shadow→highlight, sign TBD
r21_delta += lum_hue_rot;  // or band-weighted variant
float h_out = frac(h_perc + r21_delta * 0.10);
```
Magnitudes TBD from research.

## GPU cost

~3 ALU. No new taps, no new knobs.
