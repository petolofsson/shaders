# R65 — Hunt-Effect Chroma Coupling for Shadow Lift

**Date:** 2026-05-02
**Status:** Proposed

## Problem

Shadow lift produces a gray/ashy look in lifted shadow regions. Root cause is structural:
the chroma-stable tonal block (R62) scales Oklab L by `r_tonal^(1/3)` while leaving
a/b unchanged. When L rises and C stays fixed, the chroma-to-lightness ratio falls —
lifted shadows become achromatic regardless of tuning.

## Hypothesis

The Hunt effect (Hunt 1952; CIECAM02) states perceived colorfulness is luminance-dependent.
At the sub-threshold luminances typical of shadow pixels before lift, chroma signals are
perceptually suppressed. Lifting L without lifting C reveals that suppression as gray.
Coupling C to the L lift — scaling a/b by `r_tonal^n` inside the existing tonal block —
should restore perceived colorfulness proportional to the luminance increase.

## Research questions

1. What exponent `n` does the CIECAM02/Hunt model predict for luminance-coupled chroma
   scaling to maintain perceptual colorfulness?
2. Does full coupling (n = 1/3, matching L) overboost chroma, or is a softer exponent
   (n ≈ 0.1–0.2) preferred?
3. Should coupling be gated to the shadow region only (lift_w > 0) or applied globally
   to the tonal block?
4. Is there precedent in color grading literature for chroma-coupled shadow lift?

## Proposed implementation sketch

Inside the existing chroma-stable tonal block (grade.fx ~line 322):

```hlsl
// after: lab_t.x = saturate(lab_t.x * exp2(log2(r_tonal) * (1.0/3.0)));
float ab_scale = exp2(log2(max(r_tonal, 1e-5)) * HUNT_N);  // HUNT_N ∈ [0.10, 0.33]
float shadow_w = smoothstep(0.30, 0.0, lab_t.x);            // only in shadow region
lab_t.y *= lerp(1.0, ab_scale, shadow_w);
lab_t.z *= lerp(1.0, ab_scale, shadow_w);
```

Zero GPU cost: two multiplies + one smoothstep inside existing Oklab block.
No new passes, no new textures.

## Success criterion

Lifted shadow regions retain perceivable hue character. Neutral (truly achromatic) pixels
remain neutral. No chroma bleed into specular highlights.
