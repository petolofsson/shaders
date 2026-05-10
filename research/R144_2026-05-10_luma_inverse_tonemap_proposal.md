# R144 Proposal: Luma Expansion in InverseGradePS

**Date:** 2026-05-10
**Implements:** findings from R144_2026-05-10_luma_inverse_tonemap_findings.md
**Scope:** `general/inverse-grade/inverse_grade.fx` — InverseGradePS body only.
No other files change.

---

## Problem Statement

R90 (InverseGradePS) expands Oklab chroma (ab) using an IQR-derived slope but leaves Oklab L
(lightness) unchanged. The game's tonemapper compressed both L and C together. Restoring C
without restoring L breaks the C/L ratio: colors appear more saturated than their luminance
would naturally support. This violates the Hunt effect (perceived colorfulness scales with
luminance), producing perceptually incoherent midtones — especially visible in mid-dark tones
where chroma expansion is strongest (mid_weight peak at Oklab L ≈ 0.50).

At slope = 1.3 (typical value), the C/L ratio error after chroma-only expansion is +7%. Joint
expansion reduces this to under 0.5%.

---

## Algorithm

### Pivot conversion

The highway stores p50 in **linear Rec709 luma space** (HWY_P50 = x = 195). Oklab L is a
perceptual lightness (cube-root compressed). To pivot luma expansion around the actual scene
median in Oklab L space, convert via cube root:

```
p50_lab ≈ cbrt(p50_linear)
```

For a neutral grey at linear Y = 0.50: p50_lab ≈ 0.794 (the scene median in Oklab L space).
Using raw p50_linear (= 0.50) as the Oklab L pivot would place the zero-crossing at Oklab L =
0.50, which is a dark shadow (linear Y ≈ 0.125), causing the entire midtone range to expand
upward and incorrectly brightening the scene.

### Luma factor vs chroma factor

Chroma factor (existing):
```hlsl
float factor = lerp(1.0, slope, float(INVERSE_STRENGTH) * mid_weight * c_weight);
```

Luma factor (new) — c_weight is **omitted**:
```hlsl
float luma_factor = lerp(1.0, slope, float(INVERSE_STRENGTH) * mid_weight);
```

`c_weight = saturate((C − 0.10) / 0.15)` gates chroma expansion to chromatic pixels only
(near-neutrals have no meaningful chroma to expand). For luma, the game's tonemapper compressed
every pixel's luma equally, including neutrals. Applying c_weight to luma_factor would leave
grey walls and white skies with unrestored luma while their neighbors with slight color got
expanded — a visible spatial inconsistency.

### Expansion formula

Mirrors the chroma formula: expand around the pivot, apply the factor.

```hlsl
float new_L = p50_lab + (lab.x - p50_lab) * luma_factor;
lab.x = max(new_L, 0.0);
```

`max(..., 0.0)` is a defensive guard. The mid_weight bell gate (`L * (1−L) * 4`) has an exact
zero-preservation property: at Oklab L = 0 mid_weight = 0, factor = 1.0, so new_L = p50_lab +
(0 − p50_lab) · 1.0 = 0.0 exactly. Negative values cannot occur in practice, but the guard
matches the existing pattern for `new_C`.

Highlights are bounded by `saturate()` at the end of the function (already present). At L = 1.0,
mid_weight = 0, factor = 1.0, new_L = 1.0 exactly — pure white is preserved without saturate().

---

## Exact HLSL pseudocode (diff against current InverseGradePS)

Lines that change are marked. Unchanged lines shown for context.

```hlsl
float4 InverseGradePS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float4 col = tex2D(BackBuffer, uv);
    if (pos.y < 1.0) return col;
    if (INVERSE_STRENGTH <= 0.0) return col;
    float slope_enc  = ReadHWY(HWY_SLOPE);
    float slope      = max(slope_enc * 1.5 + 1.0, 1.15);
    float3 lab       = RGBtoOklab(col.rgb);
    float  C         = length(lab.yz);
    float  mid_weight = lab.x * (1.0 - lab.x) * 4.0;
    float  c_weight   = saturate((C - 0.10) / 0.15);
    float  mean_C     = tex2Dlod(MeanChromaSamp, float4(0.5, 0.5, 0, 0)).r;
    float  factor     = lerp(1.0, slope, float(INVERSE_STRENGTH) * mid_weight * c_weight);
    float2 dir        = lab.yz / max(C, 1e-5);
    float  new_C      = mean_C + (C - mean_C) * factor;
    float hue = frac(atan2(lab.z, lab.y) / 6.28318530);
    new_C     = min(new_C, max(HueCeil(hue), C));
    lab.yz    = dir * max(new_C, 0.0);

    // ++ NEW: luma expansion — restore L compressed by the game's tonemapper.
    // pivot in Oklab L space: cbrt(p50_linear) ≈ Oklab L for neutral at the scene median.
    // c_weight excluded: all pixels have compressed luma, including near-neutrals.
    float p50_lin     = ReadHWY(HWY_P50);                                     // NEW
    float p50_lab     = exp2(log2(max(p50_lin, 1e-10)) * (1.0 / 3.0));       // NEW
    float luma_factor = lerp(1.0, slope, float(INVERSE_STRENGTH) * mid_weight); // NEW
    float new_L       = p50_lab + (lab.x - p50_lab) * luma_factor;            // NEW
    lab.x = max(new_L, 0.0);                                                   // NEW

    col.rgb   = saturate(OklabToRGB(lab));
    return col;
}
```

---

## Numeric Examples

### Canonical midtone, slope = 1.30, INVERSE_STRENGTH = 0.50, p50_lin = 0.45

`p50_lab = cbrt(0.45) ≈ 0.766`

| Oklab L | mid_weight | luma_factor | new_L | delta |
|---|---|---|---|---|
| 0.55 | 0.990 | 1.124 | 0.523 | −0.027 |
| 0.65 | 0.910 | 1.114 | 0.637 | −0.013 |
| 0.75 | 0.750 | 1.094 | 0.748 | −0.002 |
| 0.80 | 0.640 | 1.080 | 0.803 | +0.003 |
| 0.90 | 0.360 | 1.054 | 0.911 | +0.011 |

The zero-crossing (no shift) is at Oklab L = p50_lab = 0.766, which corresponds to the scene
median luminance. Pixels below the median darken slightly (shadow expansion), pixels above
brighten slightly (highlight expansion).

### Shadow safety at slope = 1.30, IS = 1.0, p50_lab = 0.794

| Oklab L | mid_weight | luma_factor | new_L |
|---|---|---|---|
| 0.02 | 0.078 | 1.023 | 0.021 |
| 0.05 | 0.190 | 1.057 | 0.050 |
| 0.10 | 0.360 | 1.108 | 0.096 |
| 0.00 | 0.000 | 1.000 | 0.000 |

Shadows compress only marginally. Pure black (L = 0) is mathematically preserved.

---

## New Knobs Needed in creative_values.fx

**None.**

INVERSE_STRENGTH is shared between chroma and luma expansion. This is the correct first
implementation because both L and C were compressed by the same tonemapper event. If testing
shows the joint expansion at current INVERSE_STRENGTH (0.50) is too aggressive, the internal
attenuation can be added as a compile-time constant without a new user knob.

The creative_values.fx comment for INVERSE_STRENGTH will need updating to note that it now
controls both luma and chroma expansion. That comment edit requires explicit approval before
implementation (per CLAUDE.md rule: never modify shader header comments without approval).

---

## What Does NOT Change

- `factor` (chroma expansion factor): unchanged. c_weight remains in the chroma path.
- `new_C` computation: unchanged.
- `HueCeil` guard on chroma: unchanged. Luma has no per-hue ceiling — saturate() suffices.
- MeanChromaSamp read: unchanged.
- `saturate(OklabToRGB(lab))`: unchanged — it is the SDR ceiling for both L and C.
- All other effects: no changes.
- Highway layout: no new slots needed. HWY_P50 (x = 195) already exists and is populated by
  analysis_frame in the correct position in the chain.
- `code_rules.md`: no new SPIR-V concerns. `exp2(log2(...) * ...)` is the existing cbrt pattern
  from common.fxh. No new variable names conflict with reserved keywords.

---

## Estimated Line Count Impact

InverseGradePS body currently has ~19 lines. This adds 5 lines (p50_lin read, p50_lab convert,
luma_factor, new_L, lab.x assignment). Total after: ~24 lines. The technique block is
unchanged.

---

## Open Questions Before Implementing

1. **INVERSE_STRENGTH re-tuning.** The current value of 0.50 was calibrated for chroma-only
   expansion. Joint expansion at 0.50 will make the grade feel slightly brighter and more
   contrasty. Recommend testing with INVERSE_STRENGTH reduced to 0.35–0.40 initially and
   re-tuning EXPOSURE.

2. **creative_values.fx comment update.** The current INVERSE_STRENGTH comment says "Expands
   display IQR... Oklab chroma expansion." After implementation, it should say "luma and chroma
   expansion." This requires explicit approval.

3. **Luma expansion scale constant.** If testing reveals that luma expansion needs to be weaker
   than chroma expansion (e.g., 70% of chroma strength), a `LUMA_EXPANSION_SCALE` constant
   (not a user knob) can be added to luma_factor: `lerp(1.0, slope, float(INVERSE_STRENGTH) *
   mid_weight * LUMA_EXPANSION_SCALE)`. This question cannot be answered without visual testing.

4. **Dark-game pivot behavior.** For scenes with p50_lin < 0.30 (very dark games), p50_lab <
   0.669 and most of the visible range is above the pivot. Nearly all pixels will expand upward.
   This is mathematically correct (the game's tonemapper compressed everything) but the perceived
   result may be a noticeable brightness jump. Worth testing specifically on dark scenes.

5. **Verification of c_weight exclusion.** The absence of c_weight from luma_factor means near-
   grey pixels (smooth walls, mist, fog) will have their luma expanded. If such areas show
   visible banding or brightness stepping after expansion, it may indicate that the slope
   measurement is noisy for low-chroma scenes. The Kalman filter on p50 should prevent this,
   but confirm with observation.
