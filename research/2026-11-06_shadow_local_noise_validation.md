# Local noise validation and domain-correct propagation

The user asked to validate and follow the lead, expressing optimism about
implementation. This continuation validates part of the noise mechanism and
identifies remaining acceptance problems. A fixed local code-domain reference
reduces added luminance std on the **preserved captured noise fixture** to about
0.56%, versus 38.6% for the original combined reference. Separate synthetic
tests retain roughly 8% row-averaged shading response with restrained noise.
These are offline results, not a compiled brightness shader or real-material
acceptance. All tested real material cells still reject the model; noisy edges
retain rims. Production, profiles, configs, histories, resources, passes and
ratings remain unchanged.

## Validation question and fixed changes

The [previous selector](2026-11-06_shadow_noise_observations.md) pools selected
regions and assumes stationary Gaussian noise in log luminance. Two causes of
rejection need separating: incompatible observations across regions, and noise
that changes variance after a nonlinear domain conversion.

This reference independently samples each fixed 256×256 cell, rather than
borrowing from other regions. A 19×19 grid of 9×9 patches on 13-pixel pitch
provides three column groups for observation, fitting and held-out checking.
The estimation/validation groups have 114 patches each, exceeding the unchanged
75-patch support minimum. The first group remains an observation diagnostic;
no regional energy ranking or cross-cell estimate transfer occurs.

The prior covariance fit, physical-spectrum check, Gaussian bootstrap,
63 draws, p thresholds and support minimum remain unchanged. Analyze
`255*sRGBEncode(source linear Y)` as the primary noise-model domain. Analyze
log Y separately for comparison; accepting either representation after looking
at the results is **not** the acceptance rule. Source code-luminance is a scalar
derived from linear Y, not a claim that per-channel game noise shares that model.

## Domain and actual-input checks

Known 256×256 source-code fields are flat code 16, periodic shading of amplitude
6 codes/period 64, or finer deterministic texture, combined with no noise or
unit Gaussian white/short-range grain. The code-domain model accepts the noisy
flat/shading cases in the initial test. Log-domain validation rejects one valid
white-noise shading case that code-domain validation accepts. This supports
domain mismatch as one real cause of rejection; it does not explain every
previous failure.

Noiseless texture and texture-plus-noise reject in both domains. Noiseless
periodic shading also rejects because its nonzero residual does not fit the
noise model. This causes an undesirable **engagement asymmetry**: the present
reference can enhance a noisy shading field while abstaining on its cleaner
counterpart. It is not a satisfactory general activation rule or evidence of
stable engagement as noise changes.

The existing 512×512 floating GPU source regions split into four fixed cells
each. All **12 wall/metal/timber cells reject** in both representations. The
256×256 captured RGB-noise fixture now has enough local observations and passes
both representations. This confirms an adequate-noise observation contract in
that fixture, not discovery of a valid noise model for actual materials. No
model threshold was relaxed to obtain that result.

## Local code-to-log propagation prototype

The covariance model is learned from the observed source code-luminance in its
own cell. If the code-domain model does not pass, the reference abstains.
For passing cells only:

1. Estimate a smooth latent code field with the fixed 9×9 quadratic prediction.
   Its residual error relative to known clean fields is recorded in controls;
   the latent field is not assumed to be ground truth.
2. Draw 64 Gaussian fields with the fitted nonnegative code-noise spectrum.
   Add each to that latent field, clamp to SDR code range, decode to linear Y
   and convert to log Y. This explicitly propagates the nonlinear conversion,
   rather than reusing code variance as log variance.
3. Form the same four-level Laplacian noise coefficients and local energies.
   Their simulated mean and standard deviation supply the fixed one-sigma
   enhancement-confidence margin.
4. Retain the original source-capped proposed increments, coarse base, source
   shadow window, bounded RGB gain and SDR headroom limit.

This Monte Carlo construction is a **CPU feasibility reference**. It is not
an eight-pass shader design, a runtime-cost claim, or a request to add these
simulations/resources to production. Finite simulation error, fitted-spectrum
error, Gaussian noise assumptions and latent-field error remain. The existing
half-color helper and its chromatic-noise costs are unchanged.

## Measured results

On the captured GPU noise input, readback values feed CPU current/color/combined
evaluation. The earlier full-chain current/half-color values are preserved:

| Variant | Center code-equivalent luminance std | Center ab std |
| --- | ---: | ---: |
| Current | 0.472745 | 0.209700 |
| Half-color only | 0.472097 | 0.260870 |
| Local-noise combined CPU reference | 0.474737 | 0.260862 |

Thus brightness adds **0.56%** luminance std over color-only in this fixture.
That compares with +38.6% for the original combined CPU reconstruction on the
same input and center mask. This is not a fresh GPU brightness output, real
game grain measurement or proof of unchanged chromatic noise across scenes.
The fixture result uses one Monte Carlo seed, not independent simulation-seed
or temporal repeat validation.

Separate scalar synthetic controls use decoded code-domain fields and the
configured affine black mapping as current output, rather than the full grade.
Three fixed source-noise seeds give:

| Condition | Range across source-noise seeds |
| --- | ---: |
| Flat white: added luminance std | +1.77% to +2.13% |
| Flat grain: added luminance std | +2.94% to +3.47% |
| Shading plus white: row-mean std gain | +8.63% to +8.83% |
| Shading plus grain: row-mean std gain | +7.64% to +7.96% |

Row-mean std emphasizes the repeated shading signal but retains finite residual
noise. It is not a real-material neighboring-shade metric or fidelity score.
These new code-domain fixtures differ from the previous additive-log fixtures
with roughly 15% shading response. Do not compare their percentages as a
candidate ranking without matching inputs and signal amplitudes.

## Locality and noisy-edge stress

Independent local flat fields at code 16/48 with noise sigma 1/3 estimate
variance about 0.983/8.851 versus truth 0.995/8.955. Their added luminance std
ranges about 0.44–2.11%. The reference never borrows the sigma-1 estimate to
control the sigma-3 field. This checks the local contract in known conditions;
it does not supply full-frame region boundaries, coverage, overlap blending or
safe cross-region interpolation.

Noiseless small and softened steps abstain exactly. With unit white noise,
both pass the model and acquire correction rims: row-averaged profile excursions
relative to plateau correction are approximately −0.205/+0.216 code for the
small step and −0.272/+0.294 code for the softened step. Low noise amplification
does **not** fix final boundary/order behavior. Those fractional-code profile
values are not independent evidence of invisibility.

## Decision and next work

There is validated conditional progress on noise representation, local support
and propagation. It does not establish that the combined brightness/color goal
is close to implementation: the material model rejects all tested real cells,
engagement differs between clean/noisy shading, noisy rims remain, and the Monte
Carlo reference is not a proposed runtime architecture. Do not activate it,
relax acceptance to force material engagement, or present synthetic shading
gains as retained wall/metal/timber gains.

The next useful design work is a supported material/shading model with stable
engagement and final boundary restraint. Keep the local code-domain noise result
as a benchmark for that design, rather than returning to region-wide log-noise
transfer or more automatic threshold tuning. No new GPU capture, actual-config
validation, motion, performance profiling, score change or publication follows.

Artifacts: `captures/shadow_noise_local_validation_20261106/` preserves local
domain checks, the CPU prototype, three source-noise-seed controls, the captured
noise-fixture evaluation, noisy-edge/local-level controls and verification.
All old failures and the earlier source/profile/config epoch remain intact.
