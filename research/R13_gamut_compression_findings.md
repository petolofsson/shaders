# R13 — Gamut Compression: Findings

**Date:** 2026-04-28  
**Status:** Research complete — gate-free fix is trivial; also found hue-preserving improvement

---

## 1. Internal Audit

**Current (grade.fx Stage 3, lines 477–483):**
```hlsl
float3 chroma_rgb = OklabToRGB(float3(density_L, f_oka, f_okb));
float  rmax       = max(chroma_rgb.r, max(chroma_rgb.g, chroma_rgb.b));
if (rmax > 1.0)
{
    float L_grey = dot(chroma_rgb, float3(0.2126, 0.7152, 0.0722));
    float gclip  = (1.0 - L_grey) / max(rmax - L_grey, 0.001);
    chroma_rgb   = L_grey + gclip * (chroma_rgb - L_grey);
}
lin = saturate(chroma_rgb);
```

**Problems:**
1. `if (rmax > 1.0)` is a hard conditional on a pixel property — violates the no-gates rule.
2. The grey-point desaturation shifts hue: the grey axis in Oklab (a=0, b=0) is neutral, but the Luma-weighted grey point `L_grey` does not preserve the (a,b) direction.
3. No rolloff: rmax=0.999 is untouched; rmax=1.001 gets hard compression. Potential seam.

---

## 2. Literature

### 2.1 ACES Reference Gamut Compression (VWG 2020 / ACES 2.0)

**Source:** ACES Virtual Working Group on Gamut Mapping (2020); ACES 2.0 specification.

The ACES powerP compression curve:

$$d_c = d_n \quad \text{if } d_n < t$$
$$d_c = t + \frac{d_n - t}{\left(1 + \left(\frac{d_n - t}{s}\right)^p\right)^{1/p}} \quad \text{if } d_n \geq t$$

$$s = \frac{l - t}{\left(\frac{1 - t}{l - t}\right)^{-p} - 1)^{1/p}}$$

Parameters (ACES 2.0): t ∈ [0.803, 0.880] per channel, l ∈ [1.147, 1.312], p = 1.2.

**Gate compliance: FAIL.** The formula has an explicit conditional branch on $d_n < t$. Does not satisfy the no-gates rule.

### 2.2 Björn Ottosson — Oklab Gamut Clipping (2021)

**Source:** Ottosson, B. "A perceptual color space for image processing" (blog, 2021).

Hue-independent adaptive-L₀ method. Finds the achromatic projection point L₀ as:

$$L_a = L_1 - 0.5$$
$$e_1 = 0.5 + |L_a| + \alpha C_1$$
$$L_0 = \frac{1 + \text{sgn}(L_a)\left(e_1 - \sqrt{e_1^2 - 2|L_a|}\right)}{2}$$

Then intersects the line from $(L_0, 0)$ to $(L_1, C_1)$ with the sRGB gamut boundary.

**Gate compliance: PASS.** Uses `sgn()` and `sqrt()` only — both are arithmetic intrinsics with no branch in SPIR-V. Fully gate-free.

**Hue preservation: PASS.** Projects along the (a,b) chroma direction, not toward the grey point. Hue angle preserved.

**Complication:** Requires finding the sRGB gamut boundary for each hue, which involves a `find_cusp()` function. Not trivial to port without additional texture lookups or precomputed tables.

### 2.3 Simplest Gate-Free Fix

The existing grey-point desaturation logic is mathematically correct when `rmax > 1.0`. The only code problem is the `if` statement. The fix:

$$\text{gclip} = \text{saturate}\left(\frac{1 - L_\text{grey}}{\max(\text{rmax} - L_\text{grey},\; 0.001)}\right)$$

**Proof of identity:**
- When `rmax ≤ 1`: $1 - L_\text{grey} \geq \text{rmax} - L_\text{grey}$ (since $L_\text{grey} \leq \text{rmax} \leq 1$), so the ratio ≥ 1.0, `saturate()` returns 1.0, and `chroma_rgb` is unchanged. ✓
- When `rmax > 1`: ratio < 1.0, `saturate()` returns it as-is, chroma is compressed. ✓
- When `rmax ≤ L_grey` (near-grey pixel): `max(..., 0.001)` catches division near zero, result saturates to 1.0. ✓

**Gate compliance: PASS.** No `if` statement.

---

## 3. Proposed Solutions

### Finding 1 — Gate-Free Fix: saturate(gclip) [PASS — Trivial]

Replace the `if (rmax > 1.0)` block with an always-on version:

**Current:**
```hlsl
if (rmax > 1.0)
{
    float L_grey = dot(chroma_rgb, float3(0.2126, 0.7152, 0.0722));
    float gclip  = (1.0 - L_grey) / max(rmax - L_grey, 0.001);
    chroma_rgb   = L_grey + gclip * (chroma_rgb - L_grey);
}
```

**Proposed:**
```hlsl
float L_grey = dot(chroma_rgb, float3(0.2126, 0.7152, 0.0722));
float gclip  = saturate((1.0 - L_grey) / max(rmax - L_grey, 0.001));
chroma_rgb   = L_grey + gclip * (chroma_rgb - L_grey);
```

- 3-line change. No new ALU cost (saves one branch, one compare).
- Preserves existing behaviour for all out-of-gamut pixels exactly.
- For in-gamut pixels: gclip = 1.0 (identity), no change.
- Injection point: `grade.fx:477–483`.

### Finding 2 — Hue-Preserving Fix: (a,b) axis scaling [PASS — Moderate]

Instead of grey-point desaturation (which can subtly shift hue), scale the (a,b) vector using `rmax_probe` (which is already computed at line 470):

```hlsl
// rmax_probe already computed from OklabToRGB(final_L, f_oka, f_okb)
float C_scale = min(1.0, 1.0 / max(rmax_probe, 1.0));
float2 ab_final = float2(f_oka, f_okb) * C_scale;
float3 chroma_rgb = OklabToRGB(float3(density_L, ab_final.x, ab_final.y));
// Remove the if-block entirely; saturate() is the SDR ceiling
```

**Gate compliance:** `min(1.0, ...)` and `max(..., 1.0)` are arithmetic intrinsics, not branches. PASS.  
**Hue preservation:** Scaling the (a,b) vector maintains the direction exactly. PASS.  
**Limitation:** Hard clamp at rmax_probe=1 — no smooth rolloff before the boundary. Same seam risk as original, but seam is at chroma scale = 1.0 rather than inside an `if` block.

**Improvement over Finding 1:** Hue angle is preserved; no luminance-weighted grey axis distortion.

### Finding 3 — Soft Pre-Compression via rmax_probe [PASS — See note]

For a true soft rolloff starting before the gamut boundary (e.g., at rmax_probe = 0.85), the `rmax_probe` is the right handle. A Reinhard-style rolloff starting at threshold `t`:

```hlsl
float t = 0.85;
float d = max(rmax_probe - t, 0.0);          // 0 in-gamut, positive out
float s = (1.0 - t) * (1.0 - t);            // Reinhard scale
float rmax_soft = t + d - d * d / (d + s);  // Reinhard derivative: identity at 0, asymptotes at ~1
float C_scale = rmax_soft / max(rmax_probe, 1e-6);
float2 ab_final = float2(f_oka, f_okb) * C_scale;
float3 chroma_rgb = OklabToRGB(float3(density_L, ab_final.x, ab_final.y));
```

**Gate compliance:** `max(x, 0.0)` is a built-in intrinsic (no branch). PASS.  
**Note:** `max(rmax_probe - t, 0.0)` introduces a C0 kink at rmax_probe = t — the derivative is discontinuous but the function value is continuous. Whether this produces a visible seam is scene-dependent; it is far less likely than a seam at rmax=1.0 because t=0.85 falls well within normal gamut for typical scenes.

---

## 4. Strategic Assessment

| Finding | Gate-free | Hue preserved | Rolloff | Implementation cost |
|---------|-----------|---------------|---------|---------------------|
| F1 — saturate(gclip) | PASS | Partial (grey-axis) | None (clamp) | Trivial (3 lines) |
| F2 — (a,b) scale | PASS | PASS | None (clamp) | Minor (refactor) |
| F3 — Reinhard pre-compress | PASS | PASS | Soft | Low-moderate |

**Recommendation:** F1 is the minimum required fix (gate compliance). F2 is a one-pass improvement with no added cost. F3 is the best perceptual outcome but introduces a soft-gate approximation at t=0.85.

Given the no-gates rule is primarily about visual seams: F2 at minimum, F3 if smoothing before the boundary is desired. F1 is acceptable only if hue distortion from grey-point desaturation is imperceptible at current CHROMA_STRENGTH levels.
