# Nightly Stability Audit — 2026-05-01

## Summary

Register pressure in `ColorTransformPS` is the primary structural concern: 140 scalars at source-declaration level (185 worst-case with `[unroll]` amplification), exceeding the 128-scalar Vulkan driver spilling threshold by 12–57 scalars. The unsafe-math picture is largely clean — all log/sqrt/div/pow sites carry guards — with one genuine CORRUPT risk in `analysis_frame.fx` where a frametime-scaled EMA coefficient is unclamped and can exceed 1.0 during low-FPS stutters. All BackBuffer row guards are present and correctly positioned. Temporal history formats and cold-start handling are sound; the EMA coefficient issue in `analysis_frame` is the only temporal correctness gap.

---

## A. Register pressure

**Source file:** `general/grade/grade.fx` — `ColorTransformPS` (lines 197–378)

### Variable inventory

| Type | Variables (declaration sites) | Scalars (source-level) | Scalars (with `[unroll]`) |
|------|-------------------------------|------------------------|--------------------------|
| `float4` | col, perc, zstats, zone_lvl, bs¹, hist¹, pixel — **7** | 28 | 20 + 24 + 24 = **68** |
| `float3` | lin, r19_sh_delta, r19_mid_delta, r19_hl_delta, lin_pre_tonal, lab, rgb_probe, chroma_rgb — **8** | 24 | 24 |
| `float2` | ab_in, ab_s — **2** | 4 | 4 |
| `float` | zone_log_key, zone_std, eff_p25, eff_p75, spread_scale, zone_str, r19_luma, r19_sh, r19_hl, r19_mid, r19_scale, luma, zone_median, zone_iqr, clahe_slope, iqr_scale, dt, bent, new_luma, r18_str, illum_s0, illum_s1, illum_s2, luma_s, log_R, retinex_luma, D1, D2, D3, e1, e2, e3, e_sum, detail, clarity_mask, sd, g, stevens_att, spread_att, auto_clarity, shadow_lift, lift_w, C, h, r21_delta, h_out, la, k, k4, fl, hunt_scale, cm_t, cm_w, mean_chroma, chroma_adapt, chroma_str, density_str, new_C, total_w, green_w, w¹, lifted_C, final_C, r21_cos, r21_sin, C_safe, abney, dtheta, cos_dt, sin_dt, f_oka, f_okb, sh, ch, f_hk, hk_boost, final_L, rmax_probe, headroom, delta_C, density_L, rmax, L_grey, gclip — **84** | 84 | 89² |
| `int` | bi, band — **2** | — (int regs) | — |
| **TOTAL (float regs)** | | **140** | **~185** |

¹ Loop-local inside `[unroll]` loop over 6 bands — at source level 1 declaration site each; with full unroll the compiler allocates 6 independent register slots per variable.  
² Adds 5 for `w` amplified ×6.

- **Total estimated scalars in ColorTransformPS: 140 (source-level) / ~185 (unroll worst-case)**
- **Risk level: HIGH** — 140 exceeds the 128-scalar spilling threshold at source-declaration level; unroll amplification can push to ~185, making spilling nearly certain on AMD RDNA and some Intel Arc drivers.
- Note: inlined helper bodies (`FilmCurve` ~17 scalars, `OklabHueNorm` ~3, `HueBandWeight` ~2 × 12 calls) add further pressure not reflected above.

### Top variable groups (by scalar contribution)

| Rank | Group | Count | Scalar contribution |
|------|-------|-------|-------------------|
| 1 | `float` scalars | 84 vars | 84 |
| 2 | `float4` | 7 declaration sites | 28 (source) / 68 (unrolled) |
| 3 | `float3` | 8 vars | 24 |
| 4 | `float2` | 2 vars | 4 |
| 5 | `int` | 2 vars | 2 (non-float) |

### Fold candidates (written once, consumed in one expression)

| Variable(s) | Line(s) | What to fold | Scalars saved |
|------------|---------|-------------|---------------|
| `pixel` | 375 | `return DrawLabel(float4(lin, col.a), …)` | **4** |
| `e1, e2, e3, e_sum` | 265–268 | Inline into `detail` expression: `D1*(D1*D1/…) + …` | **4** |
| `dt, bent` | 244–245 | Fold chain: `new_luma = saturate(zone_median + (luma-zone_median)*(1 + zone_str*iqr_scale*(1-saturate(abs(luma-zone_median)))))` | **2** |
| `retinex_luma` | 258 | Fold directly into `lerp` on line 259 | **1** |
| `luma_s` | 254 | Inline `max(new_luma,0.001)` into log calls | **1** |
| `rmax_probe` | 363 | Fold into `headroom = saturate(1.0 - max(rgb_probe.r,…))` | **1** |
| `r19_scale` | 225 | Replace with literal `0.0003` in delta expressions | **1** |
| **Total** | | | **14 scalars → 126 (below threshold)** |

---

## B. Unsafe math sites

| File | Line | Expression | Unsafe condition | Severity |
|------|------|------------|-----------------|----------|
| `analysis_frame.fx` | 247 | `lerp(prev, raw, (LERP_SPEED/100.0)*(frametime/10.0))` | `frametime > ~233 ms` (< ~4 fps, or stutter pause) → coefficient > 1.0 → lerp extrapolates outside [0,1] on R16F texture | **CORRUPT** |
| `analysis_frame.fx` | 257 | same pattern in `SatHistSmoothPS` | same | **CORRUPT** |
| `general/grade/grade.fx` | 288 | `OklabHueNorm(lab.y, lab.z)` when `lab.y=0, lab.z=0` (achromatic) | `abs(b)+1e-10` bias prevents NaN; hue output is arbitrary (~0.25) — downstream `HueBandWeight` and `r21_delta` receive coherent but meaningless hue. Produces cosmetically wrong hue for grey pixels only. | **BENIGN** |

**All other checked sites are guarded:**

- `grade.fx:214` — `pow(max(col.rgb, 0.0), EXPOSURE)` — `max` guard ✓
- `grade.fx:255–257` — `log(luma_s / illum_sN)` — both operands floored at `0.001` ✓
- `grade.fx:258` — `log(max(zone_log_key, 0.001))` — guarded ✓
- `grade.fx:272` — `sqrt(abs(detail))` — `abs` guard ✓
- `grade.fx:287` — `length(lab.yz)` (implicit sqrt of sum-of-squares) — always ≥ 0 ✓
- `grade.fx:307` — `pow(max(fl, 1e-6), 0.25)` — guarded ✓
- `grade.fx:332` — `new_C / total_w` — ternary guard `(total_w > 0.001)` ✓
- `grade.fx:341` — `final_C / C_safe` where `C_safe = max(C, 1e-6)` ✓
- `grade.fx:371` — `(1-L_grey) / max(rmax-L_grey, 0.001)` ✓
- `corrective.fx:291` — `log(max(zm, 0.001))` zone median ✓
- `corrective.fx:299` — `sqrt(max(m2*0.0625 - zavg*zavg, 0.0))` ✓
- `corrective.fx:325` — `sqrt(var)` where `var = max(…, 0.0)` ✓
- `analysis_frame.fx:278` — `(frc > 0.0) ? 1.0/frc : 0.0` ✓

---

## C. BackBuffer row guard

Passes without an explicit `RenderTarget` (i.e., those that write BackBuffer) in the two audited files:

| Pass | File | Shader function | Guard present? | Guard location | Notes |
|------|------|----------------|----------------|----------------|-------|
| `Passthrough` | `corrective.fx` | `PassthroughPS` | **YES** | Line 350 — before `DrawLabel` | ✓ Correct |
| `ColorTransform` | `grade.fx` | `ColorTransformPS` | **YES** | Line 200 — immediately after BB sample, before all processing | ✓ Correct |

All other passes in both files specify explicit `RenderTarget`s and are exempt from the guard requirement.

**No CRITICAL findings** — both guards are present and positioned before any write.

**Addendum:** `analysis_frame.fx` `DebugOverlayPS` (also a BackBuffer writer) carries a guard at line 235. `HANDOFF.md` (R27 note) described this as a latent open item; the guard is present in the current code and the HANDOFF entry is stale.

---

## D. Temporal history accumulation

### EMA blend coefficients

| Location | Coefficient expression | Range analysis | Status |
|----------|----------------------|----------------|--------|
| `corrective.fx:268–269` | `KALMAN_K_INF = 0.095` (p25/p75 EMA) | Literal constant — strictly in (0,1) | ✓ |
| `corrective.fx:339–340` | `KALMAN_K_INF = 0.095` (std/wsum EMA) | Same | ✓ |
| `corrective.fx` Kalman K | `P_pred / (P_pred + KALMAN_R)` | `P_pred > 0`, `KALMAN_R = 0.01 > 0` → K ∈ (0,1) always | ✓ |
| `analysis_frame.fx:247` | `(4.3/100) * (frametime/10)` | At 60 fps ≈ 0.072; at ~4 fps ≈ 1.0; **below ~4 fps > 1.0** | **FAIL** — not bounded |
| `analysis_frame.fx:257` | same | same | **FAIL** |
| `analysis_frame.fx` Kalman K | `P_pred / (P_pred + KALMAN_R_PERC)` | `KALMAN_R_PERC = 0.005 > 0` → K ∈ (0,1) always | ✓ |

### History texture formats

| Texture | Format declared | R/W file | Status |
|---------|----------------|----------|--------|
| `ZoneHistoryTex` | `RGBA16F` | corrective.fx | ✓ |
| `ChromaHistoryTex` | `RGBA16F` | corrective.fx | ✓ |
| `PercTex` | `RGBA16F` | analysis_frame.fx | ✓ |
| `CreativeLowFreqTex` | `RGBA16F` | corrective.fx | ✓ |
| `CreativeZoneHistTex` | `R16F` | corrective.fx | ✓ |
| `CreativeZoneLevelsTex` | `RGBA16F` | corrective.fx | ✓ |
| `LumHistTex` / `LumHistRawTex` | `R16F` | analysis_frame.fx | ✓ |
| `SatHistTex` / `SatHistRawTex` | `R16F` | analysis_frame.fx | ✓ |

**No RGBA32F textures found** across all audited files. ✓

### Cold-start frame

- `ZoneHistoryTex`, `ChromaHistoryTex`, `PercTex`: all Kalman filters guard with `(prev.a < 0.001) ? 1.0 : prev.a` — on frame 0 the uninitialized `.a = 0` triggers P_prev = 1.0, giving K ≈ 0.99 (near-instant convergence). ✓
- `LumHistTex` / `SatHistTex` (EMA only): on frame 0 the feedback texture reads GPU-zero, producing `lerp(0, raw, factor) = raw * factor` — attenuated first-frame histogram. Not a crash; converges within ~10 frames. **BENIGN.**

---

## E. R19–R22 targeted review

### R21 — hue rotation: sincos path at C=0 (achromatic pixels)

The rotation reconstructs (a,b) in vector space via:
```hlsl
sincos(r21_delta * (0.10 * 6.28318), r21_sin, r21_cos);
float2 ab_in  = float2(lab.y * r21_cos - lab.z * r21_sin,
                       lab.y * r21_sin + lab.z * r21_cos);
float  C_safe = max(C, 1e-6);
float2 ab_s   = ab_in * (final_C / C_safe);
```

For an achromatic pixel: `lab.y = 0, lab.z = 0` → `ab_in = (0,0)`. `C_safe = max(0, 1e-6) = 1e-6`. `final_C`: C=0 after R22 scaling, and `PivotedSCurve(0, pivot>0, str)` returns `saturate(negative) = 0`, so `new_C = 0`, `lifted_C = 0`, `final_C = 0`. Therefore `ab_s = (0,0) * 0 = (0,0)`. **No NaN at any step. Safe by construction. ✓**

Note: `OklabHueNorm(0,0)` returns ≈ 0.25 (via 1e-10 bias), giving a nonzero `r21_delta` and a valid (if meaningless) sincos call — but it feeds only `ab_in` which is zero anyway.

### R22 — sat-by-luma: can chained saturate() produce negative C?

```hlsl
C *= saturate(1.0 - 0.20 * saturate(1.0 - lab.x / 0.25)
                  - 0.25 * saturate((lab.x - 0.75) / 0.25));
```

Let A = saturate(1 − lab.x/0.25), B = saturate((lab.x − 0.75)/0.25). A=1 requires lab.x ≤ 0; B=1 requires lab.x ≥ 1.0 — these are **mutually exclusive** in SDR (lab.x ∈ [0,1]). Therefore:
- A=1, B=0: multiplier = 1.0 − 0.20 = **0.80**
- A=0, B=1: multiplier = 1.0 − 0.25 = **0.75**
- Any mixed case: minimum ≥ 0.75

Inner expression is always ≥ 0.75 before the outer `saturate()`. **C cannot become negative. The outer `saturate()` is never exercised. ✓**

### R19 — 3-way corrector: can temp/tint deltas push linear values below 0 or above 1 before Stage 2?

With knob ranges ±100 and `r19_scale = 0.030/100 = 0.0003`, the maximum per-channel delta magnitude from any single region is (|TEMP| + |TINT|×0.5) × 0.0003 ≤ (100 + 50) × 0.0003 = 0.045. Across all three regions their weights sum to 1.0 (r19_sh + r19_mid + r19_hl = 1), so worst-case total delta in any channel ≤ 0.045 — a shift too small to take an in-range [0,1] value out of [−0.05, 1.05]. The explicit `saturate()` on line 231 clamps the result to [0,1] **before Stage 2 reads `lin`**. **Safe by construction. ✓**

---

## Priority fixes

1. **`analysis_frame.fx:247,257` — CORRUPT: clamp frametime-scaled EMA coefficient**  
   Both `LumHistSmoothPS` and `SatHistSmoothPS` use `(LERP_SPEED/100.0) * (frametime/10.0)` as the lerp weight without bounding it. At < ~4 fps (or any pause/stutter producing frametime > 233 ms) the weight exceeds 1.0, causing lerp to extrapolate and corrupt the smoothed histogram textures that feed the CDF walk and percentile cache.  
   **Fix:** wrap the coefficient in `saturate()`:
   ```hlsl
   // Before (line 247 / 257):
   lerp(prev, raw, (LERP_SPEED / 100.0) * (frametime / 10.0))
   // After:
   lerp(prev, raw, saturate((LERP_SPEED / 100.0) * (frametime / 10.0)))
   ```

2. **`general/grade/grade.fx:265–375` — HIGH: fold register pressure below 128 scalars**  
   Source-level scalar count is 140, unroll-amplified worst-case ~185. Apply the fold candidates identified in Section A to save ~14 scalars (to ~126) and bring the shader below the Vulkan driver spilling threshold. Highest-value individual folds: `pixel` (−4), `e1/e2/e3/e_sum` (−4), `dt/bent` (−2). Consider also splitting the `[unroll] for (int band …)` loop into a non-unrolled loop if the driver allows it, to avoid the 40-scalar hit from `bs` and `hist` amplification.

3. **`general/grade/grade.fx` — LOW: stale HANDOFF note (cosmetic)**  
   `HANDOFF.md` R27 section lists "`analysis_frame` DebugOverlay missing guard" as an open item. The guard is present at `analysis_frame.fx:235`. Update HANDOFF to close this item on next human-initiated edit session.
