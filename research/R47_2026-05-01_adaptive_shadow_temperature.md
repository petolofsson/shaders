# R47 — Adaptive Shadow Colour Temperature

**Date:** 2026-05-01
**Status:** Implemented — disabled pending validation

---

## Problem

Same principle as R46 (highlight colour temperature) applied to the shadow zone.
The 3-way corrector's SHADOW_TEMP was fixed at 0 — no scene awareness. In scenes
with a strong chromatic light source, shadows can develop an unintended warm or cool
bias introduced by the pipeline. The same highlight-restricted R-B ratio approach
used in R46 can be applied to the shadow range.

---

## Signal: shadow-restricted R-B ratio

Restrict the R-B measurement to pixels below p25 luma (the bottom quartile):

```
shadow_bias = (mean_R_lo − mean_B_lo) / (mean_R_lo + mean_B_lo + ε)
```

Where mean_R_lo / mean_B_lo are mean red and blue values for pixels where luma < p25.
Result in [−1, 1]: positive = warm shadows, negative = cool shadows.

p25 is already Kalman-smoothed in PercTex.r — inherited temporal stability.

---

## Implementation

### Step 1 — corrective.fx: ShadowBiasPS pass

Mirrors WarmBiasPS exactly, but uses `step(s.a, p25)` to select shadow pixels
(luma <= p25) instead of `step(p75, s.a)` for highlight pixels.

```hlsl
float4 ShadowBiasPS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float p25     = tex2Dlod(PercSamp,       float4(0.5, 0.5, 0, 0)).r;
    float prev_sb = tex2Dlod(ShadowBiasSamp, float4(0.5, 0.5, 0, 0)).r;

    float sum_r = 0.0, sum_b = 0.0, sum_w = 0.0;
    [unroll] for (int sy = 0; sy < 8; sy++)
    [unroll] for (int sx = 0; sx < 8; sx++)
    {
        float2 uv_s = float2((sx + 0.5) / 8.0, (sy + 0.5) / 8.0);
        float4 s    = tex2Dlod(CreativeLowFreqSamp, float4(uv_s, 0, 0));
        float  wt   = step(s.a, p25);  // pixels at or below p25
        sum_r += s.r * wt;
        sum_b += s.b * wt;
        sum_w += wt;
    }

    float mean_r    = sum_r / max(sum_w, 1.0);
    float mean_b    = sum_b / max(sum_w, 1.0);
    float sb_curr   = (mean_r - mean_b) / max(mean_r + mean_b, 0.001);
    float sb_smooth = lerp(prev_sb, sb_curr, KALMAN_K_INF);
    return float4(sb_smooth, 0.0, 0.0, 1.0);
}
```

Stored in ShadowBiasTex (1×1 RGBA16F) — same architecture as WarmBiasTex.

### Step 2 — grade.fx: inject into r19_sh_delta

```hlsl
float shadow_bias  = tex2Dlod(ShadowBiasSamp, float4(0.5, 0.5, 0, 0)).r;
float sh_temp_auto = clamp(lerp(0.0, -20.0, smoothstep(0.02, 0.12,  shadow_bias))
                         + lerp(0.0, +15.0, smoothstep(0.02, 0.10, -shadow_bias)), -22.0, 18.0);
float sh_temp_f    = SHADOW_TEMP + sh_temp_auto;
```

---

## Correction ranges

Smaller than R46 — shadows are perceptually less sensitive to chromatic shifts
(Purkinje effect, rod dominance in dark regions) and shadow temperature is more
often intentional artistic character (candlelight warmth, moonlight cool).

| Direction | Range | Clamp |
|-----------|-------|-------|
| Warm shadows → cool | 0 to −20 | −22 |
| Cool shadows → warm | 0 to +15 | +18 |

---

## Status and findings

Implemented and then disabled during the same session. Root problem identified:
the R-B ratio signal measures the chromatic character of shadow pixels, but in UI
and inventory screens (which dominate p25 in dark-background UIs), the signal
reads incorrectly — dark UI chrome and slot backgrounds are not scene shadows.

R46 suffered the same issue: yellow ammo box UI assets dominated the warm_bias
signal, causing overcorrection. Both R46 and R47 auto corrections were disabled
in grade.fx pending a more reliable scene-content gate.

**Infrastructure retained:** WarmBiasTex, ShadowBiasTex, WarmBiasPS, ShadowBiasPS
remain in corrective.fx. The signal is valid for gameplay scenes (non-UI). A
future gate (e.g., scene complexity threshold via zone_std) could re-enable
the correction only when the scene has sufficient spatial structure to make the
R-B ratio meaningful.
