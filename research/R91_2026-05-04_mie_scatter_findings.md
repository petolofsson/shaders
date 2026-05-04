# R91 Findings — Mie Per-Channel Scatter Radius (2026-05-04)

## Status: Implemented

## What was built

`general/pro-mist/pro_mist.fx` — per-channel mip selection replaces single blended `diffused` float3.

## Change

Before: `float3 diffused = lerp(diffuse0, diffuse1, scene_softness * 0.35)` — all channels shared
one mip blend ratio.

After:
```hlsl
float  g_blend     = scene_softness * 0.35;
float3 scatter_src = float3(diffuse1.r, lerp(diffuse0.g, diffuse1.g, g_blend), diffuse0.b);
```

- Red → mip 1 (wider): longer wavelengths in Mie intermediate regime scatter at larger angles
- Blue → mip 0 (tighter): shorter wavelengths undergo more frequent scatter events, tighter PSF
- Green → scene_softness blend (unchanged visual character)

## Physical basis

Pro-Mist polymer particles (0.5–5µm) are in the Mie intermediate regime (x = πd/λ ≈ 5–30).
In this regime, forward-scatter half-angle increases with wavelength: larger λ → wider PSF,
smaller λ → tighter PSF. The current warm-bias weights (scatter_r/scatter_b from WarmBiasTex
and the `float3(scatter_r*1.05, 1.00, scatter_b*0.92)` final multiply) are unchanged — they
operate on the resulting scatter_delta independently.

## GPU cost

~3 ALU delta. No new taps. mip 0 and mip 1 were already fetched.

## Novelty

No other real-time Pro-Mist implementation models wavelength-dependent scatter radius.
All previous implementations use a luminance-based or single-channel blur weighted
uniformly across R/G/B. This is the spectral-physical distinction between a polymer
diffusion filter and a simple luminance blur.
