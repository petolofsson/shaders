# Research: retaining shading while restraining noise

The user requested further web research and experiments to reduce noise while
keeping material-gradient gains as high as possible. Primary-source research
and four fixed CPU references extend the [noise-restraint screen](2026-11-06_shadow_noise_restraint.md).
None establishes a better overall brightness/color candidate. The more selective
references suppress noise strongly but lose useful response; less conservative
patch matching retains somewhat more texture but increases correlated-noise
amplification. Production, profiles, configs and ratings remain unchanged.

## Research findings

1. **Dependencies across scales.** Şendur and Selesnick model a wavelet
   coefficient jointly with its coarser-scale parent, rather than shrinking it
   independently. Their [local-variance paper](https://eeweb.engineering.nyu.edu/iselesni/pubs/BiShrinkSPL.pdf)
   derives an adaptive bivariate shrinkage rule. This motivates checking whether
   coherent parent structure can retain fine material response. Their wavelet
   representation and white-noise model differ from our correlated Laplacian
   coefficients and unknown game noise.
2. **Neighborhood covariance.** Portilla, Strela, Wainwright and Simoncelli's
   [Gaussian-scale-mixture model](https://www.cns.nyu.edu/pub/lcv/portilla03-reprint.pdf)
   uses joint neighborhoods across positions/scales. It supports modeling
   relationships rather than treating every coefficient independently. Its
   full Bayesian covariance machinery is not implemented in these pilots.
3. **Patch recurrence.** Buades, Coll and Morel's
   [non-local-means reference](https://www.ipol.im/pub/art/2011/bcm_nlm/)
   motivates comparing patches to preserve repeated structure while averaging
   noise. A small local coefficient-patch reference below tests that principle;
   it is not a full NLM or BM3D implementation.
4. **Correlation must be modeled.** Mäkinen, Azzari and Foi's
   [correlated-noise collaborative-filtering paper](https://webpages.tuni.fi/foi/papers/ICIP2019_Ymir.pdf)
   accounts for noise covariance in transform coefficients, patch matching and
   aggregation. It assumes a known noise power spectrum. This is an important
   missing input here: reproducing its filter alone would not supply a valid
   blind game-noise estimate. Overlapping patches can also have correlated
   noise, even with initially white input.
5. **Noise estimation is a separate problem.** Pyatykh, Hesser and Zheng's
   [PCA noise-estimation paper](https://medphyssrv1.medma.uni-heidelberg.de/cms/sites/default/files/img/Stanislav/noise_param_estimation/2013_noise_level_estimation_tip.pdf)
   estimates white-noise variance from image-block covariance eigenvalues,
   including textured images. This suggests a route away from counting all
   local texture variation as noise. Its white-noise scalar estimate is not a
   ready solution for arbitrary correlated game grain or banding.

These papers support research directions, not appearance or implementation
claims for this shader. No external code/package, neural model, temporal filter
or motion-vector dependency was added. No source text or implementation was
copied into production.

## Fixed references tested

All reuse the same dense pre-dither source/current/half-color GPU readbacks.
The original proposed coefficient increments, source-support cap, source shadow
window, original coarse base and RGB gain/headroom limit stay fixed. Only the
increment-confidence calculation changes. The existing output is never blurred
or denoised, and the half-color helper's chromatic-noise costs remain.

- **Parent-support pilot:** average normalized child and expanded parent local
  signal-to-uncertainty energies before positive-part confidence. This is a
  dependency heuristic, not published BiShrink.
- **Bivariate reference:** apply the local-variance shrinkage form
  `max(1 - sqrt(3)*noiseVariance/(signalSigma*vectorRadius), 0)`, with guarded
  denominators and a parent normalized to child marginal noise scale. This
  applies the published rule's form to enhancement confidence in a different
  representation. Cross-scale covariance is still approximate; do not call it
  an exact reproduction or dismiss the published method based on these results.
- **Patch-recurrence reference:** average source coefficients over a 7×7 search
  using 3×3 coefficient-patch distances, subtract an estimated pair noise energy
  and use an exponential weight. The signed ratio of that estimate to the
  original coefficient controls the proposed increment, bounded to [0,1]. This
  small search is a local feasibility reference, not full non-local matching.
  The pair-noise approximation does not model every overlapping/correlated
  patch covariance.
- **Quadratic-structure reference:** a least-squares 9×9 quadratic fit replaces
  the within-band median trend. MAD of its residual estimates uncertainty,
  bounded below by the earlier propagated white-noise estimate. The idea is to
  keep smooth curvature from being counted as noise. It does not calibrate all
  correlated-noise residual responses and is an original exploratory model,
  not an implementation of the PCA paper.

All constants are fixed; no parameter sweep or adoption optimization follows.
The quadratic fit reproduces an interior quadratic to numerical precision in
a finite control. That arithmetic property does not establish correct game
signal/noise classification.

## Dense material/noise results

As in the previous report, compare combined output with **color-only** on the
same source-selected dense material pairs. Noise std is continuous
sRGB-code-equivalent luminance variation in the original 64×64 RGB noise-patch
center. The material measure is the mean signed 4-pixel log-Y gap, with the
previous source L/chroma/gap selection. Overlapping pair gains are not visual
quality scores, and these percentages are not perceptual thresholds.

| Fixed reference | Added RGB-noise std | Wall gap gain | Metal gap gain | Timber gap gain |
| --- | ---: | ---: | ---: | ---: |
| Earlier independent-noise | +2.43% | +6.55% | +10.86% | +14.91% |
| Earlier conservative band | +0.20% | +1.92% | +4.30% | +3.43% |
| Parent-support pilot | +0.19% | +1.63% | +3.96% | +3.01% |
| Bivariate reference | +0.021% | +0.64% | +2.00% | +1.24% |
| Patch recurrence | +1.42% | +2.16% | +4.78% | +4.84% |
| Quadratic structure | +0.20% | +2.02% | +3.91% | +3.93% |

The bivariate reference is quietest here but gives up most measured material
response. Patch recurrence keeps somewhat more selected response than the
conservative reference, with higher added noise. Quadratic fitting changes the
balance slightly rather than clearly improving it. Native timber previews show
small texture differences without an established clear dimensional improvement.
No blind/user appearance assessment or full-scene benefit is claimed.

## Correlated stresses and edge controls

These separate scalar controls use the configured affine black mapping, not
the full grade, and compare each result with its own current baseline. Their
noise inputs and masks match the previous screen. Do not compare their std
levels directly with the dense RGB/full-chain fixture.

| Reference | Blurred correlated grain: added std | Vertical banding: added std |
| --- | ---: | ---: |
| Earlier independent-noise | +42.1% | +41.7% |
| Earlier conservative band | +7.3% | +10.1% |
| Parent-support pilot | +6.0% | +11.0% |
| Bivariate reference | +2.3% | +5.6% |
| Patch recurrence | +10.7% | +13.9% |
| Quadratic structure | +9.1% | +7.5% |

Thus the very small white-noise-patch number does not establish general noise
restraint. The bivariate reference improves these stresses too, but at a high
material-response cost. No tested reference dominates the earlier alternatives
across the material and noise cases. Banding and shading can have similar
spatial structure; interscale persistence alone cannot label one as unwanted.

Finite black/flat controls remain exact. Small and softened steps still acquire
rims and neighboring-shade reversals: small-step maximum correction is roughly
0.031/0.034/0.034/0.028 stops for parent/bivariate/recurrence/quadratic. The clean
periodic shading std gain is about 8% for parent/bivariate, 11% recurrence and
20% quadratic; adding noise to that signal also retains some response but is
not a clean/noisy ground-truth reconstruction guarantee. Material reversals
remain in the dense reports. No broad motion, phase-stability, gamut, zero-gate,
GPU numerical or actual-config validation was warranted by these results.

## Decision and next design lead

Do not port these references or select one from the lowest noise number alone.
The useful lead is **estimating noise separately from structured material
variation, including its spatial correlation**, then using that estimate in
confidence/matching. Full-covariance or collaborative methods are plausible
research directions, not ready shader replacements. A lower-eigenvalue white
noise estimate also cannot simply be substituted for an unknown colored-noise
spectrum. Diagnose that estimation problem on known-signal controls and real
source-selected regions before adding more filter machinery or new runtime
resources. Boundary/order behavior remains a separate unresolved requirement.

Local artifacts: `captures/shadow_noise_structure_20261106/` has `model.py`,
generators, separate `parent/`, `bivariate/`, `recurrence/`, `quadratic/` reports,
arrays and native previews, `controls.json`, and a native-size interactive
[review](../captures/shadow_noise_structure_20261106/review.html). These are CPU
references on preserved GPU inputs, with approximate CPU preview encoding and
dither. Verification preserves input/dependency/production identities and the
prior noise-screen artifact manifest. No new GPU process was needed; no active
shader/profile/config/history/resource/pass/rating or publication changed.
