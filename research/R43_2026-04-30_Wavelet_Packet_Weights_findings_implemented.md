# R43 — Energy-Normalised Wavelet Packet Weights — Findings
**Date:** 2026-04-30
**Searches:**
1. Coifman & Wickerhauser 1992 wavelet packet best-basis energy criterion convergence
2. Energy-normalized wavelet adaptive subband weights image enhancement sharpening 2020–2024
3. Wavelet best-basis squared coefficients energy criterion additive cost function
4. Per-pixel adaptive multi-scale detail weight energy normalization image clarity stability
5. Wavelet subband energy normalization degenerate flat region numerical stability epsilon
6. AMD FidelityFX CAS contrast adaptive sharpening per-pixel local contrast weight algorithm

---

## Key Findings

### 1. Coifman & Wickerhauser — Best-Basis Foundation

The 1992 paper "Entropy-Based Algorithms for Best Basis Selection" (IEEE Trans. Information
Theory, Vol. 38 No. 2, pp. 713–718) establishes the canonical best-basis search over wavelet
packet trees. The core requirement is that the cost function C be **additive**: for any two
disjoint subbases A1, A2 the condition C(A1 ∪ A2) = C(A1) + C(A2) must hold. This
additivity allows a fast bottom-up tree search (O(N log N)).

The criterion used in the original paper is **Shannon entropy** of the normalised squared
coefficients — that is, the energy fraction pₖ = dₖ²/Σdᵢ² — because it is additive and
because it measures sparsity/concentration of the energy distribution. The squared
coefficient (energy) is the correct atomic quantity; abs(d) would break the orthonormal
energy interpretation and is not used in any standard best-basis formulation.

**Convergence/stability proofs:** The best-basis algorithm is proven to converge to a
global minimum of the additive cost over the full wavelet packet tree in O(N log N) time
(Wickerhauser 1992, also formalised in "The Solution of a Problem of Coifman, Meyer, and
Wickerhauser on Wavelet Packets," Constructive Approximation, Springer, 2010). These proofs
are tree-level (whole-signal) rather than per-pixel, which is the adaptation R43 makes.

**Implication for R43:** The per-pixel application in R43 is a local analogue of
best-basis selection, not a direct application. Rather than selecting a single winner
band (hard best-basis), R43 uses the energy fractions as soft continuous weights. This is
a well-motivated relaxation: soft weighting by energy fraction has stronger signal-dependent
grading than hard selection and avoids discontinuities at band-switching boundaries.

### 2. Energy Fraction as Weight — Prior Art

- **Subband image enhancement with adaptive weights (ScienceDirect, 2011):** Infrared
  sea-surface images — wavelet coefficients clustered; weights per cluster assigned by
  energy content. The approach of deriving per-region (or per-pixel) weights from subband
  energy concentration is explicitly applied in image sharpening contexts.
- **WavEnhancer (JCST 2024):** Unifies wavelet and transformer for image enhancement;
  separates frequency bands and processes them with content-dependent weights — energy
  magnitude drives which band receives more gain.
- **DiffLL (arXiv 2024, low-light enhancement):** Applies wavelet-based decomposition in
  multi-scale space; different frequency bands processed separately with signal-level
  weights. Explicitly noted to provide "better control over detail sharpening."
- **Subband Adaptive Enhancement IEEE 2021:** Discrete wavelet transform with per-subband
  adaptive gain derived from SNR/energy content; orthogonality of DWT ensures per-band
  gains do not leak across bands.
- **Multi-scale Retinex / WGIF (Frontiers 2022):** Adaptive regularisation weight
  derived from local signal content to avoid halo at edges — conceptually similar:
  signal energy drives a per-pixel continuous weight.

None of these apply the exact formulation dᵢ²/Σdⱼ² as a continuous per-pixel mixing
weight inside a single clarity pass, but all validate the pattern of energy-derived
adaptive subband weighting in enhancement pipelines.

### 3. Squared Coefficients vs. Abs(d) — Correct Metric

The literature is unambiguous. The Coifman–Wickerhauser framework defines energy as the
squared L2 norm of coefficients. All standard additive cost functions (Shannon entropy,
log-energy entropy, ℓ¹ norm, Stein) use dₖ² as the energy atom. The signal-processing
DSP.SE canonical answer on "energy normalization across wavelet subbands" confirms that
1/√s scaling for the CWT, or equivalently dᵢ², is the quantity that measures true band
energy in an L2 sense.

Using abs(d) instead of d² would give an L1 measure of activity — valid as a sparsity
proxy but not the energy fraction that underpins Coifman–Wickerhauser's proofs. For
R43's goal (soft energy-proportional blending), d² is the correct and theoretically
grounded choice.

### 4. Real-Time / GPU Prior Art

AMD FidelityFX Contrast Adaptive Sharpening (Lottes, 2019) is the most relevant GPU
prior art. CAS computes a per-pixel sharpening weight from local contrast (min/max
neighbourhood luma), inversely proportional to contrast level — already sharp areas
receive less sharpening. The principle is identical to R43's intent: signal content
locally modulates the sharpening weight. CAS operates in spatial domain (single scale);
R43 extends the same logic to three frequency bands via energy fractions.

No published GPU shader was found that applies the wavelet packet energy-fraction formula
explicitly, but the pattern of per-pixel, content-adaptive, multi-scale weighting is
well-established in real-time post-processing (CAS, RCAS, adaptive-sharpen by bacondither).

### 5. Stability Under Degenerate Inputs

**Uniform / flat regions:** All Dᵢ ≈ 0. The `max(e_sum, 1e-6)` guard fires; weights
become e1/1e-6 : e2/1e-6 : e3/1e-6, which are all numerically tiny. The weighted sum
detail_wp = D1·(e1/e_sum) + … ≈ 0 because all Dᵢ ≈ 0, regardless of the weight
values. The guard makes the division safe but the product Dᵢ·(eᵢ/e_sum) vanishes anyway.
This is safe.

**All-energy-in-one-band (sharp edge):** e1 >> e2, e3 → weights → (≈1, ≈0, ≈0) →
detail_wp ≈ D1. This is the most common and well-behaved case.

**Can every pixel simultaneously have all energy in D1?** Yes — a globally fine-textured
image (film grain, noise floor) will have D1 dominant everywhere. The result is that
detail_wp ≈ D1 everywhere, which is identical to the current behaviour with weight 0.50
(except the weight is now 1.0, increasing clarity gain). This is a real difference from
the fixed-weight version and must be considered when setting CLARITY_STRENGTH. A globally
noisy frame will see stronger clarity than the current code. The mitigating factor is that
CLARITY_STRENGTH is an exposed tuning knob in creative_values.fx, so re-calibration
is a single parameter adjustment.

**Mixed-sign scenario:** If D1 > 0 and D2 < 0 (pixel brighter than fine base, darker
than mid base — possible at some gradient inflection points), the energy fractions are
still positive (d²), so the weights are positive. The weighted sum can partially cancel:
detail_wp = D1·w1 + D2·w2 where w1,w2 > 0 and signs differ. This is correct signal
behaviour — the bands genuinely have opposite polarity and partial cancellation is the
right outcome. No sign-flip or instability arises.

---

## Literature Support Summary

| Claim | Support |
|---|---|
| Energy fraction (d²/Σd²) is the correct basis for subband weighting | Strong — Coifman & Wickerhauser 1992, IEEE Trans. Info. Theory; all standard wavelet best-basis literature |
| Squared coefficient is correct over abs(d) | Strong — universal in L2-normed wavelet literature; DSP.SE energy normalisation references |
| Soft continuous energy-weight blending (vs hard best-basis selection) | Moderate — no direct citation of this exact formulation; well-motivated relaxation of C&W hard selection |
| Per-pixel adaptive subband weighting for image sharpening | Good — ScienceDirect 2011, WavEnhancer 2024, DiffLL 2024, IEEE subband adaptive 2021 |
| Real-time GPU per-pixel adaptive sharpening weight | Strong — FidelityFX CAS (same conceptual pattern, single-scale spatial) |
| Numerical safety of epsilon guard at flat regions | Strong — standard technique; independently verifiable by algebra |

---

## Parameter Validation

**Sign preservation:** Confirmed. The weights eᵢ/e_sum are always strictly positive
(all terms squared). detail_wp is a positive-weight linear combination of the Dᵢ values.
The sign of detail_wp is therefore determined by the dominant signed band value, which
is the correct physical meaning.

**Range:** detail_wp is bounded by [min(D1,D2,D3), max(D1,D2,D3)] because the weights
form a convex combination (all positive, summing to 1.0). In the fixed-weight version
the weights also sum to 1.0 (0.50+0.30+0.20), so the range bound is identical. No
new clipping risk is introduced.

**Numerical safety:** At e_sum → 0 (flat pixel), the max() clamp to 1e-6 prevents
divide-by-zero. The subsequent product Dᵢ·(eᵢ/1e-6) is also ≈ 0 because Dᵢ ≈ 0.
The clamp value of 1e-6 is appropriate for luma residuals expressed in [0,1] linear
light — the smallest meaningful luma difference is well above 1e-3.

**Interaction with bell/gain function:** The existing bell function takes detail_wp as
input. Because the range is identical to the fixed-weight version (convex combination
of the same Dᵢ), the bell function sees the same input domain and its output is
unchanged in character. No re-tuning of the bell parameters is required unless the
user finds clarity too strong on noise-heavy frames (all-D1 case above).

**Interaction with chroma co-boost (line 326):** The chroma co-boost also consumes
`detail` unchanged. Same range argument applies — no regression expected.

---

## Risks and Concerns

1. **Calibration shift on globally textured content.** When D1 dominates across the
   whole frame (heavy noise, film grain, foliage), the effective clarity weight on D1
   jumps from 0.50 to ≈1.0. CLARITY_STRENGTH will need a downward nudge (≈ ×0.5) to
   maintain parity on such content. This is a known, controllable risk.

2. **Soft convexity means no true "best-basis" interpretation.** R43's formula does not
   select one optimal band — it blends all three. This is intentional (avoids hard
   discontinuities), but it means that in intermediate cases (D1 ≈ D2 >> D3), the
   effective weight is ≈(0.5, 0.5, 0) rather than strictly picking D1. The result is
   a blended clarity that may be slightly blurrier at fine edges than hard selection
   would be. In practice this is desirable (less ringing).

3. **No formal per-pixel convergence proof.** The C&W proofs apply to tree-level cost
   minimisation over whole signals/frames, not pixel-wise. R43's per-pixel application
   is a reasonable analogy but is not covered by the published convergence guarantees.
   In practice this is irrelevant for a real-time visual effect — each pixel is
   independent and the formula is algebraically deterministic.

4. **ALU cost is modest but real.** Three multiplies (e1,e2,e3), one add, one max,
   three divides (compiles to multiply-by-reciprocal after the single 1/e_sum
   reciprocal). Net delta: +6–7 ALU ops on top of the existing clarity path. Given
   the GPU budget constraint (UE5 saturated), this is acceptable but should be
   confirmed against the vkBasalt timing budget on the target hardware.

---

## Verdict

**Proceed to implementation trial.** The proposal is well-grounded:

- The energy-fraction weighting is the correct mathematical quantity (L2-normed, from
  Coifman–Wickerhauser 1992), not an ad-hoc heuristic.
- Sign, range, and flat-region numerical safety are all analytically confirmed.
- Prior art in image enhancement (2011–2024) validates per-subband energy-adaptive
  weighting for sharpening purposes.
- Real-time GPU precedent (FidelityFX CAS) confirms that per-pixel content-adaptive
  weighting is practical and well-understood.
- The only calibration risk (stronger clarity on globally textured frames) is controlled
  via CLARITY_STRENGTH in creative_values.fx — no architectural change needed.
- Zero new passes, zero new texture taps, ~6 additional ALU ops.

Primary open question before shipping: visual comparison on a noisy/grainy frame to
assess whether CLARITY_STRENGTH needs adjustment, and confirmation that the chroma
co-boost at line 326 does not produce over-saturation on fine-detail pixels where
detail_wp is now ≈ D1 rather than 0.50·D1.
