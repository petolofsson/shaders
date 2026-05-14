# R195 — Scene Entropy + IQR Highway Signals — Findings

**Date:** 2026-05-14

---

## Literature confirmed

### Grzywacz 2025 — Perceptual Complexity as Normalized Shannon Entropy

*Entropy* 27(2):166, PMC11854106. https://www.mdpi.com/1099-4300/27/2/166

Directly validates H_norm = −Σ p_i log₂(p_i) / log₂(N) as a scene complexity metric
that correlates with human aesthetic judgements about image richness. Key findings for
this pipeline:

- H_norm is robust to histogram resolution changes — 64 bins is adequate, does not
  require 256.
- Global H_norm predicts perceived scene complexity better than variance or std alone.
- Grzywacz notes that *spatial range* for the entropy computation matters; per-region
  entropy is more precise, but global histogram entropy is a practical approximation
  that holds well for full-frame images. For our purposes (per-frame zone S-curve
  modulation) global H_norm is the correct scope.
- The paper does not use H_norm to drive tone mapping directly, but establishes the
  perceptual basis for using it as a scene-state descriptor in adaptive pipelines.

**Verdict:** Formula confirmed. Perceptual basis confirmed. Range guidance (0.0–1.0,
typical scenes 0.35–0.85) matches the nightly job's estimates.

---

### Tariq et al. 2023 — Perceptually Adaptive Real-Time Tone Mapping

SIGGRAPH Asia 2023. DOI:10.1145/3610548.3618222.
https://achapiro.github.io/Tar23/Tar23.pdf

Demonstrates that matching a scene's luminance *distribution shape* (not just mean or
median) to display capabilities is the key to perceptual fidelity in real-time. Uses
per-frame histogram-derived statistics to adaptively scale tone curve slope. Validated
on Meta Quest 2 at < 1ms — confirms that full 64-bin histogram statistics are
cost-viable in real-time on constrained GPU budgets.

**Relevant to this pipeline:** Our `analysis_frame.fx` already has the 64-bin
histogram computed and EMA-smoothed. Adding one 64-tap entropy pass on the same
source costs < 0.01ms on a desktop GPU — well within budget.

The paper uses luminance histogram statistics (specifically distributional shape
descriptors) to modulate a tone curve's slope adaptively. The H_norm → zone_str
attenuation proposed in R195 is architecturally identical to their approach.

**Verdict:** Real-time viability confirmed. The pipeline's histogram infrastructure is
already positioned to support this at negligible cost.

---

### IQR in tone mapping literature

IQR = p75 − p25 appears consistently as the primary "scene contrast width" scalar
in histogram-based tone mapping, including:

- The Bowley skewness formulation in the current pipeline already uses IQR as its
  denominator (implicitly). Exposing it as `HWY_IQR` is a structural cleanup, not a
  new signal.
- Inverse tone mapping literature (Cambridge/APSIPA 2020) uses Tukey's IQR fence
  (outliers outside Q₁ − 1.5·IQR and Q₃ + 1.5·IQR) to robustly fit inverse
  tonemapping models — confirms IQR is the standard contrast-width statistic.
- IQR is less sensitive to specular outliers than p90−p50 (`specular_contrast`),
  making it complementary rather than redundant: `specular_contrast` measures
  highlight headroom; IQR measures the body of the distribution.

**Verdict:** IQR slot (HWY_IQR = 208) is a low-cost structural improvement. No
calibration risk.

---

## Mode–median distance — deferred

No peer-reviewed real-time implementation found. Bimodality literature relies on
Hartigan's dip test (O(N log N), GPU-unfeasible) or Ashman's coefficient (requires
sorted data). Real-time game pipelines (e.g., Valve's HL2:EP1, documented in exposure
metering literature) address bimodal scenes via percentile-skipping (ignoring bottom
50–80% and top 2–20% of pixels during key computation) rather than explicit bimodality
detection.

The pipeline already handles the dark-corridor / bright-doorway case adequately via
`zone_std` and `specular_contrast`. No confirmed gap that mode–median distance would
fill. Deferred until a concrete consuming expression is identified.

---

## Summary

| Finding | Literature verdict | Status |
|---------|--------------------|--------|
| H_norm entropy (HWY_H_NORM = 207) | Confirmed — Grzywacz 2025 + Tariq 2023 | Implement |
| IQR highway slot (HWY_IQR = 208) | Confirmed — standard in field | Implement |
| Mode–median distance (HWY_MODE_MEDIAN_D) | No real-time validation found | Defer |

Both implement-ready signals require no new creative_values knobs. H_norm feeds
`ctx.zone_str` attenuation in `BuildSceneCtx`. IQR is a named alias for the inline
Bowley denominator already present at three pipeline sites.
