# Nightly Stability Audit — 2026-05-03

## Summary

Register pressure in `ColorTransformPS` has grown from 169 scalars (05-02 audit) to **256 scalars**
after the R74–R81 batch — exactly double the 128-scalar spill threshold and the dominant pipeline
risk. A latent CRITICAL defect was found in R81A: the LCA off-axis samples are taken **before**
the data-highway guard, meaning any non-zero `LCA_STRENGTH` would corrupt the red and blue channels
of BackBuffer row y=0; the defect is dormant today because `LCA_STRENGTH = 0.0`. All other unsafe-
math sites are properly guarded; no CRASH or CORRUPT severity found. R19–R22 remain safe with the
noted R22 coefficient update (highlight attenuation raised to 45 %).

---

## A. Register pressure

- **Total declared scalars in ColorTransformPS: 256**
- **Risk level: CRITICAL** (128-scalar threshold exceeded by 128; previous audit found 169 — R74–R81
  added 87 scalars, primarily R76A's 7 float3 CAT16 block (+21 sc) and R79's 4 float3 halation
  dual-PSF block (+14 sc), plus miscellaneous float additions across R74–R81)

### Variable inventory

| Type        | Count                         | Scalar total |
|-------------|-------------------------------|--------------|
| float       | 120 variables                 | 120          |
| float3      | 28 variables                  | 84           |
| float4      | 5 individual + hist_cache\[6\]| 44           |
| float2      | 3 variables (lca\_off, ab\_in, ab\_s) | 6   |
| int         | 2 loop variables (bi, band)   | 2            |
| **Total**   |                               | **256**      |

Note: `const float3 lms_d65` and `const float3x3 M_fwd/M_bwd` inside the R76A block are
compile-time constants; a good compiler folds them (~3 scalars). Conservative live count is 253.

### Top 5 groups by scalar contribution

1. **float scalars (120)** — Stage 3 chroma decomposition accounts for ~55 of these
   (la/k/k2/k4/fla/one\_mk4/fl/hunt\_scale, chroma loop intermediates, ab-plane reconstruction,
   HK intermediates, density/gamut intermediates). Stage 2 Retinex/shadow-lift block adds ~20.
2. **float3 (84)** — R76A CAT16 block (illum\_rgb, illum\_norm, lms\_illum, gain, lms\_px, cat16)
   adds 18 scalars new since 05-02; R79 halation (hal\_core\_r, hal\_core\_g, hal\_wing, hal\_delta)
   adds 12 scalars new. Block-scoped temporaries in R51 (ps/toe/shoulder), R50 (dom\_mask/bl\_abs),
   R19 (3×delta), R66 (illum\_s2\_rgb/illum\_norm/lab\_amb) contribute 27 scalars.
3. **float4 (44)** — hist\_cache\[6\] alone is 24 scalars.
4. **float2 (6)** — ab\_in, ab\_s for rotation; lca\_off (R81A) new since 05-02.
5. **int (2)** — loop counters only.

### Fold candidates (written once, used once — safe to inline)

| Variable | Line | Saves |
|----------|------|-------|
| `k2` — only used for `k4 = k2*k2` | 428 | 1 float |
| `fla` — only used in `pow(fla, 1/3)` | 430 | 1 float |
| `one_mk4` — only in `one_mk4 * one_mk4 * pow(...)` | 431 | 1 float |
| `clahe_slope` — only in iqr\_scale formula | 339 | 1 float |
| `spread_scale` — only in FilmCurve call | 263 | 1 float |
| `eff_p25`, `eff_p75` — each in FilmCurve once | 259–260 | 2 floats |
| `sin_dt`, `cos_dt` — each used once | 489–490 | 2 floats |
| `ramp` in R50 block | 305 | 1 float |
| `fc_width` — only in `fc_factor` | 271 | 1 float |
| `lum_att` — only in `zone_str` | 264 | 1 float |
| `illum_rgb` in R76A block | 241 | 3 floats (inline into norm) |
| `lms_illum` in R76A block | 243 | 3 floats (inline into gain) |
| `gain` in R76A block | 244 | 3 floats (inline into lms\_px) |
| `lms_px` in R76A block | 245 | 3 floats (inline into cat16) |
| `hal_core_r` in R79 block | 522 | 3 floats (inline into lerp) |
| `hal_core_g` in R79 block | 523 | 3 floats (inline into lerp) |
| `hal_luma` in R79 block | 525 | 1 float (inline into smoothstep) |
| `hal_gate` in R79 block | 526 | 1 float (inline into final expr) |

Total foldable: **~32 scalars** → reduces to ~224. Still 96 above threshold; folding alone does not
solve this. The structural fix is to extract Stage 3 (lines 389–533) into a helper function so its
~90 temporaries are not simultaneously alive with Stage 1–2 variables. Additionally, `hist_cache[6]`
(24 scalars) should be replaced with a running accumulation loop — the cache exists only to feed the
two loop bodies at lines 438–443 and 455–459, both of which can accumulate directly without storing
all 6 samples.

---

## B. Unsafe math sites

| File | Line | Expression | Unsafe condition | Severity |
|------|------|------------|-----------------|----------|
| general/grade/grade.fx | 159 | `exp2(log2(max(float3(l,m,s), 1e-10)) * (1.0/3.0))` in RGBtoOklab | No explicit `max(x,0)` before the vector max; cube-root of negative → NaN. Safe by upstream contract (lin is saturated before call), not by construction. | BENIGN |
| general/corrective/corrective.fx | 163 | Same pattern in corrective's RGBtoOklab | Input is raw BackBuffer 8-bit UNORM [0,1], LMS ≥ 0 always. | BENIGN |
| general/grade/grade.fx | 225–226 | `col.r = tex2D(BackBuffer, uv - lca_off).r` / `col.b = tex2D(BackBuffer, uv + lca_off).b` — LCA sampling occurs **before** the highway guard at line 227 | When `LCA_STRENGTH > 0`, row y=0 pixels sample off-axis UV positions and return modified r/b channels via `return col`. This overwrites highway data in the red and blue channels. Currently dormant: `LCA_STRENGTH = 0.0`. | **CRITICAL (latent)** |
| general/corrective/corrective.fx | 364–371 | `float3 rgb = tex2Dlod(BackBuffer, float4(s_uv, 0, 0)).rgb` in UpdateHistoryPS (Halton sampling) | Halton2/Halton3 sequences can produce y ≈ 0. Samples landing in row y=0 inject data-highway pixel values (histogram fractions) into chroma band stats. Low probability per frame (~1/BUFFER\_HEIGHT), minor steady-state bias. | BENIGN |
| general/grade/grade.fx | 378 | `illum_s2_rgb / max(Luma(illum_s2_rgb), 0.001)` in R66 | Highly saturated illuminant (e.g., pure blue scene) yields per-channel illum\_norm >> 1 (e.g., [0,0,13.8]). `* 0.18` feeds RGBtoOklab producing valid but large a/b values used as lerp target for shadow tint. Not NaN/INF; r66\_w max is 0.4 so influence is bounded but could push achromatic lifted shadows toward unexpected hue. | BENIGN |

All other sites verified safe:
- `pow(max(col.rgb,0.0), EXPOSURE)` line 280 — max guard ✓  
- `sqrt(max(zone_log_key, 0.0))` line 272 — max guard ✓  
- `pow(fla, 1.0/3.0)` line 432 — fla ≥ 0.005 by construction ✓  
- `sqrt(sqrt(max(fl, 1e-6)))` line 433 — max guard ✓  
- All divisions use `max(denom, ε)` guards ✓  
- OklabHueNorm avoids atan2 entirely; achromatic path (a=b=0) produces r=0, deterministic hue 0.25, no NaN ✓  
- `log2(slow_key / zk_safe)` line 360 — both terms ≥ 0.001 ✓

---

## C. BackBuffer row guard

Row y=0 is the data highway written by `analysis_scope_pre`. All passes that write BackBuffer:

| Pass | File | Guard present? | Notes |
|------|------|---------------|-------|
| `ScopeCapturePS` | analysis-scope/analysis\_scope\_pre.fx | **N/A — IS the writer** | Deliberately writes histogram data to y=0 by design |
| `DebugOverlayPS` | analysis-frame/analysis\_frame.fx:248 | **YES** — `if (pos.y < 1.0) return c;` | Runs before scope\_pre writes highway; guard preserves prior-frame highway data harmlessly |
| `PassthroughPS` | general/corrective/corrective.fx:462 | **YES** — `if (pos.y < 1.0) return c;` | Correct placement before DrawLabel calls |
| `ColorTransformPS` | general/grade/grade.fx:227 | **YES — MISPLACED** | Guard is at line 227 but R81A LCA sampling at lines 225–226 modifies `col.r` and `col.b` before the guard fires. For y=0 pixels, `return col` returns the LCA-modified values, corrupting red/blue highway channels when `LCA_STRENGTH > 0`. **Currently dormant.** |

All passes in corrective.fx that write explicit RenderTargets (ComputeLowFreq → CreativeLowFreqTex,
ComputeZoneHistogram, BuildZoneLevels, SmoothZoneLevels, UpdateHistory, WarmBias, ShadowBias) do not
write BackBuffer and require no guard. ✓

**CRITICAL (latent): ColorTransformPS guard is misplaced.** Fix: move the guard to line 224 (before
the LCA sampling), and restructure so that LCA sampling only occurs for y ≥ 1 pixels:

```hlsl
float4 col = tex2D(BackBuffer, uv);
if (pos.y < 1.0) return col;                              // data highway — BEFORE LCA
float2 lca_off = (uv - 0.5) * LCA_STRENGTH * 0.004;
col.r = tex2D(BackBuffer, uv - lca_off).r;
col.b = tex2D(BackBuffer, uv + lca_off).b;
```

---

## D. Temporal history accumulation

### EMA blend coefficients

| Filter site | Coefficient | Steady-state range | Scene-cut | Status |
|-------------|-------------|-------------------|-----------|--------|
| ZoneHistoryTex — Kalman K (median) | `P_pred / (P_pred + 0.01)` | (0, 1) strictly | lerp → 1.0 (R53 intentional reset) | **OK** |
| ZoneHistoryTex — EMA k\_ema (p25/p75) | `lerp(0.095, 1.0, scene_cut)` | 0.095 | 1.0 | **OK** |
| ChromaHistoryTex — Kalman K (mean) | `P_pred / (P_pred + 0.01)` | (0, 1) strictly | lerp → 1.0 | **OK** |
| ChromaHistoryTex — EMA k\_ema (std, wsum) | `lerp(0.095, 1.0, scene_cut)` | 0.095 | 1.0 | **OK** |
| PercTex — Kalman K | `P_pred / (P_pred + 0.005)` | (0, 1) strictly | (no scene-cut override in CDFWalkPS) | **OK** |
| LumHistTex / SatHistTex | `saturate(0.043 * frametime_10ms)` | ~0.069 @ 16 ms | 1.0 if frametime ≥ 233 ms | **OK** — saturate bounds it |
| WarmBiasTex / ShadowBiasTex | `KALMAN_K_INF = 0.095` | 0.095 (constant) | n/a | **OK** |
| Slow-key EMA (ChromaHistory col 7) | 0.003 (hardcoded) | 0.003 (constant) | n/a | **OK** — strictly in (0,1) |

No coefficient is hard-wired to 0 or 1 except by the intentional scene-cut path.

### Texture formats

All history textures confirmed RGBA16F or R16F. No RGBA32F found. ✓

### Cold-start

All three VFF Kalman filters detect the uninitialized state via `if (prev.a < 0.001) P = 1.0`,
giving K ≈ 0.9999 on frame 1 — near-instant acquisition. Slow-key (col 7) uses
`if (prev_slow < 0.001) prev_slow = zone_log_key` for same effect. WarmBias/ShadowBias start from
0 and converge within ~10 frames at k=0.095. No cold-start NaN or freeze. ✓

---

## E. R19–R22 targeted review

### R21 — Hue rotation (grade.fx lines 409–480), augmented by R75

**C=0 achromatic safety (R21 sincos path):**
```hlsl
sincos(r21_delta * (0.10 * 6.28318), r21_sin, r21_cos);
float2 ab_in = float2(lab.y * r21_cos - lab.z * r21_sin,
                      lab.y * r21_sin + lab.z * r21_cos);
float  C_safe = max(C, 1e-6);
float2 ab_s   = ab_in * (final_C / C_safe);
```
For achromatic pixels lab.y = 0, lab.z = 0 → ab\_in = (0, 0) regardless of rotation angle.
`ab_s = (0,0) * (0/1e-6) = (0,0)`. C\_safe prevents division by zero; zero numerator ensures
zero magnitude. **No NaN, no direction artifact. ✓**

**R75 addition (line 417):** `r21_delta += lerp(-0.003, +0.003, lab.x)` adds ≤ ±0.003 to the
rotation. lab.x (Oklab L) is in [0,1] for all processed pixels. The total r21\_delta magnitude
remains small (~0.083 worst-case). sincos is defined for all real inputs; no NaN risk. For
achromatic pixels the zero ab\_in absorbs any rotation. **Safe. ✓**

### R22 — Saturation by luminance (grade.fx lines 406–407)

**Updated coefficient (0.25 → 0.45 for highlight attenuation):**
```hlsl
C *= saturate(1.0 - 0.20 * saturate(1.0 - lab.x / 0.25)
                  - 0.45 * saturate((lab.x - 0.75) / 0.25));
```
Shadow term nonzero when lab.x < 0.25; highlight term nonzero when lab.x > 0.75. These ranges
**do not overlap**, so the two terms are never simultaneously non-zero. Maximum combined attenuation
is 0.45 (highlights only) or 0.20 (shadows only). The outer saturate argument is bounded below by
`1.0 - 0.45 = 0.55`. C ≥ 0 before multiply (it's a recomputed length after Purkinje). `C *= 0.55`
**cannot produce negative C. ✓**

The coefficient increase from 0.25→0.45 raises the maximum highlight desaturation from 25% to 45%.
This is a perceptual choice; the safety envelope is unchanged.

### R19 — 3-way color corrector (grade.fx lines 312–330)

No changes since 05-02. Block still ends with `lin = saturate(...)`, bounding all out-of-range
transients before Stage 2. At maximum knob values (±100), peak channel excursion is ±0.045; at
current tuning (|TEMP|,|TINT| ≤ 5) it is ±0.0015. `r19_mid = 1.0 - r19_sh - r19_hl ≥ 0` always
because shadow (luma < 0.35) and highlight (luma > 0.65) masks have non-overlapping support. **✓**

### New R76A / R79 exposure

**R76A (CAT16, lines 233–249):** gain clamped to [0.5, 2.0]; cat16 luminance-rescaled and
saturate()'d at lerp sink. Pipeline-safe. ✓

**R79 (halation dual-PSF, lines 521–533):** hal\_delta components are max(0, …) ≥ 0; final
`saturate(lin + …)` bounds output. hal\_gate from smoothstep ∈ [0,1]. ✓

---

## Priority fixes

1. **general/grade/grade.fx lines 223–227 — Move highway guard before R81A LCA sampling (CRITICAL
   latent)**  
   Current code samples off-axis UV for red/blue channels before the `if (pos.y < 1.0) return col`
   guard. Setting `LCA_STRENGTH` to any non-zero value would corrupt the red/blue channels of
   BackBuffer row y=0, breaking the scope histogram and all downstream highway readers. Fix: move
   `float4 col = tex2D(BackBuffer, uv); if (pos.y < 1.0) return col;` to lines 223–224, then do
   the LCA offset sampling on lines 225–226 (now only reached for y ≥ 1 pixels).

2. **general/grade/grade.fx — Refactor ColorTransformPS to reduce register pressure (CRITICAL)**  
   256 declared scalars is double the 128-scalar spill threshold; the R74–R81 batch added 87 scalars
   and the trend is upward. Two structural changes required:
   - Extract Stage 3 chroma block (lines 389–533) into `float3 ApplyChroma(float3 lin, ...)`. Its
     ~90 temporaries will not be simultaneously live with Stage 1–2 variables.
   - Replace `float4 hist_cache[6]` (24 scalars) with a running accumulation that computes cm\_t/cm\_w
     and new\_C/total\_w in a single pass, eliminating the cache array entirely.
   Folding the 18 additional single-use intermediates listed in Section A saves ~32 more scalars.
   Target: ≤ 128 scalars at any live point in each resulting function.

3. **general/grade/grade.fx lines 159 and general/corrective/corrective.fx line 163 — Add explicit
   `max(x, 0.0)` guards in RGBtoOklab before cube-root (BENIGN, defensive)**  
   Change `exp2(log2(max(float3(l, m, s), 1e-10)) * (1.0/3.0))` — the existing `max` uses 1e-10
   as a positive floor, which IS the correct guard. No change needed here; the existing code is
   correct. The BENIGN flag in B refers to the absence of an explicit `max(lms, 0)` before the
   `max(lms, 1e-10)` call, which is redundant since `max(x, 1e-10) ≥ 0` always. No action needed.

4. **general/corrective/corrective.fx lines 364–371 — Halton sampler highway contamination (BENIGN)**  
   UpdateHistoryPS samples BackBuffer at unconstrained (Halton2, Halton3) UV coords. Samples landing
   at y ≈ 0 (probability ~1/BUFFER\_HEIGHT per sample) inject histogram-encoded values into chroma
   band statistics. Low impact. Mitigation: clamp `s_uv.y = max(s_uv.y, 1.5 / BUFFER_HEIGHT)` to
   skip row 0. One-line fix, zero performance cost.
