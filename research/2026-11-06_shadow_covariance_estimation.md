# Noise-covariance estimation: conditional progress

The user asked to continue the noise-estimation lead while retaining material
gradients. A new fixed CPU diagnostic estimates short-range noise covariance
separately from local smooth structure. It recovers known white/correlated noise
well in its synthetic scope. Using its covariance and local-energy uncertainty
reduces a synthetic correlated-grain amplification from about 42% to 3.6%, while
retaining roughly 15% averaged periodic-shading response gain.

This is conditional progress, **not a real-material candidate**. Noiseless
texture is still misclassified, real material estimates are inconsistent, long
range banding violates the model and step rims remain. Production, profiles,
configs, resources, passes, histories and ratings are unchanged. No GPU capture
or active brightness-shader change was needed.

## Why estimate covariance first

The [previous research](2026-11-06_shadow_noise_structure_research.md) found that
independent-noise confidence retains more material response but fails correlated
grain, while within-band MAD suppresses useful texture. A scalar white-noise
floor alone cannot characterize a colored-noise spectrum. A raw smallest
patch-covariance eigenvalue in these controls is about 0.712 for unit white
noise but only 7.5e-8 for unit correlated grain. This is a diagnostic baseline,
not the full published adaptive PCA algorithm, and not evidence against that
paper's stated white-noise model.

Single-image estimation needs a signal prior. Liu, Freeman, Szeliski and Kang's
[noise-estimation work](https://people.csail.mit.edu/celiu/denoise/estnoise/)
uses smooth regional models and residual statistics, noting contamination by
unmodeled image structure and limited coverage. The new model below is our
own fixed diagnostic, not a reproduction of that camera-noise estimator.
Mäkinen, Azzari and Foi's
[correlated-noise analysis](https://webpages.tuni.fi/foi/papers/ICIP2019_Ymir.pdf)
also explains why covariance affects transform-domain variance and filtering.
Neither source validates this shader application.

## Fixed estimation model

Assume that within nonoverlapping 9×9 patches, clean log luminance is quadratic,
and additive stationary noise has zero covariance beyond four pixels along
either axis. Remove the six-dimensional quadratic subspace with projector Q.
The residual patch covariance is modeled as `Q * noiseCovariance * Q`.
Fit 41 unique symmetric stationary covariance lags by linear least squares.
The resulting design has rank 41/41 and condition number about 8.13. This
identifiability depends on the finite covariance support and signal model;
it does not identify arbitrary noise separately from arbitrary texture.

The fitted spectrum can have small negative components from finite-sample or
model error. The diagnostic records those components; propagation uses a
nonnegative spectrum projection, which changes the estimate and is not an
independent physical-validity proof. For unit correlated grain on a flat field,
negative frequencies occupy about 28% of sampled bins but carry only 0.24% of
the positive spectral power. Frequency count alone would overstate this error.

The model is stationary within the analyzed input. Real source log-noise can be
heteroscedastic, and scene boundaries/material texture can violate the smooth
signal prior. No threshold was fitted to make real regions pass these assumptions.

## Estimator controls and real-input check

Seeded 512×512 known-signal fields compare flat, quadratic, periodic smooth
shading and fine deterministic texture with white noise, blurred correlated
grain, vertical banding and no noise. On flat/quadratic/smooth fields, white and
short-range grain variance estimates differ from truth by less than 1% in the
initial realization. A later independent-seed check in a smaller log-domain
fixture has white errors −0.5% to +0.5% and grain errors about −3.4% to +3.4%.
These finite seeded results are not universal accuracy bounds.

The two important failures are preserved:

- Fine deterministic texture with **zero actual noise** produces estimated
  variance about 0.26. The quadratic model cannot explain it and counts it as
  noise. The covariance fit residual is large, but no calibrated acceptance
  test is established.
- Unit vertical banding produces estimated variance about 0.587, because its
  long-range correlation violates the four-pixel covariance support. Its fit
  residual and spectral errors are also large.

Dense actual post-inverse source patches from the earlier GPU readbacks give
global log-domain estimates roughly 0.287 wall, 0.473 metal and 0.100 timber,
versus Haar median estimates 0.00114/0.00610/0.00481. Haar is not ground truth;
the disagreement exposes model dependence rather than proving either estimate.
Splitting inputs into fixed 72×72 blocks reduces large-boundary mixing, but
actual-region estimates still vary widely. Wall 10th–90th percentiles span
0.0022–0.7566; metal 0.0496–1.1138; timber 0.0309–0.2338. By contrast, the
RGB-noise fixture spans 0.00497–0.00525. A median over blocks is not enough:
the noiseless-texture control still estimates about 0.271 at the block median.
No new material-gradient gain is claimed or computed from those unreliable
global estimates.

## Synthetic enhancement feasibility

Use known source log Y `−7.5 + signal + noise` on 256×512 pixels: signal is zero
or a 0.25-stop sinusoid with 64-pixel period; noise is zero or 0.1-stop Gaussian
white/grain/banding. Convert to gray linear RGB and retain the configured
affine black mapping as current output. This is a new scalar synthetic fixture,
**not** the previous RGB code-16 full-chain noise patch or real GPU grading.

Fit covariance from the observed synthetic source without using the clean
signal or true noise. Propagate the nonnegative spectrum through the exact
four-level/four-phase coefficient analysis kernels. The same local 9×9 band
energy has noise mean μ and Gaussian standard deviation σ derived from
covariance, using `Var(energy) = 2 * sum(w_i*w_j*Cov(i,j)^2)`.
Independent seeded propagation checks have predicted/empirical mean and std
ratios within about 3% in the realizations tested.

Noise-only local energy sometimes exceeds its mean by chance. Taking only its
positive excess creates selection bias. A fixed one-standard-deviation margin
therefore uses `saturate((energy−μ−σ)/max(energy,1e-12))` for the **proposed
enhancement increments**. This is a fixed Gaussian-model margin, not a calibrated
probability guarantee, perceptual threshold or strength sweep. Noise-estimate
uncertainty and non-Gaussian behavior remain outside that calculation.

| Synthetic condition | Earlier independent-noise confidence | Covariance alone | Covariance plus energy uncertainty |
| --- | ---: | ---: | ---: |
| Flat white noise: added code-equivalent std | +6.4% | +6.5% | +2.1% |
| Flat correlated grain: added std | +41.9% | +9.9% | +3.6% |
| Flat banding: added std | +42.8% | +12.2% | +7.6% |
| Clean periodic shading: row-mean std gain | +23.8% | +23.8% | +23.8% |
| Shading plus white noise: row-mean std gain | +20.3% | +20.2% | +19.8% |
| Shading plus grain: row-mean std gain | +22.6% | +16.9% | +15.4% |

Row-mean std averages over the repeated shading rows to emphasize signal; it
still contains finite residual noise and is not a ground-truth material-gradient
or fidelity measure. Total noisy-shading std is not labeled noise amplification,
because intentional shading changes too. Three independent holdout seeds give
flat-white amplification about 2.0–2.1%, grain 3.2–4.1%, and grain/shading
row-mean gains about 15.1–15.9%. No parameters changed between seeds.

Separate configured-affine black/flat controls remain exact. Small/softened
steps retain overshoot, undershoot and reversals, with maximum corrections about
0.033/0.037 stops. The covariance work does not fix reconstructed boundaries.
The earlier source cap, bounded gain and color path remain unchanged conceptually;
no full-color, real-material, zero-gate, GPU, motion or active-config validation
of this synthetic helper is claimed.

## State and next work

This establishes that correlation-aware noise estimation and local-energy
uncertainty can improve the synthetic noise/shading tradeoff when the signal
model holds. It does not establish reliable blind noise estimation on actual
materials. Do not feed the current global material estimates into production,
calibrate a threshold on these three regions, or present the 15% synthetic
response as retained wall/metal/timber gains.

The next design question is how to identify credible smooth observations or
otherwise constrain noise separately from legitimate texture, with explicit
abstention when that identification is weak. Intensity dependence, long-range
correlation, insufficient observations and boundary/order protection remain.
That is still design work, not an adoption blocker requiring a user decision.

Artifacts: `captures/shadow_noise_covariance_20261106/` contains `estimate.py`,
the estimator/block reports, `spectral_model.py`, original spectral controls,
energy-uncertainty controls, independent holdouts/edge controls, propagation/PSD
validation and verification. All are CPU experiments on synthetic fields or
preserved dense GPU inputs. No new runtime, production/profile/config change,
effectiveness re-score, commit or push follows.
