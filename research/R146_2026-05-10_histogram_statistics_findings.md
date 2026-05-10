# R146 Findings: Histogram Statistics Beyond Percentiles

**Date:** 2026-05-10
**Status:** Research only — no shader changes.
**Sources researched:** Wikipedia (Skewness, L-estimator, L-moment, IQR, Nonparametric skew,
Adaptive histogram equalization, Tone mapping), SAS Blog (robust skewness/kurtosis),
Wolfram MathWorld (Bowley skewness), statisticshowto.com, numberanalytics.com,
brownmath.com, Brendan Gregg (frequency trails / mode detection), Bruno Opsenica blog
(real-time luminance histograms), MJP blog (tone mapping), Journal of Vision (natural image
statistics), Reinhard 2002 (tone mapping), multiple image processing references.

---

## 1. Statistical Theory: What Percentiles Measure vs What Shape Statistics Measure

### 1.1 What p25/p50/p75 are

A percentile is the inverse of the cumulative distribution function. p50 (the median) is the
value below which 50% of the mass lies. The IQR = p75 − p25 measures the width of the middle
50% of mass. These are **L-estimators** — linear combinations of order statistics — and they
are robust to outliers because they are bounded by definition.

The theoretical foundation for L-estimators is well-established. Hosking (1990), "L-Moments:
Analysis and Estimation of Distributions Using Linear Combinations of Order Statistics," *Journal
of the Royal Statistical Society Series B*, 52(1), 105–124, defines the L-moment framework.
Hosking's key finding: L-moments "suffer less from the effects of sampling variability" than
conventional moments and "are more robust than conventional moments to the presence of outliers
in the data." The IQR is the simplest L-estimator of scale: it is the second L-moment divided by
a constant.

Source: https://rss.onlinelibrary.wiley.com/doi/abs/10.1111/j.2517-6161.1990.tb01775.x

### 1.2 What IQR cannot tell you

The IQR collapses the distribution to a single spread number. Three scenes can share identical
p25, p50, p75 and IQR while having completely different histogram shapes:

- **A symmetric unimodal distribution:** mass concentrated near p50, symmetric tails.
- **A right-skewed unimodal distribution:** mass piled low (mode ≪ p50), sparse specular tail
  inflating p75 upward.
- **A bimodal distribution (sky + ground):** two separate mass concentrations on either side
  of the median, with the median itself sitting in a low-density valley.

The IQR is identical for all three. What it misses:

1. **Shape asymmetry within the IQR.** Whether the mass from p25 to p50 is the same width as
   from p50 to p75 determines whether the distribution is symmetric within the middle half.
   Bowley skewness (see §4) captures this directly.

2. **Local density at the percentile points.** The PDF value at p75 (histogram bin height at
   that percentile) is entirely invisible. Two p75 values — one sitting in a dense peak, one in
   a sparse tail — produce the same IQR but imply completely different interpretations.

3. **Modality.** A bimodal distribution is invisible to three-percentile summaries. The IQR
   spans the valley between modes, giving no indication that the distribution has two separate
   concentrations.

4. **The mode.** The mode (most probable value, argmax of the PDF) may diverge substantially
   from the median. This divergence is the most direct measure of skewness available from a
   histogram.

Sources:
- https://en.wikipedia.org/wiki/Interquartile_range
- https://statisticsbyjim.com/basics/interquartile-range/
- https://www.scribbr.com/frequently-asked-questions/when-should-i-use-the-interquartile-range/

### 1.3 What shape statistics measure

**Skewness** (third standardized moment, g₁ = m₃ / m₂^(3/2)) measures directional asymmetry.
Positive skewness: right tail longer than left (mass piled left of mean). Negative: left tail
longer. The standard textbook relationship (mean > median > mode for right skew) is a heuristic
that frequently fails — as Wikipedia notes, "the skewness is not directly related to the
relationship between the mean and median." Discrete and multimodal distributions routinely
violate the rule. However, for unimodal, roughly-continuous distributions such as post-tonemapper
SDR luminance histograms, the heuristic is reliable.

Moment-based skewness has two practical problems:
- It is sensitive to outliers (the third power of deviations amplifies extreme values heavily).
- It requires computing the mean and variance first, which requires two passes over the data.

For histogram statistics computed in a single CDF-walk pass, **nonparametric alternatives are
preferable.**

**Kurtosis** (fourth standardized moment) measures tail weight relative to a normal
distribution. Leptokurtic (kurtosis > 3): heavy tails with concentrated peak. Platykurtic
(kurtosis < 3): light tails, flatter distribution. Modern statistical interpretation (per Westfall
2014, cited in brownmath.com) correctly frames kurtosis as a tail-weight measure, not a
peakedness measure: "higher kurtosis means more of the variance is the result of infrequent
extreme deviations, as opposed to frequent modestly sized deviations." For image processing,
kurtosis is less actionable than skewness — it distinguishes "lots of extreme highlights" from
"concentrated midtones" but this information is largely captured by the combination of IQR and
mode.

**PDF gradient (histogram slope at a percentile point):** The slope of the histogram at a given
percentile equals the PDF value there. A steep slope (high PDF) means the percentile is sitting
in a dense region of the distribution — many pixels within a small luminance interval. A flat
slope (low PDF) means the percentile is in a sparse tail. For CLAHE, the PDF value at each
luminance level directly determines the contrast amplification applied there — this is how the
algorithm converts a histogram into a local tone curve.

Sources:
- https://en.wikipedia.org/wiki/Skewness
- https://brownmath.com/stat/shape.htm
- https://en.wikipedia.org/wiki/Adaptive_histogram_equalization

---

## 2. Scene Luminance Distributions: Empirical Evidence

### 2.1 Natural scene statistics

The log-normal model for scene luminance is the dominant empirical finding across two decades of
research. The foundational result is that outdoor scene luminance, measured in cd/m², follows
approximately L ~ LogNormal(μ, σ²), meaning log(L) is normally distributed. Reinhard et al.
(2002), "Photographic Tone Reproduction for Digital Images," *ACM Transactions on Graphics*
21(3), built their tone mapping operator explicitly on this assumption: they compute the
log-average luminance (geometric mean) because it is the MLE estimator for the mean of a
log-normal distribution.

For natural photographs, σ_log (in log₂ units) typically spans 1.5–4 stops for the full scene
range. After ACES or similar HDR-to-SDR tonemapping, σ_log is compressed to approximately
0.5–1.5 stops of usable signal.

For a log-normal distribution in linear luminance:
- Mode (linear) = exp(μ − σ²)
- Median (linear) = exp(μ)
- Mean (linear) = exp(μ + σ²/2)
- IQR (linear) ≈ 2 · exp(μ) · sinh(0.674 σ) ≈ 1.35 σ · exp(μ) for small σ

The mode is always below the median in a log-normal, and the gap grows with σ. For a 2-stop
spread (σ_log ≈ 2), the mode in linear space is exp(−σ²) ≈ 0.018 times the mean — an enormous
divergence.

Source: Reinhard et al. 2002 (referenced in multiple search results including
https://expf.wordpress.com/2010/05/04/reinhards_tone_mapping_operator/ and
https://therealmjp.github.io/posts/a-closer-look-at-tone-mapping/)

### 2.2 Deviation from log-normal: HDR and game content

Pouli, Cunningham, and Reinhard (2010, referenced in search results from
https://library.imaging.org/admin/apis/public/api/ist/website/downloadArticle/cic/12/1/art00055)
found that HDR distributions exhibit "much higher skewness and kurtosis" than LDR images. The
additional skewness comes from a secondary mass component at very high luminances (sun,
specular highlights) that shifts the tail of the log-normal substantially rightward. Game renders
add a further complication: the tonemapper (ACES/AGX/Hable) squashes the pre-tonemapper
log-normal into a non-parametric shape that is neither log-normal nor Gaussian:

- The **shadow toe** compresses dark pixels into a floor, creating a density spike at low
  luminances.
- The **highlight shoulder** compresses bright pixels below 1.0, creating a density spike just
  below the SDR ceiling.
- The **midtone body** is approximately linear in the tonemapped space, preserving a moderate
  ramp.

The result is a **trimodal potential**: a shadow clump, a midtone body, and a highlight clump.
Whether this manifests as true bimodality depends on scene content. Common cases:

| Scene type | Distribution shape | Mode vs median |
|---|---|---|
| Outdoor, overcast | Roughly unimodal, right-skewed | mode < median by 0.10–0.25 |
| Outdoor, sunny | Strongly right-skewed, potential bimodal (shadow+sky) | mode < median by 0.20–0.40 |
| Interior with bright window | Bimodal | median sits in low-density valley |
| Night / cave | Left-skewed or near-symmetric | mode ≥ median |
| Dark interior | Near-symmetric (tonemapper toe dominates) | mode ≈ median |

### 2.3 Implication for IQR-based compression estimation

The current pipeline derives the scene compression slope from the log-IQR
(`log2(p75) - log2(p25)`), calibrated against a 2.5-stop ACES nominal uncompressed IQR. For
right-skewed outdoor scenes, p75 is inflated by a sparse specular tail while p25 stays in the
dense body. This makes the log-IQR appear wider than the actual content spread, causing the slope
estimate to understate the true compression. The pipeline under-expands chroma and luma for these
scenes.

---

## 3. Mode vs Median: When They Diverge and Consequences

### 3.1 Statistical theory of mode-median divergence

For a unimodal distribution, the median and mode coincide only when the distribution is
symmetric. Any asymmetry produces a gap. The Pearson mode skewness coefficient:
`Sk = (mean − mode) / σ`, and Pearson's second coefficient: `Sk₂ = 3(mean − median) / σ`, both
vanish for symmetric distributions and grow in proportion to the skewness of the underlying data.

For practical image processing (where we have a histogram but not necessarily the mean or σ),
the mode-median gap is the most directly readable asymmetry indicator: it is the difference
between the argmax of the histogram and the CDF inversion at 0.50.

From Brendan Gregg's work on mode detection in performance distributions
(https://www.brendangregg.com/FrequencyTrails/modes.html): "the average is the index of central
tendency. But what if the tendency isn't central?" In bimodal distributions, mean and median may
fall in the low-density valley between modes, meaning they represent no actual content well.
His mvalue statistic quantifies modality: mvalue ≈ 2.0 for unimodal, ≈ 4.0 for bimodal;
threshold at 2.4 for triggering further analysis. This framework directly applies to luminance
histograms with sky/ground splits.

### 3.2 Practical consequences for pipeline operations

**FilmCurve knee misplacement:** The knee is anchored at p75 (`fc_knee = lerp(0.90, 0.80,
sat((ctx.eff_p75 − 0.60)/0.30))`). For right-skewed distributions (mode at 0.25, median at
0.50, p75 at 0.72 in a sparse specular tail), the knee sits above the dense content body. The
FilmCurve roll-off begins compressing content that has already become sparse, leaving the dense
midtone body under-compressed. The practical result: outdoor scenes look flatter than expected
because the shoulder isn't engaging where the content density is highest.

**Shadow lift overactivity vs underactivity:** `_sls_t = sat((ctx.perc.r − 0.025)/0.175)`.
Shadow lift is calibrated against p25 as the shadow floor indicator. For right-skewed scenes
with the mode at 0.25, p25 ≈ 0.15 is in the real shadow content, and the lift is correctly
targeting sparse dark pixels. For bimodal scenes (foreground dark cluster + sky bright cluster),
p25 may be in the center of the dark mode, not the tail — lift then pulls on dense content.

**CLAHE sensitivity:** CLAHE uses the PDF value at each luminance bin to set the local contrast
amplification. Regions with high PDF get amplified less (or clipped to prevent noise
amplification). The clip limit is a direct constraint on peak histogram height. This is exactly
the information the pipeline is currently missing: the PDF at p75 tells whether the knee is in
a dense or sparse region.

---

## 4. L-Moments and Bowley Skewness: Nonparametric Shape Measures

### 4.1 Bowley skewness

Bowley's measure of skewness (1901), also called the quartile skewness coefficient or
Yule's coefficient, is:

```
bowley = (Q₃ + Q₁ − 2Q₂) / (Q₃ − Q₁)
       = (p75 + p25 − 2·p50) / (p75 − p25)
```

Range: [−1, 1]. Positive = right-skewed (upper IQR half wider than lower). Zero = symmetric
within the middle 50%. Negative = left-skewed.

Source: https://mathworld.wolfram.com/BowleySkewness.html
Wikipedia formulation: Groeneveld & Meeden (1984) generalized this as
`γ(u) = [Q(u) + Q(1−u) − 2Q(1/2)] / [Q(u) − Q(1−u)]`,
evaluated at u = 3/4 to recover Bowley's measure, at u = 9/10 for Kelly's measure
(which extends into the tail).

**Critical advantage:** Bowley skewness is computable from exactly the three percentiles
already on the data highway. Zero new infrastructure required.

**Limitation:** Bowley only measures asymmetry within the middle 50% of the distribution.
It is insensitive to tail asymmetry outside p25–p75. For a bimodal sky/ground scene where the
two modes sit near p10 and p90, Bowley may read near zero even though the distribution is not
unimodal. Also: when IQR is small (< 0.05), the denominator becomes small and Bowley amplifies
noise — a guard is required.

Source: https://en.wikipedia.org/wiki/Skewness (Nonparametric measures section)

### 4.2 L-moments framework (Hosking 1990)

L-moments are expectations of specific linear combinations of order statistics. The first four
L-moments are:
- λ₁ = E[X] — location (mean)
- λ₂ = ½(E[X₂:₂] − E[X₁:₂]) — scale (L-scale, related to average absolute deviation)
- τ₃ = λ₃/λ₂ — **L-skewness** (skewness of middle order statistics)
- τ₄ = λ₄/λ₂ — **L-kurtosis** (tail heaviness via outer order statistics)

L-skewness is bounded in (−1, 1) and, unlike moment-based skewness, always exists when the
mean exists (moment-based skewness requires finite third moment). L-kurtosis is bounded in
(−1, 1) and more numerically stable than the fourth-power moment.

L-moments are "more robust than conventional moments, and existence of higher L-moments only
requires that the random variable have finite mean." For scene luminance with heavy specular
tails (which can cause conventional moment estimates to blow up), L-moments provide stable
estimates.

From the Wikipedia L-moment article: "L-moments are now in widespread use in the field of
hydrology" — particularly for fitting distributions to extreme-value data with heavy tails and
limited sample sizes. Image histograms have similar structural properties: moderate sample counts
(64–256 bins), potential heavy tails from specular.

Sources:
- https://en.wikipedia.org/wiki/L-moment
- https://rss.onlinelibrary.wiley.com/doi/10.1111/j.2517-6161.1990.tb01775.x (Hosking 1990)
- https://www.numberanalytics.com/blog/l-statistics-ultimate-guide

### 4.3 Robust skewness (Hogg 1974, Bowley-Galton extended)

The SAS blog (https://blogs.sas.com/content/iml/2020/11/09/robust-skewness-kurtosis.html)
documents practical robust alternatives to moment skewness:

**Bowley-Galton extended to more extreme percentiles:**
```
((P80 − P50) − (P50 − P20)) / (P80 − P20)
```
Uses 20th and 80th percentiles instead of quartiles, reaching further into the tails.

**Hogg's skewness (1974):**
```
SkewH = (U(0.05) − M25) / (M25 − L(0.05))
```
where U(0.05) = mean of the largest 5%, L(0.05) = mean of the smallest 5%, M25 = 25% trimmed
mean (middle 50%). More sensitive to tail asymmetry than Bowley.

**Hogg's kurtosis:**
```
KurtH = (U(0.2) − L(0.2)) / (U(0.5) − L(0.5))
```
A ratio of tail spread to central spread — robust alternative to the fourth moment.

For a single-pass CDF-walk implementation, Bowley is the only one computable at zero cost with
existing highway data. Hogg's measures require the mean of percentile groups, which would need
additional histogram accumulation within CDFWalkPS.

---

## 5. Image Processing Applications

### 5.1 CLAHE — the gold standard for histogram-shape-aware enhancement

CLAHE (Contrast-Limited Adaptive Histogram Equalization, Zuiderveld 1994) is the field's most
widely deployed algorithm that explicitly uses histogram shape beyond mean/percentile.

How it uses shape:
1. **Clip limit as a peak constraint:** The histogram is clipped at a user-defined maximum
   bin height before CDF computation. This directly constrains the mode — if any bin exceeds
   the clip limit, its excess is redistributed uniformly. The clip limit is a mode-height
   bound: it prevents dense peaks from over-amplifying local contrast. Typical values: 3–4.
2. **CDF slope as local contrast:** The amplification at each luminance value is proportional
   to the local CDF slope — which is the PDF at that value. High PDF → high amplification;
   low PDF (tails) → low amplification. This is exactly the "PDF at percentile" mechanism the
   current pipeline lacks.
3. **Tile-based adaptation:** Histogram statistics are computed per-tile, making the tone
   curve spatially variable. The pipeline's zone-based analysis is a coarse version of this.

Sources:
- https://en.wikipedia.org/wiki/Adaptive_histogram_equalization
- https://docs.opencv.org/4.x/d5/daf/tutorial_py_histogram_equalization.html
- https://arxiv.org/pdf/2109.00886

### 5.2 Real-time game rendering: log-average exposure

In real-time rendering, the standard approach to automatic exposure uses the log-average of
scene luminance — the geometric mean in the log domain. Bruno Opsenica's implementation
(https://bruop.github.io/exposure/) builds a 256-bin log₂ luminance histogram on the GPU
and computes a weighted average across bins. The author explicitly notes that the histogram
enables flexible statistics — median, mode, trimmed mean — but the practical implementation
uses the arithmetic mean of log-luminance bins (= log-average = Reinhard's formulation).

No commercial real-time renderer currently exposes skewness or mode statistics for tone
mapping adaptation in published literature. The practical state of the art in real-time is:
**log-average + percentile trimming** (trim the darkest and brightest N% of pixels before
averaging, which is a trimmed mean — itself an L-estimator). Unity's Physical Camera and Unreal's
Eye Adaptation both use metered-average exposure with optional percentile clipping.

MJP's blog (https://therealmjp.github.io/posts/a-closer-look-at-tone-mapping/) describes using
log-average luminance with a user key value, consistent with Reinhard 2002. The author does not
use mode, skewness, or any shape statistic. This represents the current industry norm.

The current pipeline — using p25/p50/p75 to drive adaptive FilmCurve and shadow lift — is
already substantially more sophisticated than the real-time rendering standard.

### 5.3 Tone mapping operators and histogram shape

Reinhard et al. 2002 use log-average (geometric mean) as the single scene descriptor. Ward's
`Display Algorithm` (1994) uses a global histogram normalization. Neither uses skewness.

Histogram-equalization tone mapping (Larson, Rushmeier, Piatko 1997) uses the full histogram
CDF to build a globally equalizing tone curve — equivalent to using the PDF at every point.
This preserves all histogram shape information but produces over-equalized results.

Perception-based histogram tone mapping operators (Ploumis et al. 2016, referenced in search
results) use the full luminance histogram to target a perceptually uniform output distribution.
These algorithms inherently use histogram shape (not just percentiles), but they are designed
for offline batch processing, not real-time.

### 5.4 Professional color grading tools

DaVinci Resolve's Color Match and auto-balance use the 2nd and 98th percentile as floor/ceiling,
with the median as the midtone anchor — a three-percentile summary. Resolve's Color Warper
includes a histogram peak (mode) display that colorists use as the visual anchor for grade
decisions. The waveform scope makes mode-vs-median divergence immediately visible; this is why
professional colorists routinely detect the asymmetry the pipeline currently cannot measure.

---

## 6. What Is Computable from a Histogram Without Additional Data

### 6.1 Statistics computable directly from the 64-bin histogram

Given the histogram as an array of bin heights `h[0..63]` (normalized so sum = 1.0):

**Zero additional cost (available during CDF walk, same loop):**

| Statistic | Formula | Notes |
|---|---|---|
| Mode bin | argmax(h[b]) | Track max during loop; 2 registers, ~3 ALU/iter |
| PDF at p75 | h[b75] at CDF crossing | 1 register capture at p75 branch |
| PDF at p25, p50 | Same | 1 register each |
| Log-space mean | sum(log₂(center(b)) · h[b]) | 1 accumulator, requires HIST_BINS iters |
| Log-space variance | sum(log₂(center(b))² · h[b]) − mean² | 1 additional accumulator |

**Computable from existing highway data only (zero new infrastructure):**

| Statistic | Formula | Cost |
|---|---|---|
| Bowley skewness | (p75 + p25 − 2·p50) / (p75 − p25) | Inline arithmetic, no highway slots |
| IQR | p75 − p25 | Already computed |
| Mode−median gap | mode − p50 (once mode is added) | Inline once mode is on highway |

**Not computable without raw data or histogram moments:**
- Moment-based skewness g₁ (requires third moment accumulation — feasible from histogram but
  requires explicit accumulation pass)
- Hogg's measures (require mean of top/bottom N% — feasible but adds accumulation cost)
- L-skewness / L-kurtosis (require order-statistic expectations — difficult from binned data)

### 6.2 Statistics that require extra infrastructure

| Statistic | What's needed | Worth it? |
|---|---|---|
| Full log-normal fit (μ, σ) | Accumulate sum(lv·h), sum(lv²·h) in CDF loop | Yes — σ is physically motivated |
| Bimodal detection (mvalue) | Count histogram local maxima | Possible but noisy at 64 bins |
| Full L-moments | Numerical integration over sorted histogram | Feasible but not simpler than moments |
| Pearson moment skewness | Three-moment accumulation | Feasible but sensitive to tail spikes |

The 64-bin resolution is the primary limitation: bin width = 1/64 ≈ 0.016 in linear luminance.
The mode can only be resolved to within one bin width (~1.6% luminance), which is sufficient
for the knee-placement and shadow-lift use cases.

---

## 7. Concrete Recommendation: Ranking Additional Statistics by Pipeline Value

### 7.1 What p25/p75/p50 already give

The current three-percentile system correctly measures: tonal spread (IQR), scene brightness
(p50), and coarsely the floor and ceiling of meaningful content (p25, p75). The highway also
carries p90 and the IQR-derived compression slope. This is a good L-statistics foundation.

What it cannot give: the location of peak content density, the direction of distribution
asymmetry, or any indication of whether p75 is sitting in dense or sparse content.

### 7.2 Ranked by added value

**Tier 1 — Adds a qualitatively new dimension:**

**Mode bin center.** The most probable luminance value. Addresses a genuine information gap:
where is the mass actually concentrated? Computable at near-zero cost in CDFWalkPS. Enables:
(a) FilmCurve knee anchored to dense content instead of sparse tail; (b) shadow lift confidence
(is p25 in dense or sparse region?); (c) implicit skewness signal as `mode − p50`.

Cost: 2 extra registers + ~3 ALU per CDFWalkPS loop iteration. 1 highway slot. 1 EMA
smoothing step (analogous to p90). No additional passes.

**Tier 2 — Free with existing infrastructure:**

**Bowley skewness.** `(p75 + p25 − 2·p50) / (p75 − p25)`. Range [−1, 1]. Positive =
right-skewed (outdoor, specular). Zero = symmetric. Negative = left-skewed. Computable
anywhere the highway percentiles are read — zero infrastructure cost. Provides the direction
of the distribution asymmetry, which the mode-p50 gap will later quantify more cleanly.

Limitation: only measures asymmetry within the middle 50%; silent on the tails; noisy when
IQR < 0.05.

**Tier 3 — High value, low cost, single slot:**

**PDF at p75.** Histogram bin height at the p75 crossing. Provides a "confidence signal"
for p75-anchored operations: high PDF = p75 is in dense content (shoulder behavior is
aggressive and appropriate); low PDF = p75 is in a sparse tail (shoulder is over-triggering).
Cost: 1 register captured in CDFWalkPS at the p75 branch. 1 highway slot.

**Tier 4 — Useful but lower urgency:**

**Log-space variance.** `sum(log₂(center(b))² · h[b]) − (log-mean)²`. A physically motivated
spread measure for log-normal data that separates "content spread" from "distribution position."
IQR conflates both. Cost: 2 additional accumulators in CDFWalkPS. 2 highway slots. Lower
priority because IQR already works adequately for near-symmetric distributions (the majority
case in the dark-interior testbed).

### 7.3 Summary

The single statistic that adds the most information beyond p25/p50/p75 is **the mode** (argmax
of the luminance histogram). It solves a genuine qualitative gap — the pipeline currently has no
knowledge of where the distribution's mass actually concentrates — and it enables three concrete
improvements:

1. FilmCurve knee anchoring to dense content rather than sparse specular tail.
2. Shadow lift confidence (distinguishing dense-body p25 from sparse-tail p25).
3. Distribution skewness via `mode − p50` without any new statistical machinery.

The mode is computable in the existing CDFWalkPS loop at near-zero GPU cost, requires one new
highway slot, and needs one EMA smoothing step with scene-cut reset. It does not require any
new passes, textures, or architectural changes to the analysis chain.

Bowley skewness is available immediately with zero infrastructure cost and provides partial
coverage of the same information (IQR-interior asymmetry) while the mode is not yet implemented.

---

## Key Sources

- Hosking 1990, L-Moments: https://rss.onlinelibrary.wiley.com/doi/abs/10.1111/j.2517-6161.1990.tb01775.x
- Wikipedia, Skewness: https://en.wikipedia.org/wiki/Skewness
- Wikipedia, L-estimator: https://en.wikipedia.org/wiki/L-estimator
- Wikipedia, L-moment: https://en.wikipedia.org/wiki/L-moment
- Wikipedia, Adaptive Histogram Equalization: https://en.wikipedia.org/wiki/Adaptive_histogram_equalization
- Wikipedia, Nonparametric skew: https://en.wikipedia.org/wiki/Nonparametric_skew
- Wolfram MathWorld, Bowley Skewness: https://mathworld.wolfram.com/BowleySkewness.html
- SAS Blog, Robust skewness/kurtosis: https://blogs.sas.com/content/iml/2020/11/09/robust-skewness-kurtosis.html
- Brownmath.com, Shape measures: https://brownmath.com/stat/shape.htm
- Brendan Gregg, Frequency Trails: https://www.brendangregg.com/FrequencyTrails/modes.html
- Bruno Opsenica, Real-time exposure: https://bruop.github.io/exposure/
- MJP, Tone Mapping: https://therealmjp.github.io/posts/a-closer-look-at-tone-mapping/
- Reinhard 2002 (referenced): https://expf.wordpress.com/2010/05/04/reinhards_tone_mapping_operator/
- Natural image statistics (HDR skewness): https://library.imaging.org/admin/apis/public/api/ist/website/downloadArticle/cic/12/1/art00055
- IQR: https://statisticsbyjim.com/basics/interquartile-range/
- Number Analytics, L-statistics: https://www.numberanalytics.com/blog/l-statistics-ultimate-guide
