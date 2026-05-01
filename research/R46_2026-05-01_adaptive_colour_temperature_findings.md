# R46 — Adaptive Colour Temperature — Findings

**Date:** 2026-05-01
**Status:** Ready to implement

---

## Summary

Three effects can share one scene-warmth signal computed from a highlight-restricted R-B
ratio. ChromaHistoryTex col 7 is free. The signal is computed inline in the existing
UpdateHistoryPS pass (corrective.fx) — zero new passes, zero new textures. Grade.fx
reads it to auto-correct HIGHLIGHT_TEMP; pro_mist reads it to adapt scatter weights.
Total new texture reads: 1 per effect per frame.

---

## Q1: Proxy accuracy — resolved: use direct R-B ratio, not hue-band proxy

The ChromaHistoryTex warm_energy proxy (red+yellow vs cyan+blue band weighted mean chroma)
measures HUE DISTRIBUTION, not channel imbalance. It answers "does the scene contain more
warm-hued objects?" — not "are the highlights warm?". These diverge in mixed scenes (warm
foreground, cool sky). Insufficient for precise highlight temperature correction.

**Better approach: White-Patch Retinex variant.**
Literature (Finlayson & Trezzi "Shades of Grey"; MATLAB illumwhite) establishes that
highlight-restricted illuminant estimation outperforms global grey-world for scenes with
dominant coloured objects. Restrict the measurement to pixels above p75 luma:

```
warm_bias = (mean_R_hi − mean_B_hi) / (mean_R_hi + mean_B_hi + ε)
```

Where mean_R_hi / mean_B_hi are the mean red and blue channel values for pixels
where luma > p75. This is a direct chromatic adaptation signal for the highlight range.
Result is in [−1, 1]: positive = warm highlights, negative = cool highlights.

---

## Q2: Highlight restriction — resolved: p75 luma threshold

p75 is already Kalman-smoothed in PercTex.b. Using it as the highlight floor:
- Restricts the warm_bias to the top quartile of scene luminance
- Tracks the correct pixel population (near-white specular and bright diffuse surfaces)
- Temporal stability inherited from Kalman p75 smoothing

Global grey-world (all pixels) is unreliable for game footage with large coloured surfaces.
Highlight-restricted is the correct choice.

---

## Q3: Storage — resolved: ChromaHistoryTex col 7

ChromaHistoryTex is 8×4 RGBA16F. Columns 0–5: hue band stats. Column 6: zone global
stats (R32). **Column 7 is free.** Store warm_bias EMA there: `.r = warm_bias`.

Kalman-smooth with same steady-state gain (KALMAN_K_INF) used for chroma bands.
This prevents pumping on scene cuts — same temporal budget as all other history textures.

---

## Q4: Smoothstep range — resolved from linear-light R-B expectations

Typical linear-light R-B differences:
- Neutral scene (D65): R-B ≈ 0.00
- Warm indoor tungsten: R-B ≈ 0.05–0.10
- Strong tungsten / firelight: R-B ≈ 0.12–0.20
- Cool overcast/shade: R-B ≈ −0.05 to −0.10

Mapping to correction strength:
```hlsl
float warm_bias   = tex2D(ChromaHistory, float2(7.5 / 8.0, 0.5 / 4.0)).r;
float auto_hl_t   = lerp(0.0, -30.0, smoothstep(0.02, 0.12, warm_bias));
// Symmetric cool correction
float auto_hl_t_c = lerp(0.0, +20.0, smoothstep(0.02, 0.10, -warm_bias));
float hl_temp_auto = auto_hl_t + auto_hl_t_c;
```

Cap: `clamp(hl_temp_auto, -35.0, +25.0)` — prevents runaway in extreme scenes.

---

## Q5: Pro_mist sharing — resolved: bind ChromaHistoryTex col 7 in pro_mist

ChromaHistoryTex is not currently bound in pro_mist.fx. Adding it costs one sampler
declaration and one tex2Dlod call. No new texture, no new pass. The scatter weights
then adapt:

```hlsl
float warm_bias_pm = tex2Dlod(ChromaHistSamp, float2(7.5 / 8.0, 0.5 / 4.0, 0, 0)).r;
float scatter_r    = lerp(1.05, 1.00, smoothstep(0.02, 0.12, warm_bias_pm));
float scatter_b    = lerp(0.92, 1.00, smoothstep(0.02, 0.12, warm_bias_pm));
// Warm scene → neutral scatter; cool scene → warm scatter (film character preserved)
```

---

## Q6: Manual HIGHLIGHT_TEMP interaction — resolved: additive, auto is baseline

The auto correction becomes the baseline; manual HIGHLIGHT_TEMP offsets from it:

```hlsl
// grade.fx Stage 1 — replace fixed HIGHLIGHT_TEMP with:
float hl_temp_final = HIGHLIGHT_TEMP + hl_temp_auto;
float3 r19_hl_delta = float3(+hl_temp_final + HIGHLIGHT_TINT * 0.5,
                             -HIGHLIGHT_TINT,
                             -hl_temp_final + HIGHLIGHT_TINT * 0.5) * r19_scale;
```

When HIGHLIGHT_TEMP = 0 (passthrough): auto drives correction fully.
When HIGHLIGHT_TEMP ≠ 0: user offsets from the auto baseline. Intuitive.

---

## Implementation plan

### Step 1 — corrective.fx: compute warm_bias in UpdateHistoryPS

In the UpdateHistoryPS pass (already reads BackBuffer + PercTex), add highlight-restricted
R-B accumulation across all pixels. Write EMA-smoothed warm_bias to ChromaHistoryTex col 7.

```hlsl
// In UpdateHistoryPS — accumulate over all pixels via fullscreen pass
// NOTE: this pass currently writes per-band — restructure to also write col 7
// OR: add a dedicated single-pixel WarmBiasPS pass (cheapest — 1 fullscreen tap → 1×1)
```

The cleanest approach: a new single-pixel pass in corrective.fx that reads the
CreativeLowFreqTex (already a 1/8-res version of the scene) and computes mean R and B
for texels above p75 luma. CreativeLowFreqTex has luma in .a — already available.

```hlsl
float4 WarmBiasPS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    // Only compute at pixel (7, 0) — col 7 of ChromaHistoryTex
    if (pos.x < 7.0 || pos.x >= 8.0 || pos.y >= 1.0) {
        return tex2D(ChromaHistory, uv);  // pass through other cols unchanged
    }
    float p75 = tex2Dlod(PercSamp, float4(0.5, 0.5, 0, 0)).b;
    float sum_r = 0.0, sum_b = 0.0, sum_w = 0.0;
    // Sample CreativeLowFreqTex (1/8 res) — cheap, ~64 samples covers full frame
    for (int y = 0; y < 8; y++) {
        for (int x = 0; x < 8; x++) {
            float2 uv_s = float2((x + 0.5) / 8.0, (y + 0.5) / 8.0);
            float4 s    = tex2Dlod(CreativeLowFreqSamp, float4(uv_s, 0, 0));
            float  w    = step(p75, s.a);  // weight 1 if luma > p75, 0 otherwise
            sum_r += s.r * w;
            sum_b += s.b * w;
            sum_w += w;
        }
    }
    float mean_r   = sum_r / max(sum_w, 1.0);
    float mean_b   = sum_b / max(sum_w, 1.0);
    float wb_curr  = (mean_r - mean_b) / max(mean_r + mean_b, 0.001);
    float prev_wb  = tex2D(ChromaHistory, uv).r;
    float wb_smooth = lerp(prev_wb, wb_curr, KALMAN_K_INF);
    return float4(wb_smooth, 0.0, 0.0, 0.0);
}
```

This uses `step()` instead of a dynamic branch (no gate) and samples CreativeLowFreqTex
which is already bound and free — no new texture reads from the full BackBuffer.

### Step 2 — grade.fx: inject auto highlight temp

At the existing HIGHLIGHT_TEMP line (grade.fx ~line 229), add:
```hlsl
float warm_bias  = tex2D(ChromaHistory, float2(7.5 / 8.0, 0.5 / 4.0)).r;
float hl_auto    = clamp(lerp(0.0, -30.0, smoothstep(0.02, 0.12,  warm_bias))
                       + lerp(0.0, +20.0, smoothstep(0.02, 0.10, -warm_bias)), -35.0, 25.0);
float hl_temp_f  = HIGHLIGHT_TEMP + hl_auto;
// Replace HIGHLIGHT_TEMP with hl_temp_f in r19_hl_delta
```

### Step 3 — pro_mist.fx: bind ChromaHistoryTex, adapt scatter weights

Add ChromaHistoryTex sampler declaration. Replace fixed scatter weights with adaptive ones.

---

### Step 3 — pro_mist.fx: adapt scatter weights and halation weights

WarmBiasTex sampler added. Scatter weights and halation chromatic weights both adaptive:

```hlsl
// Scatter
float  warm_bias = tex2Dlod(WarmBiasSamp, float4(0.5, 0.5, 0, 0)).r;
float  scatter_r = lerp(1.05, 1.00, smoothstep(0.02, 0.12, warm_bias));
float  scatter_b = lerp(0.92, 1.00, smoothstep(0.02, 0.12, warm_bias));
result = base.rgb + scatter_delta * float3(scatter_r, 1.00, scatter_b) * adapt_str * luma_gate;

// Halation
float hal_r = lerp(1.20, 1.00, smoothstep(0.02, 0.12, warm_bias));
float hal_b = lerp(0.25, 0.50, smoothstep(0.02, 0.12, warm_bias));
result += delta_h * float3(hal_r, 0.60, hal_b) * auto_hal * halo_gate;
```

Warm scene → neutral scatter + less red halation bleed + more blue halation.
Cool scene → warm scatter + full red halation (cinematic character preserved).

### Architecture decision — 1×1 WarmBiasTex over ChromaHistoryTex col 7

ChromaHistoryTex col 7 approach from initial plan was rejected: UpdateHistoryPS zeroes
col 7 each frame (returns `float4(0,0,0,0)` for band_idx >= 7), destroying the EMA history.
A dedicated `WarmBiasTex` (1×1 RGBA16F) is the only texture that WarmBiasPS writes, so the
previous frame's value persists correctly between frames.

---

## Perceptual safety

| Property | Assessment |
|----------|-----------|
| Pumping on scene cuts | Prevented by EMA on warm_bias (KALMAN_K_INF = 0.095) |
| Overcorrection | Clamped to ±35 correction range |
| Artistic override | HIGHLIGHT_TEMP still works as additive offset |
| SDR ceiling | No luminance change — temperature correction is channel redistribution |
| New pass cost | 1×1 WarmBiasPS: 64 taps on 1/8-res CreativeLowFreqTex — negligible |

---

## Adaptive pipeline survey — conducted after R46 implementation

Full audit of remaining hardcoded chromatic assumptions, post R46:

| Stage | Fixed value | Signal | Status |
|-------|------------|--------|--------|
| pro_mist — scatter weights | `float3(1.05, 1.00, 0.92)` | warm_bias | **Implemented R46** |
| pro_mist — halation weights | `float3(1.20, 0.60, 0.25)` | warm_bias | **Implemented R46** |
| grade.fx — highlight temperature | None (zero) | warm_bias | **Implemented R46** |
| grade.fx — shadow temperature | None (SHADOW_TEMP = 0) | shadow R-B ratio (pixels < p25) | Candidate R47 |
| pro_mist — clarity multiplier | `1.10` fixed | zone_std (not bound in pro_mist) | Low priority |
| grade.fx — Naka-Rushton floor | `0.04` | p25 noise estimate | Low priority |
| FilmCurve knee/toe | User knobs | No — artistic intent | N/A |
| Abney hue offsets | Fixed perceptual model | No — scene-independent | N/A |

**R47 candidate: shadow colour temperature.**
Same architecture as warm_bias. Requires:
- ShadowBiasPS pass in corrective.fx — pixels below p25, R-B ratio
- 1×1 ShadowBiasTex
- grade.fx: inject sh_temp_auto into r19_sh_delta (symmetric correction, opposite sign)
