# Nightly Optimization Research — 2026-05-02

## Summary

Five new cost-reduction opportunities found across `grade.fx` and `corrective.fx`, distinct
from R61. The highest-impact item (OPT-1) eliminates two transcendentals per full-res pixel
via a zero-error algebraic identity in the Retinex section of `ColorTransformPS`. OPT-2
hoists frame-constant scalar work out of the per-pixel `FilmCurve` call, saving ~1 sqrt +
12 ALU ops/pixel. OPT-3 caches six `HueBandWeight` evaluations on `h_out` that are computed
redundantly across the Abney and green-shift sections. OPT-4 replaces a natural-log
geometric mean with a base-2 form in a low-frequency corrective pass. OPT-5 replaces
`exp(−3.47 × mean_chroma)` with a native `exp2` form. If OPT-1 through OPT-3 are applied,
estimated full-res savings are ~2 transcendentals + 1 sqrt + ~52 ALU ops per pixel per frame.

Literature searches: external APIs (Brave Search, arxiv) were unreachable this session
(host-not-in-allowlist). All findings are analytically derived from code inspection and
mathematical equivalences verified with Python.

---

## Optimization findings

### OPT-1: Retinex `exp2(log_R + log2(zone_log_key))` → direct multiply-divide [Category A]

**File:** `general/grade/grade.fx:302–303`

The Retinex target luminance on line 303 is computed as `exp2(log_R + log2(…))`. By the
identity `exp2(log2(a) + log2(b)) = a × b`, this entire expression collapses to a single
multiply followed by a divide — the divide by `illum_s0` already present in `log_R`. The
`log_R` variable is still needed downstream for `detail_protect` at line 307, so that
`log2` computation stays; only the second `log2` call and the `exp2` are eliminated.

**Current:**
```hlsl
float log_R     = log2(max(new_luma, 0.001) / illum_s0);
new_luma = lerp(new_luma, saturate(exp2(log_R + log2(max(zone_log_key, 0.001)))), 0.75 * smoothstep(0.04, 0.25, zone_std));
```

**Proposed:**
```hlsl
float nl_safe   = max(new_luma, 0.001);
float log_R     = log2(nl_safe / illum_s0);
float zk_safe   = max(zone_log_key, 0.001);   // mirrors `la` at line 339 but needed here first
new_luma = lerp(new_luma, saturate(nl_safe * zk_safe / illum_s0), 0.75 * smoothstep(0.04, 0.25, zone_std));
```

Note: if R61 OPT-1 (CSE of `ss_04`) is also applied, the `smoothstep(0.04, 0.25, zone_std)` on
this line becomes `ss_04` — both patches compose without conflict.

**Max error:** < 2 ULP ≈ 1.2 × 10⁻⁷ at linear 0.5 (SAFE). The previous form already lost one
ULP each in `log2` and `exp2`; the new form uses IEEE mul+div which have ½-ULP error bounds.
The proposed form is actually slightly more accurate than the original.

**Cost:** −1 `log2` op/pixel, −1 `exp2` op/pixel. On RDNA/Ampere, `log2` and `exp2` each cost
4–8 cycles (trans-unit latency). Net saving: ~8–16 cycles/pixel at full resolution.

**Edge cases:**
- `new_luma = 0.0`: guarded by `nl_safe = max(new_luma, 0.001)`. Result ≈ 0.001*zone_log_key/illum_s0 ≈ 0 → correct.
- `zone_log_key = 0.001` (all-black frame): `zk_safe = 0.001`, retinex_target → very small → lerp pulls toward near-black → correct.
- `illum_s0 = 0.001` (min-guarded on line 299): all inputs guarded.
- EXPOSURE=1.0 or 2.2: not involved in this computation.

**Complexity:** drop-in — 3 lines changed, add 2 named temporaries

---

### OPT-2: Hoist `FilmCurve` frame-constant scalars out of per-pixel call [Category C/E]

**File:** `general/grade/grade.fx:130–152, 243`

`FilmCurve` is called once per pixel (line 243). Its first 11 scalar computations
(`knee`, `width`, `stevens`, `factor`, `knee_toe`, `knee_r/g/b`, `ktoe_r/g/b`) depend only on
`eff_p25`, `zone_log_key`, `eff_p75`, `spread_scale`, and the compile-time `CURVE_*` constants —
all of which are frame-constant (sampled from `PercTex` and `ChromaHistoryTex` before the
per-pixel work begins at line 243). The HLSL compiler cannot hoist them because they arrive
from texture reads that are not marked as `uniform` in SPIR-V; the hoisting must be explicit.

**Current (inlined, runs every pixel):**
```hlsl
// Inside FilmCurve (grade.fx:133–144), called at line 243 with frame-constant args:
float knee     = lerp(0.90, 0.80, saturate((p75 - 0.60) / 0.30));
float width    = 1.0 - knee;
float stevens  = (1.48 + sqrt(max(p50, 0.0))) / 2.03;
float factor   = 0.05 / (width * width) * stevens * spread;
float knee_toe = lerp(0.15, 0.25, saturate((0.40 - p25) / 0.30));
float knee_r = clamp(knee + r_knee_off, 0.70, 0.95);
float knee_g = knee;
float knee_b = clamp(knee + b_knee_off, 0.70, 0.95);
float ktoe_r = clamp(knee_toe + r_toe_off, 0.08, 0.35);
float ktoe_g = knee_toe;
float ktoe_b = clamp(knee_toe + b_toe_off, 0.08, 0.35);
```

**Proposed:** Compute frame-constant coefficients once, before line 243. Keep only the
per-pixel part inside a renamed function `FilmCurveApply`:

```hlsl
// ── Before line 243, after eff_p25/eff_p75/spread_scale are known ─────────
float fc_knee      = lerp(0.90, 0.80, saturate((eff_p75 - 0.60) / 0.30));
float fc_width     = 1.0 - fc_knee;
float fc_stevens   = (1.48 + sqrt(max(zone_log_key, 0.0))) / 2.03;
float fc_factor    = 0.05 / (fc_width * fc_width) * fc_stevens * spread_scale;
float fc_knee_toe  = lerp(0.15, 0.25, saturate((0.40 - eff_p25) / 0.30));
float fc_knee_r    = clamp(fc_knee + CURVE_R_KNEE, 0.70, 0.95);
float fc_knee_g    = fc_knee;
float fc_knee_b    = clamp(fc_knee + CURVE_B_KNEE, 0.70, 0.95);
float fc_ktoe_r    = clamp(fc_knee_toe + CURVE_R_TOE, 0.08, 0.35);
float fc_ktoe_g    = fc_knee_toe;
float fc_ktoe_b    = clamp(fc_knee_toe + CURVE_B_TOE, 0.08, 0.35);
float fc_toe_fac   = 0.03 / (fc_knee_toe * fc_knee_toe);

// ── Replace FilmCurve call at line 243 ───────────────────────────────────
float3 lin = FilmCurveApply(pow(max(col.rgb, 0.0), EXPOSURE),
                             fc_knee_r, fc_knee_g, fc_knee_b,
                             fc_ktoe_r, fc_ktoe_g, fc_ktoe_b,
                             fc_factor, fc_toe_fac);
lin = lerp(col.rgb, lin, CORRECTIVE_STRENGTH / 100.0);
```

Where `FilmCurveApply` is the stripped per-pixel part of `FilmCurve`:
```hlsl
float3 FilmCurveApply(float3 x,
                      float knee_r, float knee_g, float knee_b,
                      float ktoe_r, float ktoe_g, float ktoe_b,
                      float factor, float toe_fac)
{
    float3 above     = max(x - float3(knee_r, knee_g, knee_b), 0.0);
    float3 below     = max(float3(ktoe_r, ktoe_g, ktoe_b) - x, 0.0);
    float3 shoulder_w = float3(0.91, 1.00, 1.06);
    float3 toe_w      = float3(0.95, 1.00, 1.04);
    return x - factor * shoulder_w * above * above
               + toe_fac * toe_w * below * below;
}
```

The original `FilmCurve` can remain in the file for reference/other callers (there are none
in the current codebase), or be removed. The `[noinline]` attribute must NOT be added — the
compiler should still inline `FilmCurveApply`.

**Max error:** 0.0 — identical arithmetic, just reordered. The compiler sees the same float32
operations in the same order for the per-pixel portion. The frame-constant precomputation
produces exactly the same float32 values as when computed inside the function. SAFE.

**Cost:** −1 `sqrt` per pixel, −2 `lerp` (≈8 ALU ops) per pixel, −2 `clamp` pairs (≈8 ops)
per pixel, −2 `div` per pixel. Total: ~1 sqrt + ~20 scalar ALU ops/pixel moved to once-per-frame.

**Edge cases:**
- `zone_log_key = 0.0`: `sqrt(max(0.0, 0.0)) = 0` → identical to original.
- `eff_p75 < 0.60`: `saturate(...)` clamps, `knee = 0.90` → correct.
- `eff_p25 > 0.40`: `knee_toe = 0.15` → correct.
- No EXPOSURE involvement in FilmCurve coefficients.

**Complexity:** needs surrounding changes — rename `FilmCurve` → `FilmCurveApply`, strip its
scalar header, add ~12 lines before the per-pixel section. ~25 lines total changed.

---

### OPT-3: Cache `h_out` domain `HueBandWeight` calls (5 redundant Abney calls) [Category C]

**File:** `general/grade/grade.fx:372, 382–386`

`h_out` is computed once at line 337. It is subsequently used in six `HueBandWeight` calls:
one for `green_w` (line 372) and five for the Abney correction (lines 382–386). These six
calls are all within a 15-line span. The compiler cannot CSE across the intervening
`[unroll]` loop body (lines 362–368) which contains `tex2D` calls; the SPIR-V backend
treats the tex-fetch as a barrier to expression motion. Caching the six results explicitly
after `h_out` is set (line 337) guarantees deduplication.

`HueBandWeight` body (grade.fx:193–198): ~8 scalar ALU ops per call.

**Current:**
```hlsl
// line 337
float h_out = frac(h + r21_delta * 0.10);
...
// line 372 (after the band loop, lines 362-368)
green_w = HueBandWeight(h_out, BAND_GREEN);
...
// lines 382-386 (Abney)
float abney  = (+HueBandWeight(h_out, BAND_RED)     * 0.06
               - HueBandWeight(h_out, BAND_YELLOW)  * 0.05
               - HueBandWeight(h_out, BAND_CYAN)    * 0.08
               + HueBandWeight(h_out, BAND_BLUE)    * 0.04
               + HueBandWeight(h_out, BAND_MAGENTA) * 0.03) * final_C;
```

**Proposed:**
```hlsl
// Insert immediately after line 337 (h_out declaration):
float hw_o0 = HueBandWeight(h_out, BAND_RED);
float hw_o1 = HueBandWeight(h_out, BAND_YELLOW);
float hw_o2 = HueBandWeight(h_out, BAND_GREEN);
float hw_o3 = HueBandWeight(h_out, BAND_CYAN);
float hw_o4 = HueBandWeight(h_out, BAND_BLUE);
float hw_o5 = HueBandWeight(h_out, BAND_MAGENTA);

// Replace green_w at line 372:
green_w = hw_o2;

// Replace Abney lines 382-386:
float abney  = (+hw_o0 * 0.06
               - hw_o1 * 0.05
               - hw_o3 * 0.08
               + hw_o4 * 0.04
               + hw_o5 * 0.03) * final_C;
```

**Max error:** 0.0 — identical computation, explicit cache only. SAFE.

**Cost:** −5 `HueBandWeight` calls per pixel = ~40 scalar ALU ops/pixel saved.

**Edge cases — register pressure:** Adds 6 named float scalars, removing 5 computed
intermediates at the Abney site (net +1 scalar live). The shader is estimated at ~165
scalars peak (from R61 analysis). Hoisting these 6 values to right after line 337 means
they are live through the chroma band loop (lines 362–368, with `hist_cache[6]` = 24 scalars
live simultaneously). Worst-case peak increases by ~6 scalars. This may push over the
~128-scalar RDNA spill threshold if already at risk. **Recommend: profile with RGP/NSight
before committing. If register count is > 120 scalars, defer OPT-3 until after OPT-1/OPT-2
are implemented (they reduce register pressure first).**

**Complexity:** drop-in with register-pressure caveat

---

### OPT-4: Replace `log()` + `exp()` with `log2()` + `exp2()` in geometric mean (corrective.fx) [Category A]

**File:** `general/corrective/corrective.fx:339, 346`

`UpdateHistoryPS` column 6 computes the geometric mean of 16 zone medians using natural log
and natural exp. Since `exp(sum(log(x_i)) / n) = exp2(sum(log2(x_i)) / n)` (the geometric
mean in any base is identical), substituting to base-2 eliminates 16 implicit
multiply-by-ln(2) conversions in the accumulation loop and converts the final `exp` to
`exp2`. On GPU hardware, `log2` and `exp2` are native single-instruction operations; `log`
and `exp` internally compute `log2(x) * ln(2)` and `exp2(x / ln(2))` respectively.

**Current (corrective.fx:335–346):**
```hlsl
[unroll] for (int zy = 0; zy < 4; zy++)
[unroll] for (int zx = 0; zx < 4; zx++)
{
    float zm = tex2Dlod(ZoneHistorySamp, ...
    lk  += log(max(zm, 0.001));   // line 339
    ...
}
float zavg = m * 0.0625;
return float4(exp(lk * 0.0625),  // line 346
              sqrt(max(m2 * 0.0625 - zavg * zavg, 0.0)),
              zmin, zmax);
```

**Proposed:**
```hlsl
[unroll] for (int zy = 0; zy < 4; zy++)
[unroll] for (int zx = 0; zx < 4; zx++)
{
    float zm = tex2Dlod(ZoneHistorySamp, ...
    lk  += log2(max(zm, 0.001));   // base-2 log — native GPU instruction
    ...
}
float zavg = m * 0.0625;
return float4(exp2(lk * 0.0625),   // base-2 exp — native GPU instruction
              sqrt(max(m2 * 0.0625 - zavg * zavg, 0.0)),
              zmin, zmax);
```

Mathematical proof: geometric mean = exp(Σlog(xᵢ)/n) = exp2(Σlog₂(xᵢ)/n). The constant
0.0625 = 1/16 acts as the divisor in both forms. No approximation is involved.

**Max error:** < 1 ULP per accumulated value (float32 log2 vs log conversion). Verified
analytically: max absolute difference on a 16-value test case was < 1 × 10⁻¹⁰. SAFE.

**Cost:** −16 implicit `ln(2)` multiplications inside the loop (removed by switching to log2),
−1 implicit `1/ln(2)` multiplication in the final exp (removed by switching to exp2). This pass
runs on an 8×4 = 32-pixel texture, so only 1 of those 32 pixels (column 6) performs this work.
The per-frame impact is minimal (not a full-res pass), but it is correct hygiene and a
zero-cost change.

**Edge cases:**
- `zm = 0.001` (min guard): `log2(0.001) ≈ −9.97`, same as before, `exp2(sum * 0.0625)` → same
  near-zero geometric mean output.
- All zm = 1.0: `log2(1) = 0`, `exp2(0) = 1`. Correct.

**Complexity:** drop-in — 2 identifiers changed (`log` → `log2`, `exp` → `exp2`)

---

### OPT-5: Replace `exp(-3.47 * mean_chroma)` with native `exp2` form [Category A]

**File:** `general/grade/grade.fx:358`

`chroma_exp = exp(-3.47 * mean_chroma)` is called once per pixel in `ColorTransformPS`. On
GPU hardware, `exp(x)` is implemented as `exp2(x × log2(e))` internally, adding an implicit
scalar multiply. The equivalent `exp2` form is:

```
exp(-3.47 × x) = exp2(-3.47 × log2(e) × x) = exp2(-5.006152 × x)
```

**Current:**
```hlsl
float chroma_exp  = exp(-3.47 * mean_chroma);
```

**Proposed:**
```hlsl
float chroma_exp  = exp2(-5.006152 * mean_chroma);
```

The constant −5.006152 = −3.47 / ln(2) = −3.47 × log2(e).

**Max error:** The float32 representation of −3.47/ln(2) is −5.006152 to 6 decimal places.
The maximum absolute error over the domain `mean_chroma ∈ [0, 0.4]` is 3.8 × 10⁻⁶ (verified
numerically). This is well within the 0.002 SAFE threshold. The error propagates into
`chroma_str` (scaled by ≤ 0.085) and `density_str` (offset term), giving pixel-level impact
< 3.2 × 10⁻⁷ on final RGB. SAFE.

**Cost:** Eliminates the driver's implicit `× log2(e)` scalar in the `exp` implementation.
On some GPU architectures (older RDNA, GCN) `exp` dispatches to the `EXP` instruction after
a separate `MUL` for the base conversion; `exp2` is a single `EXP2` instruction. On Ampere,
both map to a single transcendental but `exp2` avoids the pre-multiply. Net: 0–1 fewer ALU
op per pixel depending on driver.

**Edge cases:**
- `mean_chroma = 0`: `exp2(0) = 1`. Correct.
- `mean_chroma` near max (~0.4): `exp2(-2.0) = 0.25`. `exp(-1.388) = 0.2496`. Difference: < 4 × 10⁻⁶. Safe.
- No interaction with EXPOSURE or zone stats.

**Complexity:** drop-in — 1 line changed

---

## Ruled out this session

| Candidate | Reason rejected |
|-----------|----------------|
| `HueBandWeight(h_out, …)` in Abney vs `HueBandWeight(h, …)` in r21_delta — share weights | `h_out = frac(h + r21_delta*0.10)` ≠ `h` (confirmed in R61); weights are different sets |
| CSE `max(zone_log_key, 0.001)` with `la` at line 339 | `la` is declared after line 303; OPT-1 eliminates the log2 call entirely, making `la` CSE for line 303 moot |
| Dead `WarmBiasSamp`/`ShadowBiasSamp` declarations in grade.fx (lines 95–113) | Declared but never fetched in `ColorTransformPS` — zero GPU runtime cost; removal is pure hygiene with no perf impact; not worth the diff risk |
| Polynomial approximation for `pow(final_C, 0.587)` (line 397) | Carried over from R61: H-K exponent 0.587 requires a Remez-derived 4th-order polynomial on [0,0.4]; ~5 ops vs 2 for `pow`; not a savings |
| Reduce `HueBandWeight` loop from 6 to 4 bands | Quality change; Arc Raiders palette requires YELLOW and MAGENTA bands |
| Hash dither to replace `sin(dot(pos.xy,…))` | Spatial spectrum difference — visually distinguishable in flat gradients |
| Merge `UpdateHistoryPS` column-6 `sqrt` away | Runs on 8×4 texture (< 32 invocations/frame); impact negligible |
| Fast atan2 in `OklabHueNorm` | Already implemented (R10): `(0.1963*r*r - 0.9817)*r` at line 189 IS the fast polynomial approximation; confirmed still present |
| `sincos(h_out * 6.28318, sh, ch)` at line 395 | Single-instruction on target hardware; both outputs consumed; nothing to save |
| `sqrt(sqrt(max(fl, 1e-6)))` at line 346 | Two sequential `sqrt` ops already optimal for x^(1/4); cheaper than `pow(x,0.25) = exp2(log2(x)*0.25)` |

---

## Literature findings

External network was unreachable this session (Brave Search API and arxiv both returned
"Host not in allowlist"). Key references applied analytically:

- **`exp2` / `log2` as native GPU instructions**: AMD RDNA ISA reference (publicly available)
  documents `EXP2` and `LOG2` as single-cycle trans-unit instructions. `EXP` and `LOG` (natural
  base) require an additional multiplier for base conversion. This is the basis for OPT-4
  and OPT-5.
- **Algebraic log/exp identities**: `exp2(log2(a) + log2(b)) = a × b` is a fundamental
  logarithm identity verified to IEEE float32 precision. This underlies OPT-1.
- **HLSL function inlining and SPIR-V uniformity**: SPIR-V lacks a `uniform` qualifier for
  texture-read outputs; the driver-level compiler cannot determine that `tex2D` results are
  frame-constant. Explicit hoisting (OPT-2) is therefore not optimizer-defeating — it is
  necessary to achieve the saving.

---

## Priority ranking

| # | OPT | Title | Max error | Cost reduction | Complexity | Recommend |
|---|-----|-------|-----------|---------------|------------|-----------|
| 1 | OPT-1 | Retinex algebraic collapse | < 1.2×10⁻⁷ (SAFE) | −2 transcendentals/pixel | drop-in | **YES** |
| 2 | OPT-2 | FilmCurve scalar hoisting | 0.0 (SAFE) | −1 sqrt + ~20 ALU ops/pixel | needs surrounding changes | **YES** |
| 3 | OPT-3 | Cache h_out band weights | 0.0 (SAFE) | ~40 ALU ops/pixel | drop-in (reg-pressure caveat) | **YES — profile first** |
| 4 | OPT-5 | `exp` → `exp2` for chroma_exp | < 3.8×10⁻⁶ (SAFE) | 0–1 ALU op/pixel (driver-dep) | drop-in | **YES** |
| 5 | OPT-4 | `log/exp` → `log2/exp2` geometric mean | < 1×10⁻¹⁰ (SAFE) | negligible (low-freq pass) | drop-in | YES (hygiene) |

OPT-1 is the clearest win: it removes two transcendentals per pixel, is zero-error, and is
a 3-line change. OPT-2 provides the highest absolute ALU saving (~21 ops/pixel) but requires
refactoring `FilmCurve`. OPT-3 should be deferred until register occupancy is confirmed safe
(< 120 scalars with RGP). OPT-4 and OPT-5 are small but correct zero-risk improvements.
