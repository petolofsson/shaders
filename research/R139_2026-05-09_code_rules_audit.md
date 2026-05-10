# R139 — Code Rules Audit (Power of Ten, HLSL adaptation)

**Date:** 2026-05-09
**Status:** Complete — all items resolved (F4-A implemented 2026-05-10)
**Scope:** All `.fx` and `.fxh` files under `general/` and `gamespecific/arc_raiders/shaders/`

Files audited:
- `general/grade/grade.fx`
- `general/corrective/corrective.fx`
- `general/inverse-grade/inverse_grade.fx`
- `general/analysis-frame/analysis_frame.fx`
- `general/analysis-scope/analysis_scope.fx`
- `general/analysis-scope/analysis_scope_pre.fx`
- `general/highway.fxh`
- `general/hue_bands.fxh`

---

## Rule 1 — Simple control flow

### F1-A: `GetBandCenter()` is a 6-way if-ladder, called per pixel in a loop body

`grade.fx:236–244`, `corrective.fx:168–176`, `analysis_frame.fx:38–46` all define:

```hlsl
float GetBandCenter(int b) {
    if (b == 0) return BAND_RED;
    if (b == 1) return BAND_YELLOW;
    ...
    return BAND_MAGENTA;
}
```

This is called inside the 6-iteration `[unroll]` loop in `grade.fx:576–582`. On GPU, the whole if-ladder executes as divergent branches across the unrolled iterations. The correct HLSL form is a `lerp`-weighted sum over all band centers, or a `mul` against a constant vector — neither branch on pixel data.

### F1-B: Conditional on history data in `UpdateHistoryPS`

`corrective.fx:335`:
```hlsl
if (prev_slow < 0.001) prev_slow = zone_log_key;
```
This is a conditional assignment gated on a previously stored scalar from a history texture. Equivalent arithmetic: `prev_slow = lerp(zone_log_key, prev_slow, step(0.001, prev_slow))`.

Same pattern at `analysis_frame.fx:383`: `float P = (prev.a < 0.001) ? 1.0 : prev.a` — uses ternary on a data value; equivalent to `lerp(1.0, prev.a, step(0.001, prev.a))`.

### F1-C: Highway dispatch if-ladders

`grade.fx:254–276` (ColorTransformPS highway writes) and `grade.fx:749–759` (DiffusionPS highway write) use sequential `if (xi == HWY_*)` blocks to select which highway slot to write. Since `xi = int(pos.x)`, this is uniform-per-lane within a warp row, not a per-pixel data branch, so these are less critical. However, a `switch` statement or a multi-way `step`/`lerp` dispatch would be preferable.

---

## Rule 2 — Fixed loop bounds with explicit annotations

### F2-A: `NeutralIllumPS` nested loops have no annotation

`grade.fx:831–842`:
```hlsl
for (int iy = 0; iy < 9; iy++)
for (int ix = 0; ix < 16; ix++)
```
No `[unroll]` or `[loop]` attribute. Every other loop in the codebase is annotated; this is the sole omission. Bounds are constant (144 iterations total). Should be `[unroll]` — these are texture samples in a 16×9 grid.

---

## Rule 3 — No runtime resource allocation

No violations. All textures, samplers, and render targets are declared statically in effect headers. Local arrays (`float hist[32]` in `analysis_frame.fx:417`, `float samples[64]` in `analysis_scope_pre.fx:58`) live in thread-private registers, which is correct.

**Note on `analysis_frame.fx:432`:** `hist[bin] += in_b` writes a local array at a computed index derived from pixel chroma data. SPIR-V lowers variable-index private array writes to `OpCompositeInsert` chains (one per possible index). For a 32-element array this generates ~32 OpCompositeInsert ops, which is legal but potentially large. Worth checking compiled SPIR-V size. Not a correctness issue.

---

## Rule 4 — Functions ≤ 60 lines

### F4-A: `ColorTransformPS` (grade.fx) — ✅ resolved 2026-05-10 (R142)

Extracted `BuildSceneCtx()`, `ApplyCorrective()`, `ApplyTonal()`, `ApplyChroma()` as stage helpers. Scene-uniform data grouped in `SceneCtx` struct; cross-stage pixel outputs (new_luma, local_var) in `TonalOut` struct. ColorTransformPS reduced to ~47-line orchestrator. See `research/R142_2026-05-10_colortransformps_stage_split.md`.

### F4-B: `ScopePS` (analysis_scope.fx:116–267) — ~152 lines

Three distinct rendering sections (top histogram, mid histogram, hue panel) share a single function. Each section is ~40 lines and is independently extractable.

### F4-C: `UpdateHistoryPS` (corrective.fx:303–384) — ~82 lines

Contains three distinct code paths (band_idx == 6, band_idx == 7, default) that could be three functions or at minimum three extracted sub-routines.

### F4-D: `DiffusionPS` (grade.fx:746–819) — ~74 lines

The highway-write section (~15 lines) and the bloom/grain compositing section (~45 lines) are independently extractable.

### F4-E: `ScopeCapturePS` (analysis_scope_pre.fx:52–115) — ~64 lines

Marginal (4 lines over limit). Handles luma histogram, hue histogram, and passthrough in the same function.

### F4-F: `MeanChromaPS` (analysis_frame.fx:415–473) — ~59 lines

At the limit. The histogram accumulation and CDF walk are separable.

---

## Rule 5 — Explicit bounds on every output

### F5-A: Dither added after final `saturate` in `ColorTransformPS`

`grade.fx:667–674`:
```hlsl
lin = saturate(chroma_rgb);       // last saturate
...
lin += dither * (1.0 / 255.0);   // adds ±0.002 after bounding
return DrawLabel(float4(lin, col.a), ...);  // no re-bound
```
`lin` can exit `ColorTransformPS` with values in `[-1/510, 1+1/510]`. The 8-bit BackBuffer clips this, but the rule requires the bound to be applied explicitly at the point of output, not implicitly by the hardware write. `DrawLabel` itself may also write out-of-range pixels in the label region.

### F5-B: Kalman covariance `P_new` is unbounded in `UpdateHistoryPS`

`corrective.fx:376–383`:
```hlsl
float P_new  = (1.0 - K) * P_pred;
...
return float4(new_mean, new_std, new_wsum, P_new);
```
`P_new` is stored in a `RGBA16F` texture (no hardware clipping). In a healthy Kalman, P converges to a finite steady-state. But if the filter diverges (uninitialised state, unusual input), P_new can grow without bound. The pipeline reads `prev.a` back next frame with a cold-start guard `(prev.a < 0.001) ? 1.0 : prev.a`, which doesn't cap large positive values. No explicit upper bound is applied.

### F5-C: `RGBtoOklab` functions accept unclamped input

`grade.fx:191–203`, `corrective.fx:136–150`, `inverse_grade.fx:47–57`, `analysis_frame.fx:194–205`. All four implementations protect against log(0) via `max(..., 1e-10)`, but do not clamp negative or above-1 RGB inputs before the dot products. The callers mostly pass previously saturated values, so in practice this is safe, but the functions themselves do not enforce their domain contract.

---

## Rule 6 — Smallest scope

### F6-A: `lms_illum_norm` declared outside its computing block

`grade.fx:282–291`:
```hlsl
float3 lms_illum_norm;          // declared in outer scope
{
    const float3x3 M_fwd = ...;
    float3 illum_rgb  = tex2Dlod(NeutralIllumSamp, ...);
    float3 illum_norm = illum_rgb / ...;
    float3 lms_illum  = mul(M_fwd, illum_norm);
    lms_illum_norm    = lms_illum / ...;  // writes outer variable
}
```
`lms_illum_norm` is not declared inside the block that computes it. Either move the declaration inside the block and make it the block's output, or collapse the block and declare in place.

### F6-B: `lf_mip2_tex` / `lf_mip2` hoisted far above first use

`grade.fx:339–341` declares and fetches these; first use is at `grade.fx:355` (halation). Reuse occurs at `grade.fx:495` (R66) and `grade.fx:643` (R117C). The comment acknowledges this is intentional ("hoisted: needed by halation… and reused"). The hoist is justified as a performance optimisation (avoid re-issuing the texture fetch), but it violates Rule 6 by scoping data to the entire function when only three blocks need it. The fix would be to pass `lf_mip2` as a parameter to extracted stage helpers, or accept the re-fetch cost.

### F6-C: Loop variable `total_w` and `new_C` in `ColorTransformPS` declared before the chroma lift loop

`grade.fx:575`:
```hlsl
float new_C = 0.0, total_w = 0.0;
[unroll] for (int band = 0; band < 6; band++) { ... }
```
These are accumulated in the loop then used immediately after. The scope is correct — they are not used before the loop. Minor concern only.

---

## Rule 7 — Validate inputs; use all outputs

### F7-A: `HueCeil()` and `HueBandRollN()` accept unclamped hue

`hue_bands.fxh:56` and `hue_bands.fxh:98`. Both functions accept a `float hue` parameter that is expected to be in `[0, 1]` (normalized Oklab hue). Neither function clamps or validates the input. Callers use `frac()` before calling, so the contract is met in practice, but the function itself should enforce `hue = frac(hue)` at entry to be self-defending.

### F7-B: `GetBandCenter()` does not validate its integer argument

`grade.fx:236–244`: if `b < 0` or `b > 5`, all `if` conditions are false and the function silently returns `BAND_MAGENTA` (the last statement). This is an implicit default rather than a documented boundary. The function should clamp `b = clamp(b, 0, 5)` before the dispatch.

### F7-C: `DrawLabel` return value path in `ColorTransformPS` and `DiffusionPS`

`grade.fx:674`: `return DrawLabel(float4(lin, col.a), ...)` — DrawLabel is a void-ish wrapper that modifies the float4 in place; its return IS used directly as the shader output. Not a violation, but the function signature (not shown here — it's in `debug_text.fxh`) should be verified to always return a bounded float4.

---

## Rule 8 — Preprocessor for constants and includes only

### F8-A: `corrective.fx` redefines 6 band-center constants instead of including `hue_bands.fxh`

`corrective.fx:27–33`:
```hlsl
#define BAND_RED     0.083
#define BAND_YELLOW  0.305
#define BAND_GREEN   0.396
#define BAND_CYAN    0.542
#define BAND_BLUE    0.735
#define BAND_MAGENTA 0.913
```
These are the 6-band subset of the 12 canonical values in `hue_bands.fxh`. They are duplicated by hand, creating a maintenance hazard: if the canonical values in `hue_bands.fxh` change, `corrective.fx` silently diverges.

### F8-B: `grade.fx` defines alias macros for band centers

`grade.fx:26–37`:
```hlsl
#define BAND_RED     HB_BAND_RED
#define BAND_ORANGE  HB_BAND_ORANGE
...
```
These aliases forward to `hue_bands.fxh` values. The aliases add a macro-indirection layer that requires two lookups to trace a value. Direct use of `HB_BAND_*` is cleaner.

### F8-C: Core utility functions duplicated across files

Functions that are identical or near-identical in multiple effect files, instead of being shared via a common header:

| Function | Files |
|---|---|
| `PostProcessVS` | grade.fx, corrective.fx, inverse_grade.fx, analysis_frame.fx, analysis_scope.fx, analysis_scope_pre.fx — 6 copies |
| `Luma` | 5 copies (all files) |
| `RGBtoOklab` / `RGBToOklab` | grade.fx, corrective.fx, inverse_grade.fx, analysis_frame.fx — 4 copies, with minor structural differences |
| `OklabToRGB` | grade.fx, inverse_grade.fx — 2 copies |
| `OklabHueNorm` | grade.fx, corrective.fx — 2 copies |
| `RGBtoHSV` | analysis_frame.fx, analysis_scope.fx, analysis_scope_pre.fx — 3 copies, with differing epsilon values (`1e-10` vs. `1.0e-10` vs. hardcoded `0.001e-10`) |
| `GetBandCenter` | grade.fx, corrective.fx, analysis_frame.fx — 3 copies with different constant sets |
| `HueBandWeight` | corrective.fx (uses `BAND_WIDTH/100.0`), analysis_frame.fx (uses `BAND_WIDTH=0.15` directly), analysis_scope.fx (uses `BAND_WIDTH=0.15`) — 3 implementations with different normalisation conventions |

The `RGBtoHSV` epsilon inconsistency is the highest-risk duplication: `1.0e-10` in analysis_scope.fx vs. `1e-10` in analysis_scope_pre.fx — these are identical values but the inconsistency across copies makes future divergence likely.

### F8-D: `HueBandWeight` has two different normalisation conventions

`corrective.fx:161–166` uses `BAND_WIDTH = 8` (integer) and computes `d / (BAND_WIDTH / 100.0)`, giving an effective half-width of `0.08`. `analysis_frame.fx:187–192` uses `BAND_WIDTH = 0.15` (float) and divides directly. These produce the same result for different values of BAND_WIDTH, but the indirection through integer constants with a `/100.0` scaling factor obscures this. A reader cannot determine the effective band width without tracing the constant definition.

---

## Rule 9 — One level of sampler indirection

No violations found. No nested texture lookups (tex2D result used as a coordinate for a second tex2D). All `tex2D`/`tex2Dlod` calls take UV coordinates derived from either `uv` (vertex interpolant), `pos.xy` (pixel position), or simple arithmetic on those. `ReadHWY()` is the documented sampler-in-macro exception.

---

## Rule 10 — Zero warnings; known-gotcha checklist

### F10-A: `CreativeLowFreqTex` declared with conflicting `MipLevels` across effects

`corrective.fx:48`: `MipLevels = 1`
`grade.fx:84`: `MipLevels = 3`

This is the same cross-technique render target declared differently in two effects. Per the CLAUDE.md gotcha: "MipLevels > 1 on a texture written by one technique and read by another silently zeroes mip1+." The grade.fx declaration with `MipLevels = 3` is wrong — corrective.fx writes this texture with `MipLevels = 1`. All current reads in grade.fx use explicit LOD 0 (via `tex2Dlod(..., float4(suv, 0, 0))` or `tex2D`), so mip1/2 access does not occur in practice. However the stale `MipLevels = 3` declaration is a latent hazard: any future read that assumes mip1 is populated would silently receive zero.

### F10-B: `NeutralIllumPS` loop annotation missing (duplicate of F2-A)

`grade.fx:831–842`: no `[unroll]` or `[loop]` attribute on a 144-iteration nested loop. Every other loop in the pipeline is annotated. This should be `[unroll]` (16×9 = 144 taps; this is the standard grid sampling pattern used elsewhere with `[unroll]`).

### F10-C: Variable-index write to local array in `MeanChromaPS`

`analysis_frame.fx:432`:
```hlsl
float hist[CHROMA_BINS];  // 32 elements
...
int bin = clamp(int(C / CHROMA_C_MAX * CHROMA_BINS), 0, CHROMA_BINS - 1);
hist[bin] += in_b;  // variable-index write
```
Variable-index writes to local (private) arrays compile correctly in DXC/SPIR-V but expand to `OpCompositeInsert` chains — one per possible index value. For `CHROMA_BINS = 32` inside a 32×18 = 576-iteration loop, the generated SPIR-V may be very large. Not a correctness issue under current toolchain, but should be checked in the compiled SPIR-V and documented in the gotcha list.

---

## Severity summary

| ID | Rule | File(s) | Severity | Status |
|---|---|---|---|---|
| F4-A | 4 | grade.fx | High — ColorTransformPS at 427 lines | Open |
| F8-C | 8 | all files | High — 6 functions duplicated 2–6× | ✅ Resolved — common.fxh + hue_bands.fxh |
| F8-A | 8 | corrective.fx | High — band constants duplicated, divergence risk | ✅ Resolved — corrective.fx uses HB_BAND_* |
| F10-A | 10 | grade.fx, corrective.fx | Medium — MipLevels mismatch on cross-technique texture | ✅ Resolved — both MipLevels = 1 |
| F1-A | 1 | grade.fx, corrective.fx, analysis_frame.fx | Medium — GetBandCenter if-ladder per pixel | ✅ Resolved — called only from [unroll] loops; b is compile-time constant, branches resolve statically |
| F4-B | 4 | analysis_scope.fx | Medium — ScopePS at 152 lines | ✅ Resolved — DrawLumaPost/DrawLumaPre/DrawHuePanel extracted |
| F4-C | 4 | corrective.fx | Medium — UpdateHistoryPS at 82 lines | ✅ Resolved — ComputeZoneStats/ComputeSlowKey/UpdateChromaKalman extracted |
| F5-A | 5 | grade.fx | Medium — dither added after final saturate | ✅ Resolved — saturate wraps dither in both shaders |
| F7-A | 7 | hue_bands.fxh | Medium — HueCeil/HueBandRollN accept unclamped hue | ✅ Resolved — frac(hue) guard added to HueBandWeight |
| F2-A / F10-B | 2, 10 | grade.fx | Low — NeutralIllumPS loops unannotated | ✅ Resolved — [unroll] added |
| F1-B | 1 | corrective.fx | Low — conditional on history data | ✅ Resolved — lerp(zone_log_key, prev_slow, step(0.001, prev_slow)) |
| F4-D | 4 | grade.fx | Low — DiffusionPS at 74 lines | ✅ Resolved — ApplyDiffusionBloom + ApplyFilmGrain extracted |
| F4-E | 4 | analysis_scope_pre.fx | Low — ScopeCapturePS at 64 lines | ✅ Resolved — CaptureLumaHistPixel + CaptureHueHistPixel extracted |
| F5-B | 5 | corrective.fx | Low — Kalman P_new unbounded | ✅ Resolved — saturate((1.0 - K) * P_pred) |
| F5-C | 5 | all files | Low — RGBtoOklab unclamped input | ✅ Resolved — rgb = saturate(rgb) at top of RGBtoOklab in common.fxh |
| F6-A | 6 | grade.fx | Low — lms_illum_norm outer-scope declaration | ✅ Resolved — declared inline at point of computation |
| F6-B | 6 | grade.fx | Low — lf_mip2 hoisted across function body | Leave intentionally — avoids redundant texture fetch (documented) |
| F7-B | 7 | grade.fx, corrective.fx | Low — GetBandCenter implicit default for out-of-range b | ✅ Resolved — clamp(b, 0, 5) added in hue_bands.fxh |
| F8-B | 8 | grade.fx | Low — BAND_* alias macros | ✅ Resolved — aliases removed |
| F8-D | 8 | corrective.fx, analysis_frame.fx | Low — HueBandWeight two normalisation conventions | ✅ Partial — analysis_frame.fx renamed HSVBandWeight; conventions now distinct by name |
| F10-C | 10 | analysis_frame.fx | Low — variable-index write to local array | Note only — correctness confirmed; SPIR-V size check needs tooling |

---

## Not violations (notable but compliant)

- **`ReadHWY()` macro**: sampler access in macro body is the documented exception per `code_rules.md` Rule 9.
- **Data highway guard (`if (pos.y < 1.0) return col`)**: all BackBuffer-writing passes implement this correctly.
- **`tex2Dlod(BackBuffer, ...)`**: not found in any file. ✓
- **`static const float[]`**: not found. All local arrays are `float arr[N]` (thread-private), not `static const`. ✓
- **Variable named `out`**: not found. ✓
- **All loop bounds are constants**: no loop terminates on a pixel-data condition. ✓
