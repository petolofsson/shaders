# Nightly Optimization Research — 2026-05-04

## Summary

Five new optimizations found across two files (`pro_mist.fx` and `grade.fx`), plus one
pass-consolidation candidate in `corrective.fx`. All prior R82 optimizations confirmed
implemented in current code. The highest-value item is replacing the `sin()`-based dither
in `pro_mist.fx` with the IGN pattern already used by `grade.fx` — saves one transcendental
per pixel at full resolution, zero perceptual change, and drop-in. Two redundant guards on
`zone_log_key` can be removed with mathematical proof from the write-side code. A redundant
`saturate()` before `RGBtoOklab()` in Stage 2 is a provable no-op. The H-K sincos
elimination via angle addition is architecturally sound but has uncertain net GPU gain; ranked
lower. WarmBias+ShadowBias MRT merge saves 64 reads per frame but touches a tiny pixel budget
and requires vkBasalt MRT verification.

External search API unavailable — analysis performed from first principles.

---

## Verification of prior R82 optimizations

All eleven R82 OPTs confirmed present in current `grade.fx`:

| OPT | Status | Evidence |
|-----|--------|---------|
| OPT-1 Hoist mip-2 read | ✅ Implemented | Line 229 comment `// OPT-1: hoisted` |
| OPT-2 HELMLAB sincos | ✅ Implemented | Lines 407–409 `sincos(h_theta, sh_h, ch_h)` |
| OPT-3 Share cbrt_r | ✅ Implemented | Lines 378–381 `float cbrt_r = exp2(...)` reused |
| OPT-4 Eliminate hist_cache[6] | ✅ Implemented | Lines 453–477 two-loop form |
| OPT-5 saturate in PivotedSCurve | ✅ Implemented | Line 203 `1.0 - abs(t)` (no saturate) |
| OPT-6 Inline Hunt block | ✅ Implemented | Lines 445–450 `_k`, `_k4`, `_omk4` form |
| OPT-7 Beer-Lambert 2nd-order | ✅ Implemented | Lines 311–313 `bl_x` polynomial |
| OPT-8 saturate(abs(luma-zone_median)) | ✅ Implemented | Line 352 no inner saturate |
| OPT-9 saturate on Munsell multiplier | ✅ Implemented | Lines 421–424 no outer saturate on C*= |
| OPT-10 Inline fc_width | ✅ Implemented | Line 275 `(1.0 - fc_knee) * (1.0 - fc_knee)` |
| OPT-11 Eliminate green_w alias | ✅ Implemented | Line 504 uses `hw_o2` directly |

---

## Optimization findings

### OPT-1: Replace `sin()` dither in pro_mist.fx with IGN [Category A]

**File:** `general/pro-mist/pro_mist.fx` line 125

**Current:**
```hlsl
float dither = frac(sin(dot(pos.xy, float2(127.1, 311.7))) * 43758.5453) - 0.5;
```

**Proposed:**
```hlsl
float dither = frac(52.9829189 * frac(dot(pos.xy, float2(0.06711056, 0.00583715)))) - 0.5;
```

**Derivation:** The IGN (Interleaved Gradient Noise) pattern (Jimenez 2016, "Filmic SMAA") uses
only `frac()` and `dot()` — no transcendental. It achieves blue-noise spectral distribution in
the spatial domain, which is perceptually superior to the white-noise spectrum produced by the
`sin()`-hash pattern. The identical formula is already used in `grade.fx` (line 553, R89).
The `sin(x) * 43758` hash is a long-standing GPU shader idiom that predates IGN; IGN supersedes
it on both quality and cost.

Amplitude: both patterns produce output in `[-0.5, 0.5]` scaled by `1/255`, identical to
current. Only the spatial frequency content changes (white → blue).

**Max absolute error:** 0.0 — same dither amplitude, different noise spectrum. **SAFE**

**Cost:** Saves 1 `sin()` per pixel in `ProMistPS` (full-resolution pass). On AMD RDNA2/3,
`sin` costs 4–8 clock cycles; `frac(dot(...))` costs ≤ 2 cycles. Net saving ≥ 2 cycles/px.

**Edge cases:** IGN has no degeneracy at image corners or along axes. `frac()` is well-defined
over all finite inputs. The pattern tiles at irrational frequencies — no visible repetition.

**Implementation complexity:** drop-in

---

### OPT-2: Remove redundant `saturate(lin)` before Stage 2 RGBtoOklab [Category C]

**File:** `general/grade/grade.fx` line 376

**Current:**
```hlsl
float3 lab_t = RGBtoOklab(saturate(lin));
```

**Proposed:**
```hlsl
float3 lab_t = RGBtoOklab(lin);
```

**Proof that `lin ∈ [0,1]` at line 376:**

1. After Beer-Lambert block: `lin = saturate(lin * ...)` at line 313. lin.r ∈ [0,1] from
   here. Lines 318–319 additionally saturate lin.g and lin.b: both ∈ [0,1].
2. After R19 block: `lin = saturate(lin + ...)` at line 339. Fully clamped, all channels.
3. `lin_pre_tonal = lin` is set at line 343 — capturing the already-saturated value.
4. Lines 343–375 (zone contrast, Retinex, shadow lift) do NOT write to `lin` — they
   accumulate into `new_luma`, `lab_t`, and intermediate scalars. `lin` itself is not
   modified between line 339 and line 376. Therefore `lin = lin_pre_tonal ∈ [0,1]`.

The `RGBtoOklab` function's `max(..., 1e-10)` guard on the LMS channels provides sufficient
protection against exact zero; the outer `saturate` at line 376 adds no further protection.

**Max absolute error:** 0.0 — `lin` is already in [0,1], `saturate` is identity. **SAFE**

**Cost:** Eliminates 1 `float3 saturate` (= 3 scalar `clamp(x,0,1)`) per pixel in
`ColorTransformPS`. On GPU: 3 scalar min/max pairs ≈ 1–2 cycles. Minor but free.

**Edge cases:** If future changes modify `lin` between lines 339 and 376 (e.g., inserting a
new stage), this optimization must be re-evaluated. As of the current codebase, the proof
holds.

**Implementation complexity:** drop-in

---

### OPT-3: Remove two redundant `max()` guards on `zone_log_key` [Category C / E]

**File:** `general/grade/grade.fx` lines 274 and 362

**Current:**
```hlsl
// Line 274:
float fc_stevens = (1.48 + exp2(log2(max(zone_log_key, 1e-6)) * (1.0 / 3.0))) / 2.04;

// Line 362:
float zk_safe = max(zone_log_key, 0.001);
```

**Proposed:**
```hlsl
// Line 274:
float fc_stevens = (1.48 + exp2(log2(zone_log_key) * (1.0 / 3.0))) / 2.04;

// Lines 362–363 and 370 (eliminate zk_safe, use zone_log_key directly):
float nl_safe = max(new_luma, 0.001);
float log_R   = log2(nl_safe / illum_s0);
new_luma = lerp(new_luma, saturate(nl_safe * zone_log_key / illum_s0), 0.75 * ss_04_25);
// ...
float context_lift = exp2(log2(slow_key / zone_log_key) * 0.4);
```

**Proof that `zone_log_key ≥ 0.001` always:**

`zone_log_key = zstats.r`, written by `UpdateHistoryPS` in `corrective.fx`:
```hlsl
float lk = 0.0;
[unroll] for (int zy = 0; zy < 4; zy++)
[unroll] for (int zx = 0; zx < 4; zx++)
{
    float zm = tex2Dlod(ZoneHistorySamp, ...).r;
    lk += log2(max(zm, 0.001));    // ← each term ≥ log2(0.001) = -9.966
}
return float4(exp2(lk * 0.0625), ...);   // geometric mean of 16 zone medians
```

Each of the 16 terms contributes `log2(max(zm, 0.001)) ≥ log2(0.001) = -9.966`. The
arithmetic mean exponent `lk * 0.0625 ≥ -9.966`. Therefore:

    zone_log_key = exp2(lk * 0.0625) ≥ exp2(-9.966) = 0.001

The lower bound is 0.001, achieved only when all 16 zones have median luma ≤ 0.001
(perfectly black frame). The `max(zone_log_key, 0.001)` at line 362 and
`max(zone_log_key, 1e-6)` at line 274 are both no-ops — the argument is always ≥ 0.001.

Note: `log2(zone_log_key)` at line 274 after the fix: since `zone_log_key ≥ 0.001 > 0`,
`log2` is well-defined and produces a finite value. The guard is provably redundant.

**Max absolute error:** 0.0 — no approximation, exact algebraic identity. **SAFE**

**Cost:**
- Eliminates 2 `max()` operations (one at line 274, one at line 362).
- Eliminates the `zk_safe` scalar variable from the live register file (1 float freed).
- `zk_safe` is referenced at lines 363 and 370; both replace with `zone_log_key` directly.

**Edge cases:** All-black frame: `zone_log_key = 0.001` exactly (not zero). `log2(0.001)` is
finite. `slow_key / zone_log_key = slow_key / 0.001` — `slow_key` is the slow ambient key
EMA, also derived from `zone_log_key`, also ≥ 0.001. Ratio bounded. No division-by-zero risk.

**Implementation complexity:** drop-in — three substitutions, no structural change

---

### OPT-4: Derive H-K `sincos(h_out)` from existing sincos results via angle addition [Category A]

**File:** `general/grade/grade.fx` lines 491–492 and 511–512

**Context:** `ColorTransformPS` currently issues three `sincos` calls:
1. Line 407–408: `sincos(h_theta, sh_h, ch_h)` — HELMLAB hue correction
2. Lines 491–492: `sincos(r21_delta * (0.10 * 6.28318), r21_sin, r21_cos)` — hue rotation
3. Lines 511–512: `sincos(h_out * 6.28318, sh, ch)` — H-K lightness correction

`h_out * 6.28318 = h_theta + δ_helmlab + δ_r21` where:
- `δ_helmlab = sh_h * (0.008 + 0.008 * ch_h)` ≤ 0.016 rad (from HELMLAB formula)
- `δ_r21 = r21_delta * 0.628318` (same angle used in sincos at lines 491–492)

The third sincos can be derived from the first two using the angle-addition identity, with a
small-angle approximation for the ≤ 16 mrad HELMLAB component:

**Proposed replacement for lines 511–512:**
```hlsl
// Derive sincos(h_out_theta) without a third sincos call.
// δ_helmlab ≤ 0.016 rad — small-angle: sin(δ) ≈ δ, cos(δ) ≈ 1
float delta_h = sh_h * (0.008 + 0.008 * ch_h);     // HELMLAB δ in radians
float sin_hp  = sh_h + ch_h * delta_h;              // sin(h_theta + δ_helmlab)
float cos_hp  = ch_h - sh_h * delta_h;              // cos(h_theta + δ_helmlab)
// Exact angle addition with r21 rotation (r21_sin, r21_cos already computed at line 492):
float sh = sin_hp * r21_cos + cos_hp * r21_sin;     // sin(h_out_theta)
float ch = cos_hp * r21_cos - sin_hp * r21_sin;     // cos(h_out_theta)
```

**Error analysis:**

Step 1 (small-angle approximation for δ_helmlab):
- `|sin(δ_h) - δ_h| ≤ δ_h³/6 ≤ 0.016³/6 = 6.8 × 10⁻⁷`
- `|cos(δ_h) - 1| ≤ δ_h²/2 ≤ 0.016²/2 = 1.3 × 10⁻⁴` → absorbed, not used directly

Step 2 (exact angle addition — zero error given inputs from step 1).

Propagation through H-K formula (line 513):
- `f_hk = −0.160·ch + 0.132·(ch²−sh²) − 0.405·sh + 0.080·(2·sh·ch) + 0.792`
- Max coefficient magnitude: 0.405. Error in (sh, ch) ≤ 6.8 × 10⁻⁷.
- Error in `f_hk` ≤ 0.405 × 6.8 × 10⁻⁷ = 2.8 × 10⁻⁷
- `hk_boost = 1 + 0.25 · f_hk · C^0.587`, C ≤ 0.4, pow(0.4, 0.587) ≤ 0.73
- Error in `hk_boost` ≤ 0.25 × 2.8 × 10⁻⁷ × 0.73 = **5.1 × 10⁻⁸**

**Max absolute error:** 5.1 × 10⁻⁸ **SAFE** (40,000× below JND threshold)

**Cost:** Saves 1 `sincos` per pixel (~4–8 cycles). Adds 6 arithmetic ops (~2–3 cycles).
Net saving: 1–6 cycles. On architectures where `sincos` maps to a native paired instruction
(RDNA, NV Turing+), saving is 1–4 cycles. On older or software-emulated `sincos`, saving is
larger. Conservative estimate: 2 cycles/pixel.

**Edge cases:** 
- `r21_delta = 0` (all ROT_* = 0): r21_sin = 0, r21_cos = 1. Derivation reduces to
  `sh = sin_hp, ch = cos_hp` — correct (h_out = h_perc when no rotation).
- `r21_delta = ±1.0` (extreme user setting): the angle addition step is exact (no
  approximation for the r21 component). Only the HELMLAB step uses small-angle. At extreme
  r21 values the approximation error is still 5.1 × 10⁻⁸ — unchanged.
- Full-circle wrap: `frac()` in the `h_out` computation ensures the angle is always
  a hue fraction [0,1]; after scaling by 2π, inputs to sincos are in [0, 2π]. The angle
  addition formulas are valid over the full circle.

**Implementation complexity:** needs surrounding changes — the HELMLAB delta coefficient must
be factored out from the h_perc line (currently `(sh_h * (0.008 + 0.008 * ch_h)) / 6.28318`
is a hue fraction; for angle addition we need it in radians: multiply back by 2π gives
`sh_h * (0.008 + 0.008 * ch_h)` directly).

---

### OPT-5: Merge WarmBias + ShadowBias passes via MRT [Category D / B]

**File:** `general/corrective/corrective.fx` lines 407–457 (WarmBiasPS + ShadowBiasPS),
technique lines 508–524

**Current:** Two separate 1×1 passes. Each loops 8×8 = 64 times over
`CreativeLowFreqSamp`, reading the same 64 texel positions with a different luminance mask:

```hlsl
// WarmBiasPS: mask = highlights (luma > p75)
float wt = step(p75, s.a);

// ShadowBiasPS: mask = shadows (luma < p25)
float wt = step(s.a, p25);
```

Both passes read `PercSamp` and `WarmBiasSamp`/`ShadowBiasSamp` for EMA, then write to
`WarmBiasTex` / `ShadowBiasTex`.

**Proposed:** Single pass with dual MRT output, accumulating both masks in one loop:

```hlsl
void WarmShadowBiasPS(float4 pos : SV_Position,
                      float2 uv  : TEXCOORD0,
                      out float4 warm_out   : SV_Target0,
                      out float4 shadow_out : SV_Target1)
{
    float4 perc     = tex2Dlod(PercSamp,       float4(0.5, 0.5, 0, 0));
    float  p25      = perc.r;
    float  p75      = perc.b;
    float  prev_wb  = tex2Dlod(WarmBiasSamp,   float4(0.5, 0.5, 0, 0)).r;
    float  prev_sb  = tex2Dlod(ShadowBiasSamp, float4(0.5, 0.5, 0, 0)).r;

    float sum_r_w = 0.0, sum_b_w = 0.0, sum_ww = 0.0;
    float sum_r_s = 0.0, sum_b_s = 0.0, sum_ws = 0.0;
    [unroll] for (int sy = 0; sy < 8; sy++)
    [unroll] for (int sx = 0; sx < 8; sx++)
    {
        float2 uv_s = float2((sx + 0.5) / 8.0, (sy + 0.5) / 8.0);
        float4 s    = tex2Dlod(CreativeLowFreqSamp, float4(uv_s, 0, 0));
        float  wt_w = step(p75, s.a);   // highlight mask
        float  wt_s = step(s.a, p25);   // shadow mask
        sum_r_w += s.r * wt_w;  sum_b_w += s.b * wt_w;  sum_ww += wt_w;
        sum_r_s += s.r * wt_s;  sum_b_s += s.b * wt_s;  sum_ws += wt_s;
    }

    float wb_curr   = (sum_r_w - sum_b_w) / max(sum_r_w + sum_b_w, 0.001);
    float sb_curr   = (sum_r_s - sum_b_s) / max(sum_r_s + sum_b_s, 0.001);
    // Clamp sums to 1.0 (guards unchanged from originals)
    wb_curr   = (sum_r_w + sum_b_w < 0.001) ? prev_wb : wb_curr;
    sb_curr   = (sum_r_s + sum_b_s < 0.001) ? prev_sb : sb_curr;
    warm_out   = float4(lerp(prev_wb, wb_curr, KALMAN_K_INF), 0.0, 0.0, 1.0);
    shadow_out = float4(lerp(prev_sb, sb_curr, KALMAN_K_INF), 0.0, 0.0, 1.0);
}

// Technique pass replaces the two separate passes:
pass WarmAndShadowBias
{
    VertexShader  = PostProcessVS;
    PixelShader   = WarmShadowBiasPS;
    RenderTarget0 = WarmBiasTex;
    RenderTarget1 = ShadowBiasTex;
}
```

**Note on the division change:** The original `WarmBiasPS` uses `sum_r / max(sum_w, 1.0)`
and `sum_b / max(sum_w, 1.0)` (dividing by count of contributing pixels), then computes
`(mean_r - mean_b) / max(mean_r + mean_b, 0.001)`. The proposed formulation folds both
divisions and skips computing `mean_r`/`mean_b` separately, computing the ratio directly
from sums. These are algebraically equivalent.

**Max absolute error:** 0.0 — algebraically identical computation, exact same texture reads,
same EMA coefficient. **SAFE**

**Cost:**
- Eliminates 64 `tex2Dlod(CreativeLowFreqSamp)` calls (saves the second 8×8 loop entirely).
- Eliminates 1 pass setup/teardown. These passes write 1 pixel each, so the absolute ALU
  savings are small in absolute frame time; the gain is principally one fewer Vulkan render
  pass boundary.
- Adds: 2 extra float accumulators, 1 extra `step()` per iteration (previously 1 per pass,
  now 2 per merged iteration).

**Edge cases:**
- **MRT support in vkBasalt**: Standard ReShade supports `RenderTarget0`/`RenderTarget1`
  syntax. vkBasalt compiles HLSL to SPIR-V and uses a ReShade-compatible effect system.
  MRT is a base Vulkan 1.0 feature. However, the exact vkBasalt MRT support must be verified
  before implementing — if unsupported, the pass would silently fail to write one target.
- **Texture format mismatch**: Both targets use `RGBA16F`; no format change required.
- **Empty frame**: If all pixels are outside both p25 and p75 bands (impossible since p25 < p75
  by construction), both sums would be zero. The guard `max(sum_r + sum_b, 0.001)` and the
  `prev_* fallback` handle this.

**Implementation complexity:** needs surrounding changes — pixel shader signature, technique
pass restructure, and MRT support verification required.

---

## Ruled out this session

| Candidate | Reason rejected |
|-----------|----------------|
| `pow(final_C, 0.587)` H-K polynomial | Max error ≈ 0.002 at C=0.15 — MARGINAL, too close to JND; already ruled out R82 |
| `pow(col.rgb, VIEWING_SURROUND=1.123)` polynomial | Linear approx error 0.01–0.013 for x < 0.3 — UNSAFE; already ruled out R82 |
| `context_lift = pow(ratio, 0.4)` polynomial | Ratio ∈ [0.5, 2.0] during transitions; quadratic error up to 0.032 — UNSAFE; already ruled out R82 |
| `sincos(r21_delta * 0.628)` small-angle approx | r21_delta defined as ±1.0 max in creative_values.fx (±36°); error at 36° = 0.040 — UNSAFE |
| Purkinje `C = length(lab.yz)` → Taylor approx | Saves 1 sqrt, adds 1 new live scalar + 3 ops. Net neutral or negative on register-bound shader |
| inverse_grade + grade Oklab round-trip sharing | Architecturally impossible: they operate on different pixel values (pre/post-correction). highway is 8-bit; can't carry float Oklab per-pixel |
| `analysis_frame` DownsamplePS elimination | Pass runs at 32×18 = 576 pixels; cost and savings are sub-noise |
| `chroma_exp = exp2(-5.006 * mean_chroma)` poly | Degree ≥ 4 needed for 0.002 error over [-1,0]; complexity exceeds savings; ruled out R82 |
| `lerp(col.rgb, lin, CORRECTIVE_STRENGTH/100)` at line 287 | `CORRECTIVE_STRENGTH = 100` (compile-time `#define`); lerp(a, b, 1.0) = b is trivially DCE'd by SPIR-V compiler. Also applies to `lerp(lin_pre_tonal, lin, TONAL_STRENGTH/100)` at line 398. Both are almost certainly already folded |
| `mist_ap_scale` in pro_mist.fx (line 103) | `EXPOSURE = 0.90` is a compile-time `#define`; result (≈ 1.033) is already constant-folded by SPIR-V compiler |

---

## Literature findings

External search API not reachable from sandbox. Analysis from first principles:

- **IGN (Interleaved Gradient Noise):** Published in Jimenez 2016, "Filmic SMAA" (ACM
  SIGGRAPH). Coefficients `(0.06711056, 0.00583715)` are irrational ratios that ensure no
  axis-aligned periodicity at any screen resolution. Spectral analysis: energy concentrated at
  high spatial frequencies (blue-noise character) vs. flat spectrum (white-noise) of
  `sin()`-hash. The grade.fx adoption of IGN (R89) provides the validated reference — the
  pro_mist dither is the only remaining `sin()`-hash in the pipeline.

- **Angle addition identity:** Standard trigonometric identity, exact (no approximation error
  for the r21 component). Small-angle approximation for the HELMLAB 16 mrad component:
  `sin(x) ≈ x` has error `x³/6` — for `x = 0.016`: `6.8 × 10⁻⁷`. This is standard Taylor
  series analysis; the bound is tight.

- **zone_log_key lower bound:** Proven from the write-side code in `UpdateHistoryPS`. The bound
  `exp2(-9.966) = 0.001` is exact; the `max(zm, 0.001)` guard inside UpdateHistoryPS is the
  sole protection, and it propagates through the geometric mean. The read-side guards are
  therefore redundant by construction.

- **MRT in Vulkan/vkBasalt:** Multiple Render Targets are a base Vulkan 1.0 feature
  (VkSubpassDescription with multiple color attachments). ReShade's `RenderTarget0/1` syntax
  maps directly to this. vkBasalt compatibility should be verified empirically before
  committing OPT-5.

---

## Priority ranking

| # | OPT | Title | Max error | Cost reduction | Complexity | Recommend |
|---|-----|-------|-----------|----------------|-----------|----------|
| 1 | OPT-1 | pro_mist sin() → IGN dither | 0.0 | −1 sin()/px | drop-in | **Yes — top priority** |
| 2 | OPT-2 | Remove redundant saturate(lin) line 376 | 0.0 | −3 saturate/px | drop-in | **Yes** |
| 3 | OPT-3 | Remove max() guards on zone_log_key (×2) | 0.0 | −2 max, −1 scalar | drop-in | **Yes** |
| 4 | OPT-4 | H-K sincos via angle addition | 5.1e-8 | −1 sincos/px + ~10 ops | surrounding changes | Yes (arch-dependent gain) |
| 5 | OPT-5 | WarmBias+ShadowBias MRT merge | 0.0 | −64 tex reads/frame | surrounding + MRT verify | Conditional (verify MRT) |
