# R85 — Inter-Channel Dye Masking
**2026-05-03 | Stage 1 novel +5%**

## Problem

R81C (Beer-Lambert) models intra-channel dye absorption: dominant-channel dye attenuates
its own channel. In real colour negative film, the three dye layers have spectral overlaps:
the cyan dye (red-record layer) absorbs slightly in green; the magenta dye (green-record
layer) absorbs slightly in blue. These inter-channel terms produce the characteristic warm
shadow desaturation and cross-channel compression that makes film look different from digital.

No other real-time post-process implementation models this. The Kodak 2383 datasheet includes
spectral dye density curves that can be used to derive the coupling coefficients.

## Targets

Stage 1 novel: 70% → 75% (after R84)

## Research questions

1. What are the inter-channel absorption fractions for Kodak 2383 at operating density
   (~0.5–1.5D)? Specifically: cyan→green and magenta→blue bleed fractions?
2. Are yellow→red or yellow→green bleeds significant enough to model?
3. Do these terms interact constructively or destructively with the existing R81C
   Beer-Lambert dominant-channel attenuation?
4. What saturation/luminance gate (if any) is needed to prevent the cross-channel terms
   from firing on low-chroma pixels where dom_mask approaches 0?

## Proposed implementation

Stage 1, after R81C Beer-Lambert block:

```hlsl
// inter-channel dye coupling from Kodak 2383 spectral dye density curves
// cyan dye (red-record) bleeds into green; magenta dye (green-record) bleeds into blue
float3 dye_cross = float3(
    0.0,
    dom_mask.r * sat_proxy * ramp * 0.018,   // cyan → green
    dom_mask.g * sat_proxy * ramp * 0.022    // magenta → blue
);
lin = saturate(lin * (1.0 - dye_cross));
```

Coefficients (0.018, 0.022) are initial estimates from spectral data — to be refined.

GPU cost: ~6 MAD. No new taps. No new knobs.

## Constraints

- Inter-channel terms must be strictly smaller than intra-channel terms (dominant channel
  must remain dominant) — validate this numerically
- No gate on the cross-channel term — must be self-limiting via `dom_mask * sat_proxy`
  approaching 0 on low-chroma or low-luminance pixels
- No visible seaming on skin tones (critical — test on Arc Raiders character close-ups)
