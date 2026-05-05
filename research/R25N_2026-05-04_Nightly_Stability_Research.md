# Nightly Stability Audit — 2026-05-04

## Summary

Register pressure in `ColorTransformPS` is the dominant structural risk: ~240 declared scalars (non-loop-expanded) versus the 128-scalar spill threshold, making GPU register spilling likely on many Vulkan drivers.  All unsafe-math sites are properly guarded — no NaN/INF paths found.  BackBuffer highway guards are intact on every BB-writing pass; temporal EMAs are within bounds; R19–R22 targeted review finds no defects.

---

## A. Register pressure

**Methodology:** every distinct local variable declared inside `ColorTransformPS` (grade.fx lines 221–551) was enumerated and typed.  Loop-local variables counted once (unroll expansion noted separately).  Compile-time-foldable `const` matrices noted but excluded from the pressure total.

### Totals by type

| Type      | Variables | Scalars |
|-----------|-----------|---------|
| float     | 119       | 119     |
| float3    | 29        | 87      |
| float4    | 6 (non-loop) | 24   |
| float2    | 4         | 8       |
| int       | 2 (loop vars) | 2   |
| **Total** | **160**   | **240** |

*Excluded from total (compile-time constants, likely folded by SPIR-V compiler):*
- `const float3x3 M_fwd` (line 233): 9 scalars
- `const float3x3 M_bwd` (line 236): 9 scalars
- `const float3 lms_d65` (line 239): 3 scalars

*Loop expansion (both loops are `[unroll]`):*
- First loop (6 iters): `float4 hc` per iteration → +20 additional scalars
- Second loop (6 iters): `float pivot`, `float w` per iteration → +10 additional scalars
- **Worst-case total with unroll expansion: ~270 scalars**

### Risk level: **CRITICAL**

240 declared scalars is 1.9× the 128-scalar spill threshold.  Drivers that spill to VRAM will show frame-time spikes and potential hangs on lower-VRAM configurations.  A previous audit (R26) identified this; the codebase has grown since.

### Top 5 variable groups by scalar cost

1. **Stage 3 CHROMA float scalars** — `C`, `h`, `h_perc`, `r21_delta`, `h_out`, `hw_o0–hw_o5`, `_k`, `_k4`, `_omk4`, `hunt_scale`, `cm_t/w`, `mean_chroma`, `chroma_exp`, `chroma_mc/p50_t`, `chroma_drive/str`, `density_str`, `new_C`, `total_w`, `lifted_C`, `vib_mask/C`, `C_ceil`, `final_C`, `r21_cos/sin`, `C_safe`, `abney`, `dtheta`, `cos/sin_dt`, `f_oka/b`, `sh/ch`, `f_hk`, `hk_boost`, `final_L`, `headroom`, `delta_C`, `density_L`, `ck_near/fac`, `rmax_probe`, `L_grey`, `gclip_ok` — **~45 scalars**

2. **float3 group: CAT16 + halation + R66 blocks** — `lms_illum_norm`, `illum_rgb`, `illum_norm` (×2 scopes), `lms_illum`, `gain`, `lms_px`, `cat16` (CAT16); `illum_s2_rgb`, `lab_amb` (R66); `hal_core_r/g`, `hal_wing`, `hal_delta` (halation) — 14 vars × 3 = **42 scalars**

3. **Stage 2 TONAL float scalars** — `luma`, `zone_median`, `zone_iqr`, `clahe_slope`, `iqr_scale`, `new_luma`, `illum_s0`, `illum_s2`, `local_var`, `nl_safe`, `log_R`, `zk_safe`, `local_range_att`, `texture_att`, `detail_protect`, `slow_key`, `context_lift`, `shadow_lift_str`, `shadow_lift`, `lift_w`, `r_tonal`, `cbrt_r`, `r65_ab`, `r65_sw`, `scene_cut`, `achrom_w`, `r66_w` — **27 scalars**

4. **float3 group: lin and tonal pipeline** — `lin`, `lin_pre_tonal`, `lab_t`, `lab`, `rgb_probe`, `chroma_rgb`, `r19_sh/mid/hl_delta`, `dom_mask`, `bl_abs`, `bl_x`, `ps`, `toe`, `shoulder` — 15 vars × 3 = **45 scalars**

5. **Zone/FilmCurve frame-constants** — `zone_log_key`, `zone_std`, `eff_p25/p75`, `ss_08_25`, `ss_04_25`, `spread_scale`, `lum_att`, `zone_str`, `fc_knee`, `fc_stevens`, `fc_factor`, `fc_knee_toe`, `fc_knee_r/b`, `fc_ktoe_r/b`, `fc_toe_fac` — **18 scalars**

### Fold candidates (written once, consumed once or aliased)

| Variable | Line | Notes |
|----------|------|-------|
| `sin_dt` | 500 | `= dtheta` — pure alias, used only at line 502; fold into `f_okb` expression |
| `r65_ab` | 381 | `= cbrt_r` — pure alias, used at lines 383–384; fold inline |
| `illum_s2` | 358 | `= max(lf_mip2.a, 0.001)` — used only at line 359 for `local_var`; fold inline |
| `fc_stevens` | 274 | used once in `fc_factor` on line 275; fold inline |
| `spread_scale` | 266 | used once in `fc_factor` on line 275; fold inline |

---

## B. Unsafe math sites

Scanned: grade.fx (full), corrective.fx (full), analysis_frame.fx (full), analysis_scope_pre.fx (full).  All safety-critical operations (log, pow, sqrt, division, atan2-equivalent) were individually traced.

| File | Line | Expression | Unsafe condition | Severity |
|------|------|------------|-----------------|----------|
| — | — | — | *No unsafe sites found* | — |

### Detailed findings

**log / log2:**
- `grade.fx:159`, `corrective.fx:163` — `log2(max(float3(l,m,s), 1e-10))` in `RGBtoOklab`; guarded. SAFE.
- `grade.fx:361` — `log2(nl_safe / illum_s0)` where `nl_safe ≥ 0.001`, `illum_s0 ≥ 0.001`; quotient always > 0. SAFE.
- `grade.fx:370` — `log2(slow_key / zk_safe)` where both ≥ 0.001. SAFE.
- `corrective.fx:339` — `log2(max(zm, 0.001))`. SAFE.
- `analysis_frame.fx:259` — `log2(max(perc.b, 0.01))`, `log2(max(perc.r, 0.01))`. SAFE.

**pow with negative base:**
- `grade.fx:251` — `pow(max(col.rgb, 0.0), VIEWING_SURROUND)`: base clamped ≥ 0. SAFE.
- `grade.fx:283` — `pow(max(col.rgb, 0.0), EXPOSURE)`: base clamped ≥ 0. SAFE.
- `grade.fx:508` — `pow(final_C, 0.587)`: `final_C ≥ 0` by construction (derived from `length()`). SAFE.
- `grade.fx:443` — `pow(5.0 * zone_log_key, 1.0/3.0)`: `zone_log_key = exp2(...)` always > 0. SAFE.

**division by zero:**
- `grade.fx:241` — `illum_rgb / max(Luma(illum_rgb), 0.001)`. SAFE.
- `grade.fx:243` — `lms_illum / max(lms_illum.g, 0.001)`. SAFE.
- `grade.fx:244` — `lms_d65 / max(lms_illum, 0.001)` per-component. SAFE.
- `grade.fx:247` — `Luma(col.rgb) / max(Luma(cat16), 0.001)`. SAFE.
- `grade.fx:309` — `(lin - lin_min) / max(sat_proxy, 0.001)`. SAFE.
- `grade.fx:351` — `(clahe_slope - 1.0) / max(zone_str, 0.001)`. SAFE.
- `grade.fx:372` — `0.149169 / (illum_s0 * illum_s0 + 0.003)`: denominator ≥ 0.003. SAFE.
- `grade.fx:377` — `new_luma / max(luma, 0.001)`. SAFE.
- `grade.fx:454` — `cm_t / max(cm_w, 0.001)`. SAFE.
- `grade.fx:473` — `new_C / total_w` inside `(total_w > 0.001) ?` guard. SAFE.
- `grade.fx:490` — `final_C / C_safe` where `C_safe = max(C, 1e-6)`. SAFE.
- `grade.fx:509` — `lab.x / lerp(1.0, hk_boost, ...)`: denominator ≥ ~0.8 (hk_boost bounded by Hellwig coefficients). SAFE.
- `grade.fx:526` — `(1.0 - L_grey) / max(rmax_probe - L_grey, 0.001)`. SAFE.
- `corrective.fx:380` — `sum_wc / max(sum_w, 0.001)`. SAFE.
- `analysis_frame.fx:307` — `1.0 / frc` inside `(frc > 0.0) ?` guard. SAFE.

**sqrt with negative argument:**
- `grade.fx:274` — `sqrt(max(zone_log_key, 0.0))`. SAFE.
- `grade.fx:442` — `sqrt(sqrt(max(..., 1e-6)))`. SAFE.
- `corrective.fx:347` — `sqrt(max(m2 * 0.0625 - zavg * zavg, 0.0))`: variance clamped. SAFE.
- `corrective.fx:383` — `sqrt(max(..., 0.0))`. SAFE.

**atan2(0,0) equivalent:**
- `grade.fx:183–189` — `OklabHueNorm(a, b)`: denominator `ay + abs(a) = abs(b) + 1e-10 + abs(a)` ≥ 1e-10 for all inputs including a=0, b=0. SAFE.

---

## C. BackBuffer row guard

Passes writing BackBuffer (no explicit `RenderTarget` in technique block):

| Pass | File | Lines | Guard present? | Notes |
|------|------|-------|---------------|-------|
| `PassthroughPS` | corrective.fx | 461–472 | **YES** — line 464: `if (pos.y < 1.0) return c;` | Final corrective pass; keeps BB alive for grade.fx |
| `ColorTransformPS` | grade.fx | 220–551 | **YES** — line 223: `if (pos.y < 1.0) return col;` | Guard is the first action after initial BackBuffer read |
| `DebugOverlayPS` | analysis_frame.fx | 243–267 | **INTENTIONAL WRITER** — `if (pos.y < 1.0)` block writes xi=194–197, passes through all other row-0 pixels | Legal highway extension; does not corrupt scope_pre data (xi 0–193) |
| `ScopeCapturePS` | analysis_scope_pre.fx | 52–115 | **INTENTIONAL WRITER** — two gated conditions for `pos.y < 1.0`; xi 0–128 and xi 130–193 written; all others pass through | Primary highway writer; correct by design |

**No missing or misplaced guards.** All non-intentional BB writers guard at or before the first write.

Guard placement note for `ColorTransformPS`: the guard at line 223 fires before the LCA sample rewrite at lines 226–227, so row-0 data is returned untouched even when `LCA_STRENGTH > 0`. Correct.

---

## D. Temporal history accumulation

### EMA / Kalman blend coefficients

| History texture | Pass | Coefficient | Range | Notes |
|-----------------|------|-------------|-------|-------|
| `ZoneHistoryTex` | `SmoothZoneLevelsPS` | Kalman K (line 307) | (0, 1) strictly — `P_pred / (P_pred + 0.01)`, P_pred > 0 | On scene cut: `lerp(K, 1.0, scene_cut)` → K=1.0 when cut=1; intentional, discards history on hard cut |
| `ZoneHistoryTex` | `SmoothZoneLevelsPS` | EMA `k_ema` (line 315) | [KALMAN_K_INF=0.095, 1.0] | 1.0 on scene cut — intentional |
| `ChromaHistoryTex` (bands 0–5) | `UpdateHistoryPS` | Kalman K (line 392) | (0, 1) — same formula | Same scene-cut boundary at 1.0 |
| `ChromaHistoryTex` (band 7, slow key) | `UpdateHistoryPS` | 0.003 (line 357) | Constant ∈ (0,1) | Very long time constant; acceptable |
| `WarmBiasTex` | `WarmBiasPS` | KALMAN_K_INF = 0.095 (line 429) | Constant ∈ (0,1) | SAFE |
| `ShadowBiasTex` | `ShadowBiasPS` | KALMAN_K_INF = 0.095 (line 455) | Constant ∈ (0,1) | SAFE |
| `PercTex` | `CDFWalkPS` | Kalman K (line 333) | (0, 1) strictly | SAFE |

**All coefficients are strictly within (0, 1) in steady state.**  The scene-cut path drives coefficients to 1.0, which is an intentional design choice (instant adaptation on hard cuts), not a bug.

### Texture formats

| Texture | Format | Notes |
|---------|--------|-------|
| `ZoneHistoryTex` | RGBA16F | OK |
| `ChromaHistoryTex` | RGBA16F | OK |
| `WarmBiasTex` | RGBA16F | OK |
| `ShadowBiasTex` | RGBA16F | OK |
| `PercTex` | RGBA16F | OK |
| `SceneCutTex` | RGBA16F | OK |
| `CreativeLowFreqTex` | RGBA16F | OK |

No RGBA32F textures found.  All bounded formats. ✓

### Cold-start behaviour

- **ZoneHistoryTex / ChromaHistoryTex (Kalman):** `P_prev = (prev.a < 0.001) ? 1.0 : prev.a` at corrective.fx lines 302 and 387. Uninitialized texture has `.a = 0`; P is set to 1.0 → K approaches 1.0 → first measurement fully adopted. **Handled.**
- **ChromaHistoryTex band 7 (slow key):** `if (prev_slow < 0.001) prev_slow = zone_log_key` (line 356). Seeds with current frame value. **Handled.**
- **WarmBiasTex / ShadowBiasTex:** No explicit cold-start seed; first frame blends 0 toward measured value with weight 0.095.  Converges within ~20 frames.  **Acceptable; not a crash.**
- **PercTex:** `P = (prev.a < 0.001) ? 1.0 : prev.a` (line 329).  **Handled.**
- **SceneCutTex:** First frame `p50_prev = 0`; scene_cut fires on first frame (large delta).  This is cosmetic (one-frame Kalman spike); all downstream readers tolerate scene_cut ∈ [0,1]. **Acceptable.**

---

## E. R19–R22 targeted review

### R21: Hue rotation — C=0 (achromatic) path via sincos

The rotation is implemented as a vector-space 2D rotation (grade.fx lines 485–490), not as sincos on a `C=0` hue angle:

```hlsl
sincos(r21_delta * (0.10 * 6.28318), r21_sin, r21_cos);   // line 486
float2 ab_in  = float2(lab.y * r21_cos - lab.z * r21_sin, // line 487
                       lab.y * r21_sin + lab.z * r21_cos); // line 488
float  C_safe = max(C, 1e-6);                              // line 489
float2 ab_s   = ab_in * (final_C / C_safe);                // line 490
```

When `lab.y = 0` and `lab.z = 0` (achromatic, C=0):
- `ab_in = (0, 0)` — zero vector; rotation of a zero vector is zero regardless of angle. No NaN from sincos.
- `final_C`: traced through R22 → C=0, through chroma lift loop → `PivotedSCurve(0, pivot, str) = saturate(pivot - pivot*(1 + str*(1-pivot))) = saturate(-pivot*str*(1-pivot)) = 0` (all factors positive, result negative, saturate clamps to 0). So `new_C = 0`, `lifted_C = 0`, `vib_C = 0`, `final_C = min(0, max(C_ceil, 0)) = 0`.
- `ab_s = (0, 0) * (0 / 1e-6) = (0, 0)`. No NaN — numerator is zero.
- Downstream: `f_oka = 0`, `f_okb = 0`. Output is achromatic. **No NaN possible. ✓**

`sincos` argument order at line 486 (`r21_sin` first, `r21_cos` second) matches HLSL signature `sincos(x, out s, out c)`. **Correct.**

### R22: Saturation by luminance — can C go negative?

```hlsl
C *= (1.0 - 0.20 * saturate(1.0 - lab.x / 0.25)
         - 0.45 * saturate((lab.x - 0.75) / 0.25));  // lines 419–420
```

Shadow term is nonzero only when `lab.x < 0.25`; highlight term is nonzero only when `lab.x > 0.75`.  These ranges are disjoint — both terms cannot be simultaneously nonzero.  Maximum combined reduction: max(0.20, 0.45) = 0.45.  Minimum factor = 1.0 − 0.45 = **0.55 > 0**.

Since `C = length(lab.yz) ≥ 0` and the factor ≥ 0.55, `C` after R22 is ≥ 0 and cannot go negative. **No negative C. ✓**

### R19: 3-way corrector — linear values before Stage 2

```hlsl
lin = saturate(lin + r19_sh_delta * r19_sh + r19_mid_delta * r19_mid + r19_hl_delta * r19_hl);
// line 339
```

The `saturate()` wrapping the entire R19 output unconditionally clamps to [0, 1] before Stage 2 sees any values.  Even at extreme knob settings (TEMP=±100, TINT=±100, sh_temp_auto=±22), the maximum per-channel delta is ±(122 + 50) × 0.0003 ≈ ±0.0516, and any resulting out-of-range values are clipped by `saturate()`.

At current values (SHADOW_TEMP=−5, MID_TEMP=+3, HIGHLIGHT_TEMP=−3, all TINT=0, sh_temp_auto bounded by zone_std gate), deltas are ≤ ±0.0015 per channel.  **No out-of-range values enter Stage 2. ✓**

---

## Priority fixes

1. **Register spilling — grade.fx ColorTransformPS (~240 scalars, threshold 128):** Split the function at the Stage 3 boundary: extract the chroma pipeline (lines 401–527) into a second pixel shader consuming a float-point intermediate render target (e.g., RGBA16F), and chain it as a second pass within the same `OlofssonianColorGrade` technique. This halves per-shader register pressure and eliminates the spill risk on affected drivers. Cross-reference R26, R64 which have previously modeled this split. File: `general/grade/grade.fx`, lines 400–527.

2. **Fold register aliases to recover ~5 scalars:** `sin_dt` (grade.fx:500), `r65_ab` (grade.fx:381), `illum_s2` (grade.fx:358), `fc_stevens` (grade.fx:274), `spread_scale` (grade.fx:266) are all single-use aliases. Inlining them eliminates 5 scalar registers at zero cost. Small gain individually, but worthwhile alongside any broader scalar-reduction effort.

3. *(Informational)* `analysis_scope_pre.fx line 58` declares a `float samples[64]` local array. Per CLAUDE.md the forbidden form is `static const float[]`; this plain local array should be fine in SPIR-V. Monitor for driver-specific issues if scope output appears corrupted.
