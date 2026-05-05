# Nightly Optimization Research — 2026-05-05

## Summary

Four concrete optimizations found across categories A, B, and C. All are in `grade.fx`
`ColorTransformPS`, the only full-resolution per-pixel shader in the chain.
No pipeline restructuring required for any of them.

The highest-impact single finding is OPT-3 + OPT-4 together: two lerps that are provably dead
code because `TONAL_STRENGTH` and `CORRECTIVE_STRENGTH` are compile-time `#define`s equal to 100.
These can be deleted unconditionally.

OPT-1 (third sincos elimination) is the only transcendental saving; it requires a small
surrounding restructure but the error bound is tight.

Category F (inverse\_grade / grade Oklab sharing) and pass consolidation are both ruled out —
detailed reasoning in the "Ruled out" section.

---

## Optimization findings

### OPT-1: Eliminate third `sincos` via angle-addition + HELMLAB small-angle reuse [Category A]

**File:** `general/grade/grade.fx:370–458`

**Background — three `sincos` calls per pixel in ColorTransformPS:**

| Line | Call | Purpose |
|------|------|---------|
| 371–372 | `sincos(h_theta, sh_h, ch_h)` | HELMLAB 2-harmonic Fourier correction |
| 435–436 | `sincos(r21_delta * 0.6283, r21_sin, r21_cos)` | R21 per-band hue rotation |
| 455 | `sincos(h_out * 6.28318, sh, ch)` | H-K correction (Hellwig 2022) |

The H-K `sincos` at line 455 operates on `h_out * 2π`, which equals
`h_theta + δ_helmlab + r21_angle` — i.e. the angle already computed at line 371-372,
plus two small perturbations whose `sin/cos` values are already in registers.

**Current code (lines 370–373 + 435–436 + 455):**
```hlsl
float h_theta = h * 6.28318;
float sh_h, ch_h;
sincos(h_theta, sh_h, ch_h);
float h_perc  = frac(h + (sh_h * (0.008 + 0.008 * ch_h)) / 6.28318);
// ...
float r21_cos, r21_sin;
sincos(r21_delta * (0.10 * 6.28318), r21_sin, r21_cos);
// ...
float sh, ch;
sincos(h_out * 6.28318, sh, ch);
```

**Proposed replacement (lines 370–373 + 435–436 + 455 restructured):**
```hlsl
float h_theta = h * 6.28318;
float sh_h, ch_h;
sincos(h_theta, sh_h, ch_h);
// Store HELMLAB delta for reuse in OPT-1 below (saves recomputing the sub-expression)
float dh      = sh_h * (0.008 + 0.008 * ch_h);   // HELMLAB correction [radians], |dh| <= 0.016
float h_perc  = frac(h + dh / 6.28318);
// ...
float r21_cos, r21_sin;
sincos(r21_delta * (0.10 * 6.28318), r21_sin, r21_cos);
// ...
// OPT-1: derive sincos(h_out * 2pi) from already-computed sincos values.
// Step 1 — apply HELMLAB small-angle correction to (sh_h, ch_h):
//   sin(h_theta + dh) ≈ sh_h + ch_h*dh   (1st-order; |error| <= dh^2/2 = 1.28e-4)
//   cos(h_theta + dh) ≈ ch_h - sh_h*dh
float sh_p = sh_h + ch_h * dh;
float ch_p = ch_h - sh_h * dh;
// Step 2 — apply R21 rotation via exact angle-addition (r21_sin/r21_cos already computed):
float sh = sh_p * r21_cos + ch_p * r21_sin;
float ch = ch_p * r21_cos - sh_p * r21_sin;
// (delete the sincos(h_out * 6.28318, sh, ch) line)
```

**Error analysis:**

- HELMLAB small-angle error per component:
  `|sin(θ+δ) − sin(θ) − cos(θ)·δ| ≤ δ²/2`
  With max `|dh| = 0.016 rad` (when `sh_h = ch_h = 1`):
  error ≤ `0.016² / 2 = 1.28 × 10⁻⁴`
- R21 angle-addition is exact — no additional error introduced.
- Effect on H-K `f_hk` (linear + quadratic in `sh`/`ch`):
  error in f_hk ≤ `(0.160 + 0.132·2 + 0.405 + 0.080·2) × 1.28 × 10⁻⁴ ≈ 3.9 × 10⁻⁴`
- Effect on `hk_boost = 1 + 0.25 · f_hk · pow(C, 0.587)`:
  max `C = 0.4`, `pow(0.4, 0.587) ≈ 0.65`
  error in hk_boost ≤ `0.25 × 3.9 × 10⁻⁴ × 0.65 ≈ 6.3 × 10⁻⁵` — well below JND

**Max absolute error:** 1.28 × 10⁻⁴ (SAFE — 15× below the 0.002 JND floor)

**Cost reduction:**
- Remove: 1 `sincos` — quarter-rate instruction on modern GPU (RDNA/Turing), ~16–20 cycle latency
- Add: 2 muls + 1 add (step 1) + 4 muls + 2 add/sub (step 2) = 9 full-rate ops
- `dh` subexpression is also saved by hoisting it from line 373 (was computed implicitly in `h_perc`, now stored)
- Net at 2560×1440 / 60 fps: ~220 M pixel invocations/s; saving 1 quarter-rate sincos saves roughly
  12–18 cycles/pixel → meaningful throughput on saturated compute pipelines

**Edge cases:**
- When `r21_delta = 0` (all ROT_* knobs at 0), `r21_sin = 0`, `r21_cos = 1`, so step 2 is identity — correct
- When `dh = 0` (h_theta = 0 or π; sh_h = 0), step 1 is identity — correct
- Wrapping: `frac()` in the original `h_out` computation handles the wraparound; step 1-2 operate on sine/cosine values which are already period-agnostic — no wrapping issue

**Complexity:** Needs surrounding changes — restructure ~8 lines across three existing blocks.
The change is local to ColorTransformPS with no new variables except `dh` (float) and `sh_p`/`ch_p` (both float).

---

### OPT-2: `tex2D` → `tex2Dlod` for constant-coordinate and mipless texture reads [Category B]

**File:** `general/grade/grade.fx:226, 229, 309, 417`

In ColorTransformPS, several `tex2D` calls use either (a) compile-time-constant UV coordinates,
or (b) samplers declared with `MipLevels = 1` where LOD computation is wasted work.
`tex2D` compiles to `OpImageSampleImplicitLod` (SPIR-V) which requires the GPU's derivative
unit to compute `dUV/dx` and `dUV/dy` for mip selection. For constant UV or single-mip
textures this derivative work is thrown away.

**Current code — four sites:**
```hlsl
// Line 226
float4 perc = tex2D(PercSamp, float2(0.5, 0.5));

// Line 229
float4 zstats = tex2D(ChromaHistory, float2(6.5 / 8.0, 0.5 / 4.0));

// Line 309 (ZoneHistoryTex declared with MipLevels = 1)
float4 zone_lvl = tex2D(ZoneHistorySamp, uv);

// Line 417 — inside [unroll] for (int band = 0; band < 6; band++)
float pivot = tex2D(ChromaHistory, float2((band + 0.5) / 8.0, 0.5 / 4.0)).r;
```

**Proposed replacement:**
```hlsl
// Line 226
float4 perc = tex2Dlod(PercSamp, float4(0.5, 0.5, 0, 0));

// Line 229
float4 zstats = tex2Dlod(ChromaHistory, float4(6.5 / 8.0, 0.5 / 4.0, 0, 0));

// Line 309
float4 zone_lvl = tex2Dlod(ZoneHistorySamp, float4(uv, 0, 0));

// Line 417
float pivot = tex2Dlod(ChromaHistory, float4((band + 0.5) / 8.0, 0.5 / 4.0, 0, 0)).r;
```

Note: `ReadHWY(slot)` in `highway.fxh` already uses `tex2Dlod` — consistent with this change.

**Max absolute error:** 0 — `tex2Dlod(..., 0)` is exactly `tex2D` at LOD 0, which is what the
hardware selects for constant UV (gradient = 0) and for `MipLevels = 1` textures.

**Cost reduction:**
- Eliminates GPU derivative computation (`ddx`/`ddy`) for 9 texture fetches per pixel
  (lines 226, 229 = 2; line 309 = 1; line 417 × 6 = 6)
- On RDNA2/3 and Turing+, derivative units are shared — freeing them reduces quad-wave contention
- Also signals to the SPIR-V compiler that these reads have no UV gradient dependency,
  enabling better instruction scheduling

**Edge cases:** None. `tex2Dlod` at LOD 0 is identical to `tex2D` where gradient → 0 or mips = 1.

**Complexity:** Drop-in — 9 mechanical substitutions across 4 lines (line 417 is one source line,
the compiler unrolls it to 6).

---

### OPT-3: Delete dead `lin_pre_tonal` register and lerp [Category C]

**File:** `general/grade/grade.fx:307, 362`

`TONAL_STRENGTH` is a compile-time `#define` in `creative_values.fx`:
```c
#define TONAL_STRENGTH  100
```
This means `TONAL_STRENGTH / 100.0 = 1.0` at compile time. `lerp(a, b, 1.0) = b` — the
blend from `lin_pre_tonal` to `lin` is always the identity. `lin_pre_tonal` is assigned
at line 307 and never read except at line 362. Both are dead code.

**Current code:**
```hlsl
// Line 307
float3 lin_pre_tonal = lin;

// ...100 lines of tonal computation...

// Line 362
lin = lerp(lin_pre_tonal, lin, TONAL_STRENGTH / 100.0);
```

**Proposed replacement:**
```hlsl
// Delete line 307 entirely (lin_pre_tonal never used in any live path)
// Delete line 362 entirely (lerp with weight 1.0 is identity)
```

**Max absolute error:** 0 — dead code removal.

**Cost reduction:**
- 3 fewer scalar register slots (float3 `lin_pre_tonal`) held across ~55 lines of shader
- 1 fewer `float3` assignment per pixel (line 307)
- 1 fewer `lerp` per pixel (line 362) — `lerp(a, b, 1.0)` compiles to a scalar + 3 mads on some drivers

**Edge cases:** If `TONAL_STRENGTH` is ever changed from 100, this optimization must be
reverted. The `#define` comment in `creative_values.fx` already says "Not tuning knobs — leave
at 100", so this is safe. A guard comment at the deletion site is sufficient.

**Complexity:** Drop-in.

---

### OPT-4: Delete dead `CORRECTIVE_STRENGTH` lerp [Category C]

**File:** `general/grade/grade.fx:257`

`CORRECTIVE_STRENGTH` is also a compile-time `#define = 100` in `creative_values.fx`.
The lerp at line 257 blends `col.rgb` (pre-corrective) with `lin` (post-exposure + FilmCurve)
at weight 1.0 — always returns `lin`.

**Current code:**
```hlsl
// Line 257
lin = lerp(col.rgb, lin, CORRECTIVE_STRENGTH / 100.0);
```

**Proposed replacement:**
```hlsl
// Delete line 257 entirely
```

**Max absolute error:** 0.

**Cost reduction:** 1 fewer `lerp` per pixel (3 fused multiply-adds). Minor, but free.

**Edge cases:** Same caveat as OPT-3: reverts if `CORRECTIVE_STRENGTH` is changed.
`col.rgb` is still needed downstream for `col.a` in the `DrawLabel` return — no other cleanup needed.

**Complexity:** Drop-in.

---

## Ruled out this session

| Candidate | Reason rejected |
|-----------|----------------|
| H-K `pow(final_C, 0.587)` polynomial (line 458) | GPU `pow` compiles to 2 instructions (log2 + exp2). A minimax polynomial of sufficient accuracy (max error < 0.002) over [0, 0.5] requires degree ≥ 4 = 5 muls + 4 adds, which is more expensive than the 2-instruction hardware path. |
| `pow(col.rgb, EXPOSURE)` polynomial (EXPOSURE = 0.90, line 253) | Exponent 0.90 has no cheap integer decomposition; domain [0.01, 1] requires degree ≥ 5 for < 0.002 error. More instructions than hardware pow3. |
| `pow(col.rgb, VIEWING_SURROUND)` polynomial (1.123, line 221) | Same as above — no useful rational-power shortcut, broad domain. |
| Oklab stage-2 → stage-3 double round-trip elimination (lines 340–365) | Blending in Oklab (`lerp(lab_pre, lab_post, t)`) differs from blending in RGB then converting (`RGBtoOklab(lerp(rgb_pre, rgb_post, t))`). The difference is perceptually detectable for TONAL_STRENGTH < 100 use cases and changes the intentional RGB-space lerp semantics of stage 2. No-op at TONAL_STRENGTH = 100 but OPT-3 already handles that case. |
| ProMist downsample pass elimination (use `CreativeLowFreqTex` mip 2 instead of `MistDiffuseTex`) | `CreativeLowFreqTex` is captured pre-grade (before corrective.fx). `MistDiffuseTex` is post-grade. For scenes with strong color grading, the pre-grade blur would have visibly different chroma. The diffusion blend strength is ~6–14%, so error is reduced but still perceptually risky in high-saturation shots. Not worth trading quality for one 1/4-res pass. |
| Highway pre-compute of frame-uniform transcendentals (`fc_stevens` cube-root at line 244, `context_lift` pow-0.4 at line 334) | Both are frame-uniform (derived from 1×1 / 8×4 texture reads). The highway is 8-bit UNORM. For `zone_log_key` (range [0.01, 0.5]), highway precision = 1/255 ≈ 0.004. Propagated through `cbrt`: d(cbrt)/dx at x=0.3 ≈ 0.74, → error 0.003 > 0.002 JND threshold. A dedicated float16 1×1 pass could hold the values but that adds a new texture + pass, negating the savings for two scalar values. |
| Pass consolidation in `corrective.fx` (merge WarmBias into UpdateHistory, etc.) | All non-Passthrough corrective passes run at sub-fullscreen resolution (4×4, 32×16, 1×1). GPU dispatch overhead dominates over shader compute cost at these sizes. Merge would require MRT support; savings on sub-1K-pixel passes are negligible relative to the full-res grade.fx cost. |
| **Category F**: inverse\_grade Oklab round-trip sharing with grade.fx Stage 3 | `RGBToOklab` in `inverse_grade.fx` operates on the raw game swapchain image. `RGBtoOklab` in `grade.fx` line 365 operates on post-corrective lin (after EXPOSURE, FilmCurve, PrintStock, DyeCoupling, 3-way, tonal stage, shadow lift). The two input images are algebraically unrelated. Additionally, the 8-bit UNORM BackBuffer quantization round-trip between effects destroys any LMS sub-expression that could be shared. No reuse possible. |
| `HueBandWeight` smoothstep → linear in grade.fx (lines 163–168) | grade.fx uses `t*t*(3-2*t)` smoothstep for band weights; corrective.fx uses linear. Switching grade.fx to linear saves 18 muls/pixel (18 calls × 1 mul + 1 add each). But at the band half-width (d = BW/4), linear vs smoothstep differ by 0.094 in normalized weight — sufficient to cause visible hue-selectivity shifts at band edges. Perceptually MARGINAL, violates "self-limiting by construction" spirit. |

---

## Literature findings

- **Seblagarde 2014** ("Inverse trigonometric functions GPU optimization for AMD GCN"):
  `sin`/`cos` execute in 2–4 cycles on GCN; `asin`/`acos`/`atan` execute in 30–40 cycles.
  `sincos` is confirmed as a single combined quarter-rate instruction on GCN and NVIDIA Turing+.
  Source: https://seblagarde.wordpress.com/2014/12/01/inverse-trigonometric-functions-gpu-optimization-for-amd-gcn-architecture/

- **Narkowicz 2010** ("Shader Optimizations"): "Transcendental instructions (rcp, sqrt, rsqrt,
  cos, sin, log, exp) are quarter-rate." Confirms 4× throughput penalty vs full-rate ops.
  Source: https://knarkowicz.wordpress.com/2010/10/26/shader-optimizations/

- **Nic Taylor (DSPrelated 2019)** on atan2 polynomial error bounds: degree-3 Remez approximation
  achieves max error 6.7×10⁻⁵ — the current `OklabHueNorm` fast atan2 (R10N) already matches
  this class. No improvement available for atan2. Confirmed R10N still state-of-the-art.
  Source: https://www.dsprelated.com/showarticle/1052.php

- **Cbrt via Newton-Raphson + hardware sqrt**: Several Shadertoy implementations demonstrate
  starting from `sqrt(x)` as initial guess for cbrt, then 2 Newton iterations. On GPU,
  the `exp2(log2(x)/3)` idiom (already used throughout the pipeline) remains preferred because
  hardware log2/exp2 are the same cost as hardware sqrt, and the Newton iterations add
  4 mul/div ops each. No improvement over current `exp2(log2(x) * 0.333)` pattern.
  Source: https://www.shadertoy.com/view/ssyyDh

---

## Priority ranking

| # | Title | Max error | Cost reduction | Complexity | Recommend |
|---|-------|-----------|----------------|------------|-----------|
| 1 | OPT-3: Delete dead `lin_pre_tonal` / lerp | 0 | 3 register slots + 2 ops/px | Drop-in | **Yes — immediate** |
| 2 | OPT-4: Delete dead CORRECTIVE\_STRENGTH lerp | 0 | 1 lerp/px | Drop-in | **Yes — immediate** |
| 3 | OPT-2: tex2D → tex2Dlod (9 fetches) | 0 | 9 derivative computations/px | Drop-in | **Yes — immediate** |
| 4 | OPT-1: Third sincos elimination | 1.28 × 10⁻⁴ | 1 quarter-rate sincos/px | 8-line restructure | **Yes — next session** |
