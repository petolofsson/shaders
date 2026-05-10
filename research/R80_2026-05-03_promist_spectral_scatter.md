# R80 — Pro-Mist Spectral Scatter Model

**Date:** 2026-05-03
**Status:** Proposed

## Problem

The Pro-Mist implementation (R55) uses luminance-neutral mip blending with IQR-adaptive
strength. Three physical properties of real diffusion filters are not modelled:

1. **Wavelength-dependent scatter.** Mie/Rayleigh scattering from polymer particles
   produces blue-biased scatter — the bloom halo is cooler-coloured than a luminance
   scatter implies.

2. **Scene-key insensitivity.** The scatter blend is constant for a given IQR. But
   mist visually dominates in low-luminance conditions and is less visible in high-key
   exteriors for the same absolute filter strength.

3. **Aperture-scatter coupling.** Real optical diffusion filters interact with lens
   aperture — wider aperture converges rays before the filter, reducing effective
   diffusion. `EXPOSURE` correlates loosely with aperture (high EXPOSURE = dim scene =
   wider aperture equivalent).

## Research tasks

### R80A — Spectral scatter
1. Find Mie scattering approximation for polymer particles (~1–10 µm diameter).
   Derive the wavelength-dependent scatter ratio R:G:B.
2. Find published MTF measurements for Pro-Mist or equivalent diffusion filters
   (Lindgren 2019 or equivalent). Determine if the spectral MTF roll-off is measurable
   or if it's below perceptual threshold at typical strength values.

### R80B — Scene-key adaptive strength
Derive a scaling factor from `zone_log_key` that brightens mist in dark scenes and
reduces it in bright scenes. Target: mist strength variation of ~±30% across the
realistic zone_log_key range (0.02–0.40).

Candidate formula: `mist_scale = pow(zone_log_key, -0.3)` (inverted — dark scenes
boost mist). Verify range at extremes.

### R80C — Aperture proxy
Derive the relationship between EXPOSURE value and effective aperture scatter reduction.
EXPOSURE is a power applied to linear input: `pow(col, EXPOSURE)`. At EXPOSURE=1.0
(neutral), full scatter. At EXPOSURE=0.7 (boosting input = darker scene = wider
aperture), scatter slightly wider. At EXPOSURE=1.2 (darkening input = bright scene =
narrower aperture), scatter slightly tighter.

Determine if this relationship is perceptually meaningful or too small to warrant
implementation.

## Likely implementation

```hlsl
// R80A: spectral scatter (blue-biased)
// mip blend uses slightly different weights per channel

// R80B: scene-key adaptive
float mist_key_scale = pow(max(zone_log_key, 0.02), -0.30);
mist_str *= clamp(mist_key_scale, 0.7, 1.4);

// R80C: aperture proxy
float mist_ap_scale = lerp(1.1, 0.9, saturate((EXPOSURE - 0.8) / 0.6));
mist_str *= mist_ap_scale;
```

## GPU cost

R80A: ~2 ALU. R80B: 1 pow + 1 clamp. R80C: 1 lerp. No new taps.
