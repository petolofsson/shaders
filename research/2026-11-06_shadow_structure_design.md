# Structure confidence and full-chain base design

## Decision

Do not implement the tested scale-confidence correction. Aggregating evidence across pixels separates the synthetic noise from a smooth sinusoidal signal better than the earlier pixel thresholds, but the correction still creates opposing step rims and leaves a smooth ramp unchanged. An exact paired-base grade evaluation is also not yet justified: in the affine limit it reduces to the already rejected shared-offset mechanism. More accurate evaluation alone does not supply the missing edge/noise restraint.

Production, profiles, configs and ratings remain unchanged. This report records a failed feasibility model and an analytical design constraint; it does not reject every spatial or temporal approach.

## Research and inference

[Eilertsen, Mantiuk and Unger, Real-time noise-aware tone mapping](https://computergraphics.on.liu.se/rntm/) combines contrast-distortion control, detail extraction and noise-visibility control. Its HDR video pipeline and display/camera assumptions do not establish a suitable SDR game-noise model for this chain. The relevant design lesson is to account for detail and noise together, rather than classify every small difference as useful shading.

[Shu and Wu, Locally Adaptive Rank-Constrained Optimal Tone Mapping](https://doi.org/10.1145/3225219) formulates tone mapping around local order constraints. That published objective supports explicitly checking order, but is not proof that a cheap neighborhood approximation or our projected/quantized outputs preserve it. The previous graph and constrained local-Laplacian experiments retain their failures; this research does not reopen them.

Our inference: spatially aggregated evidence might retain coherent shading that per-pixel one-code thresholds suppress. Test that distinction before another GPU candidate.

## CPU scale-confidence probe

The ignored script `captures/shadow_scale_confidence_20261106/probe.py` uses scalar source linear Y and the actual affine stage `y=0.9925*x+0.0025`. It compares source and output log-Y bands between Gaussian sigma 2 and 8 pixels. Local source-band energy, averaged at sigma 8, is compared with the band variance predicted for hypothetical independent uniform -1/0/+1 sRGB-code error. The calculation uses the squared impulse-response norm; this assumes locally stationary independent error, not a calibrated game-noise distribution.

Half the missing band is multiplied by a clipped Wiener-style confidence, a near-black/upper-shadow window and a strong-edge suppression field, then bounded to ±0.15 stops. The output is a common luminance gain. Fixed parameters define one feasibility model; no parameter search was run. Gaussian convolutions and the maximum filter are implemented with NumPy. An initial attempt could not import SciPy and produced no results; the successful standalone rerun is the recorded result.

Controls are 128×512 scalar fixtures. Quantities below are continuous encoded code equivalents, before rounding; this is not final shader/dither behavior. Interior statistics exclude 32 vertical and 64 horizontal boundary pixels.

| Fixture | Result |
| --- | --- |
| Flat code 16 | Zero correction |
| Independent code 16 ±1 noise | Encoded std 0.645343→0.645889 codes, about +0.085% |
| Code 16 ±1, 64-pixel-period sine | Encoded std 0.559371→0.582071 codes, about +4.1% |
| Code 8→40 smooth ramp | Zero correction in the measured interior |
| Code 16→18 step | Output falls 0.00004925 linear below the low plateau and rises 0.00005536 above the high plateau; flat-side row reversals appear |
| Code 16→96 step | Dark-side undershoot 0.00006505 linear despite strong-edge suppression |

The large-step mask can suppress the center while the wider band-filter support still changes its surrounding plateau. Thus reduced noise response does not establish safe edges. The sine/noise contrast is promising only as a signal-selection observation; the ramp and step results reject this correction as a shadow-gradient solution. Ordinary decreasing portions of sine/noise fixtures are not ordering defects; the script's negative-step counts only diagnose reversals directly on the originally nondecreasing step/ramp fixtures. Results are in `synthetic.json`. No real-image, GPU, color, translation, measured motion, or performance result follows.

## Why another fixed curve cannot solve the held tradeoff

Let `u=log2(Y)` and a scalar output curve be `v=u+c(u)`. If it returns to identity at both ends of a finite interval, then `c(b)-c(a)=0`, hence the integral of its relative slope adjustment `c'` is zero. Any nonzero interval with slope above one must be compensated by slope below one elsewhere. Requiring slope at least one everywhere and identity at both ends forces identity throughout (for an absolutely continuous curve).

This does not forbid useful curves or establish a perceptual requirement of unit slope. It explains why moving the compact curve's knots merely reallocates the contrast cost. Its independent timber failure is consistent with this constraint; a different training set cannot remove the budget. Brightness shifts or changes in which regions pay the cost can be artistically valid, but are not evidence of universally preserved shadows.

## Exact paired-base proposal: check before GPU work

A more faithful reference could evaluate the actual grade twice at the same UV/context: once on pixel `x` and once on brightness base `m`. A source-shading reconstruction would use `G(m)*x/m`, and compare it with ordinary `G(x)`. This would be more exact than independently smoothing output screenshots, but still needs a valid base, chroma treatment and black protection, plus duplicate evaluation or additional storage.

In the affine case `G(x)=a*x+B`, the reconstructed result is `a*x+B*x/m`; its difference from the original is exactly `B*(x/m-1)`. That is the mechanism in the previous [shared-offset feasibility](2026-11-06_shared_offset_feasibility.md) and [failed synthetic screen](2026-11-06_shared_offset_synthetic.md). Exact base evaluation therefore does not, by itself, address the known black-boundary, noise or rim failures. We should not pay for a full GPU experiment solely to recover this known limit.

The remaining implementation gap is specific: establish evidence for selecting meaningful source shading while preserving boundaries, black behavior and subtle colors. Aggregate scale confidence alone fails; exact evaluation alone fails in the affine limit. A future design needs an additional justified distinction or an explicitly accepted visual tradeoff, before adding resources or attempting adoption validation. The original provisional color candidate retains its neutral-source and ordering limitations.
