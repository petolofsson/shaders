# R142 — ColorTransformPS Stage Split (F4-A)

**Date:** 2026-05-10
**Status:** Plan only — not implemented
**Scope:** `general/grade/grade.fx` — ColorTransformPS only

---

## Problem

ColorTransformPS is ~350 lines (post-R139 helper extractions). Rule 4 ≤60 lines.
Three named stages exist in comments (CORRECTIVE / TONAL / CHROMA) but all inline.
Goal: make ColorTransformPS a ~50-line orchestrator that calls three named helpers.

---

## Two kinds of data inside the function

### A — Scene constants (uniform across all pixels this frame)
Texture fetches that return the same value for every UV:

| Variable | Source |
|---|---|
| `lms_illum_norm` | `NeutralIllumSamp` (1×1) |
| `perc` | `PercSamp` (1×1) |
| `scene_cut` | `ReadHWY(HWY_SCENE_CUT)` |
| `zone_log_key`, `zone_std` | `ChromaHistory` col 6 |
| `slow_key` | `ChromaHistory` col 7 |
| `fc_stevens` | `ReadHWY(HWY_STEVENS)` |
| Derived: `eff_p25`, `eff_p75`, `ss_08_25`, `ss_04_25`, `spread_scale`, `zone_str`, `lum_att` | from above |
| Derived: all FilmCurve coefficients (`fc_knee`, `fc_factor`, `fc_knee_r/b`, etc.) | from above |
| Derived: `shadow_lift_str` | from `perc` |
| Derived: `chroma_str_base` | from `zone_log_key` + `CHROMA_STR` |
| Derived: `cfilm_floor` | from `lms_illum_norm` |

These go into a `SceneCtx` struct, built once at the top of ColorTransformPS.

### B — Per-pixel values (UV-dependent or derived from `lin`)
| Variable | Origin | Stage |
|---|---|---|
| `lf_mip2` | `LowFreqMip2Samp(uv)` | CORRECTIVE (halation), TONAL (R66), CHROMA (R117C) |
| `lf_mip1` / `illum_s0` | `LowFreqMip1Samp(uv)` | TONAL only |
| `zone_lvl` | `ZoneHistorySamp(uv)` | TONAL only |
| `col_luma` | `Luma(col.rgb)` | TONAL (fine_var) |
| `lin` | evolves through all stages | — |
| `new_luma` | computed in TONAL | consumed in CHROMA |
| `local_var` | computed in TONAL | consumed in CHROMA (chroma_str spatial mod) |

`lf_mip2` is needed by all three stages — hoist it to ColorTransformPS and pass it down.
`lf_mip1`, `zone_lvl`, `col_luma` are TONAL-only — fetch inside ApplyTonal.
`new_luma` and `local_var` are the only pixel-derived cross-stage outputs (TONAL → CHROMA).

---

## Proposed structures

```hlsl
struct SceneCtx {
    // Illuminant
    float3 lms_illum_norm;
    float3 cfilm_floor;
    // Percentiles / zone
    float4 perc;
    float  eff_p25, eff_p75;
    float  zone_log_key, zone_std, zone_str;
    float  ss_08_25, ss_04_25;
    float  scene_cut;
    float  slow_key;
    // FilmCurve
    float  fc_knee,   fc_knee_r,  fc_knee_b;
    float  fc_knee_toe, fc_ktoe_r, fc_ktoe_b;
    float  fc_factor, fc_toe_fac, fc_stevens;
    // Shadow lift
    float  shadow_lift_str;
    // Chroma
    float  chroma_str_base;
};

struct TonalOut {
    float3 lin;
    float  new_luma;
    float  local_var;
};
```

---

## Proposed function signatures

```hlsl
SceneCtx BuildSceneCtx();
// All scene-uniform fetches + derived scalars. No UV dependency.

float3 ApplyCorrective(float3 lin, float2 uv, float4 lf_mip2_tex, SceneCtx ctx);
// Input:  lin = pow(col.rgb, EXPOSURE) + film floor applied
// Output: lin after FilmCurve + DIR + halation + print stock +
//         masking coupler + dye matrix + bleach bypass + 3-way CC
// Uses lf_mip2_tex.rgb for halation. ~25 lines — mostly calls to already-extracted helpers

TonalOut ApplyTonal(float3 lin, float col_luma, float2 uv, float4 lf_mip2_tex, SceneCtx ctx);
// Input:  lin post-CORRECTIVE
// Output: TonalOut { lin, new_luma, local_var }
// Uses lf_mip2_tex.rgb (R66 ambient tint) and lf_mip2_tex.a as illum_s2 (Retinex far scale).
// Fetches lf_mip1/illum_s0 and zone_lvl internally (TONAL-only).
// ~55 lines (zone S-curve, Retinex, shadow lift, R62 Oklab tonal, R65 Hunt, R66 ambient tint)

float3 ApplyChroma(float3 lin, float new_luma, float local_var,
                   float4 lf_mip2_tex, SceneCtx ctx);
// Input:  lin post-TONAL, new_luma + local_var from TonalOut
// Output: lin post-CHROMA (ready for dither + return)
// ~80 lines (Purkinje, R22, R133, R21, chroma lift, memory colors,
//            ceilings, vibrance, HK, Abney, R117C induction, density, gamut)
```

---

## ColorTransformPS after refactor

```hlsl
float4 ColorTransformPS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float4 col = tex2D(BackBuffer, uv);
    if (pos.y < 1.0) { /* highway write block — unchanged, ~25 lines */ }

    SceneCtx ctx       = BuildSceneCtx();
    float4 lf_mip2_tex = tex2D(LowFreqMip2Samp, uv);  // .rgb = colour, .a = illum_s2 (Retinex)

    float  col_luma = Luma(col.rgb);
    float3 lin      = col.rgb * (FILM_CEILING - ctx.cfilm_floor) + ctx.cfilm_floor;
    lin = ApplyCorrective(lin, uv, lf_mip2_tex, ctx);

    TonalOut tonal = ApplyTonal(lin, col_luma, uv, lf_mip2_tex, ctx);
    float3 result  = ApplyChroma(tonal.lin, tonal.new_luma, tonal.local_var, lf_mip2_tex, ctx);

    float dither = frac(52.9829189 * frac(dot(pos.xy, float2(0.06711056, 0.00583715)))) - 0.5;
    result = saturate(result + dither * (1.0 / 255.0));

    return DrawLabel(float4(result, col.a), pos.xy, 270.0, 50.0,
                     54u, 71u, 82u, 65u, float3(0.2, 0.50, 1.0)); // 6GRA
}
```

ColorTransformPS: ~50 lines. Under the 60-line limit.

---

## Estimated stage sizes after split

| Helper | Est. lines | Notes |
|---|---|---|
| `BuildSceneCtx` | ~35 | All uniform fetches + derived scalars |
| `ApplyCorrective` | ~25 | Mostly helper calls, already extracted |
| `ApplyTonal` | ~55 | At limit — acceptable |
| `ApplyChroma` | ~80 | Still over; secondary target if needed |
| `ColorTransformPS` | ~50 | Under limit ✓ |

`ApplyChroma` at ~80 lines is the secondary concern. It could be split further into
`ApplyChromaLift` (Purkinje → vibrance, ~45 lines) + `ApplyChromaFinish` (HK → gamut, ~40 lines),
but that increases cross-function state. Leave as a second pass if 80 lines proves unreadable.

---

## Risk assessment

| Risk | Likelihood | Mitigation |
|---|---|---|
| HLSL struct return (TonalOut) compiles correctly in SPIR-V | Low — structs are standard | Verify with test compile |
| SceneCtx fields grow unmanageable | Medium — 20+ fields today | Document which stage owns what |
| ApplyChroma still ~80 lines | Certain | Accept for now; document |
| Compiler fails to inline stage helpers (performance regression) | Very low — HLSL always inlines | None needed |
| `lf_mip2_tex.a` (illum_s2) needed by TONAL (Retinex) and CORRECTIVE has `.rgb` only | Must not split the fetch | All three signatures take `float4 lf_mip2_tex`; each extracts what it needs |

---

## What is NOT changing

- All already-extracted helpers (ApplyHalation, ApplyPrintStock, ApplyDyeMatrix, etc.) — untouched
- Highway write block — stays verbatim in ColorTransformPS
- Dither + DrawLabel — stays in ColorTransformPS
- No GPU cost change — compiler inlines all helpers regardless
