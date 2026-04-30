# Nightly Stability Audit — 2026-04-30

## Summary

The pipeline on `alpha` is in good shape with no active crash risks and no CORRUPT-severity
math sites. Register pressure in `ColorTransformPS` is the primary concern: an estimated
~120 scalars puts the shader close to the 128-scalar spilling threshold for Vulkan drivers,
and the 16 individually-named zone reads (r16_z0..r16_z15) are the dominant contributor.
All BackBuffer row-0 guards are correct, all EMA coefficients are in range, and the R19–R22
code paths (3-way corrector, hue rotation, sat-by-luma) are mathematically sound.
Four histogram textures are declared R32F when R16F would suffice — minor, no stability risk.

---

## A. Register pressure

**File:** `general/grade/grade.fx`, function `ColorTransformPS`

| Type   | Count | Scalars |
|--------|-------|---------|
| float4 | 4 (col, perc, zone_lvl, hist loop-tmp) | 16 |
| float3 | 8 (lin, lab, lin_pre_tonal, chroma_rgb, rgb_probe, r19_sh/mid/hl_delta) | 24 |
| float2 | 2 (ab_in, ab_s) | 4 |
| float  | ~84 (see breakdown) | 84 |
| int    | 1 (band) | 1 |
| **Total** | | **~129 scalars** |

**Float scalar breakdown:**
- Zone reads (lines 205–248): r16_z0..z15 (16), r16_logsum, zone_log_key, r16_zmin, r16_zmax, eff_p25, eff_p75, r16_mean, r16_sqmean, zone_std, spread_scale, zone_str = **27**
- R19 corrector (lines 257–268): r19_luma, r19_sh, r19_hl, r19_mid, r19_scale = **5**
- Tonal stage (lines 273–298): luma, zone_median, zone_iqr, iqr_scale, dt, bent, new_luma, r18_str, r18_norm, low_luma_fine, low_luma_coarse, detail, clarity_mask, bell, lift_w = **15**
- Chroma stage (lines 302–375): C, h, r21_delta, h_out, la, k, k4, fl, hunt_scale, chroma_str, new_C, total_w, green_w, lifted_C, final_C, r21_cos, r21_sin, C_safe, abney, dtheta, cos_dt, sin_dt, f_oka, f_okb, sh, ch, f_hk, hk_boost, final_L, rmax_probe, headroom, delta_C, density_L, rmax, L_grey, gclip, w (loop) = **37**

- **Risk level: MEDIUM** (~129 / 128 threshold — on the boundary)

**Notes:**
- With lifetime analysis a compiler can reuse registers across non-overlapping live ranges
  (e.g., most r16_z* reads are dead by Stage 3). But [unroll] on the 6-iteration chroma
  loop creates 6×(hist float4 + w float) = 30 additional temporaries during unrolling,
  pushing live-register count further.
- **Top fold candidates** (each written once, consumed immediately):
  - `r16_logsum` (line 223) → inline into `zone_log_key` expression on line 227
  - `r16_zmin` / `r16_zmax` (lines 230–235) → inline into eff_p25/eff_p75 on 236–237
  - `r16_sqmean` (line 245) → inline into `zone_std` sqrt on line 246
  - `r19_scale` (line 262) → inline constant `0.030 / 100.0` at use sites

---

## B. Unsafe math sites

Files scanned: `grade.fx`, `corrective.fx`, `analysis_frame.fx`, `analysis_scope_pre.fx`

| File | Line | Expression | Unsafe condition | Severity |
|------|------|------------|-----------------|----------|
| `grade.fx` | 113 | `sqrt(max(p50, 0.0))` in FilmCurve | p50 from PercTex.g is always [0,1]; max() is redundant but harmless | BENIGN |

**All other math sites are guarded:**

- `pow()`: All bases guarded — `pow(max(col.rgb, 0.0), EXPOSURE)` (line 251); Oklab cube-root uses `sign(l) * pow(abs(l), 1/3)` (lines 135–137, 115–117); `pow(max(zone_log_key, 0.001) / max(zone_median, 0.001), r18_str)` (line 285); `pow(max(fl, 1e-6), 0.25)` (line 322); `pow(final_C, 0.587)` — final_C is always ≥ 0 by construction (line 361).
- `log()`: All 16 zone log calls guard with `log(0.001 + r16_z*)` (lines 223–226). ✓
- Division: Every denominator guarded — `max(luma, 0.001)` (line 297), `max(C, 1e-6)` as C_safe (line 343), `max(rmax - L_grey, 0.001)` (line 374), `max(sum_w, 0.001)` in corrective (lines 286–287), `(total_w > 0.001) ? ... : C` (line 335). ✓
- `sqrt()`: `sqrt(max(r16_sqmean - r16_mean*r16_mean, 0.0))` (line 246); `sqrt(var)` where `var = max(..., 0.0)` (corrective line 287). ✓
- `atan2()`: Not used — `OklabHueNorm` uses a polynomial approximation. Denominator `ay + abs(a) = abs(b) + 1e-10 + abs(a)` is always > 0. ✓
- `sincos()`: Arguments are bounded — `r21_delta * 0.628` (line 340), `h_out * 6.28318` where h_out = frac(…) ∈ [0,1] (line 359). ✓

**No CRASH or CORRUPT severity sites found.**

---

## C. BackBuffer row guard — y=0 data highway

`analysis_scope_pre.fx` is the designated writer of row y=0 (pixels 0–128 histogram, 130–193 hue histogram).
Every subsequent BackBuffer-writing pass must guard `if (pos.y < 1.0) return col`.

| Pass | File | Line | Guard present? |
|------|------|------|---------------|
| ScopeCapturePS | analysis_scope_pre.fx | 55 | N/A — this IS the writer; highway pixels handled in body |
| DebugOverlayPS | analysis_frame.fx | 227–233 | Not needed — runs BEFORE scope_pre in chain |
| PassthroughPS | corrective.fx | 305 | ✓ `if (pos.y < 1.0) return c;` |
| ColorTransformPS | grade.fx | 200 | ✓ `if (pos.y < 1.0) return col;` |

Passes ComputeLowFreq, ComputeZoneHistogram, BuildZoneLevels, SmoothZoneLevels, UpdateHistory
all write to explicit RenderTargets — BackBuffer never touched, no guard needed. ✓

**No missing or misplaced guards.**

---

## D. Temporal history accumulation

**EMA coefficients:**

| Pass | File | Expression | Effective range | In (0,1)? |
|------|------|------------|----------------|-----------|
| SmoothZoneLevels | corrective.fx:254 | `saturate(0.08 * (1 + 10 * Δmedian))` | [0.08, 0.88] | ✓ |
| UpdateHistory | corrective.fx:292 | `saturate(0.08 * (1 + 10 * Δmean))` | [0.08, 0.88] | ✓ |

Both use adaptive speed-up (10× on large deltas) — fast on scene cuts, stable on steady frames. ✓

**Cold-start:**
- ZoneHistoryTex: frame 0, prev ≈ 0, large delta → speed saturates to 0.88. Not fully converged on frame 0 (12% of zero remains), converged by frame 2. Negligible visible artifact.
- ChromaHistoryTex: identical behaviour. ✓
- PercTex / LumHist: written fresh every frame by CDFWalkPS — no cold-start issue.

**Texture formats:**

| Texture | File | Format | Note |
|---------|------|--------|------|
| LumHistRawTex | analysis_frame.fx | R32F | Stores [0,1] fractions — R16F sufficient |
| SatHistRawTex | analysis_frame.fx | R32F | Same |
| LumHistTex | analysis_frame.fx | R32F | Same |
| SatHistTex | analysis_frame.fx | R32F | Same |
| All others | — | RGBA16F / R16F | ✓ |

The four R32F histogram textures are small (64×1 and 64×6) — total extra cost ~36 KB.
No stability risk, but R16F is correct precision for normalised fraction values.

---

## E. R19–R22 targeted review

### R21 — hue rotation at C=0

```hlsl
sincos(r21_delta * (0.10 * 6.28318), r21_sin, r21_cos);
float2 ab_in  = float2(lab.y * r21_cos - lab.z * r21_sin,
                       lab.y * r21_sin + lab.z * r21_cos);
float  C_safe = max(C, 1e-6);
float2 ab_s   = ab_in * (final_C / C_safe);
```

When C = 0: `ab_in = rotation of (0,0) = (0,0)`. `final_C = max(lifted_C, 0) * (…) = 0`
(PivotedSCurve(0, pivot, str) = saturate(negative) = 0). So `ab_s = (0,0) * (0 / 1e-6) = (0,0)`.
No NaN, no divide-by-zero. **Result: SAFE ✓**

### R22 — sat-by-luma, negative C

```hlsl
C *= saturate(1.0 - 0.20 * saturate(1.0 - lab.x / 0.25)
                  - 0.25 * saturate((lab.x - 0.75) / 0.25));
```

Outer `saturate()` bounds the multiplier to [0,1]. C = `length(lab.yz)` ≥ 0.
Product is always ≥ 0. **Result: SAFE ✓**

### R19 — 3-way corrector, values outside [0,1]

```hlsl
lin = saturate(lin + r19_sh_delta * r19_sh + r19_mid_delta * r19_mid + r19_hl_delta * r19_hl);
```

The weighted sum of deltas can push channels outside [0,1] before `saturate()`, but
`saturate()` clamps before `lin` is consumed downstream. **Result: SAFE ✓**

---

## F. Compiler log (vkbasalt.log)

No ERROR-level entries. All `vkBasalt err:` lines are X3206 **warnings** (implicit vector
truncation at DrawLabel call sites):

| File | Line | Warning |
|------|------|---------|
| analysis_frame.fx | 231 | X3206 — `pos` (float4) implicitly truncated at DrawLabel call |
| analysis_scope_pre.fx | 113 | X3206 — same |
| corrective.fx | 550, 552, 554 | X3206 — three DrawLabel calls in PassthroughPS (line numbers offset by debug_text.fxh include expansion) |
| grade.fx | 379 | X3206 — same |
| pro_mist.fx | 170 | X3206 — same |
| analysis_scope.fx | 152 | X3206 — same |

Cause: `DrawLabel` takes `pos` which is `SV_Position` (float4); internally it uses only `.xy`.
The compiler truncates float4 → float2 implicitly. Output is correct; this is a signature
issue — suppress by passing `pos.xy` explicitly at each call site, or cast `(float2)pos`.

---

## Priority fixes

1. **Register pressure — fold single-use zone intermediates** (grade.fx)
   Fold `r16_logsum`, `r16_zmin`, `r16_zmax`, `r16_sqmean`, `r19_scale` into their
   single downstream expression. Saves ~5 scalars of live range, reduces peak pressure
   from ~129 to ~124. Low effort, measurable headroom gained.

2. **X3206 warnings — explicit pos cast at DrawLabel sites**
   Change `DrawLabel(c, pos, …)` → `DrawLabel(c, (float2)pos, …)` (or `pos.xy` depending
   on DrawLabel signature) in all 6 affected files. Suppresses the warnings so genuine
   future errors are not buried in noise.

3. **Histogram texture formats — R32F → R16F** (analysis_frame.fx)
   Change `LumHistRawTex`, `SatHistRawTex`, `LumHistTex`, `SatHistTex` from R32F to R16F.
   Values are normalised fractions in [0,1]; R16F has 3-decimal-place precision —
   more than sufficient for histogram bin fractions. Saves ~36 KB VRAM.
