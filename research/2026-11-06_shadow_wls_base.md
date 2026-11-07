# Research: coherent brightness transfer through a common base

The user requested more research. This screen changes the decomposition rather
than weakening the rejected noise classifier. A fixed WLS-style common-guide
reference engages continuously on clean and noisy shading, preserves calculated
source-black correction after anchoring, and retains small real-material
brightness responses. It is a research direction, **not a shader adoption
candidate**: appearance gains are subtle, stronger noise costs remain, centering
is crop-based, and no practical fixed-pass runtime design is established.
Production, profiles, configs, histories, resources, passes and ratings remain.

## Research basis and distinction

Farbman, Fattal, Lischinski and Szeliski's
[edge-preserving decomposition paper](https://www.microsoft.com/en-us/research/wp-content/uploads/2008/08/Farbman-EPD-small-SG08.pdf)
uses weighted least squares to form coarse bases and residual details. It
discusses how distorted base edges can produce halos on recombination and
acknowledges ambiguity in deciding which features to preserve. Its formulation
motivates testing structure at a chosen scale without declaring all fine
variation to be noise. The paper does not validate our transfer rule, noise
targets, color behavior or game-agnostic application.

The new CPU reference uses source log luminance for common positive smoothing
weights and operates on source/output **code-luminance difference**. It is not
the paper's complete multiscale tone tool. Parameters are fixed at lambda 0.125,
alpha 1.2 and epsilon 1e-4; the lambda value is our reference choice, not a
claimed published default. No strength/scale sweep follows.

## Common-base and anchored transfer

Let s be post-inverse source linear RGB, o the half-color pre-dither output,
and C denote 255*sRGBEncode(Y). Build one positive symmetric WLS operator from
the source guide ln(max(Ys,1e-5)), with cardinal weights
`lambda / (abs(guideDifference)^alpha + epsilon)`.
Solve `(I + weightedLaplacian)*b = Cs−Co`. With a fixed guide this is equivalent
to smoothing source and output with the same linear operator then subtracting.
It avoids independently constructed bases and per-coefficient source caps.

The first diagnostic adds half the centered b to current code luminance. It
preserves the crop mean but shifts the black side of a mixed black/gray step
by about 0.74 code. That **unanchored diagnostic is not retained as a candidate**.

The fixed follow-up uses the existing profile BLACKS value (0.0025 in both
profiles) and the prior source shadow window's upper fade:

```text
w = Ys/(Ys + BLACKS) * (1 − smoothstep(0.08, 0.15, Ys))
reference = sum(w*b)/sum(w), with an unavailable-weight guard
deltaCode = 0.5*w*(b − reference)
targetCode = currentCode + deltaCode
```

Zero source Y has zero calculated correction. Constant fields have zero
correction to numerical precision. The weighted centering preserves total code
mean before any SDR/headroom restriction. After decoding target Y, a common RGB
gain and headroom limit retain current RGB ratios. No clipping or headroom
limit engages in the measured anchored cases. These are CPU properties, not
GPU zero-bypass, universal order or gamut-continuity contracts.

The anchor is a consequence of the existing black setting, not a new profile
choice. No user control, auto-exposure target or production tone map is added.
The centering reference currently comes from the analyzed crop; that is not a
valid substitute for a specified full-frame/runtime reference.

## Numerical validation and synthetic behavior

The diagonal-preconditioned conjugate-gradient solver reaches actual relative
residuals below 1e-9 in the recorded fields. A separate small dense system built
from the energy definition agrees within 1e-8, preserves constant row sums and
has minimum eigenvalue near one. No measured base violates its scalar input
minimum/maximum. Some cases require several hundred iterations; this is not a
fixed-pass shader implementation or performance measurement.

The anchored scalar controls use source code values, the configured affine
black mapping as current output, and no complete grade/color pipeline:

| Fixed synthetic condition | Anchored diagnostic |
| --- | ---: |
| Clean code-16, amplitude-2/period-64 shading: std gain | +7.3% |
| Same shading plus unit white noise: row-mean std gain | +8.6% |
| Flat unit white noise: added std | +1.8% |
| Flat unit correlated grain: added std | +3.3% |
| Clean small step: plateau distortion | about 0.004 code |
| Noisy small step: plateau distortion | about 0.032–0.035 code |
| Soft step: plateau distortion outside its transition | about 0.005 code |

The clean/noisy response is continuous here; no model-acceptance gate disables
the clean case. Row-mean std still contains finite residual noise and is not a
real-material or fidelity measure. Source-black correction is zero in the
constant/black-step/ramp controls, and the full neutral ramp remains ordered.
The ramp's whole-range std changes about −0.22%; enhancement is not uniform.
Remaining small step distortions are not labeled halo-free.

Two independent source-noise seeds retain about +1.82–1.84% unit-white and
+3.21–3.29% unit-grain amplification. At three times the noise amplitude, costs
rise to about +4.02–4.04% white and +5.56–5.61% grain. The source guide therefore
still treats some stronger grain as structure. Do not call this solved noise
control or adjust thresholds to hide these cases.

On the preserved captured RGB-noise input, CPU evaluation gives luminance std
0.472097 color-only → 0.478011 anchored, about **+1.25%**, with ab std 0.260862
versus prior color-only 0.260870. This is weaker noise suppression than the
previous Monte Carlo prototype's +0.56%, but avoids that model's hard region
rejection. The color helper's prior chromatic-noise cost remains. No new GPU
brightness output or actual-game temporal-noise result is claimed.

## Dense material reference

Use the same verified source/current-half-color floating GPU inputs, larger
native crops and source-selected overlapping pair masks as previous reports.
No screenshot dither is used in the measurements. CPU previews use approximate
encoding/dither and are not compiled candidate screenshots.

| Material | 4-px signed log-Y gap gain over color-only | Mean Oklab L change | Reversed 4-px pairs: prior → anchored |
| --- | ---: | ---: | ---: |
| Wall | +0.96% | +0.0197 | 47 → 40 |
| Metal | +3.91% | +0.0159 | 301 → 178 |
| Held timber | +3.16% | +0.0088 | 6 → 4 |

The diagnostic engages on these real inputs, unlike the rejected covariance
classifiers. Native images show subtle shading/texture changes without an
established clear overall naked-eye improvement. Larger gaps and fewer selected
reversals are explanatory metrics, not acceptance or universal order guarantees.
No new whole-chain effectiveness score follows.

A centering-only context proxy holds the filtered base fixed and derives the
reference from each half of the same crop. The selected 4-px gaps stay close to
the whole-crop values: wall 0.07667–0.07683, metal 0.13983–0.13997 and timber
0.15213–0.15237. This does not rerun the filter under actual cropping, establish
full-frame centering, or validate composition changes/motion/cuts.

## Limitations and next lead

Retain this as a coherent-base research reference, not an implementation queue.
It has more stable engagement than the noise classifier and lower measured
step distortion in the stated controls, but smaller material gains and remaining
noise costs. Full-frame centering, nearby-material/highlight cooperation, strong
noise, temporal stability, quantization and a practical runtime decomposition
remain open. Source/current differences also contain intentional grading, not
only loss from the black offset; recovering them indiscriminately is unjustified.

Before a GPU trial, determine whether a specified full-frame reference and a
plausible fixed-pass base can retain a visibly worthwhile benefit. Do not port
the iterative solver, turn this into a profile/strength search, or claim that
the existing eight passes already implement it. Preserve the prior Monte Carlo
noise result as a benchmark, with its different fixtures and activation failure.

Artifacts: `captures/shadow_wls_base_20261106/` contains the fixed solver,
unanchored/anchored controls, dense native comparisons, strength-of-noise
holdouts, captured-noise evaluation, centering proxy and numerical/audit records.
An initial soft-step plateau metric incorrectly included part of the transition;
`initial_soft_step_including_transition.json` preserves it. The corrected metric
excludes that interval; filtering was unchanged. Generators refuse overwriting
the preserved outputs. No new GPU runtime, profile/config/header/history/pass
change, adoption decision, score, commit or push follows.
