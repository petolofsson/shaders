# R133 — Munsell Highlight Desaturation: Research Proposal
**Date:** 2026-05-08
**Stage:** Stage 2 (Tonal) — novelty gap at 87%, target ≥90%

---

## Problem statement

The existing R74 implementation in `ColorTransformPS` desaturates highlights via a linear ramp:

```hlsl
float r74_desat = 0.30 * saturate((lab.x - 0.80) / 0.20);
```

This is a gate — hard onset at L=0.80, linear slope, no physical grounding. It violates the
no-gates rule (hard threshold causes visible seam) and is not calibrated to Munsell data.

The Munsell dataset documents a fundamental perceptual constraint: **maximum achievable chroma
decreases as Munsell value approaches 10 (white)**. A perfectly white surface has no chroma
(C=0 by definition). The rolloff starts well below V=10 and varies by hue — yellow tightens
earlier than red. This physical boundary is currently missing as a first-class constraint.

The PLAN.md designates this "a genuinely absent physical term" for Stage 2.

---

## Research goals

1. **Munsell chroma-value envelope** — what is C_max(V, H) across the Munsell solid? Specifically
   the upper arm (V=6–10) where highlights live. Are published Renotation data tables available?

2. **Oklab mapping** — how does Munsell value map to Oklab L? The relationship is close but not
   linear (Oklab L is perceptually uniform via cube-root; Munsell value uses a different
   Lightness formula). What is the mapping with enough precision to calibrate the rolloff onset?

3. **Rolloff curve shape** — is the C_max(V) boundary at a given hue well-approximated by a
   power curve, quadratic, or something else? Is it symmetric around V=5 (full Munsell
   boundary) or does the upper arm have a different exponent?

4. **Hue variation** — how much does the rolloff onset differ by hue? Yellow (tightest ceilings
   in hue_bands.fxh) vs. red/magenta (loosest). Should the L-threshold for rolloff onset be
   hue-dependent, or is a single global curve adequate?

5. **Interaction with HueCeil()** — HueCeil() imposes flat per-hue C ceilings, independent of L.
   The Munsell boundary would add an L-dependent multiplier on top. Are these orthogonal (can
   apply both independently), or does one subsume the other?

6. **HLSL form** — the implementation must be smooth and self-limiting (no gates, no saturate()
   hard floor). What curve form works: power of L, polynomial in L, or a smooth fade using
   `1 - pow(L, n)`? What is the correct gamma `n`?

7. **Existing prior art** — does any published real-time grading tool implement a Munsell-
   calibrated L-dependent chroma ceiling? What formulations exist in color science literature
   (Fairchild, Hunt, Wyszecki & Stiles)?

---

## Hypotheses to validate or refute

- **H1:** The Munsell upper-arm boundary is well-fit by `C_max ∝ (1 − L^n)` in Oklab, with
  n ≈ 2–4. Onset (where the boundary becomes binding) is around L=0.70–0.80.

- **H2:** Hue variation in rolloff onset is small enough (±0.05 in L) that a single global curve
  is adequate; the existing per-hue HueCeil() handles hue specificity.

- **H3:** The current R74 `0.30 * saturate((lab.x - 0.80)/0.20)` underestimates the rolloff
  depth: at L=0.95 the real Munsell boundary already forces C near zero for most hues, but the
  linear ramp only produces ~0.225 desaturation.

- **H4:** Replacing the linear ramp with a smooth power curve will eliminate the L=0.80 seam
  visible on bright, saturated surfaces (sky gradients, neon lights) without changing midtone
  chroma.

---

## Constraints

- No gates: implementation must be a smooth curve, zero hard thresholds.
- SDR by construction: rolloff must reach C=0 at L=1.0 (pure white has no chroma).
- GPU budget: single multiply or MAD per pixel; no new textures or passes.
- Interaction: must not double-desaturate with the existing 0.45 arm in R22 or with HueCeil().
- Knob: `MUNSELL_STRENGTH` (0–1 range, default 1.0) in creative_values.fx — replaces or
  augments the existing r74_desat term.

---

## Deliverable

A `_findings.md` companion covering:
- Fitted curve coefficients from Munsell Renotation data
- HLSL snippet (gate-free, SDR-safe)
- Comparison of old linear ramp vs. new curve at L = 0.80, 0.90, 0.95, 1.00
- Verdict on hue-dependence and HueCeil interaction
- Stage 2 novelty score update estimate
