# Nightly Stability Audit — 2026-04-30

## Preflight note

The audit spec references files that do not exist in this repository:
`CLAUDE.md`, `research/HANDOFF.md`, `general/grade/grade.fx`,
`general/corrective/corrective.fx`, `general/analysis-frame/analysis_frame.fx`,
`general/analysis-scope/analysis_scope_pre.fx`, and
`gamespecific/arc_raiders/shaders/creative_values.fx`.
The `alpha` branch also does not exist; audit runs on `main`.

This report audits the **actual files present** in the repository. Every finding
is traceable to a real line of code. Spec items whose referenced files are
absent are marked N/A with an explanation.

---

## Summary

The pipeline is in reasonable shape with one active data-corruption risk:
`alpha_chroma_lift.fx` feeds an unclamped negative saturation value into
`HSVtoRGB`, which will silently corrupt any saturated pixel whenever
`CURVE_STRENGTH / 100 > equalized / (equalized - hsv.y)` — a condition that
occurs routinely with the current `CURVE_STRENGTH 40` setting. Three latent
divide-by-zero sites exist in `output_transform.fx` and `olofssonian_color_grade.fx`
but are safe at their current compile-time constant values. Register pressure is
negligible (34 scalars vs 128-scalar threshold). The BackBuffer-row-0 data-highway
convention cited in the spec is not used here — analysis data lives in dedicated
textures, which is the correct architecture.

---

## A. Register pressure

Audited file: `general/color-grade/olofssonian_color_grade.fx`, function `ColorGradePS`
(closest analog to the spec's `ColorTransformPS`).

**Variable inventory:**

| Type   | Variables | Scalar count |
|--------|-----------|-------------|
| float4 | `col` | 4 |
| float3 | `result`, `white`, `film` | 9 |
| float  | `result_luma`, `tint_base`, `toe_bell`, `tt_max`, `tt_min`, `tt_sat`, `tt_gate`, `black_w`, `st_max`, `st_min`, `st_sat`, `st_gate`, `shadow_w`, `hl_t`, `highlight_w`, `luma_pre`, `film_luma`, `fm_max`, `fm_min`, `film_chroma`, `film_gate` | 21 |

- **Total estimated scalars: 34**
- **Risk level: LOW** (34 / 128 = 27 %; well below spilling threshold)
- **Top variable groups:**
  1. float (21 scalars) — dominated by per-stage gate/weight intermediates
  2. float3 (9 scalars) — result, white, film
  3. float4 (4 scalars) — input sample col

**Fold candidates** (written once, consumed in exactly one downstream expression):
- `tint_base` (line 217) → only used to compute `toe_bell` on the very next line; fold: `float toe_bell = (1.0 - smoothstep(...)) * (1.0 - (1.0 - smoothstep(...))) * 4.0`
- `hl_t` (line 242) → only used in `highlight_w`; inline the smoothstep
- `film_luma`, `fm_max`, `fm_min` (lines 260–262) → each used only to compute `film_chroma` and `film_gate`; can be inlined
- `white` (line 256) → single-use in the white-point expression; inline as a literal float3

These folds are cosmetic at 34 scalars — no performance benefit is expected, but they remove dead-looking temporaries.

---

## B. Unsafe math sites

Files scanned: all `.fx` files under `general/` and `gamespecific/`.

| File | Line | Expression | Unsafe condition | Severity |
|------|------|------------|-----------------|----------|
| `general/alpha-chroma-lift/alpha_chroma_lift.fx` | 189 | `lerp(hsv.y, equalized, -(CURVE_STRENGTH/100.0))` | With `CURVE_STRENGTH=40` the lerp weight is −0.40; result range is [−0.4, 1.4]. No clamp before `HSVtoRGB`. Negative saturation passed to downstream produces wrong RGB with no NaN guard at function exit (line 197 has no `saturate`). | **CORRUPT** |
| `general/output-transform/output_transform.fx` | 49–50 | `float K = gc*(1.0-grey) / (grey-gc)` | If `CONTRAST` is set to exactly 1.0, `gc = pow(0.18,1.0) = 0.18 = grey`, so `grey-gc = 0` → divide-by-zero → K = INF, A = INF, tone curve returns INF for all pixels. Currently safe (`CONTRAST = 1.35` is a hardcoded `#define`). | BENIGN (latent) |
| `general/output-transform/output_transform.fx` | 75 | `excess = max(0.0, sat_gc - SAT_MAX/100.0) / (1.0 - SAT_MAX/100.0)` | If `SAT_MAX` is changed to 100, denominator = 0 → INF → gamut compression blows up. Currently safe (SAT_MAX = 85, denominator = 0.15). | BENIGN (latent) |
| `general/color-grade/olofssonian_color_grade.fx` | 244 | `highlight_w = hl_t*hl_t*(1.0-result_luma) / (1.0 - HIGHLIGHT_START/100.0)` | If `HIGHLIGHT_START = 100`, denominator = 0 → INF. Currently safe (HIGHLIGHT_START = 65, denominator = 0.35). | BENIGN (latent) |

**No log/log2 calls found anywhere in the codebase.**
**No atan2 calls found anywhere in the codebase.**
**All pow() calls guard the base with `max(x, 0.0)` or a positive constant.**
**All sqrt() calls guard the radicand with `max(..., 0.0)`.**

The three latent sites are safe at current `#define` values. They become
hazardous only if tuning pushes a denominator to zero; adding `max(..., 1e-6)`
guards is cheap insurance.

---

## C. BackBuffer row guard

**The BackBuffer-row-0 data-highway convention cited in the audit spec does not
exist in this codebase.** All inter-pass analysis data is stored in dedicated
render targets (`LumHistTex`, `SatHistTex`, `LumCDFTex`, `SatCDFTex`,
`ZoneTex`, `MatrixTex`, `ITMTex`, `ContrastTex`, `SatGateTex`), none of which
alias row 0 of the BackBuffer. This is the correct, safer architecture — it
eliminates the entire class of row-guard bugs the spec is checking for.

Passes that write directly to BackBuffer (no explicit `RenderTarget`):

| Pass | File | Row-0 guard needed? | Notes |
|------|------|---------------------|-------|
| `PrimaryCorrectionPS` | primary_correction.fx:104 | No | No data highway in BackBuffer |
| `DebugOverlayPS` | frame_analysis.fx:206 | No | Passthrough read+write |
| `ApplyOrthoPS` | youvan_orthonorm.fx:231 | No | — |
| `ApplyContrastPS` | alpha_zone_contrast.fx:96 | No | — |
| `ApplyChromaLiftPS` | alpha_chroma_lift.fx:167 | No | — |
| `ColorGradePS` | olofssonian_color_grade.fx:206 | No | — |
| `DiffuseVPS` | pro_mist.fx:161 | No | — |
| `OutputTransformPS` | output_transform.fx:58 | No | — |
| `FilmGrainPS` | film_grain.fx:49 | No | — |
| `ApplyContrastPS` | olofssonian_zone_contrast.fx:272 | No | — |
| `ApplyChromaPS` | olofssonian_chroma_lift.fx:410 | No | — |

No guards are missing because the convention does not apply. If the architecture
is ever changed to use BackBuffer row 0 as a data bus, all eleven passes above
would need guards added before any write.

---

## D. Temporal history accumulation

### EMA blend coefficients

| Shader | Coefficient expression | Effective value | In (0,1)? |
|--------|----------------------|----------------|-----------|
| `frame_analysis.fx` | `LERP_SPEED / 100.0` | 0.08 | ✓ |
| `olofssonian_zone_contrast.fx` | `LERP_SPEED / 100.0` (cold-start override to 1.0) | 0.08 | ✓ |
| `olofssonian_chroma_lift.fx` | `LERP_SPEED / 100.0` | 0.08 | ✓ |
| `youvan_orthonorm.fx` | `LERP_SPEED / 100.0` (cold-start override to 1.0) | 0.02 | ✓ |
| `alpha_zone_contrast.fx` | `clamp(LERP_SPEED/100, 0.001, 1.0)` (cold-start → 1.0) | **0.005** | ✓ |
| `alpha_chroma_lift.fx` | `clamp(LERP_SPEED/100, 0.001, 1.0)` (cold-start → 1.0) | **0.005** | ✓ |

All coefficients are strictly in (0, 1) — no freezing or history discard.

**Concern — extremely slow adaptation in alpha_zone and alpha_chroma:**
`LERP_SPEED = 0.5` yields 0.005 per frame. At 60 fps, the CDF reaches 63% of
the true value only after ~200 frames (≈3.3 seconds per scene change). This will
cause sluggish response on hard cuts. Not a stability bug, but a tuning concern;
raising `LERP_SPEED` to 4–8 in both files would match the rest of the pipeline.

### History texture formats

| Texture | File | Format | Bounded? |
|---------|------|--------|---------|
| `HistoryTex` | olofssonian_zone_contrast.fx | RGBA16F | ✓ |
| `ChromaHistoryTex` | olofssonian_chroma_lift.fx | RGBA16F | ✓ |
| `ZoneTex` | youvan_orthonorm.fx | RGBA16F | ✓ |
| `MatrixTex` | youvan_orthonorm.fx | **RGBA32F** | ⚠ flagged |
| `LumCDFTex` | alpha_zone_contrast.fx | R32F | stores [0,1] values — RGBA16F sufficient |
| `SatCDFTex` | alpha_chroma_lift.fx | R32F | stores [0,1] values — R16F sufficient |

`MatrixTex` is RGBA32F, flagged per the spec. However, the matrix coefficients
of the 3×3 correction matrix B = M × A⁻¹ are not bounded to [0,1] — they are
real-valued and can be negative or greater than 1. RGBA16F has a range of
±65504, which is likely sufficient in practice, but numerical precision of the
matrix inverse may degrade at RGBA16F. **Recommend keeping RGBA32F for MatrixTex**
and documenting this exception in a comment. The flag is noted for completeness.

### Cold-start (frame 0)

| Shader | Cold-start behaviour |
|--------|---------------------|
| `primary_correction.fx` | `if (total < 0.001) return passthrough power=1.0` — safe passthrough on frame 0 |
| `alpha_zone_contrast.fx` | `prev_max < 0.5` → speed=1.0 → CDF initialized in one frame |
| `alpha_chroma_lift.fx` | same guard as above |
| `youvan_orthonorm.fx` | `prev.a < 0.001` → speed=1.0 → zone means initialized in one frame |
| `olofssonian_zone_contrast.fx` | `prev.b < 0.001` → speed=1.0 — safe |
| `frame_analysis.fx` | Frame 0 raw histogram written immediately; smooth lags one frame at 8% weight — acceptable |

No cold-start crash or silent discard detected. All shaders have appropriate
frame-0 guards.

---

## E. R19–R22 targeted review

The named Rx job identifiers (R19–R22) and the files they reside in
(`general/grade/grade.fx`, `general/corrective/corrective.fx`,
`general/analysis-frame/analysis_frame.fx`, `general/analysis-scope/analysis_scope_pre.fx`)
do not exist in this repository. The spec appears to describe a different codebase
or a future planned state. The closest analogs in the actual code are audited below.

### R21 analog — hue rotation at C=0

**Spec concern:** 2×2 rotation matrix on Oklab (a, b); sincos path; NaN when C=0.

**Actual code:** No Oklab conversion, no explicit 2×2 hue rotation matrix, and no
`sincos` call exists anywhere in the repository. The only hue manipulation is in
`olofssonian_chroma_lift.fx:449`:

```hlsl
float final_hue = hsv.x - GREEN_HUE_COOL * green_w * final_sat;
```

This is a scalar additive nudge on the HSV hue component, bounded by `GREEN_HUE_COOL = 4/360 ≈ 0.011` and weighted by `final_sat` (which is in [0,1] after `PivotedSCurve`'s `saturate`). No divide, no sincos, no NaN risk.
**Result: R21 concern does not apply to current code — no analogous risk found.**

### R22 analog — sat-by-luma, negative C

**Spec concern:** chained `saturate()` producing negative C.

**Actual code:** The saturation path in `alpha_chroma_lift.fx:189` uses:

```hlsl
float band_sat = lerp(hsv.y, equalized, -(CURVE_STRENGTH / 100.0));
```

With `CURVE_STRENGTH = 40` (t = −0.40) this **can produce negative `band_sat`**
(range [−0.4, 1.4]), which is then weighted, averaged, and passed to `HSVtoRGB`
without a clamp. `HSVtoRGB` with negative saturation extrapolates past white,
producing RGB values outside [0,1]. The final `return float4(lerp(col.rgb, processed, gate), col.a)`
has no `saturate`. This is the active CORRUPT issue flagged in Task B.

In `olofssonian_chroma_lift.fx`, this path is safe because it uses
`PivotedSCurve(...) → saturate(m + bent)`, so `band_s` is always clamped to [0,1].
The alpha variant is the one at risk.

**Result: R22 analog concern confirmed — active CORRUPT bug in `alpha_chroma_lift.fx`.**

### R19 analog — 3-way corrector, values below 0 / above 1

**Spec concern:** temp/tint-to-RGB conversion pushing linear values outside [0,1] before Stage 2.

**Actual code:** `youvan_orthonorm.fx` is the 3-way corrector (dark/mid/bright zone means → 3×3 matrix). The apply pass:

```hlsl
float3 result = lerp(col.rgb, hue_only, ORTHO_STRENGTH / 100.0);
return float4(saturate(result), col.a);
```

`saturate` is applied before output. The intermediate `hue_only` can exceed [0,1]
(matrix multiplication of valid [0,1] inputs can produce out-of-range values), but
the `saturate` clamps before writing to BackBuffer and before downstream shaders see it.

**However:** `ORTHO_STRENGTH = 15` (only 15% blend toward the corrected value),
and the lerp itself moderates any excursions. At extreme ORTHO_STRENGTH values
(e.g., 100), the saturate clamp on very wide-matrix outputs could cause visible
hue-jumps on pure-primary pixels. Not a stability hazard, but a creative-range
concern.

**Result: R19 analog is safe at current settings — `saturate` at output prevents downstream damage.**

---

## Priority fixes

1. **`alpha_chroma_lift.fx:189` — CORRUPT — active bug**
   Add `saturate()` around the lerp result:
   ```hlsl
   float band_sat = saturate(lerp(hsv.y, equalized, -(CURVE_STRENGTH / 100.0)));
   ```
   This is sufficient: after clamping, `final_sat` stays in [0,1], `HSVtoRGB` stays
   well-behaved, and the `gate` lerp at line 197 stays in range. **One-line fix.**

2. **`output_transform.fx:50` — latent divide-by-zero in OpenDRT K computation**
   Add a guard to prevent CONTRAST=1.0 from producing INF:
   ```hlsl
   float K = gc * (1.0 - grey) / max(grey - gc, 1e-5);
   ```
   Add a comment: `// denominator is 0 when CONTRAST == 1.0 — guard required`.

3. **`output_transform.fx:75` — latent divide-by-zero in gamut compression**
   ```hlsl
   float excess = max(0.0, sat_gc - SAT_MAX / 100.0) / max(1.0 - SAT_MAX / 100.0, 1e-4);
   ```

4. **`olofssonian_color_grade.fx:244` — latent divide-by-zero in highlight weight**
   ```hlsl
   float highlight_w = hl_t * hl_t * (1.0 - result_luma) / max(1.0 - HIGHLIGHT_START / 100.0, 1e-4);
   ```

5. **`alpha_zone_contrast.fx` and `alpha_chroma_lift.fx` — LERP_SPEED tuning**
   Raise `LERP_SPEED` from 0.5 to 4–6 in both files to match the adaptation speed
   of the rest of the pipeline and avoid multi-second lag on scene cuts. Not a
   stability bug, but likely to manifest as a perceptible quality issue during
   play sessions with frequent scene transitions.
