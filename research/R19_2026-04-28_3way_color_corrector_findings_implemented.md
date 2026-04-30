# R19 — 3-Way Color Corrector: Findings

**Date:** 2026-04-28
**Status:** Research complete — implementation ready

---

## 1. Internal Audit

**Current primary controls (`grade.fx`):**

```hlsl
// Stage 1 — CORRECTIVE
float3 lin = FilmCurve(pow(max(col.rgb, 0.0), EXPOSURE), eff_p25, zone_log_key, eff_p75, spread_scale);
```

`EXPOSURE` is a single power applied identically to R, G, B before FilmCurve. No per-channel control.

```hlsl
// Stage 2 — TONAL (shadow lift, creative_values.fx)
#define SHADOW_LIFT 16  // raises all channels equally
```

Global lift. No per-channel color balance in shadows.

**Stage 4 tint structure:**
- `TOE_TINT_R/G/B` — per-preset additive in the deep toe (bell curve, ~luma 0–0.30)
- `SHADOW_TINT_R/G/B` — per-preset additive in shadow region, saturation-gated
- `HIGHLIGHT_TINT_R/G/B` — per-preset additive in highlights

All tint levels are fixed per-preset. There is no user-accessible control over the color balance between shadows, midtones, and highlights independently of the preset. A user wanting warm highlights and neutral shadows has no mechanism to achieve this.

**Gap:** No mechanism for interactive per-region primary correction. Warming highlights equally warms shadows. Cooling blacks tints the whole image.

---

## 2. Literature & Physical Basis

### 2.1 ASC CDL Specification

**Source:** ASC Color Decision List (CDL) specification v1.01, American Society of Cinematographers, 2009. Documented at `acescentral.com` and ACES developer resources.

**Canonical CDL formula:**

```
out = clamp[(in × Slope + Offset)^Power]
```

Applied per channel (R, G, B independently). The three parameters have specific operational definitions:

- **Slope** — scales the signal (linear gain, no DC offset at black). Default = 1.0.
- **Offset** — adds or subtracts a fixed value at all levels (lift/lower). Default = 0.0.
- **Power** — applies a gamma curve (Power > 1 darkens midtones; Power < 1 brightens midtones). Default = 1.0.

**Lift/Gamma/Gain equivalence (DaVinci Resolve convention):**
The color wheel convention used in professional DIT tools maps to CDL as:
- **Lift** corresponds to `Offset` — shifts the floor of each channel
- **Gamma** corresponds to `Power` — adjusts midtone relative to endpoints
- **Gain** corresponds to `Slope` — scales toward highlights

CDL is the archival/interchange format; Lift/Gamma/Gain is the interactive UI convention. For our pipeline, which is SDR and linear-light, the CDL distinction matters:

**CDL range constraints:** Slope ≥ 0. Offset is unconstrained (but typically ±0.10 for practical grading). Power > 0. The clamp to [0,1] after application is the SDR ceiling — matches our `saturate()` idiom exactly.

### 2.2 Temp/Tint Decomposition

**Standard two-axis parameterization:**

The temperature/tint two-axis decomposition is the standard parameterization used in DaVinci Resolve, Adobe Camera Raw, and Lightroom for the two degrees of freedom that distinguish white balance within the Planckian locus and departures from it.

**Temperature axis** — moves along the warm/cool dimension. In linear sRGB:
- Warm: R increases, B decreases
- Cool: R decreases, B increases
- G is held neutral (temperature shift is orthogonal to green)

**Tint axis** — moves along the green/magenta dimension perpendicular to the Planckian locus:
- Magenta tint (+): G decreases, R and B increase slightly
- Green tint (−): G increases, R and B decrease slightly

**Per-channel deltas** (from Reinhard et al. color appearance model documentation and the CIE chromatic adaptation literature — D50 to D65 direction corresponds to a "cooler" temperature shift):

For a unit temperature step (+1 = warm):
```
ΔR = +δ_temp
ΔG =  0
ΔB = -δ_temp
```

For a unit tint step (+1 = magenta):
```
ΔR = +δ_tint * 0.5
ΔG = -δ_tint
ΔB = +δ_tint * 0.5
```

Combined delta for a pixel in linear RGB space:
```hlsl
float3 col_delta = float3(
    +temp_norm + tint_norm * 0.5,   // R: warm=+, magenta=+
    -tint_norm,                      // G: magenta=-
    -temp_norm + tint_norm * 0.5    // B: cool=-, magenta=+
) * delta_scale;
```

**Hue stability check:** For a neutral grey input R=G=B=k: when temp=0, tint=0, all deltas = 0 → strictly neutral at defaults. ✓

**Hue shift risk in linear RGB:** At high saturation, a temperature delta applied in linear RGB can produce a slight hue rotation because the shift moves the (R,G,B) point by an absolute amount rather than a proportional one. For example, a saturated blue (R=0.02, G=0.05, B=0.80) shifted warm by ΔR=+0.03, ΔB=−0.03 yields (0.05, 0.05, 0.77) — hue shifts from 238° toward neutral by approximately 2–3°. At the proposed δ_max=0.030 (±100 knob range), the hue rotation for a fully saturated primary is below 3°. This is below perceptual threshold for SDR content and below 8-bit quantization visibility.

**Oklab alternative:** Applying the correction in Oklab Lch (chroma/hue stage) would guarantee hue linearity by rotating in a perceptually uniform space, but would require the corrector to run after the Oklab conversion in stage 3 rather than in stage 1. This is architecturally incorrect for a primary grade (primary corrections precede tone curves in all professional pipelines). The hue shift risk in linear RGB at practical magnitudes is below threshold. **Decision: linear RGB, stage 1.**

### 2.3 Luminance Masks for Region Isolation

**Proposed mask functions:**
```hlsl
float shadow_mask    = saturate(1.0 - luma / 0.35);
float highlight_mask = saturate((luma - 0.65) / 0.35);
float mid_mask       = 1.0 - shadow_mask - highlight_mask;
```

**Partition of unity verification:**
- luma = 0.00: shadow = 1.0, highlight = 0.0, mid = 0.0. Sum = 1.0 ✓
- luma = 0.175: shadow = 0.5, highlight = 0.0, mid = 0.5. Sum = 1.0 ✓
- luma = 0.35: shadow = 0.0, highlight = 0.0, mid = 1.0. Sum = 1.0 ✓
- luma = 0.50: shadow = 0.0, highlight = 0.0, mid = 1.0. Sum = 1.0 ✓
- luma = 0.65: shadow = 0.0, highlight = 0.0, mid = 1.0. Sum = 1.0 ✓
- luma = 0.825: shadow = 0.0, highlight = 0.5, mid = 0.5. Sum = 1.0 ✓
- luma = 1.00: shadow = 0.0, highlight = 1.0, mid = 0.0. Sum = 1.0 ✓

**Partition of unity holds everywhere.** If all six temp/tint knobs are equal, the correction is uniform across luma — no tonal banding from the masking itself.

**Gate-free compliance:** Both ramps are `saturate()` — no conditionals, no branches on pixel values. PASS.

---

## 3. Proposed Implementation

### Finding 1 — Six temp/tint knobs in creative_values.fx [PASS]

New knobs added to `creative_values.fx` (global section, not per-preset):

```hlsl
// ── 3-WAY COLOR CORRECTOR ────────────────────────────────────────────────────
// TEMP: positive = warm (R up, B down), negative = cool. Range ±100.
// TINT: positive = magenta (G down, R+B up slightly), negative = green. Range ±100.
// All default to 0 — passthrough. No output change at defaults.
#define SHADOW_TEMP      0
#define SHADOW_TINT      0
#define MID_TEMP         0
#define MID_TINT         0
#define HIGHLIGHT_TEMP   0
#define HIGHLIGHT_TINT   0
```

Per-channel delta scale: `0.030 / 100.0` maps ±100 knob range to ±0.030 additive offset in linear light. Sufficient for visible correction without gamut escape before `saturate()`.

### Finding 2 — Injection point in ColorTransformPS, after Stage 1 [PASS]

**Exact insertion point:** After line 466 (`lin = lerp(col.rgb, lin, CORRECTIVE_STRENGTH / 100.0);`), before line 469 (`float3 lin_pre_tonal = lin;`).

The block operates on the corrected linear signal with CORRECTIVE_STRENGTH already applied — if CORRECTIVE_STRENGTH=0 (bypass), the 3-way corrector operates on the unmodified signal, which is correct behavior for a primary grade.

```hlsl
// ── R19: 3-way color corrector — temp/tint per region, linear light primary grade ──
{
    float r19_luma = Luma(lin);
    float r19_sh   = saturate(1.0 - r19_luma / 0.35);
    float r19_hl   = saturate((r19_luma - 0.65) / 0.35);
    float r19_mid  = 1.0 - r19_sh - r19_hl;

    float r19_scale = 0.030 / 100.0;

    float r19_sh_temp  = SHADOW_TEMP    * r19_scale;
    float r19_sh_tint  = SHADOW_TINT    * r19_scale;
    float r19_mid_temp = MID_TEMP       * r19_scale;
    float r19_mid_tint = MID_TINT       * r19_scale;
    float r19_hl_temp  = HIGHLIGHT_TEMP * r19_scale;
    float r19_hl_tint  = HIGHLIGHT_TINT * r19_scale;

    float3 r19_sh_delta  = float3(+r19_sh_temp  + r19_sh_tint  * 0.5, -r19_sh_tint,  -r19_sh_temp  + r19_sh_tint  * 0.5);
    float3 r19_mid_delta = float3(+r19_mid_temp + r19_mid_tint * 0.5, -r19_mid_tint, -r19_mid_temp + r19_mid_tint * 0.5);
    float3 r19_hl_delta  = float3(+r19_hl_temp  + r19_hl_tint  * 0.5, -r19_hl_tint,  -r19_hl_temp  + r19_hl_tint  * 0.5);

    lin = saturate(lin + r19_sh_delta * r19_sh + r19_mid_delta * r19_mid + r19_hl_delta * r19_hl);
}
```

**Passthrough verification:** When all six knobs are 0, all deltas are 0.0 → `lin` unchanged. Strictly neutral at defaults. ✓

### Finding 3 — HIGHLIGHT_GAIN deferred

`HIGHLIGHT_GAIN` (a 0–200 master highlight level) was proposed in the spec. Assessment: `EXPOSURE` already controls the pre-FilmCurve power applied to all channels, which directly sets the relationship between midtones and highlights entering the shoulder. A post-FilmCurve highlight-only scale would require either gating on luma (violating the no-gates rule) or using the highlight_mask multiplicatively — a possible follow-up but not minimum viable. **Deferred.**

---

## 4. SPIR-V Compliance

| Check | Result |
|-------|--------|
| No `static const float[]` | PASS — no arrays used |
| No `static const float3` | PASS |
| No `out` as variable name | PASS — all variables prefixed `r19_` |
| No branches on pixel values | PASS — all `saturate()`, no `if` |
| `Luma()` helper call | PASS — already defined in grade.fx |

---

## 5. Strategic Assessment

| Aspect | Assessment |
|--------|-----------|
| Physical basis | ASC CDL Offset per channel; temp/tint = standard two-axis white balance decomposition (Resolve/Camera Raw convention) |
| Hue shift risk at δ_max=0.03 | <3° at fully saturated primaries — below SDR perceptual threshold |
| Partition of unity | Verified analytically at 7 test points across full luma range |
| Gate-free | All `saturate()` ramps — no conditionals. PASS |
| New passes | None |
| New texture reads | None |
| Cost | ~12 MAD + 1 Luma call + 3 saturate — negligible |
| Interaction with EXPOSURE | EXPOSURE runs first (power); R19 corrects color balance after. Correct professional primary-grade order |
| Interaction with R17 tints | R17 tints are Stage 4 (post film-grade, preset-defined). R19 is Stage 1 (pre-tone-curve, user-defined). Different stages, different purposes — no overlap |
| Knob defaults | All zero → passthrough. No output change on install |
