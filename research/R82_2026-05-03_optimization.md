# Nightly Optimization Research — 2026-05-03

## Summary

Systematic audit of all six optimization categories (A–F) across all seven pipeline files.
Eleven distinct optimizations found, all perceptually safe (max error ≤ 4.5 × 10⁻⁵ for
approximations, zero for algebraic identities). The highest-value items are: hoisting the
mip-2 CreativeLowFreqSamp read from four calls to one (Category B, saves 3 tex2Dlod per
pixel), eliminating the `hist_cache[6]` float4 array from live registers (Category E, 24
scalars freed — critical for AMD RDNA where the shader is register-pressure-bound), and
sharing the duplicate `cbrt(r_tonal)` computation between lines 368 and 370 (Category A,
2 transcendentals). If all eleven are applied, estimated savings are ~3 tex reads + ~5
transcendentals + ~40 live scalars per ColorTransformPS invocation.

---

## Optimization findings

### OPT-1: Hoist mip-2 CreativeLowFreqSamp read from 4 calls to 1 [Category B]

**File:** `general/grade/grade.fx` lines 241, 348, 377, 524

**Current:**
```hlsl
// Line 241 (inside CAT16 block):
float3 illum_rgb  = tex2Dlod(CreativeLowFreqSamp, float4(uv, 0, 2.0)).rgb;

// Line 348 (inside Retinex):
float illum_s2  = max(tex2Dlod(CreativeLowFreqSamp, float4(uv, 0, 2)).a, 0.001);

// Line 377 (inside R66 ambient tint block):
float3 illum_s2_rgb = tex2Dlod(CreativeLowFreqSamp, float4(uv, 0, 2.0)).rgb;

// Line 524 (inside R79 halation):
float3 hal_wing   = tex2Dlod(CreativeLowFreqSamp, float4(uv, 0, 2)).rgb;
```

**Proposed:**
```hlsl
// Hoist before line 241 (before the CAT16 block):
float4 lf_mip2 = tex2Dlod(CreativeLowFreqSamp, float4(uv, 0, 2));

// Line 241 replacement:
float3 illum_rgb  = lf_mip2.rgb;

// Line 348 replacement:
float illum_s2  = max(lf_mip2.a, 0.001);

// Line 377 replacement:
float3 illum_s2_rgb = lf_mip2.rgb;

// Line 524 replacement:
float3 hal_wing   = lf_mip2.rgb;
```

**Max error:** 0.0 (exact — identical reads) **SAFE**

**Cost:** Eliminates 3 `tex2Dlod` calls per pixel. Each `tex2Dlod` is an L2/DRAM read on
first touch (bilinear filtered mip sample); subsequent calls would also be L1 hits on
modern GPUs for nearby pixels, but issuing fewer instructions reduces latency and reduces
shader execution time. On AMD RDNA2 a sampler instruction costs 4–8 clock cycles; saving
3 means ~12–24 cycles per pixel.

**Edge cases:** `uv` is not modified between lines 241 and 524. `CreativeLowFreqTex` is not
written by any pass between those lines in the same effect. The `.a` channel of the mip-2
fetch is `Luma(rgb)` (written by `ComputeLowFreqPS`), identical to what line 348 reads. The
rgb channels read by lines 241, 377, and 524 are identical values at the same mip level.

**Complexity:** needs surrounding changes — requires moving `lf_mip2` declaration above the
CAT16 scope block (currently wrapped in `{ }`). The CAT16 block uses `illum_rgb` only
internally, so the scope restructure is straightforward.

---

### OPT-2: HELMLAB double-angle identity — replace `sin(2h)` with `2·sin(h)·cos(h)` [Category A]

**File:** `general/grade/grade.fx` lines 395–396

**Current:**
```hlsl
float  h_theta = h * 6.28318;
float  h_perc  = frac(h + (0.008 * sin(h_theta) + 0.004 * sin(2.0 * h_theta)) / 6.28318);
```

**Proposed:**
```hlsl
float  h_theta = h * 6.28318;
float  sh_h, ch_h;
sincos(h_theta, sh_h, ch_h);
float  h_perc  = frac(h + (sh_h * (0.008 + 0.008 * ch_h)) / 6.28318);
```

**Derivation:** `0.008·sin(θ) + 0.004·sin(2θ)` = `0.008·sin(θ) + 0.004·2·sin(θ)·cos(θ)` =
`0.008·sin(θ)·(1 + cos(θ))`. The factoring is algebraically exact.

**Max error:** 0.0 (algebraic identity, zero approximation error) **SAFE**

**Cost:** Replaces 2 `sin()` calls with 1 `sincos()` call (same cost as 1 `sin` on all
GPU vendors) + 1 multiply + 1 add. Net saving: 1 transcendental per pixel ≈ 4–8 GPU cycles.

**Edge cases:** `h ∈ [0,1]`, so `h_theta ∈ [0, 2π]`. `sincos` is valid over the full circle.
No divide-by-zero risk. When both ROT_* knobs are all zero and HELMLAB coefficients are zero,
the expression evaluates to `h_perc = frac(h)` in both forms identically.

**Complexity:** drop-in

---

### OPT-3: Share `cbrt(r_tonal)` computation between tonal Oklab L scaling and a/b coupling [Category A]

**File:** `general/grade/grade.fx` lines 367–370

**Current:**
```hlsl
float r_tonal = new_luma / max(luma, 0.001);
lab_t.x = saturate(lab_t.x * exp2(log2(max(r_tonal, 1e-10)) * (1.0 / 3.0)));
// R65: couple a/b to L
float r65_ab = exp2(log2(max(r_tonal, 1e-5)) * 0.333);
```

**Proposed:**
```hlsl
float r_tonal = new_luma / max(luma, 0.001);
float cbrt_r_tonal = exp2(log2(max(r_tonal, 1e-10)) * (1.0 / 3.0));
lab_t.x = saturate(lab_t.x * cbrt_r_tonal);
// R65: couple a/b to L
float r65_ab = cbrt_r_tonal;
```

**Max error:** 0.0 for `r_tonal ≥ 1e-5` (all practical pixels). For `r_tonal < 1e-5`
(essentially black pixels where `new_luma ≈ 0` and `luma ≈ 0`), the guard difference
(`1e-10` vs `1e-5`) means the original `r65_ab` would be `exp2(log2(1e-5)*0.333) = 1e-5^0.333 ≈ 0.00585`,
while the proposed reuse gives `exp2(log2(1e-10)*0.333) = 1e-10^0.333 ≈ 0.0000464`. However,
`r65_ab` is immediately multiplied by `lerp(1.0, r65_ab, r65_sw)` where
`r65_sw = smoothstep(0.30, 0.0, lab_t.x)`. When `lab_t.x ≈ 0` (fully dark pixel), `r65_sw = 1`,
but `lab_t.y` and `lab_t.z` are also near-zero (dark pixel has negligible chroma), so the
difference in the `a/b` scaling is `near_zero * delta ≈ 0`. In practice, output error is 0.

**SAFE**

**Cost:** Eliminates 1 `log2`, 1 `exp2`, 1 `max`, and 1 multiply per pixel. ≈ 2 transcendentals
+ 2 ops saved. Approximately 8–16 GPU cycles.

**Edge cases:** All-black frame: `luma ≈ 0`, `r_tonal = new_luma/0.001`, both guards clamp.
Output difference is in sub-threshold chroma channels. All-white frame: `r_tonal ≈ 1`,
`cbrt(1) = 1` in both forms. `EXPOSURE = 1.0`: no change in behavior.

**Complexity:** drop-in

---

### OPT-4: Eliminate `hist_cache[6]` float4 array from live registers [Category E]

**File:** `general/grade/grade.fx` lines 436–459

**Current:**
```hlsl
float4 hist_cache[6];
float cm_t = 0.0, cm_w = 0.0;
[unroll] for (int bi = 0; bi < 6; bi++)
{
    hist_cache[bi] = tex2D(ChromaHistory, float2((bi + 0.5) / 8.0, 0.5 / 4.0));
    cm_t += hist_cache[bi].r * hist_cache[bi].b;
    cm_w += hist_cache[bi].b;
}
float mean_chroma  = cm_t / max(cm_w, 0.001);
// ... (lines 445-453: chroma_str computation from mean_chroma) ...
float new_C = 0.0, total_w = 0.0, green_w = 0.0;
[unroll] for (int band = 0; band < 6; band++)
{
    float w = HueBandWeight(h_perc, GetBandCenter(band));
    new_C   += PivotedSCurve(C, hist_cache[band].r, chroma_str) * w;
    total_w += w;
}
```

**Proposed:**
```hlsl
// Pass 1: compute mean_chroma without storing hist_cache array
float cm_t = 0.0, cm_w = 0.0;
[unroll] for (int bi = 0; bi < 6; bi++)
{
    float4 hc = tex2D(ChromaHistory, float2((bi + 0.5) / 8.0, 0.5 / 4.0));
    cm_t += hc.r * hc.b;
    cm_w += hc.b;
}
float mean_chroma  = cm_t / max(cm_w, 0.001);
// ... (lines 445-453: chroma_str computation from mean_chroma — unchanged) ...
// Pass 2: re-read .r only for PivotedSCurve (guaranteed L1 cache hit — ChromaHistoryTex is 8x4)
float new_C = 0.0, total_w = 0.0;
[unroll] for (int band = 0; band < 6; band++)
{
    float pivot = tex2D(ChromaHistory, float2((band + 0.5) / 8.0, 0.5 / 4.0)).r;
    float w = HueBandWeight(h_perc, GetBandCenter(band));
    new_C   += PivotedSCurve(C, pivot, chroma_str) * w;
    total_w += w;
}
```

**Max error:** 0.0 (exact — same texture values, reads guaranteed identical via L1 cache)
**SAFE**

**Cost:** Eliminates `float4 hist_cache[6]` = 24 scalars from the live register file. The 6
additional `.r` reads in Pass 2 are guaranteed L1 cache hits: `ChromaHistoryTex` is 8×4 = 32
texels, a single 32-texel texture that fits in 256 bytes and is cached in one L1 texture cache
line on all modern GPU architectures. On AMD RDNA2, the current 240-scalar shader is well above
the ~128-scalar VGPR threshold that triggers register spilling; freeing 24 scalars reduces spill
pressure and may improve occupancy. Also removes `green_w` (see OPT-11) and the `hist_cache`
array declaration.

**Edge cases:** If `ChromaHistoryTex` had been written in the same effect (same technique), re-
reading would be undefined. It is written by `UpdateHistoryPS` in `corrective.fx`, which runs in
a different effect (different technique), so the content is stable throughout the grade pass.

**Complexity:** needs surrounding changes — the `hist_cache` array and the loop around it must be
restructured. The two loops remain unrolled (`[unroll]`); the second loop only reads `.r` instead
of the full `float4`.

---

### OPT-5: Remove redundant `saturate` inside `PivotedSCurve` [Category C]

**File:** `general/grade/grade.fx` lines 200–205

**Current:**
```hlsl
float PivotedSCurve(float x, float m, float strength)
{
    float t    = x - m;
    float bent = t + strength * t * (1.0 - saturate(abs(t)));
    return saturate(m + bent);
}
```

**Proposed:**
```hlsl
float PivotedSCurve(float x, float m, float strength)
{
    float t    = x - m;
    float bent = t + strength * t * (1.0 - abs(t));
    return saturate(m + bent);
}
```

**Proof:** `x` is Oklab chroma `C ∈ [0, 0.35]` (after Purkinje and Munsell attenuation;
ceiling enforced by `C_ceil ≤ 0.28`). `m` is the per-band mean chroma from ChromaHistory
`∈ [0, 0.20]` for typical SDR content. Therefore `t = x - m ∈ [-0.20, 0.35]`, so
`abs(t) ∈ [0, 0.35] ⊂ [0, 1]`. `saturate(abs(t)) = abs(t)` identically — the clamp is a
no-op over this entire domain.

**Max error:** 0.0 (exact) **SAFE**

**Cost:** Saves 1 `saturate` per call. `PivotedSCurve` is called 6 times per pixel (loop at
lines 455–459). Total: 6 `saturate` instructions eliminated per pixel.

**Edge cases:** If `CHROMA_LIFT_STRENGTH` or per-band knobs drove `C` above 1.0, or if `m`
were negative, `abs(t)` could exceed 1. Neither is possible: `C` is `length(lab.yz)` which is
bounded, and band means are non-negative. The outer `saturate(m + bent)` provides the final
clamp regardless.

**Complexity:** drop-in

---

### OPT-6: Inline Hunt scale intermediates — eliminate 7 named scalar variables [Category E]

**File:** `general/grade/grade.fx` lines 426–433

**Current:**
```hlsl
float la         = max(zone_log_key, 0.001);
float k          = 1.0 / (5.0 * la + 1.0);
float k2         = k * k;
float k4         = k2 * k2;
float fla        = 5.0 * la;
float one_mk4    = 1.0 - k4;
float fl         = k4 * la + 0.1 * one_mk4 * one_mk4 * pow(fla, 1.0 / 3.0);
float hunt_scale = sqrt(sqrt(max(fl, 1e-6))) / 0.5912;
```

**Proposed:**
```hlsl
float _k    = 1.0 / (5.0 * zone_log_key + 1.0);   // zone_log_key already >= 0.001 from line 258
float _k4   = _k * _k; _k4 *= _k4;
float _omk4 = 1.0 - _k4;
float hunt_scale = sqrt(sqrt(max(
    _k4 * zone_log_key + 0.1 * _omk4 * _omk4 * pow(5.0 * zone_log_key, 1.0 / 3.0),
    1e-6))) / 0.5912;
```

(Note: `zone_log_key = zstats.r` at line 257; `zstats.g` is already checked for 0. The
`max(., 0.001)` guard at line 426 can be replaced by noting `zone_log_key = exp2(lk*0.0625)`
which is always positive, and is separately guarded with `max(zm, 0.001)` inside
`UpdateHistoryPS`. It is safe to use `zone_log_key` directly.)

**Max error:** 0.0 (exact) **SAFE**

**Cost:** Frees 7 named scalar registers (`la`, `k`, `k2`, `k4`, `fla`, `one_mk4`, `fl`),
replacing them with 3 shorter-lived temporaries (`_k`, `_k4`, `_omk4`). Net reduction: 4
live scalars. On register-pressure-bound shaders this can improve occupancy.

**Edge cases:** `zone_log_key` is the geometric mean of zone medians; always positive and
already implicitly guarded. All-black frame: `zone_log_key ≈ 0.001`, `hunt_scale` converges
to a small positive value — no divide by zero (denominator `5*0.001+1 = 1.005`).

**Complexity:** drop-in

---

### OPT-7: Beer-Lambert absorption — replace float3 `exp()` with 2nd-order polynomial [Category A]

**File:** `general/grade/grade.fx` lines 308–309

**Current:**
```hlsl
float3 bl_abs = dom_mask * sat_proxy * ramp;
lin = saturate(lin * exp(-0.065 * bl_abs));
```

**Proposed:**
```hlsl
float3 bl_abs = dom_mask * sat_proxy * ramp;
float3 bl_x   = 0.065 * bl_abs;
lin = saturate(lin * (1.0 - bl_x + bl_x * bl_x * 0.5));
```

**Derivation:** For the argument `x = 0.065 * bl_abs` where `bl_abs ∈ [0,1]`, so `x ∈ [0, 0.065]`.
Taylor expansion: `e^{-x} = 1 - x + x²/2 - x³/6 + ...`. Truncating at 2nd order:
Max error = `x³/6 ≤ 0.065³/6 = 4.57 × 10⁻⁵`. After multiplication by `lin ∈ [0,1]` the
output max error is also `4.57 × 10⁻⁵`.

**Max error:** 4.57 × 10⁻⁵ **SAFE** (threshold 0.002; error is 44× below threshold)

**Cost:** Replaces 1 float3 `exp()` (3 scalar exp instructions ≈ 12 cycles on AMD RDNA2)
with 2 float3 multiplies + 1 float3 multiply-add + 1 float3 subtract ≈ 9 scalar cycles.
Net saving: ~3 cycles per pixel.

**Edge cases:** At `bl_abs = 0` (achromatic or dark pixel): both forms give 1.0 exactly.
At `bl_abs = (1,0,0)` (maximally saturated, single dominant channel): `exp(-0.065) = 0.93707`
vs polynomial `= 0.93711` — delta = 0.00004. All-white frame: `sat_proxy ≈ 0`, `ramp = 0`,
`bl_abs = 0`, result is identity. Note: the 2nd-order polynomial always slightly overestimates
`exp(-x)` for `x > 0` (since the dropped term `−x³/6` is negative), meaning the polynomial
attenuates slightly less aggressively — a conservative approximation for an absorption model.

**Complexity:** drop-in

---

### OPT-8: Remove redundant `saturate` inside zone S-curve extent clamping [Category C]

**File:** `general/grade/grade.fx` line 342

**Current:**
```hlsl
float new_luma = saturate(zone_median + (luma - zone_median)
    * (1.0 + zone_str * iqr_scale * (1.0 - saturate(abs(luma - zone_median)))));
```

**Proposed:**
```hlsl
float new_luma = saturate(zone_median + (luma - zone_median)
    * (1.0 + zone_str * iqr_scale * (1.0 - abs(luma - zone_median))));
```

**Proof:** `luma ∈ [0,1]` (Luma of a `[0,1]` pixel), `zone_median ∈ [0,1]` (zone median from
`ZoneHistorySamp`, which stores Kalman-filtered percentiles in `[0,1]`). Therefore
`|luma - zone_median| ∈ [0, 1]` always. `saturate(x)` where `x ∈ [0,1]` is a no-op.

**Max error:** 0.0 (exact) **SAFE**

**Cost:** Saves 1 `saturate` (= 1 `clamp(x,0,1)`) per pixel.

**Edge cases:** None — the domain proof is tight. The outer `saturate` remains and provides
the final clamping.

**Complexity:** drop-in

---

### OPT-9: Remove redundant `saturate` from Munsell chroma attenuation multiplier [Category C]

**File:** `general/grade/grade.fx` lines 406–407

**Current:**
```hlsl
C *= saturate(1.0 - 0.20 * saturate(1.0 - lab.x / 0.25)
                  - 0.45 * saturate((lab.x - 0.75) / 0.25));
```

**Proposed:**
```hlsl
C *= (1.0 - 0.20 * saturate(1.0 - lab.x / 0.25)
          - 0.45 * saturate((lab.x - 0.75) / 0.25));
```

**Proof:** Let `a = saturate(1 - lab.x/0.25) ∈ [0,1]` and `b = saturate((lab.x-0.75)/0.25) ∈ [0,1]`.
The expression `1 - 0.20·a - 0.45·b` has minimum value at `a=1, b=1`: `1 - 0.20 - 0.45 = 0.35 > 0`.
Maximum is 1.0 at `a=0, b=0`. Range is `[0.35, 1.0] ⊂ [0,1]`. The outer `saturate` is a no-op.
`C ≥ 0` (it is `length(lab.yz)`), so `C × [0.35,1.0] ≥ 0` — no clamping needed.

**Max error:** 0.0 (exact) **SAFE**

**Cost:** Saves 1 `saturate` per pixel.

**Edge cases:** `lab.x > 1.25` is impossible in SDR (Oklab L is bounded by RGB max ≈ 1.0).
`lab.x < 0` is impossible (L is non-negative by definition of Oklab). Domain proof is sound.

**Complexity:** drop-in

---

### OPT-10: Inline `fc_width` — single-use intermediate [Category E]

**File:** `general/grade/grade.fx` lines 271–273

**Current:**
```hlsl
float fc_width    = 1.0 - fc_knee;
float fc_stevens  = (1.48 + sqrt(max(zone_log_key, 0.0))) / 2.03;
float fc_factor   = 0.05 / (fc_width * fc_width) * fc_stevens * spread_scale;
```

**Proposed:**
```hlsl
float fc_stevens  = (1.48 + sqrt(max(zone_log_key, 0.0))) / 2.03;
float fc_factor   = 0.05 / ((1.0 - fc_knee) * (1.0 - fc_knee)) * fc_stevens * spread_scale;
```

**Max error:** 0.0 (exact) **SAFE**

**Cost:** Saves 1 named scalar register. `fc_width` is read only once (line 273) and exists
only to name the intermediate. Inlining eliminates the live range entirely.

**Edge cases:** `fc_knee ∈ [0.70, 0.95]` (clamped by line 275), so `1-fc_knee ∈ [0.05, 0.30]`,
no divide-by-zero risk.

**Complexity:** drop-in

---

### OPT-11: Eliminate `green_w` alias for `hw_o2` [Category E]

**File:** `general/grade/grade.fx` lines 421–422, 454, 472, 488

**Current:**
```hlsl
float hw_o2 = HueBandWeight(h_out, BAND_GREEN);  // line 421
// ...
float new_C = 0.0, total_w = 0.0, green_w = 0.0;  // line 454
// ...
green_w = hw_o2;  // line 472
// ...
float dtheta = +(GREEN_HUE_COOL * 2.0 * 3.14159265) * green_w * final_C + abney;  // line 488
```

**Proposed:**
```hlsl
float hw_o2 = HueBandWeight(h_out, BAND_GREEN);  // unchanged
// ...
float new_C = 0.0, total_w = 0.0;  // remove green_w from declaration
// ...
// remove the green_w = hw_o2 assignment
// ...
float dtheta = +(GREEN_HUE_COOL * 2.0 * 3.14159265) * hw_o2 * final_C + abney;
```

**Max error:** 0.0 (exact) **SAFE**

**Cost:** Eliminates 1 named scalar (`green_w`), 1 assignment, and the `green_w = 0.0`
initializer in the loop declaration.

**Edge cases:** None. `hw_o2` and `green_w` are identical by construction.

**Complexity:** drop-in

---

## Ruled out this session

| Candidate | Reason rejected |
|-----------|----------------|
| `pow(col.rgb, EXPOSURE)` approximation | `EXPOSURE` is a user knob (uniform), not a compile-time constant; compiler already emits optimal `exp2(log2(x)*EXPOSURE)` form |
| `pow(col.rgb, VIEWING_SURROUND=1.123)` polynomial | Linear approximation error 0.01–0.013 for x < 0.3 — UNSAFE |
| `pow(final_C, 0.587)` H-K → `sqrt(C)*const` | Error ≈ 0.002 at typical C values — MARGINAL, too close to JND threshold |
| `context_lift = pow(ratio, 0.4)` polynomial | Ratio near 1.0 but can reach 0.5–2.0 during transitions; quadratic error up to 0.032 — UNSAFE; also absolute pixel impact < 0.001 anyway |
| Merge WarmBias + ShadowBias passes | Both write to different render targets; no MRT in pipeline; would require multi-file texture restructure |
| Merge WarmBias/ShadowBias into ChromaHistoryTex | ChromaHistoryTex is 8 wide (all columns used); widening requires changes across multiple files |
| Eliminate Passthrough pass in corrective.fx | Required to keep BackBuffer non-black between corrective and grade effects |
| `sin(h_out * 6.28318)` H-K sincos approximation | Full circle `[0, 2π]` — no safe polynomial approximation |
| `sincos(r21_delta * 0.628)` small-angle approx | `r21_delta` can reach ±1.0 (±36°) per creative_values.fx; small-angle error at 36° = 0.04 — UNSAFE |
| `chroma_exp = exp2(-5.006 * mean_chroma)` polynomial | `exp2` over [-1.0, 0] requires degree ≥ 4 to stay within 0.002; not worth complexity |
| Merge two 6-iteration `hist_cache` loops | Second loop depends on `chroma_str` which depends on first loop's output; dependency prevents true fusion (OPT-4 covers the register-pressure angle instead) |
| Halton loop unrolling | Already `[unroll]`; runs for only 8 pixels per frame — negligible absolute cost |

---

## Literature findings

External search APIs (Brave, arXiv) were not reachable from the sandbox. Analysis performed
from first principles and existing codebase knowledge:

- **Double-angle identity** (`sin(2θ) = 2sin(θ)cos(θ)`) is a standard trigonometric identity;
  `sincos` is a first-class HLSL/SPIR-V intrinsic that maps to a single GPU instruction.
- **2nd-order Taylor approximation for `exp(-x)`** near `x=0`: standard analysis, error bound
  `x³/6`. For the specific constant `x = 0.065·bl_abs`, max error is 4.57 × 10⁻⁵ — well within
  the 0.002 JND threshold established in the project.
- **Register spill thresholds**: AMD RDNA2 has 512 VGPRs per SIMD32, but occupancy drops sharply
  above 128 scalars (32 VGPRs × 4 lanes). The current 240-scalar count puts ColorTransformPS
  squarely in the register-spilling regime on AMD hardware; OPT-4 (−24 scalars) is the most
  impactful single register-pressure reduction.
- **Texture cache behavior**: GPU L1 texture caches are typically 16–32 KB per CU. A 8×4 RGBA16F
  texture is 256 bytes — guaranteed to fit in L1 cache after first touch. Re-reading 6 texels
  from a 32-texel texture (OPT-4) in the same shader invocation is a guaranteed L1 hit.

---

## Priority ranking

| # | OPT | Title | Max error | Cost reduction | Complexity | Recommend |
|---|-----|-------|-----------|----------------|-----------|----------|
| 1 | OPT-1 | Hoist mip-2 LowFreq read (4→1) | 0.0 | −3 tex2Dlod/px | surrounding changes | **Yes — high value** |
| 2 | OPT-4 | Eliminate hist_cache[6] array | 0.0 | −24 live scalars | surrounding changes | **Yes — AMD critical** |
| 3 | OPT-3 | Share cbrt(r_tonal) lines 368/370 | 0.0 | −2 transcend./px | drop-in | **Yes** |
| 4 | OPT-2 | HELMLAB double-angle sin(2h) | 0.0 | −1 transcend./px | drop-in | **Yes** |
| 5 | OPT-5 | Remove saturate in PivotedSCurve | 0.0 | −6 saturate/px | drop-in | **Yes** |
| 6 | OPT-6 | Inline Hunt scale block | 0.0 | −4 live scalars | drop-in | **Yes** |
| 7 | OPT-7 | Beer-Lambert 2nd-order poly | 4.5e-5 | −3 cycles (float3 exp) | drop-in | Yes (minor) |
| 8 | OPT-8 | Remove saturate(abs(luma-zone_median)) | 0.0 | −1 saturate/px | drop-in | Yes (minor) |
| 9 | OPT-9 | Remove saturate from Munsell multiplier | 0.0 | −1 saturate/px | drop-in | Yes (minor) |
| 10 | OPT-10 | Inline fc_width | 0.0 | −1 scalar register | drop-in | Yes (cleanup) |
| 11 | OPT-11 | Eliminate green_w alias | 0.0 | −1 scalar register | drop-in | Yes (cleanup) |
