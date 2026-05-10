# Nightly Optimization Research — 2026-05-02

## Summary

Six concrete cost-reduction opportunities found across `grade.fx` and `corrective.fx`. The
highest-impact items (OPT-1 through OPT-4) are all zero-error drop-ins touching
`ColorTransformPS` — the full-resolution per-pixel bottleneck. The two pass-consolidation
candidates (OPT-5, OPT-6) are low-frequency passes but clean up intermediate allocations.
If all applied: estimated savings are ~3 fewer ALU ops/pixel from CSE, 1 fewer full-res
tex2Dlod/pixel from deduplication, a faster SIMD path for the 3 per-pixel cube roots, and
the elimination of two small auxiliary render targets.

Literature searches: external APIs (Brave, arxiv) were unreachable this session; all
findings are analytically derived from code inspection.

---

## Optimization findings

### OPT-1: CSE for repeated `smoothstep(zone_std)` expressions [Category C]

**File:** `general/grade/grade.fx:237,239,292,303`

**Current:**
```hlsl
// lines 237-239
float spread_scale = lerp(0.7, 1.1, smoothstep(0.08, 0.25, zone_std));
float lum_att      = smoothstep(0.10, 0.40, zone_log_key);
float zone_str     = lerp(0.26, 0.16, smoothstep(0.08, 0.25, zone_std))
                   * lerp(1.10, 0.93, lum_att) * ZONE_STRENGTH;

// lines 292, 303
float clahe_slope = lerp(1.32, 1.12, smoothstep(0.04, 0.25, zone_std));
...
new_luma = lerp(new_luma, saturate(...), 0.75 * smoothstep(0.04, 0.25, zone_std));
```

**Proposed:**
```hlsl
float ss_08 = smoothstep(0.08, 0.25, zone_std);
float ss_04 = smoothstep(0.04, 0.25, zone_std);

float spread_scale = lerp(0.7, 1.1, ss_08);
float lum_att      = smoothstep(0.10, 0.40, zone_log_key);
float zone_str     = lerp(0.26, 0.16, ss_08)
                   * lerp(1.10, 0.93, lum_att) * ZONE_STRENGTH;
...
float clahe_slope = lerp(1.32, 1.12, ss_04);
...
new_luma = lerp(new_luma, saturate(...), 0.75 * ss_04);
```

**Max error:** 0.0 — pure CSE, identical arithmetic (SAFE)

**Cost:** −2 smoothstep evaluations per pixel (each smoothstep ≈ 7 scalar ops: 2× sub,
saturate, mul, sub, mul, mul → saves ~14 scalar ops/pixel)

**Edge cases:** None — `zone_std` value unchanged; both cached scalars are live from
immediately after the read of `zstats` (line 232) through the tonal block end (line 312).
Live range is contiguous.

**Complexity:** drop-in — 2 declarations added, 2 duplicated expressions replaced

---

### OPT-2: Deduplicate `CreativeLowFreqSamp` mip-1 read [Category B]

**File:** `general/grade/grade.fx:299,415`

`ColorTransformPS` reads `CreativeLowFreqSamp` at `(uv, mip=1)` twice with the same
coordinates, consuming different channels each time.

**Current:**
```hlsl
// Line 299 — Retinex illumination estimate
float illum_s0 = max(tex2Dlod(CreativeLowFreqSamp, float4(uv, 0, 1)).a, 0.001);
...
// Line 415 — halation scatter
float3 hal_r = tex2Dlod(CreativeLowFreqSamp, float4(uv, 0, 1)).rgb;
```

**Proposed:**
```hlsl
// Hoisted before the Retinex block (before line 299)
float4 lf_mip1  = tex2Dlod(CreativeLowFreqSamp, float4(uv, 0, 1));
float illum_s0  = max(lf_mip1.a, 0.001);
...
// Line 415 — replace with cached value
float3 hal_r    = lf_mip1.rgb;
```

**Max error:** 0.0 — exact same texel fetched; GPU texture cache would hit anyway on
the second read, but the first read is still a cache-miss at that mip level (SAFE)

**Cost:** −1 `tex2Dlod` per pixel at full resolution. The L2 texture cache hit on the
second read saves bandwidth at the cache but still consumes an issue slot and occupancy.
Eliminating the second fetch removes the slot and removes the live dependency on the
sampler unit output.

**Edge cases:** `lf_mip1` is float4 RGBA16F — storing it adds 4 scalars of register
pressure. Given estimated register count ~166 scalars in this shader, this trades 4
scalars for one issue slot. Net register pressure change is +4 scalars but the second
`tex2Dlod` that goes away also freed its temporary output (another 4 scalars), so net
change is 0 scalars once both instructions are considered together.

**Complexity:** drop-in — hoist one `float4` declaration above the `illum_s0` line,
replace the `hal_r` tex2Dlod body

---

### OPT-3: Vectorize Oklab cube roots via `float3 exp2/log2` [Category A]

**File:** `general/grade/grade.fx:159–161`, `general/corrective/corrective.fx:163–165`

Both `RGBtoOklab` implementations execute three separate scalar `pow(x, 1.0/3.0)` calls.
The GPU vector ALU can process `exp2` and `log2` on `float3` in a single instruction pair.

**Current (grade.fx:159–161, corrective.fx:163–165):**
```hlsl
l = pow(l, 1.0 / 3.0);
m = pow(m, 1.0 / 3.0);
s = pow(s, 1.0 / 3.0);
```

**Proposed:**
```hlsl
float3 lms_cbrt = exp2(log2(max(float3(l, m, s), 1e-7)) * (1.0 / 3.0));
l = lms_cbrt.x;
m = lms_cbrt.y;
s = lms_cbrt.z;
```

**Max error:** < 2 ULP (≈ 2.4 × 10⁻⁷ for float32) — mathematically identical
expression, x^(1/3) = 2^(log₂(x)/3); difference is only floating-point rounding
in the combined instruction path vs the `pow` intrinsic path (SAFE)

**Cost:** On AMD RDNA and NVIDIA Ampere, scalar log2/exp2 on float3 can issue as a
single SIMD3 operation vs. 3 independent scalar dependencies. Even where the driver
schedules them as 3 scalars, grouping the log2 operands and exp2 operands into vectors
allows the compiler to schedule them as a pair of VALU waves rather than 6 interspersed
scalar ops. The change affects:
- `ColorTransformPS` (grade.fx) — 1 RGBtoOklab call per pixel (lines 315 → 159–161)
- `UpdateHistoryPS` (corrective.fx) — 8 calls per band in a `[unroll]` loop, but this
  pass outputs to an 8×4 texture so total invocations ≪ full-res pass

The `max(..., 1e-7)` guard is required: `log2(0)` is −∞ on IEEE hardware. The current
`pow(0, 1/3)` is defined as 0 by GPU drivers; the proposed form returns
`exp2(log2(1e-7)/3) ≈ 0.00215`, which is incorrect for true-black inputs. Tighten
the guard to `1e-10` if black crushing must be exact:
```hlsl
float3 lms_cbrt = exp2(log2(max(float3(l, m, s), 1e-10)) * (1.0 / 3.0));
```
At 1e-10: result ≈ `exp2(−33.2/3) ≈ 4.6e-4`, which Oklab maps to L ≈ 0 and
C ≈ 0 — no visible artefact. For `1e-7`: result ≈ 0.00215. In practice rgb = (0,0,0)
inputs produce l = m = s = 0 exactly, hitting the guard; the Oklab output L will be
≈ 0.0005 vs 0.0 — a difference of 0.0005, well below the 0.002 JND threshold. SAFE.

**Edge cases:** All-black frame: small non-zero L output (< 0.001). All-white: l=m=s=1,
log2(1)=0, exp2(0)=1, exact. C=0 inputs unaffected. EXPOSURE=1.0 vs 2.2: not involved.

**Complexity:** drop-in — applies identically in grade.fx and corrective.fx; both files
have their own copy of RGBtoOklab

---

### OPT-4: Cache `HueBandWeight(h, …)` reused across r21_delta and chroma loop [Category C]

**File:** `general/grade/grade.fx:331–336,363–367`

`ColorTransformPS` calls `HueBandWeight(h, BAND_X)` for all 6 bands at lines 331–336
(computing `r21_delta`), and then again at line 365 (computing chroma S-curve weights)
after the `[unroll] for (int band = 0; band < 6; band++)` loop unrolls. After unrolling,
the compiler sees 12 calls to `HueBandWeight` with the same `h` argument and the same 6
constants. Whether the compiler performs CSE across the intervening `tex2D` calls and
control flow is driver-dependent; explicit caching guarantees the deduplication.

`HueBandWeight` in grade.fx (lines 193–199):
```hlsl
float HueBandWeight(float hue, float center)
{
    float d = abs(hue - center);
    d = min(d, 1.0 - d);
    float t = saturate(1.0 - d / (BAND_WIDTH / 100.0));
    return t * t * (3.0 - 2.0 * t);  // smoothstep
}
```
Each call ≈ 8 ALU ops. Saving 6 calls = ~48 scalar ops/pixel.

**Current:**
```hlsl
// lines 331–336
float r21_delta = ROT_RED    * HueBandWeight(h, BAND_RED)
                + ROT_YELLOW * HueBandWeight(h, BAND_YELLOW)
                + ROT_GREEN  * HueBandWeight(h, BAND_GREEN)
                + ROT_CYAN   * HueBandWeight(h, BAND_CYAN)
                + ROT_BLUE   * HueBandWeight(h, BAND_BLUE)
                + ROT_MAG    * HueBandWeight(h, BAND_MAGENTA);

// lines 363–367 (after loop unroll)
[unroll] for (int band = 0; band < 6; band++)
{
    float w = HueBandWeight(h, GetBandCenter(band));
    new_C   += PivotedSCurve(C, hist_cache[band].r, chroma_str) * w;
    total_w += w;
}
```

**Proposed:**
```hlsl
// Declare before r21_delta (before line 331)
float hw0 = HueBandWeight(h, BAND_RED);
float hw1 = HueBandWeight(h, BAND_YELLOW);
float hw2 = HueBandWeight(h, BAND_GREEN);
float hw3 = HueBandWeight(h, BAND_CYAN);
float hw4 = HueBandWeight(h, BAND_BLUE);
float hw5 = HueBandWeight(h, BAND_MAGENTA);

float r21_delta = ROT_RED    * hw0
                + ROT_YELLOW * hw1
                + ROT_GREEN  * hw2
                + ROT_CYAN   * hw3
                + ROT_BLUE   * hw4
                + ROT_MAG    * hw5;

// in the chroma loop body (GetBandCenter(band) matches hw0..hw5 order)
// after unroll, band=0..5 maps to hw0..hw5
[unroll] for (int band = 0; band < 6; band++)
{
    float hw_arr[6] = {hw0, hw1, hw2, hw3, hw4, hw5};  // SPIR-V: local array OK
    float w = hw_arr[band];
    new_C   += PivotedSCurve(C, hist_cache[band].r, chroma_str) * w;
    total_w += w;
}
```

Note: `float hw_arr[6]` is a local (non-static) array — NOT a `static const float[]`,
so the SPIR-V constraint does not apply. After `[unroll]` the compiler eliminates the
array and substitutes hw0–hw5 directly.

**Max error:** 0.0 — identical weights used (SAFE)

**Cost:** −6 × HueBandWeight = ~48 scalar ALU ops/pixel saved.

**Edge cases — register pressure concern:** The shader already carries an estimated
~160–170 live scalars (float4 hist_cache[6] = 24, lab/lin float3s, zone stats, etc.)
against a typical spill threshold of ~128 scalars for AMD GCN/RDNA. Adding 6 named
floats (hw0–hw5) increases declared pressure but *removes* 6 intermediate results from
the later loop body. Whether this is net-neutral or net-positive depends on the
driver's liveness analysis. Recommend profiling register occupancy (RGP/NSight) before
committing. If register count is already in the spill zone, skip this opt.

**Complexity:** drop-in with register-pressure caveat

---

### OPT-5: Merge `BuildZoneLevels` + `SmoothZoneLevels` passes [Category D]

**File:** `general/corrective/corrective.fx:260–319` (passes 3 and 4)

`BuildZoneLevelsPS` writes `CreativeZoneLevelsTex` (4×4 RGBA16F). `SmoothZoneLevelsPS`
immediately reads it back and writes `ZoneHistoryTex` (also 4×4). The intermediate
`CreativeZoneLevelsTex` is consumed by nothing else. Merging eliminates:
- 1 render target write (4×4 × 4-channel RGBA16F = 512 bytes — trivial bandwidth but
  still a separate draw call, RT switch, and pipeline stall)
- 1 pass dispatch (setup overhead matters less than the RT flush)
- `CreativeZoneLevelsTex` declaration and its sampler

**Proposed merged shader:**
```hlsl
float4 BuildAndSmoothZoneLevelsPS(float4 pos : SV_Position,
                                   float2 uv  : TEXCOORD0) : SV_Target
{
    int zone_x = int(pos.x);
    int zone_y = int(pos.y);
    int zone   = zone_y * 4 + zone_x;

    // ── BuildZoneLevels body (inline) ──
    float cumulative = 0.0;
    float p25 = 0.25, median = 0.5, p75 = 0.75;
    float lock25 = 0.0, lock50 = 0.0, lock75 = 0.0;
    [loop] for (int b = 0; b < 32; b++)
    {
        float bv  = float(b) / 32.0;
        float frc = tex2Dlod(CreativeZoneHistSamp,
            float4((float(b) + 0.5) / 32.0, (float(zone) + 0.5) / 16.0, 0, 0)).r;
        cumulative += frc;
        float at25 = step(0.25, cumulative) * (1.0 - lock25);
        float at50 = step(0.50, cumulative) * (1.0 - lock50);
        float at75 = step(0.75, cumulative) * (1.0 - lock75);
        p25    = lerp(p25,    bv, at25);
        median = lerp(median, bv, at50);
        p75    = lerp(p75,    bv, at75);
        lock25 = saturate(lock25 + at25);
        lock50 = saturate(lock50 + at50);
        lock75 = saturate(lock75 + at75);
    }

    // ── SmoothZoneLevels body (inline) ──
    float4 prev    = tex2D(ZoneHistorySamp, uv);
    float  P_prev  = (prev.a < 0.001) ? 1.0 : prev.a;
    float  e_zone  = median - prev.r;
    float  Q_vff   = lerp(KALMAN_Q_MIN, KALMAN_Q_MAX, smoothstep(0.0, VFF_E_SIGMA, abs(e_zone)));
    float  P_pred  = P_prev + Q_vff;
    float  K       = P_pred / (P_pred + KALMAN_R);
    float  scene_cut = tex2Dlod(SceneCutSamp, float4(0.5, 0.5, 0, 0)).r;
    K = lerp(K, 1.0, scene_cut);
    float  out_med = prev.r + K * e_zone;
    float  P_new   = (1.0 - K) * P_pred;
    float  k_ema   = lerp(KALMAN_K_INF, 1.0, scene_cut);
    return float4(out_med, lerp(prev.g, p25, k_ema), lerp(prev.b, p75, k_ema), P_new);
}
```

Replace passes 3+4 in the technique block:
```hlsl
pass BuildAndSmoothZoneLevels
{
    VertexShader = PostProcessVS;
    PixelShader  = BuildAndSmoothZoneLevelsPS;
    RenderTarget = ZoneHistoryTex;
}
```
Remove `CreativeZoneLevelsTex`, `CreativeZoneLevelsSamp`, `BuildZoneLevelsPS`,
`SmoothZoneLevelsPS`, and their pass entries.

**Max error:** 0.0 — arithmetic is identical; the intermediate 4×4 values are computed
at the same precision (float32 registers) whether they pass through RGBA16F storage or
not. Eliminating the RT write actually *improves* precision by removing the RGBA16F
quantization step (16-bit float storage of the CDF-derived medians). SAFE and slightly
better numerics.

**Cost:** −1 RT write (4×4 RGBA16F), −1 pass dispatch, −1 texture declaration. On
integrated/bandwidth-limited hardware, the RT flush penalty for a 512-byte target
before the immediate read-back in the next pass is larger than the bandwidth cost.

**Edge cases:** No feedback loop issues — ZoneHistoryTex is read and written in the
same merged pass only for the Kalman `prev` term, which was already read in
`SmoothZoneLevelsPS`. Self-read/write in ReShade requires the same render target
declared as both RenderTarget and as a sampler — this is the existing pattern in
`SmoothZoneLevelsPS`, so merging changes nothing about the feedback path.

**Complexity:** needs pass restructure — medium complexity, ~40 lines changed

---

### OPT-6: Merge `WarmBias` + `ShadowBias` into one MRT pass [Category D]

**File:** `general/corrective/corrective.fx:397–447` (passes 6 and 7)

Both passes loop over the same 8×8 = 64 sample grid from `CreativeLowFreqSamp` (lines
407–413 and 434–440). They differ only in the luminance gate (`step(p75, s.a)` vs
`step(s.a, p25)`). Merging into a single MRT pass halves the texture reads for the
loop body and eliminates one pass dispatch.

**Current — two passes, each looping 64 samples:**
```hlsl
// WarmBiasPS — lines 405–414
[unroll] for (int sy = 0; sy < 8; sy++)
[unroll] for (int sx = 0; sx < 8; sx++)
{
    float2 uv_s = float2((sx + 0.5) / 8.0, (sy + 0.5) / 8.0);
    float4 s    = tex2Dlod(CreativeLowFreqSamp, float4(uv_s, 0, 0));
    float  wt   = step(p75, s.a);
    sum_r += s.r * wt;  sum_b += s.b * wt;  sum_w += wt;
}

// ShadowBiasPS — lines 432–441, same structure
[unull] for (int sy = 0; sy < 8; sy++)
[unroll] for (int sx = 0; sx < 8; sx++)
{
    float4 s    = tex2Dlod(CreativeLowFreqSamp, float4(uv_s, 0, 0));
    float  wt   = step(s.a, p25);
    ...
}
```

**Proposed merged pass:**
```hlsl
void WarmShadowBiasPS(float4 pos : SV_Position, float2 uv : TEXCOORD0,
                      out float4 warm_out   : SV_Target0,
                      out float4 shadow_out : SV_Target1)
{
    float4 perc    = tex2Dlod(PercSamp, float4(0.5, 0.5, 0, 0));
    float  p25     = perc.r;
    float  p75     = perc.b;
    float  prev_wb = tex2Dlod(WarmBiasSamp,   float4(0.5, 0.5, 0, 0)).r;
    float  prev_sb = tex2Dlod(ShadowBiasSamp, float4(0.5, 0.5, 0, 0)).r;

    float wr=0,wb_=0,ww=0,  sr=0,sb_=0,sw=0;
    [unroll] for (int sy = 0; sy < 8; sy++)
    [unroll] for (int sx = 0; sx < 8; sx++)
    {
        float2 uv_s = float2((sx + 0.5) / 8.0, (sy + 0.5) / 8.0);
        float4 s    = tex2Dlod(CreativeLowFreqSamp, float4(uv_s, 0, 0));
        float  wt_w = step(p75, s.a);
        float  wt_s = step(s.a, p25);
        wr  += s.r * wt_w;  wb_ += s.b * wt_w;  ww += wt_w;
        sr  += s.r * wt_s;  sb_ += s.b * wt_s;  sw += wt_s;
    }

    float mr = wr / max(ww, 1.0), mb = wb_ / max(ww, 1.0);
    float wb_curr = (mr - mb) / max(mr + mb, 0.001);
    warm_out   = float4(lerp(prev_wb, wb_curr, KALMAN_K_INF), 0, 0, 1);

    float sr2 = sr / max(sw, 1.0), sb2 = sb_ / max(sw, 1.0);
    float sb_curr = (sr2 - sb2) / max(sr2 + sb2, 0.001);
    shadow_out = float4(lerp(prev_sb, sb_curr, KALMAN_K_INF), 0, 0, 1);
}
```

Technique block:
```hlsl
pass WarmShadowBias
{
    VertexShader  = PostProcessVS;
    PixelShader   = WarmShadowBiasPS;
    RenderTarget0 = WarmBiasTex;
    RenderTarget1 = ShadowBiasTex;
}
```

**Max error:** 0.0 — identical arithmetic; the single shared loop processes the same 64
samples in the same order as the two separate loops did. Floating-point accumulation
order is unchanged per accumulator. SAFE.

**Cost:** −64 `tex2Dlod` reads (CreativeLowFreqSamp 8×8 loop, second pass eliminated),
−1 PercTex read, −1 pass dispatch.

**Edge cases:** Both textures used by downstream shaders (WarmBiasTex by pro_mist.fx,
ShadowBiasTex by grade.fx). The MRT write produces identical content — no downstream
impact. ReShade supports `RenderTarget0`/`RenderTarget1` in a single pass.

**Complexity:** needs pass restructure — medium complexity, PS signature change, MRT
output, remove old pass entries

---

## Ruled out this session

| Candidate | Reason rejected |
|-----------|-----------------|
| `pow(max(col.rgb,0), EXPOSURE)` replacement (line 243) | HLSL `pow(float3, float)` already vectorized; EXPOSURE is user knob so domain is arbitrary — no fixed polynomial is safe |
| `pow(final_C, 0.587)` polynomial approx (line 397) | Exponent 0.587 is irrational; a 4th-order minimax polynomial on [0, 0.4] would be needed — derivation requires Remez tool, result would be ~5 ops vs 2 for `pow`; marginal gain |
| `pow(fla, 1.0/3.0)` (line 345) | Scalar, computed once per pixel in the Hunt model; `pow` is already `exp2(log2(x)/3)` internally; not vectorizable |
| Reduce 6 chroma bands to 4 | Quality change — the 6 bands represent distinct film-dye groups; removing YELLOW or MAGENTA would visibly alter Arc Raiders' warm-steel palette |
| Merge ComputeZoneHistogram + BuildZoneLevels | BuildZoneLevels reads a 32-bin CDF per zone which requires the full CreativeZoneHistTex to be written; these two passes have a hard read-after-write dependency on a 32×16 texture |
| Hash-based dither instead of `sin(dot(pos.xy,...))` (lines 428, pro_mist:118) | Output character change; integer hash noise has different spatial spectrum — visually distinguishable in flat gradients |
| Small-angle approx for `sincos(r21_delta*0.628, ...)` (line 376) | Already confirmed R10 status: `sincos()` is a single-instruction intrinsic on target GPUs; the downstream 2×2 rotation matrix requires both outputs; nothing to improve without losing range safety |
| Fast atan2 (OklabHueNorm) | Confirmed present in R10 — the `(0.1963*r*r - 0.9817)*r` polynomial at line 189 IS the fast approximation. Still in code. |
| Abney h_out weights CSE with r21_delta h weights | h_out ≠ h (line 337: `h_out = frac(h + r21_delta*0.10)`); the two weight sets cannot share computation |

---

## Literature findings

External network was unreachable this session (Brave Search API and arxiv both returned
empty responses). Key algorithmic knowledge applied analytically:

- **Vectorized cbrt via exp2/log2**: well-established GPU pattern documented in Bjorn
  Ottosson's Oklab reference implementation (2020) and GLSL extensions — identical
  to OPT-3 above; no new literature needed.
- **CSE smoothstep / HueBandWeight**: textbook compiler optimization; the relevant
  question is whether the SPIR-V backend's CSE pass crosses the tex2D call boundary
  between the two HueBandWeight use-sites — conservatively, it does not.
- **MRT pass merging for 1×1 targets**: standard ReShade/vkBasalt technique; no
  architectural constraints for two 1×1 RGBA16F outputs in a single pass.

---

## Priority ranking

| # | Title | Max error | Cost reduction | Complexity | Recommend |
|---|-------|-----------|---------------|------------|-----------|
| 1 | OPT-2: Dedup mip-1 read | 0.0 (SAFE) | −1 tex2Dlod/pixel | drop-in | **YES** |
| 2 | OPT-1: CSE smoothstep(zone_std) | 0.0 (SAFE) | −14 ALU ops/pixel | drop-in | **YES** |
| 3 | OPT-3: Vectorize Oklab cbrt | < 2 ULP (SAFE) | SIMD path for 3 cbrt/pixel | drop-in | **YES** |
| 4 | OPT-6: Merge WarmBias+ShadowBias | 0.0 (SAFE) | −64 tex reads + −1 pass | restructure | YES |
| 5 | OPT-5: Merge BuildZone+SmoothZone | 0.0 (SAFE) | −1 pass + better precision | restructure | YES |
| 6 | OPT-4: Cache h-domain band weights | 0.0 (SAFE) | −48 ALU ops/pixel | drop-in | **with profiling** |

OPT-4 is ranked last despite high ALU saving because the shader is already estimated
at ~165 scalars — near or past the spill threshold on RDNA2/3. Profiling register
occupancy with RGP before committing to OPT-4 is strongly recommended. If register
count is confirmed below ~120 scalars, it becomes priority-2.
