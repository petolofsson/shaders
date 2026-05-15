# R190 — Guided Filter Base Layer (replaces bilateral in R189)

**Date:** 2026-05-14
**Status:** Implementation ready — pending review and test

---

## Motivation

R189 uses a bilateral log-luma filter (2 separable passes, σ_s=2 texels, σ_r=0.4) to build a
base layer for the bilateral tonemapper and clarity effect. Two problems:

1. **Fixed range kernel σ_r = 0.4** is a global constant tuned for average scenes. In dark scenes
   log-domain variance is compressed; in high-contrast scenes it is wide. A single σ_r cannot be
   correct for both — it either over-smooths dark scenes or under-smooths bright ones.

2. **exp() per tap in the range kernel.** Each of the 9 bilateral taps requires an exponential
   evaluation. The guided filter replaces the range kernel entirely with a local linear model,
   removing all exp() calls and making edge-preservation emergent rather than explicit.

Reference: Hu et al., "Natureness-preserving tone mapping operator based on improved guided filter
and adaptive Gamma curve", IET Image Processing 2023 (DOI: 10.1049/ipr2.12978). The adaptive ε
formulation (§2.2, eq. 7) is adopted; the multi-scale cascading and entropy fusion are not.

---

## Background — Guided Image Filter (He et al. 2010/2013)

The guided filter models the output as a local linear function of the guidance image within each
window Ω_k:

    q_i = a_k · I_i + b_k    for all i ∈ Ω_k

In self-guided mode (guidance = input, I = p), the coefficients per window k are:

    a_k = cov(I, p) / (var_I + ε)  =  var_I / (var_I + ε)   [covariance = variance in self-guided]
    b_k = mean_p − a_k · mean_I    =  (1 − a_k) · mean_I     [simplifies in self-guided]

Because each pixel i belongs to multiple windows, the final output averages coefficients:

    q_i = mean_a_i · I_i + mean_b_i

This requires two box-filter operations: one on (I, I²) to compute (a_k, b_k), and one on
(a_k, b_k) to compute (mean_a, mean_b). Both are separable — exact in H+V passes.

### Why it preserves edges without halos

At a step edge, var_I is large → a_k → 1, b_k → 0 → q ≈ I (identity, edge preserved).
In a flat region, var_I ≈ 0 → a_k → 0 → q ≈ mean_I (maximum smoothing).
Unlike bilateral, the transition is determined by local structure, not a global σ_r.
No gradient reversal is possible: the local linear model is monotone by construction.

---

## Adaptive ε (Hu et al. 2023, eq. 7)

Standard He et al. uses a fixed ε. In log10-luma space the dynamic range of var_I is wide:
flat patches ~1e-8, textured ~1e-4, hard edges ~0.01–0.1. A single ε cannot be correct across
this range.

Hu et al. replace fixed ε with a content-adaptive form:

    a_k = var_I / ( (1 + ε) · var_I + η )

where:
- **ε** (scale factor, unitless) — controls the maximum a_k ceiling: a_k_max = 1/(1+ε)
  - ε = 0 → standard He filter (a_k can reach 1.0 → potential halos at strong edges)
  - ε = 0.05 → a_k capped at 0.952 (recommended starting point)
- **η** (bias, same units as var_I) — prevents div/0 and governs flat-region behavior
  - In log10 space, flat patches have var_I ≈ 1e-8; η = 1e-8 places the smoothing pivot there

Derivation of behavior:

    a_k = 1 / ( 1 + ε + η/var_I )

- var_I → 0  (flat):  a_k → 0  (maximum smoothing) ✓
- var_I → ∞  (edge):  a_k → 1/(1+ε) < 1 (bounded, halo-resistant) ✓
- var_I = η/ε  (pivot): a_k = 0.5 (50% smoothing)

The pivot at var_I = η/ε = 1e-8 / 0.05 = 2e-7 means the filter transitions from full smoothing
to full preservation around variance = 2e-7 in log10 space. This is slightly below the noise
floor of film grain (~1e-6), which is correct: grain stays in the base layer rather than leaking
into the detail layer.

**GPU cost of adaptive ε vs. fixed ε:** zero extra passes. var_I is already computed in Pass 1.
The change is one MAD in the a_k formula.

---

## Log10-Domain Specifics

The filter runs on log10(luma), matching the R189 bilateral. Key implications:

- **No clipping.** log10 values are negative for luma < 1.0, and R16F handles negatives cleanly.
  No encoding/decoding needed (bilateral already proved this).

- **Variance scale.** Log10 compresses variance relative to linear. A 10% linear luma variation
  around 0.5 maps to Δlog10 ≈ 0.09, so var ≈ 0.0008 — far below linear-space equivalents.
  Parameters ε and η must be tuned in log10 space, not carried over from linear-space papers.

- **Self-guided is exact.** Single-channel self-guided guided filter degenerates to the scalar
  local variance formula above. No cross-channel covariance needed.

- **b_k simplification.** In self-guided mode b_k = (1 − a_k) · mean_I exactly. No additional
  box filter needed to compute b_k — it falls out of a_k and mean_I already computed.

---

## Implementation

### Pass count and window

**2 passes** (same as current bilateral, matching current technique pass count).
Each pass uses a 2D box window — no separable trick needed at this resolution.

- **r = 4 texels** at 1/8-res → 9×9 = 81 samples per pass
  Equivalent spatial extent to current bilateral (σ_s=2 → 95% energy within ±4 texels).
- At 1080p: 1/8-res = 240×135 = 32,400 pixels. 81 taps × 32,400 = 2.6M samples per pass.
  Bilateral reference: 9 taps × 32,400 = 291K samples per pass. ~9× more samples, but:
  - No exp() per tap (bilateral has 8 exp() calls per pass)
  - Pure MAD per sample (fma-friendly)
  - High cache coherence at 1/8-res (neighbors share most of the 9×9 window)
  - Net cost expected comparable to or slightly below bilateral

### Texture changes

Remove:  `BilateralLogHTex` (R16F, intermediate H-pass — no longer needed)
         `BilateralLogHSamp`

Add:     `GuidedCoeffTex` (RG16F, 1/8-res — stores a_k in .r, b_k in .g)
         `GuidedCoeffSamp`

Keep:    `BilateralLogTex` (R16F, 1/8-res — base layer output, same semantics as before)
         `BilateralLogSamp`  (ApplyTonal reads this; no change needed in ApplyTonal)

### Define changes

Remove:
```hlsl
#define BIL_LOG_W0  1.000000
#define BIL_LOG_W1  0.882497
#define BIL_LOG_W2  0.606531
#define BIL_LOG_W3  0.324652
#define BIL_LOG_W4  0.135335
#define BIL_LOG_SR2 0.320000
```

Add:
```hlsl
#define GF_R    4           // box radius in texels at 1/8-res (9×9 window = 81 taps)
#define GF_EPS  0.05        // Hu 2023 ε scale — a_k ceiling = 1/(1+GF_EPS) ≈ 0.952
#define GF_ETA  1e-8        // η bias — pivot at var_I = GF_ETA/GF_EPS = 2e-7 (below noise floor)
```

### Pass 1: GuidedCoeffPS → GuidedCoeffTex (RG16F)

Computes local linear model coefficients (a_k, b_k) per pixel.

```hlsl
float2 GuidedCoeffPS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float px = 8.0 / BUFFER_WIDTH;
    float py = 8.0 / BUFFER_HEIGHT;
    float sum_I = 0.0, sum_II = 0.0;
    static const int N = (2 * GF_R + 1) * (2 * GF_R + 1);
    [unroll] for (int dy = -GF_R; dy <= GF_R; dy++)
    [unroll] for (int dx = -GF_R; dx <= GF_R; dx++)
    {
        float3 c = tex2D(CreativeLowFreqSamp, uv + float2(dx * px, dy * py)).rgb;
        float  I = log10(max(Luma(c), 1e-3));
        sum_I  += I;
        sum_II += I * I;
    }
    float mean_I  = sum_I  / N;
    float mean_II = sum_II / N;
    float var_I   = max(mean_II - mean_I * mean_I, 0.0);   // clamp floating-point noise
    float a_k     = var_I / ((1.0 + GF_EPS) * var_I + GF_ETA);   // Hu 2023 adaptive ε
    float b_k     = (1.0 - a_k) * mean_I;                         // self-guided simplification
    return float2(a_k, b_k);
}
```

### Pass 2: GuidedBasePS → BilateralLogTex (R16F)

Averages coefficients over each pixel's window, reconstructs base layer.

```hlsl
float GuidedBasePS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float px = 8.0 / BUFFER_WIDTH;
    float py = 8.0 / BUFFER_HEIGHT;
    float sum_a = 0.0, sum_b = 0.0;
    static const int N = (2 * GF_R + 1) * (2 * GF_R + 1);
    [unroll] for (int dy = -GF_R; dy <= GF_R; dy++)
    [unroll] for (int dx = -GF_R; dx <= GF_R; dx++)
    {
        float2 ab = tex2D(GuidedCoeffSamp, uv + float2(dx * px, dy * py)).rg;
        sum_a += ab.r;
        sum_b += ab.g;
    }
    float mean_a = sum_a / N;
    float mean_b = sum_b / N;
    float I_c    = log10(max(Luma(tex2D(CreativeLowFreqSamp, uv).rgb), 1e-3));
    return mean_a * I_c + mean_b;
}
```

### Technique pass changes

```hlsl
// Remove:
pass BilateralLogH { PixelShader = BilateralLogHPS; RenderTarget = BilateralLogHTex; }
pass BilateralLogV { PixelShader = BilateralLogVPS; RenderTarget = BilateralLogTex;  }

// Replace with:
pass GuidedCoeff   { PixelShader = GuidedCoeffPS;   RenderTarget = GuidedCoeffTex;   }
pass GuidedBase    { PixelShader = GuidedBasePS;     RenderTarget = BilateralLogTex;  }
```

Technique pass count unchanged (10 passes total). BilateralLogTex slot preserved —
ApplyTonal is completely untouched.

### CLAUDE.md update required

grade.fx pass list changes:
- `BilateralLogH` → `GuidedCoeff`
- `BilateralLogV` → `GuidedBase`

BilateralLogHTex / BilateralLogHSamp references removed. GuidedCoeffTex / GuidedCoeffSamp added.

---

## Parameter starting point and calibration

| Parameter | Value | Rationale |
|-----------|-------|-----------|
| GF_R      | 4     | Matches bilateral spatial extent (σ_s=2 → ±4 tex 9-tap) |
| GF_EPS    | 0.05  | a_k ceiling 0.952 — slight halo resistance; tune ±0.02 |
| GF_ETA    | 1e-8  | Pivot at var=2e-7, below log10-space noise floor (~1e-6) |

**Calibration procedure:**
1. Set BILATERAL_STRENGTH 0.0, CLARITY_STRENGTH 0.0 — verify base layer is visually smooth and
   edge-following (not blurring across bright windows/lamps into dark surroundings).
2. Re-enable BILATERAL_STRENGTH. Compare feel to R189 bilateral at same strength value.
   If redistribution is too strong: GF_R may be capturing too-fine detail in the base — reduce
   GF_EPS slightly (pushes a_k lower, smoother base).
   If redistribution is too weak: base is too coarse — reduce GF_R to 3 (49 taps).
3. Re-enable CLARITY_STRENGTH. Detail layer log_pixel − log_base should look like a clean
   micro-contrast map without ringing. If halos appear near windows: increase GF_EPS slightly.

**BILATERAL_STRENGTH and CLARITY_STRENGTH values from R189 are likely still valid** — the
semantics of the base layer are identical. Minor recalibration of ±0.05 expected.

---

## Expected visual difference vs. bilateral

| Scenario | Bilateral (R189) | Guided filter (R190) |
|----------|-----------------|----------------------|
| Flat uniform area | Smooth base ✓ | Smooth base ✓ |
| Gradual illumination gradient | Smooth ✓ | Smooth ✓ |
| Bright lamp against dark wall | Base bleeds slightly across edge | Base locks to edge — cleaner separation |
| High-contrast game HUD overlay | σ_r may not suppress fully | Edge-locked, HUD stays in detail layer |
| Dark scene (low overall luma) | σ_r=0.4 may over-preserve noise | var_I low → smooth base, noise in detail |
| Bright outdoor scene | σ_r correct range | Same behavior via ε ceiling |

Primary improvement: **lamp/window halo elimination** in BILATERAL_STRENGTH redistribution.
Secondary: cleaner CLARITY_STRENGTH detail near scene boundaries.

---

## SPIR-V compile note

`static const int N` as a compile-time constant in the loop bound — verify this compiles cleanly
under vkBasalt SPIR-V. If SPIR-V rejects `static const int`, replace with:
```hlsl
#define GF_N  ((2 * GF_R + 1) * (2 * GF_R + 1))
```
and use `GF_N` directly. The `[unroll]` attribute on both nested loops is required for correct
SPIR-V output — without it the compiler may emit a dynamic loop that degrades performance.
