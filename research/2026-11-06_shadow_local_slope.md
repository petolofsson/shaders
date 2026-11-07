# Local-slope reconstruction: feasibility and failure

**Do not implement this version.** A local planar-shading classifier plus gradient integration improves a clean gradual ramp while preserving the tested independent noise and hard steps. It fails more representative controls: the noisy ramp is suppressed, a blurred step acquires rims, and integrated correction leaks into black next to a ramp. No production, profile, config or rating changed.

## Distinct mechanism

The previous scale-band correction misses a ramp because subtracting two symmetric blurs removes a locally linear signal. This model estimates its **slope** instead. It smooths source and output log luminance at Gaussian sigma 4, compares their spatial gradients, and requests half their difference where a local plane explains the source variation.

For source local variance `v` and gradient of its Gaussian mean `g`, the explained variance approximation is `16*dot(g,g)`. Confidence fades from zero to one over explained/total variance 0.8–0.95. A tiny variance gate prevents floating-point cancellation from classifying constant plateaus as structure. The usual source-luma window protects the eligibility of very dark and brighter pixels. This is an exploratory classifier, not a calibrated statistical test or game-noise model.

The desired correction gradient is integrated with a screened least-squares solve: minimize squared gradient error plus `0.0001*sum(delta²)`, using natural boundaries. Conjugate gradient stops below a relative residual of 1e-6 or 600 iterations. The solved log gain is then clamped to ±0.15 stops. This is a global offline reference, not a practical shader or an order-constrained solve. In particular, source eligibility gates the requested gradients, not the final gain; the solve can propagate correction into ineligible pixels.

Script and results: `captures/shadow_plane_gradient_20261106/probe.py` and `synthetic.json`. It reuses only the NumPy filtering/math helpers from the preceding scale probe. Inputs are 96×384 scalar synthetic source images; the reference output is the current affine stage `0.9925*x+0.0025`, not the full chain. Std values are continuous sRGB code equivalents before quantization, measured with an interior crop. There is no GPU or game-image claim.

## Controls

| Fixture | Outcome |
| --- | --- |
| Constant black, constant code 16 | Unchanged |
| Independent code 16 ±1 noise | Unchanged |
| Hard code 16→18, 16→96 and 0→16 steps | Unchanged |
| Clean code 8→40 ramp | Std 5.9611→6.2538 codes, about +4.9%; no reversed row steps |
| Same ramp plus independent ±1-code noise | Zero correction: desired shading is suppressed with noise |
| Code 16 ±1, 64-pixel-period sine | Std 0.55935→0.66692 codes, about +19.2% |
| Code 16→18 transition spread over 16 pixels | Undershoot 0.00004753 and overshoot 0.00005397 linear beyond the original plateaus; reversed flat-side steps |
| Ramp with a black plateau | Black output changes by up to 0.00022825 linear; nondecreasing source gains reversed steps |

Negative row-step counts on the noise and sinusoid are expected and are not classified as defects. The relevant new reversals are on the originally nondecreasing soft-step and black-ramp fixtures. Nonzero solver residual is not the explanation: the failed one-dimensional cases converge far below 1e-6. Final gain clipping and a globally coupled solve do not enforce pixel eligibility or monotonicity.

These controls show why the first successful hard-step and clean-ramp tests are insufficient. A blurred material boundary can contain a locally plane-like interval; the classifier activates there, and gradient integration changes nearby plateaus. Independent noise lowers plane-explained variance even when real shading is present. Flat-black identity in isolation does not protect a black region in mixed content.

## Consequence for the next design

Neither a stronger plane classifier nor arbitrary smoothing is justified by this result. A useful continuation would need a concrete improvement to both **signal estimation in noisy shading** and **constraints on the reconstructed output**, rather than treating confidence on the requested gradients as final-output protection. An exact-black condition, boundary/order constraints, and a justified noise assumption would have to be part of that model from the beginning. The prior constrained-Laplacian and graph failures remain relevant warnings: adding constraints can erase the already subtle benefit.

The source images alone cannot unambiguously label a soft transition as material boundary versus lighting. That ambiguity is a design limitation, not proof that the user's goal is impossible. These rejected versions do not justify a new pass, history, sharpening effect, parameter sweep, shader activation or score increase. The provisional shadow-color lead retains its separate neutral-source and palette risks.
