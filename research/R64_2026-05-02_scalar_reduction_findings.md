# R64 — Register Pressure / Scalar Reduction — Findings

**Date:** 2026-05-02
**Status:** Analysis complete — in-shader reductions identified, estimated gap to threshold documented.

---

## Current estimate

The pre-R61 estimate was ~169 scalars. R61 and R62 changes are register-neutral:
- R61 OPT-1 (CSE smoothstep): algebraic reuse, no liveness change
- R61 OPT-2 (tex dedup, lf_mip1 hoist): read moved earlier, same scalar lives through same range
- R61 OPT-3 (vectorized cbrt): float3 pack, 0–2 fewer scalars depending on SPIR-V vectorisation
- R62 OPT-1 (Retinex algebraic collapse): added `nl_safe`, `zk_safe` (+2), removed `exp2`/`log2` temps (−2). Net neutral.
- R62 OPT-2 (FilmCurve hoisting): `fc_*` scalars were inside the inlined function body before; flat SPIR-V means they were always in the same register space. No change.
- R62 OPT-4, OPT-5: identifier substitutions. Neutral.

**Working estimate after today's changes: ~165–169 scalars. RDNA spill threshold: ~128.**
Gap to close: ~37–41 scalars.

Actual count requires shader compiler output (SPIR-V disassembly, `spirv-cross --dump-entry-points`,
or RGP capture). Without it every number here is a hand-count estimate.

---

## Peak pressure location

Peak liveness occurs during or just after the `hist_cache` load loop (grade.fx lines 362–368),
when Stage 2 carry-over and Stage 3 working set overlap:

**Carried from Stage 2 through all of Stage 3:**

| Variable | Type | Scalars | Live until |
|----------|------|---------|------------|
| `lin` | float3 | 3 | line 425 |
| `lf_mip1` | float4 | 4 | line 429 (halation) |
| `uv` | float2 | 2 | line 430 |
| `pos` | SV_Position | 4 | line 445 |
| `col` (for `.a`) | float4 | 4 | line 445 |
| `zone_log_key` | float | 1 | line 350 (`la`) |
| `perc` (for `.g`) | float4 | 4 | line 371 |

Stage 2 carry subtotal: **22 scalars** — but 15 of those are from `col` (4), `perc` (4), `lf_mip1` (4),
and `pos` (4) where only 1–2 components are actually needed.

**Stage 3 working set at the hist_cache loop:**

| Variable | Type | Scalars |
|----------|------|---------|
| `lab` | float3 | 3 |
| `C` | float | 1 |
| `h_perc` | float | 1 |
| `hunt_scale` | float | 1 |
| `r21_delta` | float | 1 |
| `h_out` | float | 1 |
| `hist_cache[6]` | float4×6 | 24 |
| `cm_t`, `cm_w` | float×2 | 2 |

Stage 3 subtotal at peak: **34 scalars**

Manual peak total: ~56. The gap to 169 is compiler-generated temporaries, loop unroll expansion,
and inlined function register pressure. The unrolled hist_cache loop forces the compiler to emit
all 6 `float4` slots simultaneously during loop body scheduling — this is the largest single block.

---

## Concrete reductions

### RED-1: `hist_cache` packing — **−12 scalars** [HIGHEST VALUE]

Only `.r` (band mean chroma) and `.b` (weight) are consumed from `hist_cache[bi]`. `.g` and `.a`
are loaded but never read after the loop.

**Current:** `float4 hist_cache[6]` = 24 scalars

**Proposed:**
```hlsl
float2 hist_cache[6];   // .x = mean, .y = weight
float cm_t = 0.0, cm_w = 0.0;
[unroll] for (int bi = 0; bi < 6; bi++)
{
    float4 hc       = tex2D(ChromaHistory, float2((bi + 0.5) / 8.0, 0.5 / 4.0));
    hist_cache[bi]  = float2(hc.r, hc.b);
    cm_t           += hc.r * hc.b;
    cm_w           += hc.b;
}
```

Update second loop: `PivotedSCurve(C, hist_cache[band].x, chroma_str)`.

Max error: 0. Drop-in.

---

### RED-2: Unpack `perc` early — **−3 scalars at Stage 3 peak**

`perc` is float4 but only `.r` (p25) and `.g` (p50) are used after Stage 1.
`.b` (p75) is consumed at line 224 and dead. `.a` (iqr) is never read.

At Stage 3 peak (around line 371), only `perc.g` is alive — but the full float4 is held.

**Proposed:** Unpack immediately after the tex2D read:
```hlsl
float4 perc_raw  = tex2D(PercSamp, float2(0.5, 0.5));
float  perc_p25  = perc_raw.r;   // used at lines 238, 314; dead after Stage 2
float  perc_p50  = perc_raw.g;   // used at line 371; dead after
float  eff_p25   = lerp(perc_p25, zstats.b, 0.4);
float  eff_p75   = lerp(perc_raw.b, zstats.a, 0.4);   // perc_raw.b used once, then dead
```

All downstream uses of `perc.r` → `perc_p25`, `perc.g` → `perc_p50`.

At Stage 3 peak: 1 scalar (`perc_p50`) vs current 4 scalars (`perc`). Saves 3 scalars.

Max error: 0. Drop-in (requires 4 substitutions in ColorTransformPS).

---

### RED-3: Pre-extract `hal_r` to free `lf_mip1` — **−1 scalar at Stage 3 peak**

`lf_mip1` (float4) is live from line 302 to line 429 (halation), spanning all of Stage 3.
Its `.a` channel becomes `illum_s0` at line 303. Its `.rgb` channels are used at line 429.

After line 303, `lf_mip1.a` is consumed; only `.rgb` is needed. Pre-extracting allows the
compiler to free the float4 and hold only a float3:

```hlsl
float4 lf_mip1  = tex2Dlod(CreativeLowFreqSamp, float4(uv, 0, 1));
float3 hal_r    = lf_mip1.rgb;    // extracted here; used at line 429
float  illum_s0 = max(lf_mip1.a, 0.001);
// lf_mip1 now dead — compiler can release 4 scalars, replacing with hal_r (3) + illum_s0 (1)
```

Then in the halation block, replace `lf_mip1.rgb` with `hal_r`.

Net: −1 scalar at Stage 3 peak (float4 → float3 live through Stage 3).

Max error: 0. Drop-in.

---

### RED-4: Pre-extract `col.a` to free `col.rgb` — **−3 scalars at Stage 2+ peak**

`col.rgb` is last used at line 248 (`lerp(col.rgb, lin, ...)`). `col.a` is used at
line 445 (DrawLabel). `col` as float4 stays live through the entire shader.

```hlsl
float4 col   = tex2D(BackBuffer, uv);
float  col_a = col.a;    // extracted here; col.rgb dead after line 248
```

Replace `col.a` at line 445 with `col_a`.

At Stage 3 peak: 1 scalar (`col_a`) vs current 4 scalars (`col`). Saves 3 scalars.

Max error: 0. Drop-in (requires 1 substitution).

---

## Summary

| # | Change | Scalars saved | Complexity |
|---|--------|--------------|------------|
| RED-1 | hist_cache float4→float2 | −12 | drop-in |
| RED-2 | Unpack perc early | −3 | drop-in (4 substitutions) |
| RED-3 | Pre-extract hal_r | −1 | drop-in (1 addition + 1 substitution) |
| RED-4 | Pre-extract col.a | −3 | drop-in (1 addition + 1 substitution) |
| **Total** | | **−19** | |

Estimated post-RED: ~146–150 scalars. Still above the 128-scalar threshold by ~18–22 scalars.

---

## Remaining gap

The in-shader changes above close ~half the gap. Closing the remainder without pass-splitting
requires deeper restructuring:

**Option A: Scope blocks for intermediate chains**
Wrap the `hunt_scale` computation chain (la, k, k2, k4, fla, one_mk4, fl — 7 scalars) in a
`{ }` block immediately before the hist_cache loop. If the HLSL→SPIR-V compiler respects
lexical scoping, those 7 scalars die before the loop starts. Savings: 0–7 scalars
(compiler-dependent; unconfirmed without actual disassembly).

**Option B: R62 OPT-3 (h_out weight cache)**
Still deferred: adds 6 scalars at the hist_cache loop peak. Do NOT apply until under threshold.

**Option C: Pass split — Stage 2 writes intermediate, Stage 3 reads it**
Split ColorTransformPS into two techniques:
- Pass 1 (Stage 1 + Stage 2): output `new_luma` packed into BackBuffer alpha or a float16 target.
  Peak: ~50 scalars.
- Pass 2 (Stage 3): read `new_luma` from the intermediate; apply full chroma pipeline.
  Peak: ~70 scalars.

Cost: 1 full-res VRAM read-write round-trip per frame. Contradicts the GPU budget constraint
(UE5 saturates GPU; extra vkBasalt overhead risks crashes). Use as a last resort only if
frame-time measurements show unacceptable cost from register spill.

---

## Recommendation

Implement RED-1 through RED-4 (all drop-ins). Verify scalar count with SPIR-V disassembly
after applying. If still above 128 and frame timing is degraded, try Option A (scope blocks).
If still insufficient, revisit pass-split with a measured VRAM bandwidth cost vs spill cost
tradeoff. Do NOT apply R62 OPT-3 until below 120 scalars.
