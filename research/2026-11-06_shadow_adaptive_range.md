# Scene-learned shadow curves and robust-base allocation

The user asked for new ways to improve brightness gradients, with both new
shadow contributions eventually near at least 75/100. This continuation tests
two different range-allocation mechanisms, rather than another interchangeable
detail filter: rank-shape transfer and a spatial-pair contrast-budget fit.
Neither supplies sufficient visible improvement for shader implementation.
Brightness recovery remains approximately 45, subtle color 70–75; these scoped
judgments do not replace the existing chain/grade 78 or tonal-model 80 estimates.

## Research and the specific change in approach

[Mantiuk, Daly and Kerofsky](https://www.cl.cam.ac.uk/~rkm38/pdfs/mantiuk08datm.pdf)
formulate display-adaptive tone mapping as constrained minimization of visible
contrast distortion. Their display/perception model and video treatment are
not reproduced here. The applicable design principle is to account for the
available tone range and competing contrast demands explicitly. Our inference
is that a scene-derived curve could avoid the earlier shelf-fitted curve's
held-timber loss, and that applying its correction to a robust brightness base
could retain broad shading without scaling all fine variation.

First verify that there is an absolute loss to address. In the preserved
same-update floating target crops, current half-color versus source mean signed
four-pixel **absolute code-luminance gap** ratios are 0.908 wall, 0.793 metal
and 0.855 timber. Their relative log-gap ratios are 0.899/0.696/0.793.
This selection has actual absolute compression as well as relative compression;
source reproduction is still not an unconditional preference target.

## Model 1: rank-shape transfer with a robust base

Estimate 9×9 median brightness bases in continuous sRGB-code-equivalent Y.
Median filtering preserves an interior linear ramp and a straight step without
the averaging across that step characteristic of a blur. It is not a semantic
material/shading separator and can remove legitimate fine structures.

For eligible shadow samples, measure 65 source/current base quantiles from
1% to 99%. Offset the source quantiles to preserve the current shadow median,
then use their monotone correspondence as a scene-learned curve. Pin its range
endpoints at codes 0 and 128. Transfer half the curve correction through the
existing source-shadow gate. Compare evaluating the curve directly on each
pixel with adding its correction from the median base while retaining the
current pixel's fine code-domain residual. Apply a common RGB gain and SDR
headroom bound. No chosen shelf pivot or profile search is used.

Initial crop-local CPU tests recover clean/noisy ramp std about 7.94%/7.80%,
and create no new reversing rows on the tested monotone step/soft-step fields.
The captured RGB noise patch gives +0.26% std for the base variant when its
curve is fitted on that patch. These are conditional controls, not an accepted
real-material result or noise guarantee in another scene.

An initial implementation incorrectly used constant right extrapolation from
`np.interp` above code 128. A dense metal crop then had a calculated correction
as large as 51.8 codes. **That version is invalid**, retained in the top-level
`report.json`, arrays and previews. It is not reclassified as the corrected
model. `fullframe.py` explicitly restores identity above 128; the independent
endpoint counterexample in `verification.json` records both behaviors.

Six complete-image CPU proxies then fit each curve from its entire scene,
not a selected material crop. Two use separate 8-bit grade-input diagnostics;
four use original-source PNG approximations. Output is the preserved half-color
screenshot, already dithered/quantized. No second dither is added. These are
not floating whole-scene inputs or captures of a compiled brightness candidate.

| Full-scene curve | Shelf absolute gap | Metal absolute gap | Rear/lower timber absolute gap |
| --- | ---: | ---: | ---: |
| Point evaluation | −12.26% | +1.60% | +7.02% / +7.86% |
| Median-base correction | −22.13% | −5.35% | +1.06% / +1.13% |

Warm floor/cool upper also lose separation. Native shelf darkens and flattens.
The rank correspondence confuses different scene populations with a desired
shading response. Reject it. Actual source-selected emitter core/halo pixels
remain unchanged in both corrected proxies; changes to surrounding dark pixels
inside broad region rectangles are not changes to the highlight cores.

## Model 2: an explicit spatial-pair contrast budget

Use observed source/current median-base differences across 16 and 32 native
pixels, sampled on a deterministic four-pixel grid. Keep same-direction
differences, source-code gaps 0.25–8, shadow eligibility and small color
differences. This is a structural selection, not a calibrated noise model.
Request half the missing absolute code gap, capped at 25% of the current gap.

Fit a 65-knot correction over codes 0–128 with fixed range endpoints, a zero
sampled mean correction, an identity penalty and a curvature penalty. A linear
solve handles the equality constraint; uniform scaling limits the underlying
curve's slopes to 0.75–1.25. Additional slope in one range must therefore be
paid for elsewhere. This is our fixed exploratory quadratic objective, not the
paper's perceptual optimizer or a demonstrated optimal visual tradeoff.

The first fit omitted the final source gate from its observation matrix.
`pair_budget/` preserves that incomplete forward model and its results.
`forward_budget/` keeps the same target, regularizers, sampling and bounds but
includes the actual gate in both pair rows and the mean constraint. This is a
model correction, not a strength/pivot sweep. The equality applies to sampled
eligible code correction, not exact full-frame RGB means, exposure or every
material mean. The base curve's monotonicity also does not prove that the gated,
spatially varying final RGB result preserves every input ordering.

| Corrected fit, point evaluation | Absolute four-pixel code-gap gain |
| --- | ---: |
| Shelf / blue wall | +1.02% / +1.34% |
| Dark metal / warm floor | +1.34% / +0.19% |
| Cool upper / cool window | +0.01% / +0.99% |
| Rear / lower timber / warm pack | +1.53% / +1.90% / +1.16% |

The median-base version largely loses those fine gains and loses 0.77% on the
warm pack. Native shelf comparisons show no clear dimensional improvement.
These results avoid much of the rank model's material damage but remain small.

## Context, broader shading and controls

Transfer the fixed whole-scene curves to the preserved dense floating target
crops. This is mixed-stage CPU calibration, not same-update full-scene fitting.
For the corrected pair model's median-base version, absolute code-gap gains at
16/32/64 pixels are wall 0.54%/0.73%/1.00%, metal 0.87%/1.08%/1.58%, timber
0.97%/1.30%/1.83%. Point evaluation retains about 1.3–2.2% across these controls.
Larger-scale measurements do not reveal a hidden large shading improvement.

Crucially, do not evaluate noise only with a curve fitted on noise. Apply the
learned GZW-dark, Arc-interior and held curves to the same captured noise field.
The corrected pair model adds about 1.87%/6.00%/5.21% code-luminance std with
point evaluation, versus **0.058%/0.178%/0.067%** through the median base. The Arc
curve on this fixture is a context stress, not a new actual Arc noise capture.
The quiet outputs also move that flat patch's mean by about +0.093/+0.261/−0.075
codes. Low noise amplification does not establish unchanged density.

Separate affine-stage synthetic controls under these same fixed curves retain
zero tested black-source change and no reversing rows on ramps/soft steps.
White/grain std costs through the base are about 0.03–0.17% / 0.20–1.22%.
However, the independent ramp's std changes −0.51%/−2.30%/+0.08% across contexts.
Thus the crop-local ramp recovery does not generalize to a different curve.
Noisy/sinusoidal derivatives are not interpreted as ordering defects.

Brute-force median checks are exact. Fitted endpoint, sampled mean and base-curve
slope checks pass; finite synthetic RGB remains within SDR bounds. All recorded
production and capture-input identities pass. Empty pair populations in the
rank full-frame report retain NaN summaries and their zero counts; they are
excluded from gains/acceptance claims. No GPU, motion, temporal convergence,
performance, actual-config or adoption contract is implied by these CPU checks.

## Decision and continuation constraint

Do not port either model or raise the brightness score. Rank matching has
substantial material costs; the forward-consistent pair budget is a more
coherent diagnostic but has insufficient visible return. Its quiet median-base
path is worth retaining as a finite benchmark, not an implementation proposal.

This narrows the next design question: how to allocate shading range using
spatial context and credible material boundaries, instead of one scene-wide
histogram or curve. Simply increasing a gain or loosening the existing budget
would not answer the independent-ramp and material-context failures. Any spatial
version must explicitly challenge boundary leakage, fine-structure loss,
context changes and movement before adding runtime machinery.

Local artifacts: `captures/shadow_rank_base_20261106/`, including the invalid
initial interpolation, six corrected rank proxies, both pair-fit epochs,
native comparisons, [review](../captures/shadow_rank_base_20261106/review.html),
context tests, numerical controls, dependencies and manifest. No new GPU process
ran. Production, profiles/configs, headers, histories/resources/passes and ratings
remain unchanged. No active runtime, adoption question or publication is pending.
