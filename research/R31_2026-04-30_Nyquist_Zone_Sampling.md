# R31 — Nyquist-Shannon Zone Sampling Analysis
**Date:** 2026-04-30
**Type:** Proposal
**ROI:** Low-medium — principled validation or targeted improvement of zone/chroma sampling

---

## Problem

The pipeline has two sampling decisions made by intuition rather than theory:

**Zone grid: 4×4 = 16 zones**
Each zone covers 1/16 of the frame. The zone median is estimated from a full CDF built
from `CreativeLowFreqTex` pixels in that zone (Pass 2, ComputeZoneHistogram). The 16-zone
grid was chosen for perceptual coverage — enough to distinguish sky/ground/mid in most
compositions. No theoretical backing for why 16 is sufficient vs. 9 or 25.

**Chroma sampling: 8 Halton samples per band per frame**
`UpdateHistoryPS` draws 8 Halton-sequence samples per frame per band to estimate per-band
chroma mean and std. The 8-sample count was chosen empirically. No principled answer to:
"how many samples are needed to estimate chroma mean to within ±X at p99?"

---

## Nyquist-Shannon applied to spatial zone sampling

The Nyquist theorem states: to reconstruct a signal up to frequency f, sample at ≥ 2f.

For zone statistics, the "signal" is the spatial variation of scene luminance. If the
scene has lighting changes at a spatial frequency of F cycles/frame (e.g. indoor/outdoor
split = 0.5 cycles/frame), the zone grid needs ≥ 2F zones per axis to capture it without
aliasing.

Most game scenes: dominant spatial frequency is 0.5–1 cycle/frame (one major
light/shadow transition). This requires 1–2 zones per axis → 1×1 to 2×2 grid.
Complex scenes (multiple light sources): up to 2 cycles/frame → 4×4 grid.

**Implication:** the 4×4 grid is at the high end for typical game scenes — it
likely oversamples most scenes and undersamples complex multi-source lighting. The
Retinex replacement (R29) already removes the need for zone-level spatial precision for
illumination correction. The zone grid is now mainly used for the S-curve anchor
(`zone_median`) and global stats (`zone_std`, `zone_log_key`).

---

## Nyquist-Shannon applied to chroma estimation

For estimating a population mean from random samples, the confidence interval is:

```
margin_of_error = z * σ / sqrt(n)
```

Where z=2.576 for p99, σ = population std, n = sample count.

For chroma (C in Oklab), typical σ ≈ 0.05–0.15 per band. Desired accuracy: ±0.01 at p99.

```
n = (z * σ / margin)² = (2.576 * 0.10 / 0.01)² = (25.76)² ≈ 663 samples
```

**8 samples per frame is far below the single-frame accuracy threshold.** However, the
Kalman filter accumulates across frames — after N frames at K≈0.095, the effective
sample count is ~1/(K) ≈ 10 frames × 8 samples = ~80 samples per steady-state estimate.
Still short of 663, but within ~3× for σ=0.10, and the error trades off with the Kalman
smoothing constraint.

**Key finding this analysis would confirm or refute:** is the 8-sample count the binding
limitation on chroma estimate accuracy, or does the Kalman accumulation make it irrelevant?

---

## Proposed research questions for web search

1. What is the minimum number of random samples needed to estimate a 1D median to within
   ε at confidence p, as a function of population variance? (Order statistics literature)
2. In satellite/remote-sensing zone analysis, what spatial resolution (number of zones)
   is used for illumination normalization across a scene?
3. Is quasi-random Halton sampling more or less efficient than stratified random for
   estimating Oklab chroma statistics — is there a theoretical sample-count advantage?

---

## Potential outcomes

**Scenario A — 16 zones is fine, 8 samples is the bottleneck:**
Increase chroma samples from 8→16 or 8→32 per frame. Cost: proportional increase in
UpdateHistoryPS work (currently the cheapest pass in the chain). Accuracy doubles/quadruples.

**Scenario B — 16 zones is over-specified, 8 samples is fine:**
The zone grid could be reduced to 2×2 or 3×3 without visual impact. Saves memory and
reduces grade.fx zone reads (currently 16 taps).

**Scenario C — both are fine, Kalman accumulation covers the gap:**
No change needed. Principled confirmation the current design is sound.

---

## Success criteria

- Clear theoretical answer to: "how many zone samples and chroma samples do we need?"
- Either a concrete code change (more samples, fewer zones) or a written confirmation
  that current values are theoretically justified
- No new passes, no new textures
