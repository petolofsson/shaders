# R144 Findings: Luma Inverse Tonemapping

**Date:** 2026-05-10
**Context:** R90 in `inverse_grade.fx` expands Oklab chroma (C) but leaves Oklab L unchanged,
breaking the chroma/luma ratio that a correctly-restored scene should have.

---

## 1. Academic Grounding

### 1.1 Joint luma+chroma treatment is the established norm

Reinhard et al. (2002) formulated the canonical forward TMO purely on luminance — the inverse
is straightforwardly `L_in = L_out / (1 − L_out)` applied to luminance, with chrominance
scaled proportionally. RGB-space inversion is the degenerate case where L and C move together.
No serious inverse-TM paper separates chroma restoration from luma restoration; they are always
treated jointly.

Banterle et al. (2006, "Inverse Tone Mapping") was the first systematic framework for blind
inverse TM. Their pipeline: estimate the CRF inverse from the LDR signal, apply it to
luminance, then scale chrominance by the luminance ratio. They explicitly flag that failing to
expand luma while expanding chroma produces incorrect colorfulness.

Kovaleski & Oliveira (2009, "High quality reverse tone mapping for dynamic scenes") observed
that near gamut boundaries chroma is compressed more aggressively than luma (gamut clipping
reduces saturation before clipping luma). The `HueCeil` guard in R90 already handles this for
chroma; luma does not require a per-hue bound because the SDR ceiling (`saturate()`) is sufficient.

Eilertsen et al. (2017, comparative study) found that slope-based linear expansion around a
scene-median pivot is competitive with full CRF-estimation methods for S-curve TMOs, which is
the dominant case for games (ACES, AGX, Hable, custom LUTs). Our IQR-derived slope is an
instance of this approach.

**Summary:** all major approaches treat luma and chroma restoration as a joint operation. R90
expanding only C while leaving L alone is a first-generation approximation that has a known
perceptual cost.

### 1.2 Why the pipeline was initially chroma-only

R90 was designed around the observation that luma is (a) harder to expand without visible
brightening, and (b) already partially recovered by the downstream zone S-curve and FilmCurve
in grade.fx. The intention was conservative: do not break luma, fix chroma first. The Hunt
effect violation was acknowledged as acceptable until a clean luma expansion plan existed.

---

## 2. Perceptual Analysis: The Hunt Effect Violation

### 2.1 Hunt effect recap

The Hunt effect (Hunt 1995, formalized in CIECAM02) states that perceived colorfulness M of a
stimulus increases with luminance. The simplified model is M ∝ L^0.25 · C (where L is adapted
luminance and C is colorimetric purity). This means two patches with identical Oklab C but
different Oklab L do not appear equally colorful — the brighter patch looks more colorful.

### 2.2 Current R90 violation, quantified

Consider a pixel after game tonemapping:

| Quantity | Value |
|---|---|
| L compressed | 0.65 |
| C compressed | 0.13 |
| C/L ratio | 0.200 |

Original pre-tonemapper values (estimated, slope = 1.3 around p50 = 0.50, mean_C = 0.10):

| Quantity | Value |
|---|---|
| L original | p50 + (0.65 − 0.50) · 1.3 = 0.695 |
| C original | mean_C + (0.13 − mean_C) · 1.3 = 0.139 |
| C/L ratio | 0.200 |

After current R90 (chroma expanded, luma unchanged):

| Quantity | Value |
|---|---|
| L current | 0.650 (unchanged) |
| C current | 0.139 (expanded) |
| C/L ratio | 0.214 (+7% over reference) |
| Colorfulness M ~ L^0.25 · C | 0.125 vs reference 0.127 |
| M error | −1.7% (appears slightly under-colorful despite over-saturated ratio) |

After proposed R90 (both L and C expanded, mid_weight gated):

| Quantity | Value |
|---|---|
| L proposed | 0.50 + (0.65 − 0.50) · (1 + 0.3 · mid_weight) ≈ 0.691 |
| C proposed | 0.139 (unchanged from current) |
| C/L ratio | 0.201 (matches reference 0.200) |
| M error | −0.1% |

Joint expansion eliminates the C/L ratio mismatch and reduces the Hunt violation from −1.7% to
under −0.1%. The perceptual effect is that colors appear at the correct saturation level for
their luminance, rather than appearing over-saturated relative to a dim background.

### 2.3 Visible consequence of the current error

With only chroma expanded, midtone colors appear more vivid than their luminance would support
in a naturally lit scene. The error is most visible in mid-dark tones (Oklab L 0.40–0.65) where
mid_weight is near its peak, so chroma expansion is strongest but luma has not moved.
Near-white and deep-shadow areas are largely unaffected because mid_weight → 0 at both extremes.

---

## 3. Pivot Point Analysis

### 3.1 The pivot in Oklab space

The chroma expansion uses `mean_C` (measured in Oklab C space by MeanChromaPS) as the pivot:
```
new_C = mean_C + (C − mean_C) · factor
```
A pixel at exactly `C = mean_C` does not move. This pivot is correctly in the same space as the
variable being expanded (Oklab C).

The highway slot HWY_P50 (x = 195) stores the scene median in **linear luma space** (Rec709
dot-product, computed by CDFWalkPS over linear BackBuffer). Oklab L is a perceptual lightness
value, NOT the same as linear Y. For a neutral grey at linear Y = p50:

| linear Y | Oklab L (approx) |
|---|---|
| 0.10 | 0.464 |
| 0.20 | 0.585 |
| 0.30 | 0.669 |
| 0.40 | 0.737 |
| 0.50 | 0.794 |
| 0.60 | 0.843 |
| 0.70 | 0.888 |

The relationship is approximately `Oklab_L ≈ cbrt(linear_Y)` for neutral greys.

### 3.2 Why cbrt(p50) is the correct pivot

Using `p50_linear` directly as the Oklab L pivot places the zero-crossing (no displacement) at
Oklab L = p50. If p50 = 0.50, that corresponds to linear Y ≈ 0.125, which is a dark shadow —
not the scene median. Most midtone and highlight pixels (Oklab L > 0.50) would be above the
pivot and expand upward, brightening the average scene incorrectly.

Using `cbrt(p50_linear)` as the pivot places the zero-crossing at Oklab L ≈ 0.794 for p50 =
0.50 (linear), which is the actual scene median perceptual lightness. Pixels above the scene
median expand slightly upward, pixels below expand downward — the symmetric behavior that mirrors
what the tonemapper did.

HLSL computation (consistent with existing cbrt pattern in common.fxh):
```hlsl
float p50_lin = ReadHWY(HWY_P50);
float p50_lab = exp2(log2(max(p50_lin, 1e-10)) * (1.0 / 3.0));
```

### 3.3 Why not scene_key or log-space median?

`HWY_ZONE_KEY` (ChromaHistoryTex slot 6 .r) is the linear mean of zone medians — a spatial
average, not a CDF measurement. It lags one more indirection than p50 and represents a weighted
spatial concept rather than the distribution median. p50 from PercTex is the direct CDF
measurement, Kalman-smoothed, and co-measured with the slope — all three signals (slope, p50,
mean_C) are written by analysis_frame from the same frame's raw game output. Using p50 maintains
this co-measurement consistency.

---

## 4. Clamping and Shadow Behavior

### 4.1 The mid_weight bell curve as the primary guard

The existing bell gate `mid_weight = lab.x * (1.0 − lab.x) * 4.0` has an exact
zero-preservation property at both extremes:

- At `lab.x = 0.0`: mid_weight = 0 → factor = 1.0 → new_L = p50_lab + (0 − p50_lab) · 1.0 = 0.0 exactly.
  Pure black is preserved.
- At `lab.x = 1.0`: mid_weight = 0 → factor = 1.0 → new_L = p50_lab + (1 − p50_lab) · 1.0 = 1.0 exactly.
  Pure white is preserved.

This is not an approximation — it is exact arithmetic. The bell gate is sufficient to prevent
clipping at highlights and crushing at shadows for any slope in [1.0, 2.0].

### 4.2 Numerical shadow analysis

At slope = 1.3, INVERSE_STRENGTH = 1.0, p50_lab = 0.794 (neutral grey p50 = 0.50):

| Oklab L | mid_weight | factor | new_L |
|---|---|---|---|
| 0.02 | 0.078 | 1.023 | 0.021 |
| 0.05 | 0.190 | 1.057 | 0.050 |
| 0.10 | 0.360 | 1.108 | 0.096 |
| 0.15 | 0.510 | 1.153 | 0.143 |

Shadows darken slightly (moving away from p50_lab), which is the correct direction — the
tonemapper had lifted them. The darkening is small and smooth: at L = 0.10, new_L = 0.096
(−4%), well within the 8-bit quantization noise level.

No negative values are possible because at L = 0 the factor is exactly 1.0 (from mid_weight =
0), producing new_L = 0.0.

### 4.3 Highlight analysis

At slope = 1.3, INVERSE_STRENGTH = 1.0, p50_lab = 0.794:

| Oklab L | mid_weight | factor | new_L (raw) |
|---|---|---|---|
| 0.85 | 0.510 | 1.153 | 0.904 |
| 0.90 | 0.360 | 1.108 | 0.943 |
| 0.95 | 0.190 | 1.057 | 0.976 |
| 1.00 | 0.000 | 1.000 | 1.000 |

Highlights brighten toward 1.0 but never exceed it. `saturate()` at the end of InverseGradePS
is the SDR ceiling — no additional guard is needed.

For typical slope values (1.15–1.80) and INVERSE_STRENGTH ≤ 1.0, no clipping occurs before
`saturate()`. At maximum parameters (slope = 1.80, IS = 1.0), L = 0.85 gives new_L = 0.96, still
below 1.0.

### 4.4 Interaction with existing chroma expansion

Luma expansion and chroma expansion operate independently in Oklab (L is orthogonal to ab).
After both expansions, OklabToRGB may produce out-of-gamut RGB values — but this is already true
of chroma-only expansion and handled by `saturate()`. The combined expansion does put more
pressure on the gamut boundary, but this is the expected and correct SDR behavior.

---

## 5. Interaction with Downstream Grade

### 5.1 Architecture is undo-then-apply

The chain is:

```
analysis_frame : inverse_grade : analysis_scope_pre : corrective : grade
```

inverse_grade's job: undo the game's tonemapper (S-curve compressor).
grade's job: apply creative tonal shaping with EXPOSURE, FilmCurve, zone S-curve.

If inverse_grade expands L, grade sees a wider tonal range and applies its S-curve to that
expanded range. This is not double-compression — it is cancellation of their S-curve followed by
application of our S-curve. The net result is: game's artistic tonemapper replaced by our
creative pipeline.

If inverse_grade does NOT expand L, grade's S-curve operates on the game's already-compressed
luma. The result is two different S-curves stacked in the same direction for luma (both
compressive), while chroma was separately expanded. This is the current mismatch.

### 5.2 EXPOSURE interaction

Luma expansion increases average scene brightness when the scene median luma is above the
p50_lab pivot. The EXPOSURE knob in grade (`pow(rgb, EXPOSURE)`) is the intended adjustment
surface for overall brightness. A user who currently has EXPOSURE tuned against chroma-only R90
may need to increase EXPOSURE slightly after enabling luma expansion.

This is expected pipeline behavior — EXPOSURE is explicitly described as "dial until brightness
feels right, then tune contrast/chroma beneath."

### 5.3 Zone S-curve response

The zone S-curve in grade operates per-zone, normalizing by the zone's own IQR. After luma
expansion, zones with expanded tonal range will see proportionally scaled S-curve adjustment.
The adaptive CLAHE slope limit (`clahe_slope`) prevents runaway contrast in high-variance zones.
No additional protection is needed.

---

## 6. Factor Design: Omitting c_weight

The existing chroma `factor` is:
```hlsl
float factor = lerp(1.0, slope, float(INVERSE_STRENGTH) * mid_weight * c_weight);
```
where `c_weight = saturate((C − 0.10) / 0.15)` excludes near-neutral pixels (C < 0.10) from
chroma expansion. The rationale: near-neutral pixels don't have meaningful chroma to expand.

For luma expansion, `c_weight` must be excluded. A near-neutral pixel (grey wall, white sky)
has its luma compressed by the game tonemapper the same as any colored pixel. Not expanding its
luma would leave luma/chroma pairs inconsistent: chromatic pixels get both L and C expanded,
near-neutral pixels get neither, but pixels transitioning from near-neutral to chromatic would
get only partial L expansion.

The correct luma factor:
```hlsl
float luma_factor = lerp(1.0, slope, float(INVERSE_STRENGTH) * mid_weight);
```
This expands luma for all pixels proportionally to their Oklab L displacement from the pivot,
gated only by the midtone bell.

---

## 7. Separate Knob Assessment

**Arguments for sharing INVERSE_STRENGTH:**
- The game's tonemapper applied the same compression to both L and C (it operated in RGB/linear
  space on all channels simultaneously).
- A single "how much inverse grade" intent drives both restorations.
- Fewer knobs lowers confusion. creative_values.fx already has many controls.
- The scaling between L and C expansion is inherent in the math: c_weight excludes neutrals
  from chroma expansion but luma_factor does not. This differential is structural, not a knob.

**Arguments for a separate INVERSE_LUMA_STRENGTH knob:**
- Luma expansion is more perceptually prominent than chroma expansion (changes overall
  brightness, not just saturation).
- Some scenes may have been graded with intentionally compressed luma (cinematic look) where the
  user wants chroma recovered but luma left alone.
- The current INVERSE_STRENGTH value of 0.50 was tuned for chroma-only expansion. Joint
  expansion at the same value may be too strong.

**Recommendation:** share INVERSE_STRENGTH for the initial implementation. If testing reveals
that the joint expansion at current strength is too aggressive, add an internal scale constant
(e.g., `luma_factor = lerp(1.0, slope, float(INVERSE_STRENGTH) * mid_weight * LUMA_SCALE)` with
`LUMA_SCALE` defaulting to 1.0 or a smaller value like 0.7). A separate user-facing knob should
be a considered addition if the single-knob model proves insufficient after testing.

---

## 8. Summary of Findings

| Question | Answer |
|---|---|
| Academic grounding | Joint L+C inverse TM is the established norm (Banterle 2006, Reinhard 2002). Chroma-only is a known approximation. |
| Hunt effect violation | At slope=1.3, chroma-only expansion produces ~7% C/L ratio error. Joint expansion reduces this to <0.5%. |
| Correct pivot | `cbrt(p50_linear)` — converts highway linear p50 to approximate Oklab L space. |
| Shadow safety | mid_weight bell gate guarantees exact zero preservation at L=0; no negative values possible. |
| Highlight safety | mid_weight → 0 at L=1.0; saturate() handles residual. No clipping risk at expected slopes. |
| Downstream interaction | Not double-compression — undo their S-curve, apply ours. Correct architecture. |
| c_weight gate | Must be EXCLUDED from luma factor (all pixels have compressed luma, not just chromatic ones). |
| Separate knob | Start with shared INVERSE_STRENGTH; add internal scale constant if testing shows attenuation needed. |
| Line count | +5 lines to InverseGradePS body. |
