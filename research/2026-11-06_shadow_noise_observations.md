# Credible noise observations: selection and abstention screen

The user requested continuing the [covariance-estimation lead](2026-11-06_shadow_covariance_estimation.md).
This screen separates observation selection, estimation and validation, checks
regional/intensity coverage, and explicitly abstains when model support is weak.
It improves diagnostics but does **not** establish a usable real-material noise
estimate or any new gradient gain. No production/profile/config/history/resource/
pass/rating change or new GPU process follows.

## Fixed method

Retain the prior 9×9 local-quadratic residual model and 41 stationary covariance
lags with support at most four pixels per axis. Sample patches on a 13-pixel
pitch, leaving four unused pixels between patches. Thus their nearest samples
are five pixels apart, beyond the assumed noise-covariance support. Within
117×117 regions, three interleaved column groups provide independent noise
observations under that assumption:

1. Rank regions by the first group's residual energy; keep the lowest quarter.
2. Estimate covariance from the second group, without selecting on those values.
3. Check predictive covariance against the third, held-out group.

This avoids directly selecting a low noise realization and estimating its level
from those same samples. It assumes enough regions actually satisfy the smooth
signal/noise model. Patch independence fails for longer-range noise. Selection
does not prove that a region's variation is unwanted noise.

Two diagnostics compare fitted-spectrum negative power and held-out covariance
error against 63 Gaussian parametric-bootstrap draws from the fitted physical
covariance. Each must have an empirical upper-tail p above 0.025; these are
coarse, plug-in model checks, not validated perceptual or semantic confidence.
Require at least 75 training and 75 held-out patches, matching the residual
subspace dimension. A fixed uniform subsample caps each group at 512 patches
for the broader-image diagnostic. No parameter or threshold sweep occurred.
Passing is named **model consistent**, never **proven noise**.

## Known-signal controls

Seeded 512×512 images combine a quadratic trend, deterministic periodic texture
and unit white/short-range grain/banding noise. Smooth-region coverage is fixed
at 0%, 25%, 50% or 100%. In the initial realization:

- White noise with 25–100% smooth coverage passes the checks, with variance
  estimates about 0.958–0.970 versus truth near one. No-smooth-coverage texture
  plus white noise is rejected.
- Grain with 50–100% smooth coverage passes, estimating about 0.868–0.873.
  The 25% case estimates about 1.014 but is rejected by the predictive check.
  This is a valid-noise false rejection, not evidence of absent noise.
- All banding coverage cases are rejected, consistent with violation of the
  short-range covariance assumption.
- Noiseless periodic texture with zero smooth coverage is rejected. When
  smooth regions exist, selection returns zero residual in the finite control;
  this does not prove other regions contain no noise.

Three independent 25%-coverage holdouts produce one white pass/two rejections
and three grain passes. This prompted additional **fixed-rule calibration**,
without changing parameters: 16 further white cases all pass, while 15/16 grain
cases pass. Across those 16 realizations, estimated variance errors range
approximately −4.9% to +3.6% white and −13.5% to +22.9% grain. These finite
counts do not establish a nominal false-rejection rate or accurate per-frame
noise estimates. Earlier failures remain included, not replaced by calibration.

## Transfer and semantic counterexamples

A spatially varying-noise control has a smooth quarter with noise variance
about 1.007, and a textured remainder with variance about 9.013. Selected smooth
observations pass the checks and estimate about 0.939. That can be a plausible
local estimate while being wrong for the rest of the image. Shared intensity
alone does not establish shared noise variance, and a low regional estimate
must not be extrapolated freely into textured materials.

There is also an exact observational ambiguity: the same pixels can represent
a smooth signal plus Gaussian noise, or a smooth signal plus intentional fixed
random-looking material texture with no added noise. An image-only estimator
receives identical input in both cases. Passing second-order/Gaussian model
checks cannot establish the intended interpretation. This is a limit of the
available evidence, not a claim that useful practical noise estimation is
impossible with additional priors or observations.

## Existing GPU-input regions

All three dense post-inverse floating source regions—wall, metal, held timber—
are rejected by the held-out model check. Their selected variance estimates
fall below the previous pooled estimates (about 0.0040/0.0601/0.0420), but lower
numbers alone do not establish better estimates. The 256×256 RGB-noise fixture
has insufficient patch support under the declared minimum. It is not labeled
noise-free or accepted at that data size.

## Broader source-image proxies and intensity strata

The three full original source PNGs offer more spatial coverage. These are
**8-bit source-image proxies**, not newly verified post-inverse floating inputs
or GPU brightness-candidate output. Source hashes match the preserved dense
capture records. All three full-image pooled checks reject the shared noise
model. Their selected observations also span broad intensity ranges, preventing
an assumption that a bright observation describes a dark material.

As a fixed follow-up, split observations into one-stop mean-log-Y strata and
repeat selection/estimation/validation independently. No bin width is tuned:

| Original source | Strata rejected | Strata lacking patch support | Strata consistent |
| --- | ---: | ---: | ---: |
| GZW dark (wall source) | 4 | 5 | 0 |
| Arc interior (metal source) | 7 | 3 | 0 |
| Held timber | 4 | 4 | 0 |

The strata are multiple exploratory model checks, not a calibrated family-wise
acceptance procedure. No bin is chosen retrospectively as a production control.
Rejection can reflect legitimate texture, non-Gaussian/quantized input,
nonstationary or long-range noise, or an inadequate smooth model. It does not
identify which explanation is correct or measure the real noise floor.

## Decision and retained work

Do not use this selector to control material enhancement, tune acceptance until
these images pass, or extrapolate a selected quiet region across the image.
The method currently supplies **abstention**, not the reliable material/noise
separation required to retain high gradient gains. The prior synthetic
covariance/uncertainty result remains valid only in its documented scope.

Reliable regional transfer and a justified distinction between noise and
legitimate texture remain unresolved. A future model needs explicit support for
those assumptions or a bounded shading target that does not require classifying
all fine variation. Boundary/order protection is independently unresolved; no
new filter port or runtime campaign is queued by these diagnostic results.

Artifacts: `captures/shadow_noise_observations_20261106/` contains selection and
bootstrap code, the coverage screen, dense-input checks, independent holdouts,
calibration, transfer/ambiguity controls, full-source/intensity proxy reports
and verification. Original failed and insufficient-data cases are preserved.
No brightness candidate, fresh material-gradient gain, GPU/temporal validation,
adoption decision, effectiveness score, commit or push follows.
