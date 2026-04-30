# R29 — Retinex Illumination/Reflectance Separation
**Date:** 2026-04-30
**Type:** Proposal
**ROI:** Medium-high — principled replacement for R18, multi-scale data already free

---

## Problem

R18 (zone luminance normalization, `grade.fx:283-286`) pulls each zone's median toward
the global log-average key:

```hlsl
float r18_str  = lerp(10.0, 30.0, smoothstep(0.08, 0.25, zone_std)) / 100.0 * 0.4;
float r18_norm = pow(max(zone_log_key, 0.001) / max(zone_median, 0.001), r18_str);
new_luma = saturate(new_luma * r18_norm);
```

The correction is spatially coarse — zone_median has 4×4 = 16 distinct values across the
frame. A pixel at the centre of a dark zone gets the same normalization as one at its
edge, even if the edge borders a bright zone. The result can produce visible zone
boundary banding in scenes with complex lighting (multiple sources, indoor/outdoor split).

---

## Retinex theory

Land (1977): an observed image I(x,y) = R(x,y) × L(x,y)
where R = reflectance (what we want — scene content) and L = illumination (what we want
to remove — the lighting condition).

In log domain: `log(I) = log(R) + log(L)`

Estimate L as a spatial blur: `L̂ ≈ blur(I)`

Therefore reflectance: `log(R) = log(I) - log(L̂) = log(I / L̂)`

Multi-Scale Retinex (MSR) combines estimates at multiple spatial scales:
```
log(R) = Σ_s w_s * log(I(x,y) / blur_s(I(x,y)))
```

The per-pixel, spatially smooth illumination estimate is strictly better than the 16-zone
step function R18 uses — same goal, finer spatial resolution, no zone boundaries.

---

## The free lunch

`corrective.fx` already computes `CreativeLowFreqTex` (BUFFER_WIDTH/8 × BUFFER_HEIGHT/8,
RGBA16F, **MipLevels=3**). Luma is stored in `.a`. The three mip levels are:

| Mip | Approx. resolution | Spatial scale |
|-----|--------------------|---------------|
| 0   | BW/8 × BH/8       | Fine (~120px blur at 1080p) |
| 1   | BW/16 × BH/16     | Medium |
| 2   | BW/32 × BH/32     | Coarse (~480px blur at 1080p) |

These are already computed, already on the GPU, already read by the clarity stage
(`grade.fx:288-290`). Using them as Retinex illumination estimates costs **zero extra
passes and zero extra taps** beyond what clarity already reads.

---

## Proposed replacement for R18

```hlsl
// Multi-Scale Retinex — illumination/reflectance separation
// Replaces R18 zone-level normalization with pixel-local estimate
float illum_s0 = tex2D(CreativeLowFreqSamp, uv).a;                     // fine
float illum_s1 = tex2Dlod(CreativeLowFreqSamp, float4(uv, 0, 1)).a;    // medium
float illum_s2 = tex2Dlod(CreativeLowFreqSamp, float4(uv, 0, 2)).a;    // coarse

float log_R = (log(max(new_luma, 0.001) / max(illum_s0, 0.001))
             + log(max(new_luma, 0.001) / max(illum_s1, 0.001))
             + log(max(new_luma, 0.001) / max(illum_s2, 0.001))) / 3.0;

// Restore to display scale: target the global log key
float retinex_luma = saturate(exp(log_R + log(max(zone_log_key, 0.001))));
new_luma = lerp(new_luma, retinex_luma, r18_str / 0.12);
```

Or more conservatively — blend Retinex against R18 at a controlled mix ratio,
preserving the zone_std-adaptive strength that R18 already uses.

---

## Advantages over R18

| | R18 (current) | Retinex (proposed) |
|--|---------------|-------------------|
| Spatial resolution | 4×4 zones (16 values) | Per-pixel (BW/8 × BH/8) |
| Zone boundary artifacts | Possible | None — spatially smooth |
| Multi-light-source scenes | Coarse | Correct per-region |
| GPU cost | 1 texture read | 3 texture reads (mips already cached) |
| Extra passes | 0 | 0 |

---

## Risks

**Halo risk:** if the illumination estimate changes faster than the image content
(high-contrast edges at the 1/8-res scale), Retinex produces halos. The 1/8-res blur is
smooth enough that severe halos are unlikely, but this must be verified visually on
Arc Raiders scenes with hard light/shadow boundaries.

**Over-flattening:** Retinex removes illumination variation — in scenes where the
lighting gradient is part of the artistic intent (sunset, volumetric shafts), full
Retinex may over-normalize. The blend with R18_str and `TONAL_STRENGTH` provides a
control handle.

**log(0):** requires careful guarding on dark pixels. All `log()` calls must clamp
input to `max(x, 0.001)`.

---

## Research questions for web search

1. What weights (w_s) for the three Retinex scales give the best perceptual result?
   Published MSR implementations typically use equal weights — is there a principled
   alternative for display-referred SDR images?
2. What is the correct output normalization for MSR on SDR content? Standard MSRCR uses
   a gain/offset per-channel — does that translate to a luma-only implementation?
3. Are there 2023–2026 papers applying Retinex to real-time rendering or game HDR/SDR
   tone mapping? Any GPU-optimized MSR implementations?
4. Halo mitigation: has bilateral-weighted Retinex been applied in real-time contexts?

---

## Success criteria

- R18 block (`grade.fx:283-286`) replaced with MSR using mip levels 0/1/2
- No new textures, no new passes, no new corrective.fx changes
- Visually: zone boundary banding eliminated in complex lighting scenes
- Visually: no halos on hard shadow edges in Arc Raiders test scenes
- r18_str (zone_std-adaptive) preserved as the strength control
- `log` guards on all division and log inputs
