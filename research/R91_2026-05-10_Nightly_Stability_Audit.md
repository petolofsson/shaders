# Nightly Stability Audit — 2026-05-10

## Summary

Register pressure in `ColorTransformPS` is the dominant crash risk: an estimated **166 scalars** are live simultaneously, exceeding the 128-scalar spill threshold by 38 scalars; this is consistent with the intermittent crashes beginning after the R19–R22 batch, which contributed 24 new scalars to the function. All other tasks pass cleanly — BackBuffer row guards are intact, temporal history textures use bounded formats with functioning cold-start detection, and the R19–R22 code paths contain no NaN-producing sites.

---

## A. Register Pressure

**Total estimated scalars in `ColorTransformPS` (grade.fx): 166**
**Risk level: HIGH — exceeds 128-scalar spill threshold by 38 scalars**

### Variable census

| Type      | Count | Scalars |
|-----------|-------|---------|
| `float`   | 75 variables | 75 |
| `float3`  | 15 variables | 45 |
| `float4`  | 4 variables + `hist_cache[6]` | 40 |
| `float2`  | 2 variables | 4 |
| `int`     | 2 loop variables | 2 |
| **Total** | | **166** |

### Top 5 groups by scalar weight

1. **`float` scalars — 75 scalars** (zone stats, tonal intermediates, chroma scalars, HK prep, density, dither)
2. **`float3` — 45 scalars** across 15 variables: `lin`, `ps`, `toe`, `shoulder`, `dom_mask`, `r19_sh_delta`, `r19_mid_delta`, `r19_hl_delta`, `lin_pre_tonal`, `lab`, `rgb_probe`, `chroma_rgb`, `hal_r`, `hal_g`, `hal_delta`
3. **`float4` — 40 scalars**: `hist_cache[6]` array alone accounts for 24 of these; `col`, `perc`, `zstats`, `zone_lvl` add 16
4. **`float2` — 4 scalars**: `ab_in`, `ab_s`
5. **`int` — 2 scalars**: loop vars `bi`, `band`

### Single-use fold candidates (each saves 1 scalar)

| Variable | Line | Consumer |
|----------|------|----------|
| `lum_att` | 238 | Only used in `zone_str` expression (line 239–240) |
| `spread_scale` | 237 | Only used in `FilmCurve` call (line 243) |
| `cos_dt`, `sin_dt` | 384–385 | Only used in `f_oka`/`f_okb` (lines 386–387) |
| `k2`, `k4`, `one_mk4` | 337–340 | Only used in `fl` (line 341) |
| `C_safe` | 375 | Only used in `ab_s` (line 376) |
| `delta_C` | 399 | Only used in `density_L` (line 400) |
| `headroom` | 398 | Only used in `density_L` (line 400) |

Folding these 9 variables recovers 9 scalars → ~157 scalars. Still above threshold; the largest single reduction would be eliminating `hist_cache[6]` (24 scalars) by reading `ChromaHistory` inline inside the two loops rather than pre-caching — this alone would bring the total to ~142 scalars, still above threshold but below the worst-case spill band on most drivers.

The R19 block (`r19_sh_delta`, `r19_mid_delta`, `r19_hl_delta`, `r19_sh/mid/hl`, `r19_luma` — 13 scalars) and the R56 halation block (`hal_r`, `hal_g`, `hal_delta`, `hal_luma`, `hal_gate` — 11 scalars) together added 24 scalars in the post-R19 batch, pushing the function from an estimated ~142 to ~166 scalars.

---

## B. Unsafe Math Sites

| File | Line | Expression | Unsafe condition | Severity |
|------|------|------------|-----------------|----------|
| corrective.fx | 163–165 | `pow(l, 1.0/3.0)` in `RGBtoOklab` | Called from `UpdateHistoryPS` with raw BackBuffer sample (`tex2Dlod(BackBuffer, ...)`); no `max(rgb, 0)` guard before call; if driver emits negative texel values, `pow(negative, 1/3)` is SPIR-V undefined | BENIGN (vkBasalt guarantees [0,1] linearised sRGB) |

All other sites checked:

- **`log2` (grade.fx:300)** — `log2(max(new_luma, 0.001) / illum_s0)` where `illum_s0 = max(..., 0.001)`. Both bounds guarded. PASS.
- **`log` (corrective.fx:339)** — `log(max(zm, 0.001))`. Guarded. PASS.
- **`pow(max(col.rgb, 0.0), EXPOSURE)` (grade.fx:243)** — explicit `max` guard. PASS.
- **`pow(fla, 1.0/3.0)` (grade.fx:341)** — `fla = 5 * la`, `la = max(zone_log_key, 0.001) ≥ 0.005`. PASS.
- **`pow(final_C, 0.587)` (grade.fx:393)** — `final_C = max(lifted_C, C)`, both non-negative. PASS.
- **`sqrt(sqrt(max(fl, 1e-6)))` (grade.fx:342)** — inner `max` guard. PASS.
- **`sqrt(max(..., 0.0))` (corrective.fx:347, 373)** — guarded. PASS.
- **All divisions** — `max()` denominators present throughout (`max(luma, 0.001)`, `max(zone_str, 0.001)`, `max(cm_w, 0.001)`, `max(C, 1e-6)`, `max(rmax - L_grey, 0.001)`, etc.). PASS.
- **`atan2(0,0)`** — no `atan2` calls present; `OklabHueNorm` uses a polynomial approximation with `abs(b) + 1e-10` and `sign(b + 1e-10)` epsilon offsets, making (0,0) safe. PASS.

---

## C. BackBuffer Row Guard

Passes writing to BackBuffer (no explicit `RenderTarget` in technique block):

| Pass | File | Guard line | Guard present? |
|------|------|------------|----------------|
| `ScopeCapturePS` | analysis_scope_pre.fx | — | N/A — this is the **data highway writer**; conditional writes to y=0 are intentional |
| `DebugOverlayPS` | analysis_frame.fx | 247 | **YES** — `if (pos.y < 1.0) return c;` |
| `PassthroughPS` | corrective.fx | 454 | **YES** — `if (pos.y < 1.0) return c;` |
| `ColorTransformPS` | grade.fx | 224 | **YES** — `if (pos.y < 1.0) return col;` |

All guards are correctly positioned as the first action after the BackBuffer read, before any processing or write. No missing or misplaced guards. PASS.

---

## D. Temporal History

### EMA coefficients

| Texture | Pass | Coefficient | Bounded (0,1)? |
|---------|------|-------------|----------------|
| `ZoneHistoryTex` | `SmoothZoneLevelsPS` | Kalman K = P_pred/(P_pred+0.01) | Yes — except K=1.0 on scene cuts (R53, intentional) |
| `ZoneHistoryTex` p25/p75 | `SmoothZoneLevelsPS` | `k_ema = lerp(0.095, 1.0, scene_cut)` | Yes — 0.095 steady-state, 1.0 on cut (intentional) |
| `ChromaHistoryTex` | `UpdateHistoryPS` | Kalman K = P_pred/(P_pred+0.01) | Yes — same scene-cut caveat |
| `WarmBiasTex` | `WarmBiasPS` | `KALMAN_K_INF = 0.095` | Yes — constant |
| `ShadowBiasTex` | `ShadowBiasPS` | `KALMAN_K_INF = 0.095` | Yes — constant |
| `PercTex` | `CDFWalkPS` | Kalman K = P_pred/(P_pred+0.005) | Yes |
| `LumHistTex` / `SatHistTex` | `LumHistSmoothPS` / `SatHistSmoothPS` | `saturate((4.3/100) * (frametime/10))` | Yes — but saturates to 1.0 at frametime ≥ 233 ms (~4 fps); no smoothing at very low framerates, not a crash risk |

Note: K=1.0 on scene cuts is intentional per R53 design — it discards history to snap to the new scene. This is "discard history" by design, not a defect.

### Texture formats

All history textures confirmed:
- `ZoneHistoryTex`: RGBA16F ✓
- `ChromaHistoryTex`: RGBA16F ✓
- `PercTex`: RGBA16F ✓
- `SceneCutTex`: RGBA16F ✓
- `WarmBiasTex`: RGBA16F ✓
- `ShadowBiasTex`: RGBA16F ✓
- `CreativeLowFreqTex`: RGBA16F (MipLevels=3) ✓
- `CreativeZoneHistTex`: R16F ✓
- `CreativeZoneLevelsTex`: RGBA16F ✓
- `LumHistTex` / `LumHistRawTex`: R16F ✓
- `SatHistTex` / `SatHistRawTex`: R16F ✓

No RGBA32F found. PASS.

### Cold-start safety

All three Kalman-filtered textures (`ZoneHistoryTex`, `ChromaHistoryTex`, `PercTex`) detect the uninitialized state via `prev.a < 0.001` and set `P_prev = 1.0`, driving K toward ~0.99 on frame 0 — the first measurement is accepted essentially unfiltered. No texture is read before it has been written; all paths through ColorTransformPS that depend on history textures converge to valid (non-NaN) values on frame 0 because all division denominators have `max()` guards. PASS.

---

## E. R19–R22 Targeted Review

### R21 — Hue rotation, zero-chroma case (grade.fx:327–376)

**sincos path:** `sincos(r21_delta * 0.6283, r21_sin, r21_cos)` — `r21_delta` is a weighted sum of finite ROT_* knobs × HueBandWeight values ∈ [0,1]. `sincos` is well-defined for all finite inputs. No NaN possible on any input. PASS.

**Zero-chroma case (C=0 → lab.y=lab.z=0):**
- `OklabHueNorm(0, 0)`: `ay = 1e-10`, `sign(0) = 0`, `r = 0`, `th = π/2`, returns `frac(0.25 + 1.0) = 0.25` — valid normalized hue, no division by zero or NaN. PASS.
- `ab_in = (0 * r21_cos − 0 * r21_sin, 0 * r21_sin + 0 * r21_cos) = (0, 0)`
- `C_safe = max(0, 1e-6) = 1e-6`; `final_C = max(0, 0) = 0`
- `ab_s = (0, 0) * (0 / 1e-6) = (0, 0)` — no NaN (numerator 0 dominates) ✓
- Downstream: `f_oka = 0`, `f_okb = 0` → achromatic pixel stays achromatic. PASS.

### R22 — Saturation-by-luminance, negative C check (grade.fx:323–324)

```
C *= saturate(1.0 - 0.20 * saturate(1.0 - lab.x / 0.25)
                  - 0.25 * saturate((lab.x - 0.75) / 0.25));
```

- `C = length(lab.yz) ≥ 0` (length is always non-negative).
- The two inner `saturate()` calls are in [0, 0.20] and [0, 0.25] respectively. Shadow weight is high when `lab.x < 0.25`; highlight weight is high when `lab.x > 0.75` — the two cannot both be large simultaneously.
- Outer `saturate(1.0 − ≤0.45) ≥ 0.55` — always ≥ 0.55 > 0.
- `C *= [0.55, 1.0]` → C stays non-negative. Cannot produce negative C. PASS.

### R19 — 3-way corrector, linear value range (grade.fx:272–283)

```
lin = saturate(lin + r19_sh_delta * r19_sh + r19_mid_delta * r19_mid + r19_hl_delta * r19_hl);
```

- At this point `lin` has been through `FilmCurve → R51 → R50`, all ending in `saturate()` — so `lin ∈ [0, 1]`.
- Maximum delta magnitude per channel: `(|TEMP| + |TINT| * 0.5) * 0.0003 = (100 + 50) * 0.0003 = 0.045`.
- Region weights `r19_sh + r19_mid + r19_hl` partition [0,1] — their weighted sum of deltas is bounded by ±0.045.
- Final `saturate()` hard-clamps to [0, 1] before Stage 2. Cannot push below 0 or above 1. PASS.

---

## Priority Fixes

1. **grade.fx — Register pressure (HIGH):** `ColorTransformPS` carries ~166 live scalars, 38 above the 128-scalar spill threshold. The highest-impact single change: convert `float4 hist_cache[6]` (24 scalars, grade.fx:345–350) to inline reads inside the two per-band loops — this saves 24 scalars and brings the count to ~142. Secondary: fold the 9 single-use scalar intermediates listed in §A to save a further 9 scalars (~133 total). Both changes are mechanical and non-semantic; neither affects output values. **This is the most probable root cause of the post-R19 intermittent crashes.**

2. **corrective.fx:361 — `RGBtoOklab` called without input guard (BENIGN now, CORRUPT if input assumptions break):** `rgb = tex2Dlod(BackBuffer, ...)` at line 361 passes directly into `RGBtoOklab` without a `max(rgb, 0)` guard; if BackBuffer ever contains negative values (NaN propagation from a prior frame or driver anomaly), `pow(negative, 1/3)` is SPIR-V undefined and can corrupt `ChromaHistoryTex`. Recommend adding `float3 rgb_safe = max(rgb, 0.0);` before the `RGBtoOklab` call. One-line fix.

---

## Log

`/tmp/vkbasalt.log` — **not present** at audit time. No ERROR or WARNING lines to report.
