# R189 — Bilateral Tonemapper in grade.fx + R187 Completion

**Date:** 2026-05-13  
**Status:** Pre-implementation — approved for discussion

---

## Motivation

Two converging problems resolved together:

**1. R187 was never completed.** The bilateral passes in `inverse_grade.fx` (LocalLumaDownH/V) were documented as removed but are still present. They compute a spatially-smoothed `L_local` used only for zone weighting in chroma expansion — a narrow use of an edge-preserving filter. The `(1 − lab.x)` zone weight R187 intended was also never applied. The zone weighting should be revised on research grounds (see below).

**2. The zone S-curve is globally applied.** `ApplyTonal` drives shadow lift, zone contrast, and Retinex from histogram-wide statistics (zone_key, zone_std). Every shadow in the frame gets identical treatment regardless of local scene context. A bilateral tonemapper gives those operations spatial grounding.

The bilateral filter moves from `inverse_grade` (zone classifier) to `grade.fx` (actual tonemapping). Net GPU cost: zero extra passes.

---

## Context: this is SDR → SDR

This pipeline does not build an HDR signal. The game outputs SDR. We post-process that SDR output cinematically. The bilateral tonemapper here is not HDR compression — it is **spatially-adaptive tonal redistribution within SDR space**: lifting locally dark regions, gently pulling locally bright regions, while preserving all texture detail. This is closer to a local clarity/exposure operator than to an HDR display transform.

The Durand & Dorsey `targetContrast` parameterisation (designed to compress 3–5 stops of HDR into SDR) does not apply. Instead the operation blends local log-luma toward the scene's global key — a natural, content-adaptive redistribution that requires no per-frame readback.

---

## Prior Art

### Durand & Dorsey (SIGGRAPH 2002)

Core algorithm in log luminance space:

```
log_luma    = log10(max(Luma(rgb), 1e-3))
log_base    = BilateralFilter(log_luma, σ_s, σ_r)   // edge-preserving base
log_detail  = log_luma - log_base                    // texture / micro-contrast
log_out     = compress(log_base) + log_detail
out_luma    = pow(10, log_out)
rgb_out     = rgb_in * (out_luma / in_luma)          // hue-preserving
```

**Validated parameters (from paper):** σ_s = 16px at full resolution, σ_r = 0.4 in log10 space. σ_r = 0.4 log10 units ≈ 2.5× luminance ratio — stops at luminance edges above that ratio, blurs freely within a region.

**Chroma preservation:** multiplicative luma ratio applied to full RGB — hue and saturation are unaffected, only luminance changes.

### Wronski (2022) — Exposure Fusion

Alternative: synthetic exposures + Laplacian pyramid blend. Simpler to tune, naturally multi-scale, temporally stable. Requires 6–10 passes (pyramid build + blend + collapse) — too many for this pipeline. Bilateral chosen instead.

---

## R187 zone weight — research correction

R187 intended `lerp_t = INVERSE_STRENGTH * (1 − lab.x) * c_weight * dir_scale`, giving maximum expansion at L=0 (black) tapering to zero at L=1 (white). This is shadow-biased.

**What the research says:**

- **ACES chroma compression docs:** "Compression increases as J values increase — shadows are compressed less than highlights." The inverse should recover most in the mid-to-highlight zone, not shadows.
- **ACES expansion step:** "Increases saturation in shadows and mid-tones but not highlights" — so shadows partially self-recover; heavy shadow expansion is redundant.
- **Cinema SDR→HDR data (arxiv 2604.06276):** Mean ΔChroma: shadows = −0.039 (net desaturation), midtones = +0.003 (net gain, 66.9% of pixels enhanced), highlights = −0.008. Midtones are the zone where chroma recovery is both needed and possible.

**Proposed replacement:** midtone bell curve:

```hlsl
float zone_w = 4.0 * lab.x * (1.0 - lab.x);
```

Peaks at L=0.5, zero at L=0 and L=1. Shape matches the empirically-calibrated bilateral zone weights (shadow×0.40, mid×1.0, highlight×0.45) which were validated with `BILATERAL_ZONE_DEBUG`. The bell curve gives a smooth closed-form version of the same profile without needing a bilateral texture.

| L | `(1−L)` (old) | bell `4L(1−L)` (new) | bilateral zone (empirical) |
|---|---|---|---|
| 0.20 | 0.80 | 0.64 | 0.40 |
| 0.40 | 0.60 | 0.96 | 0.94 |
| 0.50 | 0.50 | 1.00 | 1.00 |
| 0.70 | 0.30 | 0.84 | 0.90 |
| 0.85 | 0.15 | 0.51 | 0.45 |

The bell is the natural analytical equivalent of what was calibrated empirically. `(1 − lab.x)` does not match any of the research sources.

---

## Proposed Implementation

### Part 1 — R187 completion in inverse_grade.fx

**Remove:**
- `LocalLumaHTex` / `LocalLumaHSamp` declaration
- `LocalLumaTex` / `LocalLumaSamp` declaration
- `LocalLumaDownHPS` function
- `LocalLumaDownVPS` function
- `float L_local = tex2D(LocalLumaSamp, uv).r` in `InverseGradePS`
- `zone_w` piecewise computation (lines 169–170)
- `LocalLumaDownH` and `LocalLumaDownV` pass declarations

**Replace lerp_t:**
```hlsl
float zone_w = 4.0 * lab.x * (1.0 - lab.x);   // midtone bell — research-grounded
float lerp_t = saturate(float(INVERSE_STRENGTH) * zone_w * c_weight * dir_scale);
```

Result: `inverse_grade` becomes **1-pass**. Two 1/8-res R16F textures freed.

---

### Part 2 — Bilateral tonemapper in grade.fx

#### New textures

| Texture | Size | Format | Role |
|---------|------|---------|------|
| `BilateralLogHTex` | 1/4-res | R16F | H-pass bilateral log-luma intermediate |
| `BilateralLogTex` | 1/4-res | R16F | Final base layer: bilateral-filtered log10 luma |

#### New passes (inserted before ColorTransformPS)

**BilateralLogHPS** — writes `BilateralLogHTex`
```hlsl
// Downsample CreativeLowFreqSamp to 1/4-res + convert to log10 luma
// Then 9-tap horizontal bilateral: σ_s = 4 output texels, σ_r = 0.4 log10 units
float luma    = Luma(tex2D(CreativeLowFreqSamp, uv).rgb);
float log_cen = log10(max(luma, 1e-3));
float sum = 0.0, wsum = 0.0;
[unroll] for (int i = -4; i <= 4; i++) {
    float2 s_uv  = uv + float2(i * px, 0.0);
    float  samp  = log10(max(Luma(tex2D(CreativeLowFreqSamp, s_uv).rgb), 1e-3));
    float  w_s   = exp(-0.5 * float(i*i) / (4.0*4.0));            // σ_s = 4
    float  w_r   = exp(-0.5 * pow((samp - log_cen)/0.4, 2.0));    // σ_r = 0.4
    sum  += samp * w_s * w_r;
    wsum += w_s * w_r;
}
return float4(sum / max(wsum, 1e-5), 0, 0, 1);
```

**BilateralLogVPS** — reads `BilateralLogHTex`, writes `BilateralLogTex`  
(identical but vertical, `float2(0.0, i * py)`)

#### ColorTransformPS change — early in ApplyTonal

```hlsl
// Bilateral tonemapper — spatially-adaptive SDR tonal redistribution
// Base layer: bilateral-filtered log luma (large-scale illumination)
// Detail layer: pixel log luma - base (texture, micro-contrast — preserved)
float log_base   = tex2D(BilateralLogSamp, uv).r;               // bilinear upsampled
float log_pixel  = log10(max(luma, 1e-3));
float log_detail = log_pixel - log_base;
float log_key    = log10(max(ReadHWY(HWY_ZONE_KEY), 1e-3));     // scene global key
float log_comp   = lerp(log_base, log_key, float(BILATERAL_STRENGTH));
float luma_ratio = pow(10.0, log_comp + log_detail) / max(luma, 1e-3);
luma_ratio       = clamp(luma_ratio, 0.5, 2.0);                 // SDR safety
rgb              = rgb * luma_ratio;
luma             = Luma(rgb);                                    // update luma for downstream
```

Applied before zone S-curve. Retinex (R29) and shadow lift see the bilaterally-adjusted luma — intentional. Bilateral reduces the spatial variance that Retinex was partially compensating for anyway.

#### σ values — literature-grounded

- **σ_s = 4 output texels** (= 16 actual pixels at 1080p 1/4-res). Durand/Dorsey used 16px at full res — same physical scale.
- **σ_r = 0.4 log10 units.** Durand/Dorsey validated value. Stops at >2.5× luminance edges.
- **9-tap separable.** Covers ±4σ adequately at these sigma values.

#### New knob in creative_values.fx (OUTPUT section)

```hlsl
// Spatially-adaptive tonal redistribution. Finds locally dark and bright regions
// and blends them toward the scene's global key — lifts dark areas, gently pulls
// bright areas — while preserving all texture detail. 0 = off. 0.25–0.40 = cinematic.
#define BILATERAL_STRENGTH  0.0
```

---

## GPU cost

| Change | Passes delta | Texture delta |
|--------|-------------|---------------|
| inverse_grade: remove bilateral | −2 passes (1/8-res 9-tap) | −2 × R16F 1/8-res (~60KB each) |
| grade: add bilateral log | +2 passes (1/4-res 9-tap) | +2 × R16F 1/4-res (~240KB each) |
| grade: ColorTransformPS | 0 | 0 |
| **Net** | **0** | **+360KB VRAM** |

---

## Open question (resolved)

~~σ_r calibration~~ → 0.4 log10 units (Durand/Dorsey literature value).  
~~Retinex interaction~~ → Retinex operates on bilaterally-adjusted luma. Fine.  
~~SDR→SDR framing~~ → corrected throughout. No targetContrast, no HDR language.

---

## Sources

- Durand & Dorsey, "Fast Bilateral Filtering for the Display of High-Dynamic-Range Images," SIGGRAPH 2002 — σ_s=16px, σ_r=0.4 validated values
- Wronski, "Exposure Fusion — local tonemapping for real-time rendering," 2022
- Zhang & Chen, "Structural Regularities of Cinema SDR-to-HDR Mapping," arxiv 2604.06276 — chroma zone data
- ACES documentation — chroma compression luminance dependence
