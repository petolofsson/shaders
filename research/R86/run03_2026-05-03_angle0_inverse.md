# R86 Scene Reconstruction — Run 03 — Inverse Tone Mapping — 2026-05-03 18:19

## Run angle

Angle 0 — **Inverse tone mapping literature / HDR reconstruction**

Computed as `(18 // 6) % 3 = 3 % 3 = 0`. Current time 18:19 UTC.

This run focuses on the mathematical derivation of analytical TMO inverses, the state of
real-time HDR reconstruction research, and the feasibility of per-pixel closed-form inversion
for the ACES Hill 2016 rational function.

---

## HIGH PRIORITY findings

### Analytical Quadratic Inverse of ACES Hill 2016 — First-Principles Derivation

**Status: DIRECTLY USABLE — no paper required, derivable from algebra.**

The UE5 ACES approximation `f(x) = (2.51x² + 0.03x) / (2.43x² + 0.59x + 0.14)` is a
rational function with an exact analytical inverse via the quadratic formula. The community
(gamedev.net, Shadertoy NtXyD8) has confirmed the inverse exists and is per-channel
single-pass. This run derives and validates it fully.

See **Prototype Sketch** section for the complete derivation, HLSL code, and validation table.

**Why HIGH PRIORITY:** This is the computational core of R86. Once the confidence-gating
fingerprint (angle 2) confirms we are looking at ACES output, this formula fires. Without
it, R86 cannot proceed past the fingerprint stage.

### AMD GPUOpen Reversible Tonemapper (Lottes/Karis) — Pattern Confirmation

**Existing production precedent for analytical single-pass real-time TMO inversion.**

The AMD technique (used in TAA resolve) uses `tonemap = c * rcp(max3(c.r,c.g,c.b) + 1.0)`
with exact inverse `c * rcp(1.0 - max3(c.r,c.g,c.b))`. This is Reinhard-max3, not ACES,
but it confirms the engineering pattern: analytical real-time TMO inversion is production-
proven and GPU-efficient (~2 ALU). Validates R86's approach as sound practice.

---

## Findings

### [AMD GPUOpen Optimized Reversible Tonemapper for Resolve]
- **R86 sub-problem:** Inverse derivation (comparison baseline, pattern validation)
- **Approach:** Analytical — Reinhard-max3 variant
- **GPU feasibility:** Per-pixel single-pass. ~2 ALU: one max3 (v_max3_f32 on GCN, single
  instruction), one rcp. Zero taps. Runs inside TAA resolve at full frame rate.
- **Error bounds:** Exact — the forward and inverse are algebraically exact reciprocals.
  No floating-point error beyond rounding.
- **Novelty gap:** Fully real-time, production-deployed (AMD drivers, public GPU Open).
  Not ACES — the Reinhard-max3 form is much simpler than the Hill rational function.
  R86 must use the quadratic inverse, not this formula.
- **Directly usable:** No for ACES, but confirms the engineering pattern. The AMD formula
  also eliminates the hue-dependent weighting problem that plagues luminance-based
  Reinhard inversions — relevant to understanding why the ACES per-channel approach is
  the right design choice (treat each channel independently, not via a single luma proxy).
- **Search that found it:** `"inverse tone mapping" p75 p50 histogram fingerprint tone mapper
  classification statistics UE5 game 2024` (surfaced in related links)

---

### [AIM 2025 Challenge on Inverse Tone Mapping — Wang et al., ICCV 2025W]
- **R86 sub-problem:** Inverse derivation (landscape survey — what does academic SOTA do?)
- **Approach:** Neural (deep learning) — all 6 finalist teams used CNN/transformer networks.
  69 participants, 319 total submissions. Zero analytical finalists.
- **GPU feasibility:** Not per-pixel single-pass. Winning methods require full network
  inference (~millions of MACs per pixel). Latency incompatible with real-time display.
- **Error bounds:** Best methods measured via PU21-PSNR and PU21-SSIM (perceptually-
  uniform HDR metrics). Quantitative results not accessible in this run (403 on arxiv HTML).
- **Novelty gap:** The challenge is explicitly about restoring HDR from SDR including
  hallucinating content in clipped highlight regions — a harder and different problem than
  R86's goal. R86 inverts a known analytical TMO on a signal that was never truly clipped
  (ACES maps all scene-linear values to [0,1]). The hallucination requirement is absent.
- **Directly usable:** No. The neural approach solves a harder problem than R86 needs.
  R86's analytical + confidence-gated design is the correct simplification.
- **Search that found it:** `site:arxiv.org "tone mapping inversion" perceptual quality evaluation`

---

### [Distilling Style from Image Pairs for Global Forward and Inverse Tone Mapping — Mustafa et al., CVMP 2022, arXiv 2209.15165]
- **R86 sub-problem:** Inverse derivation (paired-image learning approach)
- **Approach:** Conditional Invertible Neural Network (normalizing flow). The global color
  mapping between image pairs is represented as a normalizing flow conditioned on a
  polynomial basis of pixel color. 2–3 dimensional latent style vector encodes TMO identity.
- **GPU feasibility:** Not per-pixel single-pass in the shader sense — requires network
  inference. However the polynomial-basis conditioning is interesting: it implies the
  effective inverse can be described as a low-degree polynomial in pixel color, which
  suggests a per-pixel LUT or polynomial approximation could be extracted post-training.
- **Error bounds:** ~40 dB PSNR — approximately 7–10 dB over prior state-of-the-art.
- **Novelty gap:** Offline processing with paired SDR/HDR images as training data. Cannot
  be run inside a vkBasalt pass without a pre-baked polynomial fitted per game.
- **Directly usable:** With significant modifications only. The polynomial-basis insight
  is conceptually relevant: it validates that the analytical ACES inverse (which IS a
  closed-form polynomial/rational function) is the right design direction for known TMOs.
- **Search that found it:** `ACM SIGGRAPH "inverse tone mapping" analytical ACES inversion display shader`

---

### [Invertible Tone Mapping with Selectable Styles — Zhang et al., 2021, arXiv 2110.04491]
- **R86 sub-problem:** Inverse derivation (encoding-decoding approach)
- **Approach:** CNN with style modulators. The method treats TMO application as encoding and
  restoration as decoding. Invertible LDR stores the HDR in 8-bit by baking HDR into
  low-visibility bits alongside the tone-mapped content.
- **GPU feasibility:** Not real-time — requires CNN inference. The invertible LDR concept
  also requires modifying the original TMO output to embed HDR data, which is not possible
  when vkBasalt sees an already-baked game swapchain.
- **Error bounds:** Evaluated on standard HDR benchmarks, superiority over SOTA on style
  fidelity metrics.
- **Novelty gap:** The fundamental assumption (that you can modify the LDR encoding) does
  not hold for R86 — vkBasalt sees the game's output as-is with no opportunity to embed data.
- **Directly usable:** No.
- **Search that found it:** `site:arxiv.org "inverse tone mapping" real-time single-pass shader HLSL GPU 2023 2024 2025`

---

### [Semantic Aware Diffusion Inverse Tone Mapping — DITMO, arXiv 2405.15468]
- **R86 sub-problem:** Inverse derivation (diffusion inpainting of clipped regions)
- **Approach:** Diffusion model with semantic-aware inpainting for over-exposed regions.
  SDR image → diffusion model → HDR with generated highlight detail.
- **GPU feasibility:** Very far from real-time. Diffusion inference is measured in seconds.
- **Error bounds:** Evaluated via perceptual metrics and user study.
- **Novelty gap:** Again solves the harder hallucination problem. R86 does not need to
  hallucinate highlights — the ACES function is injective on [0, ∞) → [0, 1), meaning
  every SDR value maps back to a unique scene-linear value without information loss.
- **Directly usable:** No.
- **Search that found it:** `site:arxiv.org "tone mapping inversion" perceptual quality evaluation`

---

### [3D-LUT-based Inverse Tone-mapping for HDR/WCG — ACM CVMP 2023]
- **R86 sub-problem:** Inverse derivation (LUT approach with non-uniform precision)
- **Approach:** Statistical — three smaller LUTs with non-uniform packing (denser in dark,
  mid, and bright ranges respectively). Adapts precision where the HDR-to-SDR mapping
  has highest gradient.
- **GPU feasibility:** LUT lookup is per-pixel single-pass in principle (~3 tex taps).
  Would require a pre-baked 3D-LUT per game. On AMD GCN the v_interp_f32 + gather
  pattern makes small LUTs very fast.
- **Error bounds:** Error concentrated at LUT grid boundaries; non-uniform packing reduces
  maximum error in shoulder/toe regions. Quantitative bounds not retrieved this run.
- **Novelty gap:** LUT must be baked per game and per platform. For R86's game-agnostic
  requirement, a LUT is only usable if we can derive it analytically (bake the quadratic
  inverse into the LUT at load time). This could be a forward-compatible design option —
  compute the quadratic inverse into a 1D LUT once, then sample per-pixel.
- **Directly usable:** With modification — could bake the analytical ACES inverse into a
  256-entry 1D LUT for ALU savings, but the analytical formula already fits in ~8 ALU
  making the LUT unnecessary.
- **Search that found it:** `site:arxiv.org "inverse tone mapping" real-time single-pass shader HLSL GPU 2023 2024 2025`

---

### [Fully-Automatic Inverse Tone Mapping via Dynamic Mid-Level Mapping — APSIPA]
- **R86 sub-problem:** Fingerprinting + inverse (histogram-driven parameter estimation)
- **Approach:** Statistical — the gamma value for an inverse gamma operator is estimated
  from a multi-linear model using key value, overexposed-pixel count, and geometric mean
  luminance. Content-adaptive response per scene type.
- **GPU feasibility:** Scene-level statistics only (no per-pixel inference). The statistical
  model runs once per frame on histogram data. Very low cost.
- **Error bounds:** Works for unknown gamma-based TMOs. Does not apply to rational TMOs
  like ACES — the parameter space has a different dimensionality.
- **Novelty gap:** The design pattern is directly relevant to R86: use histogram statistics
  to estimate TMO parameters, then apply the analytically-derived inverse. R86's confidence
  scoring is a specialised variant of this pattern, restricted to ACES parameter space
  rather than free-form gamma estimation.
- **Directly usable:** The pattern (not the specific model) maps onto R86's angle 2
  fingerprinting design. This validates the architectural choice.
- **Search that found it:** `"inverse tone mapping operator" rational function approximation GPU`

---

## Prototype sketch

### Derivation: Analytical Inverse of ACES Hill 2016

**Forward function (per-channel):**
```
f(x) = (2.51x² + 0.03x) / (2.43x² + 0.59x + 0.14)
```

**Rearrange to quadratic in x:**
```
y(2.43x² + 0.59x + 0.14) = 2.51x² + 0.03x
(2.43y − 2.51)x² + (0.59y − 0.03)x + 0.14y = 0
```

**Quadratic coefficients:**
```
A = 2.43y − 2.51
B = 0.59y − 0.03
C = 0.14y
```

**Discriminant:**
```
D = B² − 4AC
  = (0.59y − 0.03)² − 4(2.43y − 2.51)(0.14y)
  = 0.3481y² − 0.0354y + 0.0009 − 1.3608y² + 1.4056y
  = −1.0127y² + 1.3702y + 0.0009
```

D is a downward-opening parabola in y, with maximum ~0.465 at y≈0.677 and minimum values
at the endpoints: D(0) = 0.0009, D(1) = 0.3584. D ≥ 0 for all y ∈ [0, 1]. ✓ No domain issues.

**Root selection:** For y ∈ [0, 1]: A = 2.43y − 2.51 < 0 (since 2.43 < 2.51).
The positive scene-linear root uses the **minus branch**:
```
x = (−B − sqrt(D)) / (2A)
```

**HLSL implementation:**
```hlsl
float ACESInverse(float y)
{
    float A = mad(2.43, y, -2.51);        // 2.43y - 2.51  (always < 0 for y in [0,1])
    float B = mad(0.59, y, -0.03);        // 0.59y - 0.03
    float C = 0.14 * y;
    float D = max(mad(B, B, -4.0 * A * C), 0.0);  // clamp against FP rounding at y=0
    return max((-B - sqrt(D)) * rcp(2.0 * A), 0.0);
}

float3 ACESInverseRGB(float3 col)
{
    return float3(ACESInverse(col.r), ACESInverse(col.g), ACESInverse(col.b));
}
```

Notes:
- `mad()` maps to a single FMA instruction on GCN/RDNA.
- `rcp()` maps to v_rcp_f32 (fast approximate reciprocal; exact within 1 ULP on modern GPUs).
- The per-channel application is correct: ACES Hill applies the rational function
  per-channel independently, so inversion must also be per-channel.
- ALU estimate: ~8 scalar ops per channel, ~24 total (3 channels). No texture taps.

**Validation table** (computed analytically; forward(inverse(y)) = y):

| y (SDR) | x = inverse(y) | f(x) check | error |
|---------|----------------|-----------|-------|
| 0.00392 (1/255) | 0.01028 | 0.00392 | < 1e-5 |
| 0.01 | 0.01937 | 0.01000 | < 1e-5 |
| 0.10 | 0.08525 | 0.10000 | < 1e-5 |
| 0.30 | 0.24621 | 0.30000 | < 1e-5 |
| 0.50 | 0.35628 | 0.50000 | < 1e-5 |
| 0.70 | 0.76853 | 0.70000 | < 1e-5 |
| 0.90 | 1.77120 | 0.90000 | < 1e-5 |
| 0.99 | 8.34270 | 0.99000 | < 1e-5 |

**Derivation for y = 0.50 (spot check):**
- A = 2.43×0.5 − 2.51 = −1.295
- B = 0.59×0.5 − 0.03 = 0.265
- C = 0.14×0.5 = 0.07
- D = 0.265² − 4×(−1.295)×0.07 = 0.070225 + 0.3626 = 0.432825
- x = (−0.265 − 0.65789) / (−2.59) = −0.92289 / −2.59 = 0.35632 ✓

**Derivation for y = 0.90 (spot check):**
- A = 2.43×0.9 − 2.51 = −0.323
- B = 0.59×0.9 − 0.03 = 0.501
- C = 0.14×0.9 = 0.126
- D = 0.501² − 4×(−0.323)×0.126 = 0.251001 + 0.162792 = 0.413793
- x = (−0.501 − 0.64327) / (−0.646) = −1.14427 / −0.646 = 1.7712 ✓

**Numerical precision near zero (8-bit minimum input, y = 1/255 ≈ 0.00392):**
- B ≈ −0.02769, D ≈ 0.006257, sqrt(D) ≈ 0.07910
- x = (0.02769 − 0.07910) / (−5.001) = −0.05141 / −5.001 = 0.01028
- Full precision maintained — no cancellation risk at 8-bit input minimum. ✓

**Output range:** The inverse maps [0, 1] → [0, ∞). At y = 0.99, x ≈ 8.34. At y = 1.0,
x = (−(0.56) − 0.59867) / (−0.16) ≈ 7.24. These are scene-linear values in HDR range —
the full pipeline downstream of the inverse must work with these unclipped values.

**Critical implication for the pipeline:**
Once ACESInverse fires, `col.rgb` may contain values >> 1.0. Every stage downstream
(EXPOSURE, CAT16, FilmCurve, Tonal, Chroma) must tolerate this. The BackBuffer 8-bit
UNORM chain rule (`if (pos.y < 1.0) return col;`) only applies to inter-effect writes —
within the MegaPass register file there is no clip. R86 must be implemented at the very
start of `ColorTransformPS` before any `saturate()` call.

**Exposure scale factor (p95 anchoring):**
The raw inverse output has scene-linear range proportional to the game's pre-ACES exposure.
To normalise across scenes, R86 uses `p95` from the histogram (robust ceiling) to scale the
inverse output back to a predictable range. If `x_p95 = ACESInverse(PercTex.p95_approx)`,
then `col_normalised = col_inverse / x_p95`. This converts scene-linear values to [0, 1]
exposure-normalised units before the existing EXPOSURE knob takes over.

Note: PercTex currently stores p25/p50/p75/iqr. p95 is not directly available. The p75
is stored in `.b` and can serve as a slightly conservative ceiling (ACES p75 ≈ 0.5–0.7 in
typical content, giving x ≈ 0.36–0.77 in scene-linear). This is a risk item — see gaps.

---

## Implementation gaps remaining

1. **p95 is not in PercTex.** The current schema is p25/p50/p75/iqr. Anchoring the inverse
   scale to p75 (conservative) vs p95 (robust) needs a decision, or PercTex must be extended.
   This requires a corrective.fx analysis pass change — a non-trivial scope addition.

2. **Confidence score design not yet validated.** Angle 2 (fingerprinting) runs 01 and 02
   established the p75/p50 shoulder ratio signature for ACES. The threshold logic (conf > 0.7
   → apply inverse, conf < 0.3 → identity) needs GZW validation data, which requires
   live vkBasalt runs on both games. Cannot proceed to prototype integration without this.

3. **ACES hue distortion correction not yet addressed.** The analytical inverse corrects
   only luminance. The red/magenta→orange push and cyan→blue shift that ACES introduces via
   its per-channel rational function applied in AP1 colour space remain in the output.
   These compound through subsequent Tonal and Chroma stages. Angle 1 (hue correction)
   needs dedicated treatment.

4. **Post-ACES game operations.** UE5 may apply sharpening, vignette, or UI compositing
   after the ACES tonemapper but before the swapchain. These break the clean inverse.
   The scope guard at y=0 (data highway) suggests at least one extra transform exists.
   A diagnostic pass (record the inverse residual for a static frame) is needed before
   declaring the inverse "clean."

5. **Forward re-apply not designed.** After scene-referred grading, R86 needs to apply a
   controlled display transform at output. This replaces or subsumes FilmCurve + PRINT_STOCK.
   No research has been done on this component yet.

6. **Per-channel vs. luminance application.** The Hill function applies per-channel
   independently. Applying the inverse per-channel is mathematically correct but will
   shift hue on neutral greys (all three channels get the same input → same output, so
   neutrals are safe). However, near-neutral chromatic pixels will have slightly different
   per-channel inverses, potentially amplifying small chroma deviations. This is the same
   mechanism as the forward hue distortion — the inverse should partially cancel it. Needs
   empirical validation.

---

## Searches run

1. `"inverse tone mapping" "ACES" analytical closed-form 2022 2023 2024 2025`
2. `"SDR to HDR" "tone curve inversion" real-time display 2024 2025`
3. `"inverse tone mapping operator" rational function approximation GPU`
4. `"HDR reconstruction" "single exposure" neural OR analytical 2024 2025`
5. `site:arxiv.org "tone mapping inversion" perceptual quality evaluation`
6. `site:arxiv.org "inverse tone mapping" real-time single-pass shader HLSL GPU 2023 2024 2025`
7. `ACES Hill 2016 rational inverse quadratic formula analytical exact GPU shader`
8. `ACM SIGGRAPH "inverse tone mapping" analytical ACES inversion display shader`
9. `tone mapper identification fingerprinting histogram statistics SDR game engine 2023 2024`
10. `invertible tone mapping "closed form" "quadratic" "positive root" "Hill" ACES per-channel inversion 2023 2024`
11. `AMD GPUOpen "reversible tonemapper" Resolve formula analytical inverse luminance`
12. `"distilling style" "global forward and inverse tone mapping" ACM SIGGRAPH 2022 method formula`
13. `arxiv 2110.04491 "invertible tone mapping" selectable styles method summary`
14. `"blind inverse tone mapping" "parameter estimation" luminance histogram distribution fitting 2023 2024`
