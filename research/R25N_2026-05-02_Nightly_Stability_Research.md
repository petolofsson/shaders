# Nightly Stability Audit — 2026-05-02

## Summary

Register pressure in `ColorTransformPS` is the dominant risk: 169 declared scalars across all
local variables significantly exceed the 128-scalar spill threshold, and folding the obvious
single-use intermediates saves only ~10 scalars, leaving the function at ~159. Unsafe math is
well-guarded throughout the pipeline — the only residual fragility is unguarded `pow(l, 1/3)` in
both copies of `RGBtoOklab`, which are safe by upstream contract but would silently produce NaN
if that contract were ever broken. R19–R22 are clean: no NaN paths, no negative-C, no out-of-range
linear values escape into Stage 2.

---

## A. Register pressure

- **Total declared scalars in ColorTransformPS: 169**
- **Risk level: HIGH** (exceeds 128-scalar spill threshold by 41; folding easy candidates still
  leaves ~159 — spill is probable on any driver that allocates pessimistically)

### Variable inventory

| Type   | Variables (count) | Scalar total |
|--------|-------------------|--------------|
| float  | 78                | 78           |
| float3 | 15                | 45           |
| float4 | 4 named + hist_cache[6] = 10 instances | 40 |
| float2 | 2                 | 4            |
| int    | 2 (loop vars)     | 2            |
| **Total** |               | **169**      |

### Top 5 groups by scalar contribution

1. **float scalars** — 78 scalars; the long Stage 3 decomposition (la/k/k2/k4/fla/one_mk4/fl,
   chroma lift intermediates, ab-plane reconstruction intermediates) dominates.
2. **float3** — 45 scalars (15 variables); block-scoped temporaries (ps/toe/shoulder in R51,
   dom_mask in R50, r19_*_delta in R19, hal_r/hal_g/hal_delta in R56) contribute 9 of the 15.
3. **float4** — 40 scalars; `hist_cache[6]` alone accounts for 24 of these.
4. **float2** — 4 scalars (ab_in, ab_s).
5. **int** — 2 scalars (loop counters bi, band).

### Fold candidates (written once, consumed once — could be inlined without loss of clarity)

| Variable | Line | Saves |
|----------|------|-------|
| `k2` — used only for `k4 = k2*k2` | 341 | 1 float |
| `fla` — used only in `pow(fla, 1/3)` | 343 | 1 float |
| `one_mk4` — used only in `one_mk4 * one_mk4 * pow(...)` | 344 | 1 float |
| `clahe_slope` — used only in `iqr_scale` formula | 292 | 1 float |
| `spread_scale` — used only in `FilmCurve` call | 237 | 1 float |
| `eff_p25`, `eff_p75` — each used only in `FilmCurve` call | 235–236 | 2 floats |
| `sin_dt`, `cos_dt` — each used once in f_oka/f_okb | 388–389 | 2 floats |
| `ramp` in R50 block — used only in `saturate(lin - ...)` | 266 | 1 float |

Total foldable: **~10 scalars** → reduces to ~159. Still above 128; the real solution is to
split the Stage 3 chroma block into a helper function so its temporaries are not simultaneously
alive with the Stage 1–2 temporaries. `hist_cache[6]` (24 scalars) could also be reduced by
using a running accumulation instead of caching all 6 samples before summing.

---

## B. Unsafe math sites

| File | Line | Expression | Unsafe condition | Severity |
|------|------|------------|-----------------|----------|
| general/grade/grade.fx | 159–161 | `pow(l, 1.0/3.0)` / `pow(m, …)` / `pow(s, …)` in `RGBtoOklab` | No explicit `max(x,0)` guard; cube-root of negative → NaN. Safe by contract: `lin` is `saturate()`'d at line 311 before this call, so LMS values are guaranteed ≥ 0. | BENIGN |
| general/corrective/corrective.fx | 163–165 | `pow(l, 1.0/3.0)` / `pow(m, …)` / `pow(s, …)` in `RGBtoOklab` inside `UpdateHistoryPS` | Same missing guard; input is raw BackBuffer sample. Safe by construction: BackBuffer is 8-bit UNORM, values ∈ [0,1], so LMS ≥ 0 always. | BENIGN |
| general/grade/grade.fx | 302 | `log2(max(new_luma, 0.001) / illum_s0)` | Both numerator (max-guarded) and denominator (`illum_s0 = max(…, 0.001)`) are ≥ 0.001. | SAFE (guarded) |
| general/corrective/corrective.fx | 339 | `log(max(zm, 0.001))` | Zone median zm from ZoneHistoryTex; max guard ensures arg ≥ 0.001. | SAFE (guarded) |
| general/grade/grade.fx | 397 | `pow(final_C, 0.587)` | `final_C = max(lifted_C, C)` where both terms ≥ 0 by construction (lengths and weighted sums). `pow(0, 0.587) = 0` per IEEE 754. | SAFE |
| general/grade/grade.fx | 345 | `pow(fla, 1.0/3.0)` | `fla = 5.0 * la`, `la = max(zone_log_key, 0.001)` → fla ≥ 0.005. | SAFE (guarded) |
| general/grade/grade.fx | 346 | `sqrt(sqrt(max(fl, 1e-6)))` | Double sqrt of max-guarded value. | SAFE (guarded) |
| general/grade/grade.fx | 380 | `ab_in * (final_C / C_safe)` | `C_safe = max(C, 1e-6)`. | SAFE (guarded) |
| general/grade/grade.fx | 409 | `(1.0 - L_grey) / max(rmax - L_grey, 0.001)` | Denominator max-guarded. | SAFE (guarded) |

**No CRASH or CORRUPT severity sites found.** The two BENIGN pow sites in `RGBtoOklab` are the
only residual fragility — they would produce NaN if upstream saturate() contracts were broken, but
in the current pipeline they are safe.

---

## C. BackBuffer row guard

Row y=0 is the analysis data highway written by `analysis_scope_pre`. The following passes write
BackBuffer and must guard with `if (pos.y < 1.0) return col` before any output.

| Pass | File | Guard present? | Notes |
|------|------|---------------|-------|
| `PassthroughPS` | general/corrective/corrective.fx | **YES** (line 454) | `if (pos.y < 1.0) return c;` — correct placement before DrawLabel writes |
| `ColorTransformPS` | general/grade/grade.fx | **YES** (line 224) | `if (pos.y < 1.0) return col;` — first statement after BackBuffer read, before all processing |
| `DebugOverlayPS` | general/analysis-frame/analysis_frame.fx | **YES** (line 248) | Precautionary; this pass runs before `analysis_scope_pre` writes the highway, so the guard is harmless redundancy rather than a functional requirement |
| `ScopeCapturePS` | general/analysis-scope/analysis_scope_pre.fx | **N/A — IS the writer** | Deliberately writes analysis data to y=0 by design |

**No CRITICAL issues. All BackBuffer-writing downstream passes are correctly guarded.**

Side-note: `corrective.fx` currently declares **8 passes** in its technique block (ComputeLowFreq,
ComputeZoneHistogram, BuildZoneLevels, SmoothZoneLevels, UpdateHistory, WarmBias, ShadowBias,
Passthrough). The HANDOFF.md header says "6 passes" — this is stale documentation, not a code
defect, but worth correcting in the next HANDOFF update.

---

## D. Temporal history accumulation

### EMA blend coefficients

| Filter site | Coefficient | Range in steady state | Range on scene cut | Status |
|-------------|-------------|----------------------|--------------------|--------|
| ZoneHistoryTex — Kalman K (median) | `P_pred / (P_pred + 0.01)` | (0, 1) strictly | lerp toward 1.0 via scene_cut | **OK** — 1.0 on hard cut is intentional R53 reset |
| ZoneHistoryTex — EMA k_ema (p25/p75) | `lerp(0.095, 1.0, scene_cut)` | 0.095 | 1.0 | **OK** — same reasoning |
| ChromaHistoryTex — Kalman K (mean) | `P_pred / (P_pred + 0.01)` | (0, 1) strictly | lerp toward 1.0 | **OK** |
| ChromaHistoryTex — EMA k_ema (std, wsum) | `lerp(0.095, 1.0, scene_cut)` | 0.095 | 1.0 | **OK** |
| PercTex — Kalman K | `P_pred / (P_pred + 0.005)` | (0, 1) strictly | (no scene-cut override in CDFWalkPS) | **OK** |
| LumHistTex / SatHistTex | `saturate(0.043 * frametime_10ms)` | ~0.069 @ 16ms | 1.0 if frametime ≥ 233ms | **OK** — saturate bounds it |
| WarmBiasTex / ShadowBiasTex | `KALMAN_K_INF = 0.095` | 0.095 (constant) | n/a | **OK** — strictly in (0,1) |

No coefficient is hard-wired to 0 (which would freeze history) or 1 (which would discard it),
except by the intentional scene-cut path.

### Texture formats

All history textures use `RGBA16F` or `R16F`. No `RGBA32F` found. ✓

### Cold-start

All three Kalman filters (SmoothZoneLevelsPS, UpdateHistoryPS, CDFWalkPS) detect the uninitialized
state via `if (prev.a < 0.001) P = 1.0`. With P_init = 1.0, K ≈ 0.9999 on frame 1, meaning the
first measurement nearly fully replaces the prior — correct fast-acquisition behavior. After 2–3
frames the filter settles to steady-state gain. No cold-start NaN or freeze. ✓

---

## E. R19–R22 targeted review

### R21 — Hue rotation (grade.fx lines 331–380)

**C=0 achromatic safety:** The 2×2 rotation is applied as:
```
sincos(r21_delta * 0.10 * 6.28318, r21_sin, r21_cos);
ab_in  = float2(lab.y * r21_cos - lab.z * r21_sin,
                lab.y * r21_sin + lab.z * r21_cos);
C_safe = max(C, 1e-6);
ab_s   = ab_in * (final_C / C_safe);
```
For an achromatic pixel, `lab.y = 0` and `lab.z = 0`, so `ab_in = (0, 0)` regardless of the
rotation angle. `ab_s = (0, 0) * (final_C / 1e-6) = (0, 0)`. `C_safe` prevents division by zero
in the scale step, and the zero numerator ensures the result is zero magnitude — no NaN, no
direction artifact. **Safe. ✓**

The `sincos()` call runs for all pixels (including achromatic) but `sincos` is defined for all
real inputs; no NaN risk there.

### R22 — Saturation by luminance (grade.fx lines 327–328)

```
C *= saturate(1.0 - 0.20 * saturate(1.0 - lab.x / 0.25)
                  - 0.25 * saturate((lab.x - 0.75) / 0.25));
```
The inner expression range: both saturate terms ∈ [0,1], so the argument to the outer saturate
is bounded below by `1.0 - 0.20 - 0.25 = 0.55`. The outer saturate is therefore always
applied to a value in [0.55, 1.0] — the `saturate()` itself has no effect here but confirms
the expression is always non-negative. `C ≥ 0` on entry (it is `length(lab.yz)` recomputed after
Purkinje), so `C *= [0.55, 1.0]` cannot produce negative C. **Cannot produce negative C. ✓**

### R19 — 3-way color corrector (grade.fx lines 272–283)

**Can temp/tint deltas push linear values out of [0,1] before Stage 2?** The block ends with:
```
lin = saturate(lin + r19_sh_delta * r19_sh + r19_mid_delta * r19_mid + r19_hl_delta * r19_hl);
```
At maximum knob values (TEMP/TINT = ±100), the per-channel delta is ±0.045 (`(100+50)*0.0003`).
The intermediate `lin + delta` can transiently exceed [0,1], but the `saturate()` at block exit
clamps the final result before lin is used by Stage 2. There is no path where an intermediate
out-of-range value escapes the block. At current tuning (|TEMP|,|TINT| ≤ 5), the maximum
excursion is ±0.0015 — negligible. **No out-of-range values reach Stage 2. ✓**

One note: `r19_mid = 1.0 - r19_sh - r19_hl` could theoretically be negative if the shadow and
highlight regions overlapped, but the shadow mask (luma < 0.35) and highlight mask (luma > 0.65)
have non-overlapping support, so `r19_sh + r19_hl ≤ 1` always. **r19_mid ≥ 0 always. ✓**

---

## Priority fixes

1. **general/grade/grade.fx — Register spill (HIGH): refactor ColorTransformPS**  
   169 declared scalars exceeds the 128-scalar spill threshold. The Stage 3 chroma block
   (lines 315–411) is the densest contributor. Extract it to a helper function (e.g.,
   `float3 ApplyChroma(float3 lin, float zone_log_key, float mean_chroma, float new_luma)`)
   so its ~60 temporaries are not simultaneously alive with Stage 1–2 variables. Also fold
   `k2`, `fla`, `one_mk4`, `spread_scale`, `clahe_slope` (saves ~10 scalars). Target:
   ≤ 128 scalars at any live point.

2. **general/grade/grade.fx:159–161 and general/corrective/corrective.fx:163–165 — Add
   `max(x, 0.0)` guards in RGBtoOklab before cube-root pow (BENIGN, defensive)**  
   Change `l = pow(l, 1.0/3.0)` to `l = pow(max(l, 0.0), 1.0/3.0)` (and same for m, s) in
   both copies of `RGBtoOklab`. The current pipeline guarantees non-negative inputs, but an
   explicit guard makes the function safe by construction rather than by contract, eliminating
   a future footgun if upstream saturate() calls are ever removed or reordered.

3. **research/HANDOFF.md — Update pass count for corrective.fx (documentation)**  
   HANDOFF.md states "6 passes" for corrective.fx. The technique block has 8 passes
   (ComputeLowFreq, ComputeZoneHistogram, BuildZoneLevels, SmoothZoneLevels, UpdateHistory,
   WarmBias, ShadowBias, Passthrough). Update the pass inventory comment.
