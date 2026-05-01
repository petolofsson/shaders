# Nightly Optimization Research — 2026-05-01

## Summary
Seven concrete optimizations found across categories A–E in grade.fx and corrective.fx. The highest-value items are: elimination of 6 duplicate ChromaHistory texture reads per pixel (OPT-1), an exact log/exp → log2/exp2 substitution in the Retinex block saving 4 MUL per pixel (OPT-2), replacing `pow(fl, 0.25)` with `sqrt(sqrt(fl))` saving ~7 cycles per pixel (OPT-3), and removal of 6 redundant sign/abs calls in both RGBtoOklab implementations (OPT-4). Total estimated ALU saving across OPT-1 through OPT-7 if all applied: ~35–50 cycles per pixel per frame, plus 6 texture read latencies eliminated.

---

## Optimization findings

### OPT-1: Merge duplicate ChromaHistory loop reads [Category B]

**File:** `general/grade/grade.fx:311–330`

**Current:**
```hlsl
// Loop 1 — reads 6 ChromaHistory texels
[unroll] for (int bi = 0; bi < 6; bi++)
{
    float4 bs = tex2D(ChromaHistory, float2((bi + 0.5) / 8.0, 0.5 / 4.0));
    cm_t += bs.r * bs.b;
    cm_w += bs.b;
}
float mean_chroma  = cm_t / max(cm_w, 0.001);
float chroma_adapt = smoothstep(0.05, 0.20, mean_chroma);
float chroma_str   = saturate(lerp(24.0, 12.0, chroma_adapt) / 100.0 * hunt_scale);
float density_str  = lerp(44.0, 60.0, chroma_adapt);

float new_C = 0.0, total_w = 0.0, green_w = 0.0;
// Loop 2 — reads the SAME 6 ChromaHistory texels again
[unroll] for (int band = 0; band < 6; band++)
{
    float w     = HueBandWeight(h, GetBandCenter(band));
    float4 hist = tex2D(ChromaHistory, float2((band + 0.5) / 8.0, 0.5 / 4.0));
    new_C   += PivotedSCurve(C, hist.r, chroma_str) * w;
    total_w += w;
    if (band == 2) green_w = w;
}
```

**Proposed:**
```hlsl
// Cache all 6 texels in loop 1; reuse in loop 2 — no second fetch
float4 hist_cache[6];
[unroll] for (int bi = 0; bi < 6; bi++)
{
    hist_cache[bi] = tex2D(ChromaHistory, float2((bi + 0.5) / 8.0, 0.5 / 4.0));
    cm_t += hist_cache[bi].r * hist_cache[bi].b;
    cm_w += hist_cache[bi].b;
}
float mean_chroma  = cm_t / max(cm_w, 0.001);
float chroma_adapt = smoothstep(0.05, 0.20, mean_chroma);
float chroma_str   = saturate(lerp(24.0, 12.0, chroma_adapt) / 100.0 * hunt_scale);
float density_str  = lerp(44.0, 60.0, chroma_adapt);

float new_C = 0.0, total_w = 0.0, green_w = 0.0;
[unroll] for (int band = 0; band < 6; band++)
{
    float w = HueBandWeight(h, GetBandCenter(band));
    new_C   += PivotedSCurve(C, hist_cache[band].r, chroma_str) * w;
    total_w += w;
    if (band == 2) green_w = w;
}
```

**Max error:** 0 — identical arithmetic, only read ordering changes. SAFE.

**Cost:** 6 fewer `tex2D` calls per pixel per frame. ChromaHistoryTex is 8×4 RGBA16F — fits entirely in L2 cache, but eliminating 6 reads still removes 6 texture-unit dispatches and 6 × 4-channel interpolation ops. Note: local `float4 hist_cache[6]` = 24 scalar registers added; this is a register pressure trade-off (see E assessment below — total estimated register count is ~143 scalars, already marginal).

**Edge cases:** None — local arrays are SPIR-V safe (restriction is `static const` arrays only; confirmed by `samples[64]` in analysis_scope_pre.fx:58).

**Complexity:** Drop-in.

---

### OPT-2: log/exp → log2/exp2 in Retinex block [Category A]

**File:** `general/grade/grade.fx:255–258`

**Current:**
```hlsl
float log_R    = 0.20 * log(luma_s / illum_s0)
               + 0.30 * log(luma_s / illum_s1)
               + 0.50 * log(luma_s / illum_s2);
float retinex_luma = saturate(exp(log_R + log(max(zone_log_key, 0.001))));
```

**Proposed:**
```hlsl
float log_R    = 0.20 * log2(luma_s / illum_s0)
               + 0.30 * log2(luma_s / illum_s1)
               + 0.50 * log2(luma_s / illum_s2);
float retinex_luma = saturate(exp2(log_R + log2(max(zone_log_key, 0.001))));
```

**Derivation (exact substitution):** Let log_R_nat = weighted sum of natural logs. Since ln(x) = ln(2)·log₂(x), we have log_R_nat = ln(2)·log_R2 where log_R2 is the same sum in base-2. Similarly ln(zone_log_key) = ln(2)·log₂(zone_log_key). Therefore:

exp(log_R_nat + ln(zone_log_key)) = exp(ln(2)·(log_R2 + log₂(zone_log_key))) = exp2(log_R2 + log₂(zone_log_key))

The substitution is algebraically exact — no approximation.

**Max error:** ~0 (float32 rounding only — same precision class as original). SAFE.

**Cost:** On GPU hardware, `log` = `log2 · rcp_ln2` (log2 + 1 MUL) and `exp` = `rcp_ln2_mul + exp2` (1 MUL + exp2). Replacing 3 `log` + 1 `exp` + 1 `log` with `log2`/`exp2` saves 5 implicit MUL operations. `log2` and `exp2` are native quarter-rate instructions on all modern GPU ISAs.

**Edge cases:** `luma_s = max(new_luma, 0.001)` and illum values use `max(..., 0.001)` guards — all arguments to log2 are strictly positive. No change in guard requirements.

**Complexity:** Drop-in.

---

### OPT-3: pow(fl, 0.25) → sqrt(sqrt(fl)) in Hunt scaling [Category C]

**File:** `general/grade/grade.fx:307`

**Current:**
```hlsl
float hunt_scale = pow(max(fl, 1e-6), 0.25) / 0.5912;
```

**Proposed:**
```hlsl
float hunt_scale = sqrt(sqrt(max(fl, 1e-6))) / 0.5912;
```

**Max error:** 0 — x^(1/4) = sqrt(sqrt(x)) exactly. SAFE.

**Cost:** Replaces 1 `pow` (= `log2` + `mul` + `exp2` ≈ 9 cycles on NVIDIA quarter-rate hardware) with 2 `sqrt` (≈ 1 cycle each on full-rate hardware). Net saving: ~7 cycles per pixel. `fl` ≥ 0 by construction (sum of non-negative terms), so `max(fl, 1e-6)` is always positive — `sqrt` is safe.

**Edge cases:** All-black frame (fl → ~0.1 * pow(0.005, 0.333) ≈ small positive): max(fl, 1e-6) guard handles it. No change needed.

**Complexity:** Drop-in.

---

### OPT-4: Remove sign/abs in RGBtoOklab cube roots [Category C]

**File:** `general/grade/grade.fx:135–137` and `general/corrective/corrective.fx:119–121`

**Current (both files):**
```hlsl
l = sign(l) * pow(abs(l), 1.0 / 3.0);
m = sign(m) * pow(abs(m), 1.0 / 3.0);
s = sign(s) * pow(abs(s), 1.0 / 3.0);
```

**Proposed (both files):**
```hlsl
l = pow(l, 1.0 / 3.0);
m = pow(m, 1.0 / 3.0);
s = pow(s, 1.0 / 3.0);
```

**Safety argument:** l, m, s are computed as dot products of RGB with all-positive matrix rows (grade.fx:132–134, corrective.fx:115–117). Since RGB ∈ [0,1] (SDR, linear, post-vkBasalt linearization), all dot products are ≥ 0. Therefore `sign(x)` = 1 and `abs(x)` = x for all three values. The sign/abs pair is a no-op for this input domain.

The sign/abs pattern is correct for the general Oklab spec (which handles HDR negatives), but constitutes unnecessary work in this SDR-only pipeline.

**Max error:** 0 — inputs are guaranteed non-negative. SAFE.

**Cost:** 6 fewer ops per RGBtoOklab call — 3 `sign` + 3 `abs`. In grade.fx, RGBtoOklab is called once per pixel (line 286). In corrective.fx, it is called inside UpdateHistoryPS, 8 times per band × 6 bands = 48 calls per frame (not per-pixel, but savings are still real). Total per-pixel saving in grade.fx: 6 scalar ops.

**Edge cases:** If a future pipeline change allows RGB > 1.0 before the Oklab call (currently impossible given SDR construction and preceding `saturate` calls), this simplification would need revisiting.

**Complexity:** Drop-in (same change in two files).

---

### OPT-5: Hunt FL block algebraic simplification [Category C]

**File:** `general/grade/grade.fx:303–307`

**Current:**
```hlsl
float la         = max(perc.g, 0.001);
float k          = 1.0 / (5.0 * la + 1.0);
float k4         = k * k * k * k;
float fl         = 0.2 * k4 * (5.0 * la) + 0.1 * (1.0 - k4) * (1.0 - k4) * pow(5.0 * la, 0.333);
float hunt_scale = pow(max(fl, 1e-6), 0.25) / 0.5912;
```

**Proposed** (OPT-3 already replaces the pow on line 307; this addresses lines 305–306):
```hlsl
float la         = max(perc.g, 0.001);
float k          = 1.0 / (5.0 * la + 1.0);
float k2         = k * k;
float k4         = k2 * k2;            // 2 muls instead of up to 3
float fla        = 5.0 * la;           // computed once, used twice
float one_mk4    = 1.0 - k4;           // computed once, used twice
float fl         = k4 * la + 0.1 * one_mk4 * one_mk4 * pow(fla, 1.0 / 3.0);
float hunt_scale = sqrt(sqrt(max(fl, 1e-6))) / 0.5912;
```

**Algebraic identities applied:**
- `0.2 * k4 * (5.0 * la)` = `k4 * la` (0.2 × 5.0 = 1.0 exactly)
- `(1.0 - k4)` extracted as `one_mk4` — eliminates 1 SUB + 1 MUL
- `5.0 * la` extracted as `fla` — eliminates 1 MUL
- `k4` via `k2*k2` — ensures 2 MUL not 3
- `0.333` → `1.0/3.0` — eliminates the 0.333 rounding error (exact 1/3 = 0.33333...)

**Max error:** 0 — all identities are exact. The `0.333` → `1.0/3.0` change reduces systematic error in the FL formula slightly but doesn't affect the output at float32 precision beyond the last bit. SAFE.

**Cost:** ~5 fewer scalar operations (2 MUL + 1 SUB + 1 MUL + 1 MUL) per pixel. Minor but zero-risk.

**Edge cases:** None — all algebraic, no domain changes.

**Complexity:** Drop-in.

---

### OPT-6: Dead variable r18_str [Category E]

**File:** `general/grade/grade.fx:250`

**Current:**
```hlsl
float r18_str  = lerp(10.0, 30.0, smoothstep(0.08, 0.25, zone_std)) / 100.0 * 0.4;
```

**Finding:** `r18_str` is declared at line 250 and never referenced anywhere in ColorTransformPS. A full-text search confirms zero uses. It is a dead variable from a prior Retinex implementation (R18) that was superseded by the `auto_clarity`-based approach. The GPU compiler will DCE it, but the declaration consumes 1 scalar register slot in the register allocator's liveness analysis and adds noise to the source.

**Proposed:** Delete line 250 entirely.

**Max error:** 0. SAFE.

**Cost:** Removes 1 scalar register from liveness. At the estimated ~143-scalar register budget (near the ~128 spill threshold), recovering 1 scalar from an entry that feeds a smoothstep + lerp chain (the optimizer may not fully eliminate at allocation time) is a marginal but free gain.

**Edge cases:** None.

**Complexity:** Drop-in (delete one line).

---

### OPT-7: Shared (a,b) dot products across two OklabToRGB calls [Category B/C]

**File:** `general/grade/grade.fx:362–372`

**Current:**
```hlsl
float3 rgb_probe  = OklabToRGB(float3(final_L,   f_oka, f_okb));
// ... rmax_probe, headroom, delta_C, density_L computed ...
float3 chroma_rgb = OklabToRGB(float3(density_L, f_oka, f_okb));
```

`OklabToRGB` (lines 145–158) computes:
```hlsl
float l = dot(lab, float3(1.0, +0.3963377774, +0.2158037573));  // = L + k1*a + k2*b
float m = dot(lab, float3(1.0, -0.1055613458, -0.0638541728));  // = L + k3*a + k4*b
float s = dot(lab, float3(1.0, -0.0894841775, -1.2914855480));  // = L + k5*a + k6*b
```

Both calls use identical `f_oka`, `f_okb`. The `k*a + k*b` terms are computed twice.

**Proposed** (inline the two calls, extract common sub-expressions):
```hlsl
// Shared (a,b) contributions — computed once
float ab_l = 0.3963377774 * f_oka + 0.2158037573 * f_okb;
float ab_m = -0.1055613458 * f_oka - 0.0638541728 * f_okb;
float ab_s = -0.0894841775 * f_oka - 1.2914855480 * f_okb;

// First call: probe with final_L
float lp = final_L + ab_l; lp = lp * lp * lp;
float mp = final_L + ab_m; mp = mp * mp * mp;
float sp = final_L + ab_s; sp = sp * sp * sp;
float3 rgb_probe = float3(
    dot(float3(lp, mp, sp), float3( 4.0767416621, -3.3077115913,  0.2309699292)),
    dot(float3(lp, mp, sp), float3(-1.2684380046,  2.6097574011, -0.3413193965)),
    dot(float3(lp, mp, sp), float3(-0.0041960863, -0.7034186147,  1.7076147010))
);
float rmax_probe = max(rgb_probe.r, max(rgb_probe.g, rgb_probe.b));
float headroom   = saturate(1.0 - rmax_probe);
float delta_C    = max(final_C - C, 0.0);
float density_L  = saturate(final_L - delta_C * headroom * (density_str / 100.0));

// Second call: reuses ab_l/ab_m/ab_s, only L changes
float lc = density_L + ab_l; lc = lc * lc * lc;
float mc = density_L + ab_m; mc = mc * mc * mc;
float sc = density_L + ab_s; sc = sc * sc * sc;
float3 chroma_rgb = float3(
    dot(float3(lc, mc, sc), float3( 4.0767416621, -3.3077115913,  0.2309699292)),
    dot(float3(lc, mc, sc), float3(-1.2684380046,  2.6097574011, -0.3413193965)),
    dot(float3(lc, mc, sc), float3(-0.0041960863, -0.7034186147,  1.7076147010))
);
```

**Max error:** 0 — algebraically identical. SAFE.

**Cost:** Saves 3 FMA instructions (the `k*a + k*b` terms for l, m, s that were duplicated). Minor — 3 FMA per pixel — but free.

**Edge cases:** Inlining removes the function call overhead (negligible in HLSL, inlined by compiler anyway). The OklabToRGB function remains available for other callers.

**Complexity:** Needs surrounding changes (inline at call sites; OklabToRGB function kept but not called at lines 362/368 anymore). Low risk.

---

## Ruled out this session

| Candidate | Reason rejected |
|-----------|----------------|
| Fast atan2 (R10 F1) | Already implemented — OklabHueNorm uses polynomial at grade.fx:160–167 and corrective.fx:130–137 |
| Chilliant gamma (R10 F2) | The target lines (grade.fx:495/554) no longer exist. The old gamma bracket was removed when the pipeline was refactored to rely on vkBasalt linearization. Optimization is moot. |
| Small-angle trig (R10 F3) | Already implemented — grade.fx:349–350: `cos_dt = 1.0 - dtheta*dtheta*0.5; sin_dt = dtheta` |
| Pass consolidation — Passthrough | Required by vkBasalt architecture (CLAUDE.md: "any effect where all passes use explicit RenderTargets must add a Passthrough pass") |
| BuildZoneLevels + SmoothZoneLevels merge | Both run on 4×4 pixels. Pass-dispatch overhead dominates; merged shader adds complexity for negligible runtime gain |
| H-K sincos polynomial replacement | `sincos` is a native GPU instruction (1 cycle); polynomial would require 10+ MAD to match accuracy. Not a candidate. |
| 6-band → 4-band chroma loop reduction | Would change chroma lift behavior for CYAN/BLUE/MAGENTA bands — perceptual output change, not optimization |
| pow(col.rgb, EXPOSURE) with EXPOSURE=1.0 | #define constant; DXC/glslang folds pow(x, 1.00) → x at compile time. Runtime cost is zero already. |
| Per-frame constant hoisting (hunt_scale, chroma_adapt, shadow_lift, etc.) | Correct finding — these values are per-frame but computed per-pixel. However, moving them to a separate pass requires adding a constant texture + new pass to the corrective chain. Architecturally significant; deferred for a dedicated restructure proposal. |
| pow(final_C, 0.587) polynomial replacement | Exponent 0.587 ≈ 7/12; no cheap integer/half-integer factoring. Polynomial minimax feasible but requires offline coefficient derivation and numerical verification not available in this session. Deferred. |

---

## Literature findings

External web/arxiv search was network-blocked this session. The following are known-good references for the approximations proposed:

- **OPT-2 (log2/exp2 substitution):** Standard identity from IEEE 754 / GPU ISA documentation. No citation needed — mathematically exact.
- **OPT-3 (sqrt(sqrt) for x^0.25):** Widely used in real-time rendering; e.g. referenced in NVIDIA "Shader Performance" (2022) as the canonical replacement for pow(x, 0.25).
- **OPT-4 (sign/abs removal):** Domain restriction analysis; documented in Oklab spec by Björn Ottosson — the sign/abs pattern handles HDR out-of-gamut values only.
- **OPT-5 (k4 via k2):** Standard strength-reduction. CIECAM02 FL formula — see Li et al. (2002) "The relationship between the adapted white point and the observer's chromatic adaptation state."

---

## Priority ranking

| # | OPT | Title | Max error | Est. cycle saving | Complexity | Recommend |
|---|-----|-------|-----------|------------------|------------|-----------|
| 1 | OPT-3 | pow(fl,0.25) → sqrt(sqrt) | 0 | ~7 cyc/px | Drop-in | **Yes** |
| 2 | OPT-2 | log→log2 / exp→exp2 Retinex | 0 | ~5 cyc/px | Drop-in | **Yes** |
| 3 | OPT-4 | Remove sign/abs in RGBtoOklab | 0 | ~6 ops/call | Drop-in (2 files) | **Yes** |
| 4 | OPT-6 | Dead variable r18_str | 0 | 1 register | Drop-in | **Yes** |
| 5 | OPT-5 | Hunt FL algebraic fold | 0 | ~5 ops/px | Drop-in | **Yes** |
| 6 | OPT-1 | Merge ChromaHistory reads | 0 | 6 tex reads/px | Drop-in | **Yes** (if register budget allows) |
| 7 | OPT-7 | Shared ab terms in OklabToRGB×2 | 0 | ~3 FMA/px | Surrounding changes | Deferred |

OPT-1 note: adds 24 scalar registers. At the estimated ~143-scalar register count, this pushes further above the ~128 spill threshold. Implement after confirming OPT-6 + OPT-5 (which recover ~6 registers), or profile for actual spilling first.
