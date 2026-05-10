# R59 — Multi-Scale Texture Gate for Shadow Lift

**Date:** 2026-05-02
**Status:** Research complete — safe to implement.

---

## Problem

R57 (ISL) and R58 (Retinex-aware per-pixel gate) improved shadow lift behaviour but
did not fully solve foliage flatness. R58 protects individual pixels that are locally
darker than their immediate neighbourhood. However, the lift still fires on pixels
that match their local average — and in a dense foliage region, those are the
mid-tone leaf pixels that form the "floor" of the foliage contrast range. Lifting
that floor compresses the range the foliage micro-contrast operates in, making the
region read flatter even if individual dark detail pixels are protected.

What's needed is a **regional** gate: before any per-pixel logic, determine whether
the current pixel sits in a textured area (foliage, leaf clusters, complex geometry)
or a spatially uniform dark area (flat shadow between light pools). Apply full lift
only in the latter; suppress it in the former.

---

## Solution: multi-scale illumination variance

`CreativeLowFreqTex` already has 3 mip levels. Currently the code samples mip 1
(`illum_s0`). Mip 2 is coarser — at 1920×1080 it represents a spatial average over
roughly 32×32 full-resolution pixels vs mip 1's ~16×16.

The difference between the two scales is a proxy for local image texture:

```
local_var = |illum_mip1 - illum_mip2|
```

- **Dense foliage / textured area**: mip 1 captures leaf cluster variation; mip 2
  averages it out. Difference is large (0.015–0.035).
- **Uniform deep shadow**: both mip levels agree. Difference near zero (<0.005).

Gate the lift on this:

```hlsl
float texture_att = 1.0 - smoothstep(0.005, 0.030, local_var);
```

Combined with the existing R58 per-pixel gate:

```hlsl
float shadow_lift = SHADOW_LIFT * (0.149169 / (illum_s0 * illum_s0 + 0.003))
                  * local_range_att * texture_att * detail_protect;
```

---

## Threshold derivation

| local_var | texture_att | Scene type |
|-----------|-------------|-----------|
| 0.000 | 1.000 | Perfectly uniform dark — full lift |
| 0.005 | 1.000 | Flat shadow with slight noise — full lift |
| 0.010 | 0.896 | Slight texture — mostly lift |
| 0.015 | 0.648 | Moderate foliage texture |
| 0.020 | 0.352 | Dense leaf variation — 65% suppressed |
| 0.025 | 0.104 | Very dense foliage — nearly suppressed |
| 0.030 | 0.000 | Maximum texture — no lift |

Lower bound 0.005: insensitive to noise and uniform-region luma drift between mip
levels. Upper bound 0.030: covers the realistic range of mip 1/2 divergence for
dense foliage (leaf luma range ~0.06–0.14 at 10% local average).

---

## Numerical validation

**Foliage region** (`illum_s0=0.10`, `local_var=0.020`, `SHADOW_LIFT=1.5`):

| new_luma | log_R | detail_protect | texture_att | combined | Applied Δ |
|----------|-------|----------------|-------------|----------|-----------|
| 0.03 | −1.74 | 0.000 | 0.352 | 0.000 | +0.00000 |
| 0.07 | −0.52 | 0.000 | 0.352 | 0.000 | +0.00000 |
| 0.10 | 0.000 | 1.000 | 0.352 | 0.352 | +0.00337 |
| 0.15 | +0.59 | 1.000 | 0.352 | 0.352 | +0.00341 |

**Dense foliage** (`illum_s0=0.08`, `local_var=0.030`):
All pixels: `texture_att = 0.000` → zero lift regardless of `detail_protect`. The
foliage region floor is fully protected.

**Uniform deep shadow** (`illum_s0=0.04`, `local_var=0.001`):

| new_luma | combined | Applied Δ |
|----------|----------|-----------|
| 0.04 | 1.000 | +0.01388 |
| 0.05 | 1.000 | +0.01689 |

Full lift preserved. ✓

**Lift ratio at local-avg pixels:**

| Condition | Applied Δ | Relative |
|-----------|-----------|----------|
| Uniform deep shadow (lv=0.001) | +0.01388 | 1.0× (reference) |
| Moderate foliage (lv=0.020) | +0.00337 | **4.1× less** |
| Dense foliage (lv=0.030) | +0.00000 | **no lift** |

---

## Key property: local_var is per-pixel, not per-zone

`local_var` is computed per pixel from two texture fetches. A uniformly dark pocket
sitting WITHIN a foliage area will have low local_var (both mip levels agree it's
dark) and receive full lift. Only pixels where fine-scale and coarse-scale luma
diverge — i.e. pixels that sit within or adjacent to textured structure — are
attenuated. This is the correct behaviour: lift the flat deep pockets, preserve the
micro-contrast regions.

---

## GPU cost

One additional `tex2Dlod` call on `CreativeLowFreqSamp` at mip 2. Same sampler,
same UV, trivially cheap. No new textures, no new passes, no new knobs.

---

## Implementation

**File:** `general/grade/grade.fx`, lines 299–304.

**Before:**
```hlsl
float illum_s0 = max(tex2Dlod(CreativeLowFreqSamp, float4(uv, 0, 1)).a, 0.001);
float log_R    = log2(max(new_luma, 0.001) / illum_s0);
new_luma = lerp(new_luma, saturate(exp2(log_R + log2(max(zone_log_key, 0.001)))), 0.75 * smoothstep(0.04, 0.25, zone_std));

float local_range_att = 1.0 - smoothstep(0.20, 0.50, zone_iqr);
float detail_protect  = smoothstep(-0.5, 0.0, log_R);
float shadow_lift     = SHADOW_LIFT * (0.149169 / (illum_s0 * illum_s0 + 0.003)) * local_range_att * detail_protect;
```

**After:**
```hlsl
float illum_s0  = max(tex2Dlod(CreativeLowFreqSamp, float4(uv, 0, 1)).a, 0.001);
float illum_s2  = max(tex2Dlod(CreativeLowFreqSamp, float4(uv, 0, 2)).a, 0.001);
float local_var = abs(illum_s0 - illum_s2);
float log_R     = log2(max(new_luma, 0.001) / illum_s0);
new_luma = lerp(new_luma, saturate(exp2(log_R + log2(max(zone_log_key, 0.001)))), 0.75 * smoothstep(0.04, 0.25, zone_std));

float local_range_att = 1.0 - smoothstep(0.20, 0.50, zone_iqr);
float texture_att     = 1.0 - smoothstep(0.005, 0.030, local_var);
float detail_protect  = smoothstep(-0.5, 0.0, log_R);
float shadow_lift     = SHADOW_LIFT * (0.149169 / (illum_s0 * illum_s0 + 0.003)) * local_range_att * texture_att * detail_protect;
```

Two lines added. Three gates now in series: `local_range_att` (zone IQR),
`texture_att` (multi-scale texture), `detail_protect` (per-pixel Retinex).
