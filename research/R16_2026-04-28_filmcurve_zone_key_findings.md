# R16 — FilmCurve: Zone-Informed Scene Key

**Date:** 2026-04-28  
**Status:** Research complete — implementation ready

---

## 1. Internal Audit

**Current FilmCurve** (`grade.fx` lines 296–307, called at line 403):

```hlsl
float3 FilmCurve(float3 x, float p25, float p50, float p75)
{
    float knee     = lerp(0.90, 0.80, saturate((p75 - 0.60) / 0.30));
    float width    = 1.0 - knee;
    float stevens  = (1.48 + sqrt(max(p50, 0.0))) / 2.03;
    float factor   = 0.05 / (width * width) * stevens;
    float knee_toe = lerp(0.15, 0.25, saturate((0.40 - p25) / 0.30));
    float3 above   = max(x - knee,     0.0);
    float3 below   = max(knee_toe - x, 0.0);
    return x - factor * above * above
               + (0.03 / (knee_toe * knee_toe)) * below * below;
}
```

Called as:
```hlsl
float3 lin = FilmCurve(pow(max(col.rgb, 0.0), EXPOSURE), perc.r, perc.g, perc.b);
```

Where `perc` = `tex2D(PercSamp, ...)` — a **1×1 texture** containing `(p25, p50, p75, iqr)` of the **global pixel luminance histogram**.

**ZoneHistoryTex** (4×4, RGBA16F) — confirmed from `BuildZoneLevelsPS` (corrective.fx line 488):
```hlsl
return float4(median, p25, p75, 1.0);  // per-zone: r=median, g=p25, b=p75
```
16 spatially-distinct zone medians. Currently only consumed by the zone S-curve (stage 2), not by FilmCurve (stage 1).

---

## 2. Literature

### 2.1 Reinhard et al. 2002 — Photographic Tone Reproduction

**Source:** Reinhard, E. et al. "Photographic tone reproduction for digital images." SIGGRAPH 2002.

**Log-average luminance (geometric mean key):**
$$\bar{L}_w = \exp\!\left(\frac{1}{N}\sum_i \log(\delta + L_i)\right)$$

Where δ = 0.0001 prevents log(0). This is the scene key — the "Ansel Adams Zone V" equivalent in the scene. Reinhard maps key = 0.18 (middle grey) to this geometric mean, scaling bright/dark scenes accordingly.

**Connection to zone system:**
> "Ansel Adams' Zone System assigns numbers from 0 to X to luminance values. Zone V is middle gray at 18% reflectance."

The geometric mean is the standard key estimator across the HDR tone mapping literature because it is a **spatially-unbiased** luminance estimator. Unlike arithmetic mean, it treats each sample equally on a log scale (which matches visual perception).

### 2.2 Why pixel histogram percentiles are biased

PercTex (p25/p50/p75) is computed from the raw pixel luminance histogram. For game scenes:
- **Large flat surfaces** (sky, ground planes, walls) contribute thousands of pixels per luminance bin
- **Interesting content** (characters, objects, lighting effects) may occupy 5–20% of the frame
- p50 of the pixel histogram is strongly biased toward the dominant flat region

Zone medians solve this: each of the 16 spatial zones contributes **one median value** regardless of area. A zone containing sky and a zone containing a character contribute equally. This is how a photographer's eye evaluates a scene.

**Example — overcast outdoor game scene:**
- Sky covers 40% of the frame (pixels: very bright, p50 pulled high)
- Ground covers 40% (pixels: mid-grey, dominates)
- Characters cover 20% (the interesting content)

Pixel p50 ≈ 0.40 (dominated by ground). Zone medians: ~8 sky zones, ~5 ground zones, ~3 character zones. Zone geometric mean ≈ exp(mean of log values), weighted by zone structure, not area.

### 2.3 Zone min/max vs. p25/p75 as anchors

p25/p75 are percentiles of the pixel histogram — they represent "where 25%/75% of all pixels lie." For a game scene with flat surfaces:
- p25 may reflect the modal dark color of the floor/wall (lots of similar pixels)
- p75 may reflect the modal bright color of the sky

Zone min/max represent:
- `z_min` = the darkest spatial zone's median — the darkest *region* of content
- `z_max` = the brightest spatial zone's median — the brightest *region* of content

The min/max of zone medians are closer to what an exposure-meter reading would identify as the scene's structural dark/light anchors.

---

## 3. Proposed Implementation

### Finding 1 — Zone geometric mean replaces p50 as scene key [PASS]

Compute the geometric mean of all 16 zone medians before calling FilmCurve. Use as the `p50` argument.

**In `ColorTransformPS`, before FilmCurve call:**
```hlsl
// R16-F1: zone geometric mean key (Reinhard 2002)
float r16_log_sum = 0.0;
r16_log_sum += log(0.001 + tex2D(ZoneHistorySamp, float2(0.125, 0.125)).r);
r16_log_sum += log(0.001 + tex2D(ZoneHistorySamp, float2(0.375, 0.125)).r);
r16_log_sum += log(0.001 + tex2D(ZoneHistorySamp, float2(0.625, 0.125)).r);
r16_log_sum += log(0.001 + tex2D(ZoneHistorySamp, float2(0.875, 0.125)).r);
r16_log_sum += log(0.001 + tex2D(ZoneHistorySamp, float2(0.125, 0.375)).r);
r16_log_sum += log(0.001 + tex2D(ZoneHistorySamp, float2(0.375, 0.375)).r);
r16_log_sum += log(0.001 + tex2D(ZoneHistorySamp, float2(0.625, 0.375)).r);
r16_log_sum += log(0.001 + tex2D(ZoneHistorySamp, float2(0.875, 0.375)).r);
r16_log_sum += log(0.001 + tex2D(ZoneHistorySamp, float2(0.125, 0.625)).r);
r16_log_sum += log(0.001 + tex2D(ZoneHistorySamp, float2(0.375, 0.625)).r);
r16_log_sum += log(0.001 + tex2D(ZoneHistorySamp, float2(0.625, 0.625)).r);
r16_log_sum += log(0.001 + tex2D(ZoneHistorySamp, float2(0.875, 0.625)).r);
r16_log_sum += log(0.001 + tex2D(ZoneHistorySamp, float2(0.125, 0.875)).r);
r16_log_sum += log(0.001 + tex2D(ZoneHistorySamp, float2(0.375, 0.875)).r);
r16_log_sum += log(0.001 + tex2D(ZoneHistorySamp, float2(0.625, 0.875)).r);
r16_log_sum += log(0.001 + tex2D(ZoneHistorySamp, float2(0.875, 0.875)).r);
float zone_log_key = exp(r16_log_sum * 0.0625);  // / 16
```

Replace the FilmCurve call:
```hlsl
// Before: FilmCurve(..., perc.r, perc.g, perc.b)
// After:
float3 lin = FilmCurve(pow(max(col.rgb, 0.0), EXPOSURE), perc.r, zone_log_key, perc.b);
```

**Why only p50 for F1:** The Stevens factor `(1.48 + sqrt(p50)) / 2.03` is the primary beneficiary of an unbiased key estimate. p25/p75 anchors (F2) are a secondary improvement.

### Finding 2 — Zone min/max blend improves toe/knee anchors [PASS]

Also during the 16-sample pass, collect min and max:

```hlsl
float r16_z0  = tex2D(ZoneHistorySamp, float2(0.125, 0.125)).r;
// ... (same 16 reads — combine with F1 loop, no extra texture fetches)
float z_min = min(min(min(min(min(min(min(min(
              min(min(min(min(min(min(min(r16_z0,
              r16_z1), r16_z2), r16_z3), r16_z4), r16_z5), r16_z6), r16_z7),
              r16_z8), r16_z9), r16_z10), r16_z11), r16_z12), r16_z13), r16_z14), r16_z15);
float z_max = max( /* same pattern */ );
```

Blend with pixel histogram anchors (40% zone weight — conservative):
```hlsl
float eff_p25 = lerp(perc.r, z_min, 0.4);
float eff_p75 = lerp(perc.b, z_max, 0.4);
float3 lin = FilmCurve(pow(max(col.rgb, 0.0), EXPOSURE), eff_p25, zone_log_key, eff_p75);
```

**Blend rationale:** Zone min/max are medians of their respective zones, not the absolute 25th/75th histogram percentile. A 40% weight avoids over-dependence on zone statistics while adding spatial structure-awareness. Can be tuned upward if behavior is validated.

### Finding 3 — Zone spread modulates FilmCurve factor [PASS, low risk]

Compute `zone_std` from the same 16 samples (adds mean + variance computation):

```hlsl
float r16_sum = r16_z0 + r16_z1 + ... + r16_z15;  // sum
float r16_mean = r16_sum * 0.0625;
float r16_sq_sum = r16_z0*r16_z0 + ... + r16_z15*r16_z15;
float zone_std = sqrt(max(r16_sq_sum * 0.0625 - r16_mean * r16_mean, 0.0));
```

Scale FilmCurve factor in `FilmCurve()` function (add parameter, or pre-scale externally):
```hlsl
// Before FilmCurve call, compute scale:
float spread_scale = lerp(0.7, 1.1, smoothstep(0.08, 0.25, zone_std));
// Pass to FilmCurve or multiply factor internally:
float factor = 0.05 / (width * width) * stevens * spread_scale;
```

**Range:** zone_std < 0.08 = tonally compact scene (gentle FilmCurve); zone_std > 0.25 = high scene contrast (slightly stronger compression). Scale range 0.7–1.1 is conservative.

---

## 4. Implementation Strategy

All three findings use the **same 16 zone-median reads**. No extra texture fetches beyond what F1 requires. Total additions vs. current:
- 16 `tex2D` reads (ZoneHistoryTex — 4×4, already hot in cache)
- 16 `log()` + 1 `exp()` (F1)
- 16 `min/max` (F2)
- 16 additions + 16 multiply-add + 1 `sqrt()` (F3)

**Modified FilmCurve signature** (add spread parameter):
```hlsl
float3 FilmCurve(float3 x, float p25, float p50, float p75, float spread_scale)
```

Or keep signature unchanged and compute effective inputs before the call.

**SPIR-V compliance:**
- `log()`, `exp()`, `sqrt()` — standard SPIR-V intrinsics. PASS.
- No `static const float[]`, no reserved keywords. PASS.
- No branches on pixel values. PASS.
- `tex2D` at constant (compile-time-derivable) UVs — PASS.

---

## 5. Strategic Assessment

| Finding | Justification | Risk | Impact |
|---------|--------------|------|--------|
| F1: Zone log-key | Reinhard 2002 log-average formula | Low | High — Stevens factor drives the whole curve strength |
| F2: Zone min/max blend | Structural anchors vs. histogram bias | Low–Med | Medium — toe/knee positioning more accurate |
| F3: Zone spread scale | Adaptive per scene contrast | Low | Medium — prevents over/under-compression |

**Verdict: Implement F1+F2+F3.** All three share the 16-sample pass. F1 is the highest-value change. F2+F3 add signal at near-zero extra cost. The 40% blend weight on F2 and the 0.7–1.1 scale on F3 are conservative calibrations that can be tightened after visual validation.

**Deferred:** Monotone cubic spline through the 16 sorted medians as full curve shape (requires 16-element sort network, ~56 comparators in HLSL — too expensive for marginal SDR gain). Revisit for HDR pipeline if pursued.
