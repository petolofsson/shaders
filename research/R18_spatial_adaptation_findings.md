# R18 — Spatial Adaptation: Zone Luminance Normalization

**Date:** 2026-04-28  
**Status:** Research complete — implementation ready (no new pass needed)

---

## 1. Internal Audit

**Current zone usage in stage 2 (`grade.fx`, post-R16):**

```hlsl
float4 zone_lvl   = tex2D(ZoneHistorySamp, uv);    // bilinear 4×4 sample at pixel UV
float zone_median = zone_lvl.r;
// ...
float bent     = dt + (ZONE_STRENGTH / 100.0) * iqr_scale * dt * (1.0 - saturate(abs(dt)));
float new_luma = saturate(zone_median + bent);
```

The zone S-curve applies a `PivotedSCurve(luma, zone_median, strength)` per pixel. The pivot point (`zone_median`) comes from `tex2D(ZoneHistorySamp, uv)` with `MinFilter = LINEAR, MagFilter = LINEAR`.

**Critical observation:** ZoneHistoryTex is 4×4 pixels. Sampling it with LINEAR at the current pixel's UV coordinate already provides **bilinear spatial interpolation** between zone medians. Zone boundaries are transitions spanning ~25% of screen width — no hard edges, no halos possible from this source.

**What's missing:** The zone S-curve increases local contrast *within* each zone (bends luma relative to zone_median) but does NOT normalize the absolute luminance *between* zones. A consistently dark zone at median 0.10 and a consistently bright zone at median 0.70 both receive S-curves around their respective medians — the overall luminance disparity between zones is unchanged.

---

## 2. Literature

### 2.1 Reinhard 2002 local operator

**Source:** Reinhard et al., "Photographic Tone Reproduction for Digital Images," SIGGRAPH 2002.

The local tone mapping operator uses a per-pixel local adaptation luminance `V(x,y)`:

$$L_d(x,y) = \frac{L(x,y)}{1 + V(x,y)}$$

Where `V(x,y)` is the luminance average in a neighborhood centered at the pixel. The neighborhood scale is chosen as the smallest scale where the center-surround contrast falls below a threshold (preventing halos from over-localization).

**Connection to our pipeline:**
- `V(x,y)` ≈ `zone_median` (bilinearly interpolated from ZoneHistoryTex)
- Our zones ARE the "spatial neighborhood" for local adaptation
- At 4×4 grid resolution, each zone spans ~25% × 25% of the frame — much coarser than Reinhard's local operator, but appropriate for scene-level normalization rather than detail preservation

### 2.2 Halo prevention

Halos in local tone mapping arise when the adaptation region is too small relative to the feature size — the correction changes sharply at feature boundaries, creating luminance rings. Two mechanisms prevent this:

1. **Large enough neighborhood:** Reinhard requires the adaptation scale to be larger than the sharpest feature. Our zones (1/4 screen) are vastly larger than any sharp feature — halo risk from this source is zero.

2. **Monotone mapping:** `L/(1+V)` is monotone in L — brighter pixels always map to brighter outputs. Our multiplicative normalization `L * factor` is also monotone. PASS.

3. **Smooth V:** `V(x,y)` must vary slowly. Our zone_median at `uv` varies continuously due to bilinear interpolation of a 4×4 texture — the transition between adjacent zones spans ~480px horizontally at 1920 resolution. PASS.

### 2.3 Power-law normalization vs. Reinhard

Full Reinhard local: `Ld = L / (1 + V)` — aggressive, maps V to 50% of white point.  
Our formulation: `Ld = L * (target/V)^strength` — fractional power, conservative.

The power-law form is better for our SDR context:
- At strength=0: identity (no change)
- At strength=1: full normalization (every zone mapped to same median = flat look)
- At strength=0.20: gentle correction (dark zone at 0.10 with target 0.20 → factor = 1.15×)

This matches the Reinhard local operator's intent (normalize zones toward a common key) without its aggressive HDR compression.

---

## 3. Proposed Implementation

### Finding 1 — Zone luminance normalization (no new pass) [PASS]

After the zone S-curve computes `new_luma`, apply a gentle multiplicative normalization pulling each pixel's zone median toward the global scene key (`zone_log_key` from R16).

```hlsl
// R18: zone luminance normalization — pulls zone medians toward global key
float r18_strength = SPATIAL_NORM_STRENGTH / 100.0 * 0.4;  // max power = 0.4 at strength=100
float r18_norm     = pow(max(zone_log_key, 0.001) / max(zone_median, 0.001), r18_strength);
new_luma = saturate(new_luma * r18_norm);
```

**Behavior:**
| Scene | zone_median | zone_log_key | r18_norm (at strength=20) | Effect |
|-------|------------|-------------|--------------------------|--------|
| Dark zone, avg scene | 0.10 | 0.20 | (2.0)^0.08 = 1.055 | +5.5% brightness |
| Normal zone | 0.20 | 0.20 | 1.0 | No change |
| Bright zone, avg scene | 0.70 | 0.20 | (0.286)^0.08 = 0.90 | −10% brightness |
| Night scene (all dark) | 0.08 | 0.10 | (1.25)^0.08 = 1.018 | +1.8% (small correction — zones already close to key) |

**Key properties:**
- At SPATIAL_NORM_STRENGTH = 0: `r18_norm = 1.0` → identity
- At SPATIAL_NORM_STRENGTH = 100: `r18_norm = pow(ratio, 0.4)` → strong but bounded
- Zones at the global key (zone_median ≈ zone_log_key) get zero correction
- Bilinear zone sampling prevents any block artifacts or halos
- Monotone in luma → cannot invert tonal relationships

### Finding 2 — No new pass needed [key architectural finding]

The ROADMAP anticipated a new pass for spatial blending. **This is not needed** because:
1. ZoneHistoryTex already uses `MinFilter = LINEAR; MagFilter = LINEAR`
2. A 4×4 bilinear texture sampled at full-resolution UV provides inherently smooth spatial transitions
3. The spatial smoothness is proportional to zone size (~25% of screen = graceful gradient)
4. No separate blur or blending kernel is required

The normalization lives entirely in grade.fx stage 2 — 3 extra lines, zero additional passes.

### SPATIAL_NORM_STRENGTH knob (creative_values.fx)

```hlsl
#define SPATIAL_NORM_STRENGTH  20  // 0–100; zone-to-key normalization strength
```

Default 20 = gentle correction (+5–15% adjustment for extreme zones). Range:
- 0: off (safety valve)
- 15–25: subtle spatial balancing (recommended)
- 40–60: visible zone equalization (artistic choice)
- 80–100: near-full normalization (test only — can look flat)

---

## 4. Strategic Assessment

| Aspect | Assessment |
|--------|-----------|
| Literature basis | Reinhard 2002 local operator (L/(1+V)), power-law variant for SDR |
| Halo risk | None — zone regions are 25% of screen, bilinear smoothed |
| New pass required | No — uses existing ZoneHistoryTex bilinear sampling |
| Monotonicity | Yes — multiplicative correction preserves tonal order |
| Gate-free | `pow(x,y)` with positive args, no conditionals. PASS |
| SPIR-V | `pow()` standard intrinsic. PASS |
| Cost | 1 pow + 2 div + 1 multiply — negligible |
| Interaction with zone S-curve | Additive: S-curve boosts within-zone contrast; normalization equalizes between-zone luminance |

**Verdict: Implement.** The key finding — no new pass needed — makes this significantly cheaper than the ROADMAP anticipated. The combination of zone S-curve (within-zone contrast) + zone normalization (between-zone equalization) + clarity (pixel-level detail) creates a three-tier spatial contrast system that's genuinely novel for a real-time shader.
