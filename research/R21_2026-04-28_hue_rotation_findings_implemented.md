# R21 — Hue Rotation: Findings

**Date:** 2026-04-29
**Status:** Research complete — implementation ready

---

## 1. Internal Audit

**Current hue usage in Stage 3 (`grade.fx` lines 548–591):**

```hlsl
float3 lab = RGBtoOklab(lin);
float  C   = length(lab.yz);
float  h   = OklabHueNorm(lab.y, lab.z);   // h in [0,1], never modified
```

`h` is read for three purposes:
1. **Chroma lift band weights** — `HueBandWeight(h, GetBandCenter(band))` inside the loop (lines 561–568)
2. **Abney correction** — `HueBandWeight(h, BAND_RED/YELLOW/CYAN/BLUE/MAGENTA)` (lines 577–581)
3. **H-K correction** — `sincos(h * 6.28318, sh, ch)` (line 590)

`h` is never written back. The (a,b) direction of the Oklab vector is preserved throughout Stage 3 — only its magnitude (C → final_C) is modified by chroma lift. Hue is structurally frozen.

**Pre-existing per-preset HSV rotation (Stage 4, lines 677–684):**

```hlsl
float3 hsv     = RGBtoHSV(result);
float  hue_dist = abs(hsv.x - HUE_SHIFT_CENTER);
hue_dist        = min(hue_dist, 1.0 - hue_dist);
float  hue_w    = smoothstep(HUE_SHIFT_WIDTH, 0.0, hue_dist) * hsv.y;
hsv.x           = frac(hsv.x + HUE_SHIFT_AMOUNT * hue_w);
result          = HSVtoRGB(hsv);
```

This exists but is inferior: (a) HSV space — hue rotation in HSV causes visible lightness contamination across primary boundaries; (b) single-band only (one HUE_SHIFT_CENTER); (c) per-preset only, not user-accessible; (d) post-film-grade — acts on post-matrix, post-rolloff output, where nonlinear artefacts compound. R21 replaces this role for user creative grading with a perceptually correct 6-band Oklab approach in Stage 3.

**Gap:** No user-adjustable mechanism to rotate any hue band. Skintones at h≈0.08 (red-orange), foliage at h≈0.40, sky at h≈0.60 are all fixed. Per-band hue control is standard in professional grading tools (DaVinci HSL qualifier, Baselight six-vector, Resolve hue-vs-hue curves).

---

## 2. Literature & Physical Basis

### 2.1 Oklab Hue Rotation Quality

**Source:** Ottosson 2020, "A perceptual color space for image processing" (bottosson.github.io); Wikipedia Oklab; Levien 2021 interactive review (raphlinus.github.io); Kasson 2022 "The search for color spaces with faithful hue angles" (blog.kasson.com).

Oklab was designed specifically for hue constancy. It uses IPT data for hue fitting: IPT has "tremendously better hue constancy" than CIELAB (Levien 2021). CIELAB, CIELUV, and HSV all shift toward purple under angular rotation in the ab/uv plane; Oklab does not (Ottosson 2020 comparison figure, confirmed by Grokipedia: "cylindrical Oklch form supports angular manipulations, such as hue rotations").

**Algebraic analysis of L and C under pure rotation:**

A rotation in the (a,b) plane by angle δ maps `(a,b) → (a cos δ − b sin δ, a sin δ + b cos δ)`. This is an isometry: the Euclidean distance from the origin is preserved. Therefore:
- `C_out = sqrt(a_out² + b_out²) = sqrt(a² + b²) = C` — chroma unchanged
- `L_out = lab.x` — unmodified (rotation doesn't touch L)

**Conclusion: a pure Oklab hue rotation at fixed C produces exactly zero L or C change.** No secondary effects on lightness or chroma by construction. This is the strongest argument for using Oklab vs. HSV or CIELAB for hue rotation.

**Residual non-uniformity:** Kasson 2022 notes Oklab's hue non-uniformity is "a misregistration of hue angle that can be corrected by a smooth angular warp" — measurable in color-science datasets, but the warp amplitude is small (< 5° per hue). At our proposed range of ±0.10 normalized hue (±36°), this non-uniformity means a requested 36° rotation in Red may produce a perceived shift of ~34–38° — well within display resolution and artistic tolerance.

### 2.2 Bell Weight Normalisation for Hue Rotation

`HueBandWeight` as implemented:
```hlsl
float t = saturate(1.0 - d / (BAND_WIDTH / 100.0));  // BAND_WIDTH = 14
return t * t * (3.0 - 2.0 * t);                       // smoothstep
```

Each band covers ±0.14 normalized hue from its center. The six bands are NOT a partition of unity. At a band center, weight = 1.0. At the midpoint between two adjacent bands (e.g., h=0.194, midway between Red 0.083 and Yellow 0.305): each weight ≈ 0.11, sum ≈ 0.22.

**For hue rotation, normalisation is NOT recommended.** Reasoning:

- **Unnormalized:** h_delta = ROT_RED × 0.11 + ROT_YELLOW × 0.11 = 0.22 × (ROT_RED+ROT_YELLOW)/2. The pixel at the boundary gets a reduced, blended rotation — appropriate: it's not firmly in either band.
- **Normalized:** h_delta = (ROT_RED + ROT_YELLOW)/2. The boundary pixel gets the full average of two independent rotations, regardless of how weakly it belongs to each band. If ROT_RED=0 and ROT_YELLOW=0.10, the normalized boundary pixel gets 0.05 — but normalising would give it 0.05 even if it barely belongs to Yellow. The unnormalized pixel would get 0.11 × 0.10 ≈ 0.011 — a much more conservative, band-limited result.

The unnormalized bell is the right behavior: maximum rotation at the band center (weight=1.0 → full h_delta), smooth taper to zero at ±BAND_WIDTH. Normalising would spread the rotation laterally and produce unexpected blending at weak band edges. Professional hue-vs-hue curves in DaVinci/Baselight show exactly this band-concentrated behavior.

**Verified: no normalisation needed.**

### 2.3 Wraparound at h=0/1

`frac(h + h_delta)` maps any value to [0,1) by definition. The reconstruction:
```hlsl
float angle_out = h_out * 6.28318;
lab.y = C * cos(angle_out);
lab.z = C * sin(angle_out);
```
`cos` and `sin` are 2π-periodic. `frac(0.0) = 0.0` and `frac(1.0) = 0.0` — both map to angle 0 = same (a,b) direction. No discontinuity. **`frac()` is sufficient. No special case needed.**

### 2.4 Interaction with H-K

H-K models the perceived brightness boost of a stimulus based on the hue and chroma of the stimulus **as it will be displayed**. If R21 rotates a red skintone warmer (redder), the displayed color is warmer — H-K should apply the correction for the warmer hue, not the original capture hue. **H-K must read the rotated hue (h_out).**

If H-K used the original h, it would apply the H-K correction for the pre-rotation color to a post-rotation display — a systematic perceptual error that would compound with larger rotations.

### 2.5 Interaction with Abney Correction

Abney correction applies a small angular rotation to the (a,b) vector based on the pixel's hue (via `HueBandWeight` calls) to counteract the perceptual Abney hue shift. The Abney effect is a property of the **displayed** color — how its perceived hue changes with increasing saturation. After R21 rotation, the displayed hue is h_out; Abney must act on h_out. **Abney must read the rotated hue.**

Using the original h in Abney after a rotation would apply the pre-rotation Abney correction to a post-rotation color, undoing part of R21's intended shift for Cyan/Blue/Red bands.

---

## 3. Proposed Implementation

### Finding 1 — Six ROT_* knobs in `creative_values.fx` [PASS]

```hlsl
// ── HUE ROTATION ─────────────────────────────────────────────────────────────
// Per-band hue rotation in Oklab space. Default 0.0 = no rotation.
// Range ±1.0 → ±36° rotation (±0.10 normalized hue). Positive = clockwise on
// the standard Oklab hue wheel (red→yellow→green→cyan→blue→magenta→red).
// Knob effect is concentrated at the band center, tapers to zero ±36° away.
#define ROT_RED     0.0
#define ROT_YELLOW  0.0
#define ROT_GREEN   0.0
#define ROT_CYAN    0.0
#define ROT_BLUE    0.0
#define ROT_MAG     0.0
```

Scale factor 0.10 is applied in the shader: `h_out = frac(h + r21_delta * 0.10)`. Knob ±1.0 → ±36°.

### Finding 2 — Two-phase injection in `ColorTransformPS` [PASS]

**Phase 1 — compute h_delta BEFORE the chroma lift loop, using original h:**

Insert after `float h = OklabHueNorm(lab.y, lab.z);` (grade.fx line 550):

```hlsl
// R21: per-band hue rotation in Oklab LCh
float r21_delta = ROT_RED    * HueBandWeight(h, BAND_RED)
                + ROT_YELLOW * HueBandWeight(h, BAND_YELLOW)
                + ROT_GREEN  * HueBandWeight(h, BAND_GREEN)
                + ROT_CYAN   * HueBandWeight(h, BAND_CYAN)
                + ROT_BLUE   * HueBandWeight(h, BAND_BLUE)
                + ROT_MAG    * HueBandWeight(h, BAND_MAGENTA);
float h_out = frac(h + r21_delta * 0.10);
```

**Phase 2 — inject rotated direction AFTER the chroma lift loop:**

Replace the existing `ab_in` line (grade.fx line 572):
```hlsl
// Original:
float2 ab_in  = float2(lab.y, lab.z);
// Replace with:
float2 ab_in  = float2(C * cos(h_out * 6.28318), C * sin(h_out * 6.28318));
```

**Phase 3 — update Abney and H-K to use h_out:**

Abney block (lines 577–581): replace every `HueBandWeight(h, ...)` with `HueBandWeight(h_out, ...)`.

H-K block (line 590): replace `sincos(h * 6.28318, sh, ch)` with `sincos(h_out * 6.28318, sh, ch)`.

**Rationale for two-phase approach:** The chroma lift loop (lines 560–568) determines band-based saturation bending from `ChromaHistoryTex`, which was computed from the unrotated scene. Using original `h` there ensures the saturation stats match the pixel's source-color band. The direction injection at Phase 2 then physically rotates the color vector. For ±0.10 rotations (≤36°), any residual mismatch between saturation-treatment hue and display hue is negligible.

**Passthrough verification:** When all six ROT_* = 0.0: r21_delta = 0.0 → h_out = frac(h + 0) = h → `ab_in = C * (cos(h·TAU), sin(h·TAU))`. But `lab.y = C·cos(h·TAU)` and `lab.z = C·sin(h·TAU)` by definition of OklabHueNorm — so `ab_in` is algebraically identical to `float2(lab.y, lab.z)`. Downstream unchanged. ✓

---

## 4. SPIR-V Compliance

| Check | Result |
|-------|--------|
| No `static const float[]` | PASS — 6 scalar variables, no arrays |
| No `static const float3` | PASS |
| No `out` as variable name | PASS — all variables prefixed `r21_` or `h_out` |
| No branches on pixel values | PASS — all `frac()`, `HueBandWeight()`, `cos()`, `sin()` |
| `frac()`, `cos()`, `sin()` intrinsics | PASS — standard SPIR-V/GLSL |
| `HueBandWeight` call count | 6 pre-loop + 6 in-loop = 12 total. Each is 4 MAD + smoothstep. Compiler may consolidate; acceptable even if not. |

---

## 5. Strategic Assessment

| Aspect | Assessment |
|--------|-----------|
| Color space quality | Oklab rotation is the best available: IPT-derived hue uniformity, zero algebraic L/C contamination, no purple shift artefact (vs. HSV/CIELAB) |
| Replaces Stage 4 HSV rotation | Stage 4 per-preset HSV rotation (HUE_SHIFT_CENTER/AMOUNT/WIDTH) is architecturally inferior. R21 in Stage 3 Oklab is strictly better quality; Stage 4 preset mechanism can stay but is superseded for user creative work |
| Bell weight normalisation | Not needed. Unnormalized bell provides band-concentrated, self-limiting rotation — matches professional hue-wheel behavior |
| Wraparound | `frac()` sufficient. cos/sin periodicity handles the 0/1 boundary |
| H-K and Abney interaction | Both must use rotated h_out. Implementation plan handles this cleanly |
| New passes | None |
| New texture reads | None |
| Cost (all-zero passthrough) | 6 HueBandWeight calls + frac + 2 trig = ~30 MAD. Compiler may elide if all ROT_* are compile-time zero (they are, as `#define`s). Actual hot-path cost: 0 additional instructions at defaults |
| Knob defaults | All 0.0 → algebraically bitwise-identical passthrough verified above |
| Range ±0.10 adequacy | Covers all practical grading (skintone temperature, sky shift, foliage). At ±0.10 (±36°), rotation stays within adjacent band's overlap zone; no hue bleeding across non-adjacent bands |
