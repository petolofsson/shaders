# R86 Scene Reconstruction — Run 01 — Inverse Tone Mapping — 2026-05-04 00:00

## Run angle

**Angle 0 — Inverse tone mapping / HDR reconstruction**

`(00 // 6) % 3 = 0 % 3 = 0`

This run surveys the state of the art for analytical, closed-form per-pixel inversion of the
Hill 2016 ACES rational function, with emphasis on GPU feasibility within the existing
`grade.fx` MegaPass (ColorTransformPS). The previous run (R57, angle 2) established
fingerprinting heuristics that gate whether the inverse is safe to apply; this run provides
the inverse itself.

---

## HIGH PRIORITY findings

### Closed-form quadratic inverse of Hill 2016 ACES (community derivation, confirmed)

The analytical inverse of `f(x) = (2.51x² + 0.03x) / (2.43x² + 0.59x + 0.14)` is a
single-pass, per-pixel, ~6-ALU shader expression. This derivation is already in community
circulation (Shadertoy wlfyWr, NtXyD8) and has been independently verified in this run.

**HLSL implementation — directly insertable into ColorTransformPS Stage 0:**

```hlsl
// Inverse of Hill 2016 ACES rational approximation.
// Input y: display-referred [0,1]. Output: scene-linear [0, ~7.24].
// Derived from quadratic formula; coefficients scaled ×100 for numerical cleanliness.
// Valid for y ∈ [0,1]; denominator guard required if y could exceed 1.0329.
float3 InverseACESHill(float3 y) {
    float3 D = sqrt(max(-10127.0 * y * y + 13702.0 * y + 9.0, 0.0));
    return (D + 59.0 * y - 3.0) / max(502.0 - 486.0 * y, 1e-4);
}
```

**Validation table (forward(inverse(y)) round-trip, analytical):**

| y (display-referred) | x = inverse(y) | f(x) — should equal y |
|----------------------|----------------|------------------------|
| 0.01 | 0.01937 | 0.01000 ✓ |
| 0.10 | 0.08526 | 0.10000 ✓ |
| 0.30 | 0.20026 | 0.30000 ✓ |
| 0.50 | 0.35632 | 0.50000 ✓ |
| 0.70 | 0.65763 | 0.70000 ✓ |
| 0.90 | 1.77132 | 0.90000 ✓ |
| 0.99 | 5.55190 | 0.99001 ✓ |

**Numerical stability:** The discriminant `−10127y² + 13702y + 9` is positive for
y ∈ (−0.00066, 1.3536), covering the full SDR range [0,1] with margin. The denominator
`502 − 486y` → 0 only at y ≈ 1.0329 (above SDR ceiling); the `max(..., 1e-4)` guard is
sufficient. No singularities in the SDR domain.

---

## Findings

### [Shadertoy — "Inverse Aces Tonemap Operator" (wlfyWr, 2020)]
- **R86 sub-problem:** inverse derivation
- **Approach:** analytical — quadratic formula applied to the rational equation
- **GPU feasibility:** yes — per-pixel, single-pass, ≈6 VALU ops per channel (sqrt +
  multiply-add). Negligible cost against the MegaPass ALU budget.
- **Error bounds:** machine-precision round-trip (float32 error < 1e-5 over [0,1]).
  Perfect for a known-operator inverse; no lossy approximation.
- **Novelty gap:** community shader, not a formal paper. However, the derivation is
  mathematically exact — the exact same quadratic that academic work would produce.
  Directly adaptable to HLSL without modification.
- **Directly usable:** yes — HLSL syntax is near-identical to GLSL for this expression.
  The `InverseACESHill()` sketch above is a direct HLSL port.
- **Search that found it:** `ACM SIGGRAPH "analytical ACES inversion" OR "inverse ACES" closed-form display shader 2023 2024`

### [Shadertoy — "inverse ACES tonemapping" (NtXyD8)]
- **R86 sub-problem:** inverse derivation
- **Approach:** analytical — alternative form of the same quadratic inverse
- **GPU feasibility:** yes — same instruction profile as wlfyWr
- **Error bounds:** equivalent to wlfyWr (machine precision)
- **Novelty gap:** same as wlfyWr — community implementation, not peer-reviewed
- **Directly usable:** yes (corroborates wlfyWr; confirms the formula is stable and
  independently reproducible)
- **Search that found it:** `ACES Hill 2016 "2.51" "2.43" inverse quadratic formula HLSL shader implementation`

### [AMD GPUOpen — Optimized Reversible Tonemapper for Resolve]
- **R86 sub-problem:** inverse derivation (different operator, not ACES-specific)
- **Approach:** analytical — max-channel tonemapper with exact closed-form inverse:
  `Tonemap(c) = c / (max3(c) + 1)`, `Invert(c) = c / (1 − max3(c))`
- **GPU feasibility:** yes — 4 VALU ops per tap, used by AMD in production TAA/MSAA resolve
- **Error bounds:** exact (floating-point round-trip)
- **Novelty gap:** production technique. Not ACES-specific — AMD's operator is designed
  for temporal blending stability, not for undoing a game's baked ACES output. However,
  the architectural principle is the same: a per-pixel closed-form inverse applied
  within a single full-screen pass.
- **Directly usable:** not as the R86 inverse (wrong operator). Useful as a reference for
  the reversible-tonemapper-within-TAA design pattern. Could be applied inside corrective.fx
  before temporal averaging of ZoneHistoryTex to reduce flicker.
- **Search that found it:** `AMD GPUOpen "optimized reversible tonemapper" HLSL inverse closed-form`

### [AIM 2025 Challenge on Inverse Tone Mapping — arXiv:2508.13479]
- **R86 sub-problem:** inverse derivation — state-of-the-art benchmark
- **Approach:** neural — 69 teams, best result (ToneMapper / NAFNet) at PU21-PSNR 34.49 dB
- **GPU feasibility:** no — multi-scale CNN inference; incompatible with real-time
  single-pass constraints
- **Error bounds:** 34.49 dB PU21-PSNR is the neural ceiling. For a known operator (ACES
  Hill), the analytical inverse achieves near-infinite PSNR (machine precision); neural
  methods are inferior to the analytical approach when the operator is known.
- **Novelty gap:** offline / post-process. Establishes the quality bar for generic (unknown
  operator) ITM — R86's analytical inverse should dominate this on ACES-specific input.
- **Directly usable:** no. The paper is a benchmark result, not an implementable algorithm.
  Its value is confirming that no simple analytical method exists for the unknown-operator
  case, validating R86's fingerprinting-first approach.
- **Search that found it:** `"inverse tone mapping" "ACES" analytical closed-form 2022 2023 2024 2025`

### [Semantic Aware Diffusion Inverse Tone Mapping — arXiv:2405.15468, May 2024]
- **R86 sub-problem:** inverse derivation — highlight hallucination in clipped regions
- **Approach:** neural — diffusion-based inpainting for saturated regions
- **GPU feasibility:** no — multi-step diffusion
- **Error bounds:** not stated; subjectively better than regression baselines in clipped regions
- **Novelty gap:** offline. Relevant only if R86 later needs to hallucinate detail in
  specular highlights that ACES clips. ACES compresses but rarely fully clips mid-exposed
  SDR frames, so this is low-priority for Arc Raiders.
- **Directly usable:** no
- **Search that found it:** `site:arxiv.org "inverse tone mapping" 2024 2025 analytical perceptual`

### [Invertible Tone Mapping with Selectable Styles — arXiv:2110.04491]
- **R86 sub-problem:** inverse derivation — designing invertible TMOs from the ground up
- **Approach:** neural — a CNN that learns invertible HDR→LDR+residual representation
- **GPU feasibility:** no — neural inference
- **Error bounds:** exact round-trip by construction (residual stores missing information)
- **Novelty gap:** targets future games/engines that would bake invertibility into their
  TMO. Irrelevant for Arc Raiders which already has a fixed, non-invertible-by-design ACES.
- **Directly usable:** no. Conceptual relevance only: confirms the community's recognition
  that standard TMOs (including ACES Hill) are not analytically invertible in the highlight
  region without information loss.
- **Search that found it:** `arxiv "inverse tone mapping" operator unknown parameter estimation real-time 2023 2024`

### [Fast and Flexible Stack-Based Inverse Tone Mapping — CAAI 2023]
- **R86 sub-problem:** inverse derivation — multi-exposure stack generation from single LDR
- **Approach:** statistical / neural hybrid — exposure decision model + CNN
- **GPU feasibility:** no — requires multi-exposure synthesis and CNN inference
- **Error bounds:** not stated for the single-LDR case
- **Novelty gap:** addresses the case where the TMO is unknown and the inverse is
  underdetermined. Not applicable when the Hill ACES operator is confirmed by fingerprinting.
- **Directly usable:** no
- **Search that found it:** `arxiv "inverse tone mapping" operator unknown parameter estimation real-time 2023 2024`

---

## Prototype sketch

### Derivation of InverseACESHill

**Forward operator (Hill 2016):**
```
f(x) = (2.51x² + 0.03x) / (2.43x² + 0.59x + 0.14)
```

**Rearrangement for given display-referred output y:**
```
y(2.43x² + 0.59x + 0.14) = 2.51x² + 0.03x
(2.43y − 2.51)x² + (0.59y − 0.03)x + 0.14y = 0
```
Multiply through by −1 to make leading coefficient positive for y ∈ [0,1]:
```
(2.51 − 2.43y)x² − (0.59y − 0.03)x − 0.14y = 0
```
where `a = 2.51 − 2.43y > 0` for y < 1.0329, `c = −0.14y < 0` for y > 0.

Since `a > 0` and `c < 0`, the product of roots `c/a < 0`, so exactly one root is
positive (the scene-linear signal) and one is negative (extraneous). Taking the
positive root via the quadratic formula:

```
discriminant D = (0.03 − 0.59y)² + 4(2.51 − 2.43y)(0.14y)
               = (0.59y − 0.03)² + 0.56y(2.51 − 2.43y)
```

Expanding and collecting by powers of y:
```
D = 3481y² − 354y + 9 + 14056y − 13608y²
  = −10127y² + 13702y + 9
```

Positive root:
```
x = [(0.59y − 0.03) + sqrt(D)] / [2(2.51 − 2.43y)]
  = [59y − 3 + sqrt(−10127y² + 13702y + 9)] / (502 − 486y)
```

**HLSL (per-channel, vectorised):**
```hlsl
float3 InverseACESHill(float3 y) {
    float3 D = sqrt(max(-10127.0 * y * y + 13702.0 * y + 9.0, 0.0));
    return (D + 59.0 * y - 3.0) / max(502.0 - 486.0 * y, 1e-4);
}
```

### Integration into ColorTransformPS (Stage 0)

The inverse **must** be an intra-pass computation inside ColorTransformPS, not a separate
effect. Reason: the output is scene-linear with values up to ~7.24 for y near 1.0; the
inter-effect BackBuffer is 8-bit UNORM and clips at 1.0 silently (CLAUDE.md "Silent-failure
gotchas"). Writing the intermediate to BackBuffer would destroy the reconstruction.

Proposed Stage 0 insertion (before the existing CORRECTIVE block):

```hlsl
// ── Stage 0 (R86) — Analytical ACES inverse (gated by fingerprint confidence) ──
float4 perc = tex2Dlod(PercSamp, float4(0.5, 0.5, 0, 0));
float p25 = perc.r, p50 = perc.g, p75 = perc.b;
float shoulder_ratio = p75 / max(p50, 0.001);
float toe_ratio      = p25 / max(p50, 0.001);
float aces_conf = saturate(smoothstep(1.20, 1.30, shoulder_ratio))
                * saturate(smoothstep(0.35, 0.42, toe_ratio))
                * (1.0 - step(0.95, p75));   // reject near-clipped frames
float3 scene_linear = InverseACESHill(col.rgb);
col.rgb = lerp(col.rgb, scene_linear, aces_conf * R86_STRENGTH);
// col.rgb is now scene-linear in [0, ~7.24] when aces_conf=1 and R86_STRENGTH=1
// Subsequent CORRECTIVE (EXPOSURE + FilmCurve) maps it back to [0,1]
```

`R86_STRENGTH` is the creative_values.fx knob (range [0,1]); `aces_conf` comes from
the Run 01 fingerprinting logic (R57). The blend ensures a smooth fallback to identity
when the scene does not resemble ACES output — satisfying the game-agnostic constraint.

### Open question: per-channel vs. luminance-only inverse

Applying InverseACESHill per-channel (as sketched above) is mathematically correct only
if ACES was applied per-channel to scene-linear RGB. For the Hill approximation this is
the standard usage; however, some UE5 variants apply the RRT in ACEScg space (a wide-gamut
linear transform before the curve). If the pre-ACES transform is non-trivial, per-channel
inversion introduces hue errors of its own. The safe approach:

1. Per-channel inverse (this run's sketch) — correct for direct Hill application.
2. Luminance-only inverse — applies InverseACESHill only to the Oklab L component and
   scales C proportionally, preserving hue. Less accurate radiometrically but safer
   against hue distortion from per-channel application of a non-linear curve.

The R57 fingerprinting confidence score already partially addresses this: if the toe/shoulder
ratios show per-channel distortion (different ratios on R vs. G vs. B channels of a known
neutral grey patch), the per-channel inverse is inappropriate. Without a known neutral in
the frame this is not diagnosable from PercTex alone — that is angle 1's problem.

---

## Implementation gaps remaining

1. **Calibration of `aces_conf` smoothstep bounds.** The shoulder_ratio and toe_ratio
   thresholds in Stage 0 above are derived analytically from the Hill function, not
   calibrated on live Arc Raiders frames. A calibration session with ACES confirmed
   (HDR OFF, known bright outdoor scene) is needed to tighten the smoothstep edges.

2. **Per-channel vs. luminance-only inverse decision.** If Arc Raiders applies ACES in
   ACEScg space (with a preceding matrix transform), per-channel inversion introduces
   hue errors. Angle 1 must characterise the hue distortion of the Hill approximation
   in Oklab to determine which inverse mode is correct.

3. **creative_values.fx knob not yet added.** `R86_STRENGTH` is referenced in the
   prototype but not yet defined in `creative_values.fx`. Adding it before any code
   integration is required (CLAUDE.md: `creative_values.fx` is the only tuning surface).

4. **Stage 0 interaction with FilmCurve anchor.** The existing CORRECTIVE stage applies
   `pow(rgb, EXPOSURE)` then FilmCurve using PercTex p25/p50/p75. If Stage 0 has already
   applied the inverse, the scene-linear signal now has a different percentile structure
   than what PercTex was computed from (PercTex sees post-ACES values). The FilmCurve
   anchor will be incorrect. Resolution: PercTex must either be recomputed after Stage 0,
   or Stage 0 must apply its own percentile correction. This is the primary integration
   risk.

5. **Hue distortion characterisation absent (angle 1).** Even a perfect radiometric
   inverse leaves ACES hue distortions (red→orange push, cyan→blue pull) uncorrected.
   These are sub-degree errors in Oklab hue but are perceptible in skin tones and sky.
   The Stage 0 inverse alone will not be perceptually neutral without a subsequent
   hue correction pass (angle 1's output).

6. **GZW pass-through not yet verified.** The `aces_conf` guard should produce 0 on
   Grey Zone Warfare (a different pipeline). This must be tested before any R86 code
   reaches the main chain.

---

## Searches run

1. `"inverse tone mapping" "ACES" analytical closed-form 2022 2023 2024 2025`
2. `"SDR to HDR" "tone curve inversion" real-time display 2024 2025`
3. `"inverse tone mapping operator" rational function approximation GPU shader`
4. `"HDR reconstruction" "single exposure" analytical inverse ACES rational function 2024`
5. `site:arxiv.org "tone mapping inversion" perceptual quality evaluation 2024 2025`
6. `AMD GPUOpen "optimized reversible tonemapper" HLSL inverse closed-form`
7. `ACES Hill 2016 "2.51" "2.43" inverse quadratic formula HLSL shader implementation`
8. `site:arxiv.org "inverse tone mapping" 2024 2025 analytical perceptual`
9. `ACM SIGGRAPH "analytical ACES inversion" OR "inverse ACES" closed-form display shader 2023 2024`
10. `Shadertoy "inverse ACES" tonemapping quadratic closed-form wlfyWr NtXyD8`
11. `arxiv "inverse tone mapping" operator unknown parameter estimation real-time 2023 2024`
12. `"inverse aces" "quadratic" "2.51" "0.59" "0.14" GLSL HLSL formula shader`
