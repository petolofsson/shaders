# R195 — Scene Entropy + IQR Highway Signals

**Date:** 2026-05-14
**Status:** Implementation ready

---

## Motivation

R193 (nightly, 2026-05-14) identified three new histogram descriptors for the analysis
pipeline. R195 promotes the two implement-ready findings (H_norm entropy and IQR) into
code. Mode–median distance (R193 F3) is deferred — no validated real-time consumer
identified.

**Core problem:** The pipeline currently adapts zone S-curve slope via `zone_std` (local
per-zone heterogeneity). `zone_std` is blind to the *global* tonal distribution shape.
Two scenes can share identical `zone_std`, `zone_key`, and Bowley skewness while differing
dramatically in how luminance mass is distributed across the 64 histogram bins — flat and
film-like vs. spiked and artificial. H_norm captures exactly this distinction.

---

## Finding 1 — Normalized histogram entropy (H_norm)

### Formula

```
H_norm = −[ Σ_{i=0}^{63} h_i · log₂(max(h_i, 1e-6)) ] / log₂(64)
```

`h_i`: normalized histogram bin (sums to 1.0, already computed by LumHistSmoothPS).
Division by log₂(64) = 6.0 maps to [0, 1].

H_norm ∈ [0, 1]:
- 0.0 — all mass at one luminance level (fog, overexposure, pure test signal)
- 1.0 — perfectly uniform distribution (test chart)
- 0.25–0.45 — night exterior, heavy underexposure
- 0.35–0.55 — dark interior
- 0.70–0.85 — typical outdoor scene

### Use in grade.fx

Zone S-curve strength modulation in `BuildSceneCtx`:

```hlsl
float h_norm  = ReadHWY(HWY_H_NORM);
// High entropy: rich tonal content already well-distributed — attenuate zone stretch.
// Low entropy: compressed distribution — safe to apply harder redistribution.
float h_att   = lerp(1.0, 0.75, saturate((h_norm - 0.55) / 0.30));
ctx.zone_str *= h_att;
```

At h_norm = 0.55: h_att = 1.0 (no change). At h_norm = 0.85: h_att = 0.75 (25%
attenuation). Below 0.55: h_att = 1.0 (dark/low-entropy scenes get full stretch).

The gate at 0.55 means the attenuation only fires above typical "good" scene entropy —
it is a ceiling, not a floor.

### Implementation — analysis_frame.fx

New 1×1 texture + new pass, inserted after `LumHistSmoothPS`:

```hlsl
texture2D EntropyTex { Width = 1; Height = 1; Format = R16F; MipLevels = 1; };
sampler2D EntropySamp { Texture = EntropyTex; AddressU = CLAMP; AddressV = CLAMP;
                        MinFilter = POINT; MagFilter = POINT; };

float4 HistEntropyPS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float H = 0.0;
    [loop] for (int b = 0; b < 64; b++)
    {
        float h  = tex2Dlod(LumHistSamp, float4((float(b) + 0.5) / 64.0, 0.5, 0, 0)).r;
        H       -= h * log2(max(h, 1e-6));
    }
    float h_norm = saturate(H / 6.0);
    float prev   = tex2Dlod(EntropySamp, float4(0.5, 0.5, 0, 0)).r;
    float alpha  = saturate(frametime * 0.002);
    return float4(lerp(prev, h_norm, alpha), 0, 0, 1);
}
```

Highway write in `HighwayWritePS`:

```hlsl
#define HWY_H_NORM  207   // normalized histogram entropy [0, 1]

if (xi == HWY_H_NORM)
    return float4(tex2Dlod(EntropySamp, float4(0.5, 0.5, 0, 0)).r, 0, 0, 1);
```

H_norm ∈ [0, 1] — no encoding needed, fits highway unmodified.

### GPU cost

- 64 × tex2Dlod on 64×1 LumHist (L1-resident, effectively free)
- 64 × log2 + multiply-add + 1 divide ≈ 192 ALU ops
- 1 additional 1×1 RT write
- **< 0.01ms at 4K. Negligible.**

---

## Finding 2 — IQR as explicit highway slot

IQR = p75 − p25 is the canonical "scene contrast width" statistic. It is already
computed inline at three sites (Bowley denominator, diffusion `diff_ap_scale`,
grade.fx CLAHE delta). Promoting it to a named slot eliminates the inline duplication
and makes a clean scalar available to all downstream effects without an additional pass.

```hlsl
#define HWY_IQR  208   // IQR = p75 − p25 [0, 1]

if (xi == HWY_IQR) {
    float4 p = tex2Dlod(PercSamp, float4(0.5, 0.5, 0, 0));
    return float4(p.b - p.r, 0, 0, 1);
}
```

IQR ∈ [0, 1] naturally. Typical values:
- 0.02–0.05: flat indoor lighting
- 0.10–0.20: typical outdoor
- 0.25–0.45: interior + bright window

**GPU cost: ~2 tex2Dlod (shared with adjacent slots) + 1 subtract. Effectively 0.**

---

## Finding 3 — Mode–median distance (deferred)

Deferred. No peer-reviewed real-time implementation found. No confirmed consuming
expression in grade.fx. Revisit if a concrete use case is identified.

---

## SPIR-V compliance checklist

- No `static const float[]` — loop uses scalar `float h` ✓
- No `out` as variable name ✓
- `tex2Dlod` on within-technique `LumHistSamp` ✓ (not BackBuffer)
- H_norm ∈ [0, 1] — no highway encoding needed ✓
- No gates; h_att modulation is continuous ✓
- No auto-exposure involvement ✓

---

## Files to touch

| File | Change |
|------|--------|
| `general/analysis-frame/analysis_frame.fx` | Add `EntropyTex` + `EntropySamp`; add `HistEntropyPS` pass after LumHistSmoothPS; add HWY_H_NORM and HWY_IQR writes to HighwayWritePS |
| `general/highway.fxh` | Add `#define HWY_H_NORM 207` and `#define HWY_IQR 208` with encode/decode notes |
| `general/grade/grade.fx` | In `BuildSceneCtx`: read HWY_H_NORM, compute `h_att`, apply to `ctx.zone_str` |

No changes to creative_values.fx — H_norm and IQR are internal signals, not user knobs.

---

## Calibration expectations

`ctx.zone_str` currently interpolates `lerp(0.26, 0.16, ss_08_25)` driven by `zone_std`.
The H_norm attenuation multiplies the result. Effect is additive with `zone_std`
modulation — both can fire simultaneously, and neither gates the other. In practice:

- Bright outdoor scenes (high entropy, ~0.80): zone_str attenuated ~20–25%.
  These scenes already have wide dynamic range; the S-curve can afford to be softer.
- Dark interiors (low entropy, ~0.40): no attenuation. Shadow contrast stretch runs
  at full `zone_std`-modulated strength.
- Night scenes (very low entropy, ~0.30): no attenuation. Maximum zone stretch.

No re-tuning of CONTRAST expected — the H_norm gate is additive to the existing
`zone_std` path, not a replacement.
