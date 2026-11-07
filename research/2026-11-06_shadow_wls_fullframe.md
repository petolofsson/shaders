# Full-frame WLS and fixed-pass feasibility screen

The user asked to continue the cautiously promising [common-base lead](2026-11-06_shadow_wls_base.md).
Six full-frame CPU proxies and two guided-base references now weaken its case
for implementation. Selected timber/metal response remains, but full-frame
centering changes density and reduces other material separation. Cheap guided
forms trade useful detail against noise and are not interchangeable with WLS.
Do not advance this late full-grade transfer to a GPU trial or adoption.
Production/profiles/configs/histories/resources/passes/ratings are unchanged.

## Full-frame scope

Keep the fixed WLS solver, source-relative black anchor, half transfer strength,
upper shadow fade and weighted reference. Derive the reference from every pixel
of the full input/output image rather than the earlier padded material crop.
Six cases cover GZW dark/interior, independent warm timber/pack, daylight,
vivid content and Arc emitters. All inputs match preserved hashes/current
production/profile epochs. The daylight image is 2552×1439; others are 2560×1440.
The full solver handles their actual dimensions and reaches relative residuals
below 1e-9 in 764–923 iterations. These are numerical convergence observations,
not runtime performance measurements.

This is an **8-bit source/output PNG proxy**, not new floating GPU output.
GZW dark and Arc interior use separately captured grade-input PNGs. The other
four use the original source PNG as an approximation to post-inverse input.
Existing output screenshot dither is retained; no second dither is added.
New output encoding/rounding and separate source-state precision remain limits.
The before-quantization metrics below use decoded PNG inputs; they are not
pixel-exact shader contracts or proof of real-game temporal noise behavior.

The full-frame reference changes considerably between scenes, for example
about −0.967 code for GZW dark, +0.938 Arc interior, −1.618 held timber and
+8.06/+8.25 daylight/vivid. These are the source-minus-output base references,
not exposure values. Exact mean centering does not prevent local density changes
or establish stable behavior as composition changes.

## Material results and density attribution

Use the existing fixed source regions and overlapping source-selected 4-pixel
pairs: L 12–65, log-Y gap 0.02–0.5 stops and small ab distance. Compare with
the same half-color-only baseline. In addition to the prior relative log-Y gap,
measure absolute code-luminance and Oklab-L gaps on exactly those pairs.

| Region | Relative log-Y gap change | Absolute code-Y gap change | Absolute L gap change | Mean L change |
| --- | ---: | ---: | ---: | ---: |
| GZW shelf | +1.15% | −1.85% | −1.27% | −0.398 |
| GZW wall | +0.90% | +1.05% | +1.02% | +0.040 |
| Arc dark metal | +3.54% | +1.40% | +1.82% | −0.337 |
| Arc warm floor | −4.20% | −3.32% | −3.49% | +0.194 |
| Arc cool upper | −3.21% | −3.20% | −3.23% | +0.343 |
| Held rear timber | +3.25% | +3.02% | +3.04% | −0.025 |
| Held lower timber | +3.15% | +2.92% | +2.94% | −0.042 |
| Held warm pack | +3.51% | +2.38% | +2.57% | −0.181 |

The shelf demonstrates why a larger relative gap alone is insufficient: darker
mean levels accompany a smaller absolute difference. Metal retains some absolute
response, but less than its relative metric suggests. Timber retains a small
absolute gain. Native comparisons remain subtle and do not establish a clear
overall appearance improvement sufficient to justify the added architecture.

Other selected proxy changes are mixed: daylight foliage relative gap +1.9%,
vivid blue field +1.6%, cool window +0.6%, red lamp region +1.3%, with small
lit-paving/blue-sky losses. These are limited regional descriptions, not quality
scores or universal palette/highlight contracts. Full-image changes reach
4/7/10/4/5/6 codes across dark/interior/held/day/vivid/emitter respectively.
No new all-channel-black pixels or channel-255 samples are counted.

The emitter ROI named white core contains darker surrounding pixels. The broad
source-L-12–65 pair metric deliberately excludes its bright center and must not
be labeled core damage. Separate original source masks find **31,470 core and
38,528 halo pixels unchanged** in the quantized emitter proxy. Preserve this
distinction rather than using mixed-ROI mean changes to claim highlight loss.

## Fixed-pass guided feasibility

He and Sun's [fast guided-filter note](https://arxiv.org/abs/1505.00996) motivates
computing guide statistics at reduced resolution and reconstructing from
upsampled coefficients. We test two fixed CPU forms on the preserved dense
floating inputs, using 1/8 area reduction, a 7×7 low-resolution box, and the
active grade's variance-relative regularizer constants. This adapts the joint
filter to source/output code difference; it is not an exact reproduction of
the paper, WLS, or the current shader's self-guided base.

1. **Native-guide reconstruction:** upsample averaged coefficients and evaluate
   on the full-resolution source guide. This retains more fine response but
   also reintroduces noise through the guide.
2. **Coarse-base reconstruction:** evaluate the base on the reduced guide and
   upsample that result. It suppresses noise but loses much of the fine response.

All parameters are fixed; there is no bandwidth/strength sweep. The current
CPU reference only accepts dimensions divisible by eight. Non-divisible GPU
allocation/sampling contracts remain unimplemented for these approximations.

| Dense/synthetic measurement | Native-guide form | Coarse-base form |
| --- | ---: | ---: |
| Unit white noise: added std | +8.1% | +0.08% |
| Unit correlated grain: added std | +8.1% | +0.96% |
| Dense wall 4-px relative gap gain | +3.5% | +0.28% |
| Dense metal 4-px relative gap gain | +7.8% | +1.06% |
| Dense held timber 4-px relative gap gain | +5.8% | +0.74% |
| Clean small-step left plateau distortion | 0.013 code | 0.059 code |
| Noisy small-step left plateau distortion | 0.023 code | 0.061 code |

This confirms the suspected tradeoff rather than a ready substitute. Source
black weighting and scalar/headroom guards remain, but those do not make the
decompositions equivalent. Near-constant-field std ratios are not meaningful and
are omitted; the actual recorded near-zero variances remain in the JSON.

The active [grade](../general/grade/grade.fx) computes its guided base before the
finished graded output exists. A filter of source-minus-**finished-output**
difference cannot simply reuse that existing content. A late implementation
would need an output surface and filtering/reference/composite work, while the
current iterative WLS solver is not a fixed-pass design. No performance claim,
pass-count promise, shader patch or new GPU resource follows from these CPU
references.

## Decision and next lead

The full-frame/native checks do not justify adopting or porting this late
source/output-transfer version. Do not strengthen it to make the small gains
more visible, hide losses behind the relative-gap metric, or tune guided-filter
parameters until the local examples pass. Retain the original base decomposition
as research evidence, with the new full-frame limitations superseding its earlier
cautious promise as an implementation lead.

The more defensible next design question is **stage-specific cooperation**:
target the known black-offset contribution before subsequent grading, rather
than treating every source/finished-output difference as lost detail. Such a
model could leave intended tonal/color decisions downstream and might make its
input available before the existing tonal passes. That is an unvalidated lead,
not a claim that spare channels, current resources or the eight passes already
support it. Establish its mathematical behavior and full-chain appearance before
changing production, producers, histories or configuration.

Artifacts: `captures/shadow_wls_fullframe_20261106/` contains solver records,
full-frame PNG proxies, native comparisons, saved bases, `absolute.json` and
[review](../captures/shadow_wls_fullframe_20261106/review.html).
`captures/shadow_wls_guided_20261106/` holds the two fixed reconstruction forms
and their controls. Saved float32 bases reconstruct the absolute-gap diagnostic;
its reference agrees within 1e-5 code with the original float64 computation.
All original crop evidence, failed/rejected models and input identities remain.
No new GPU run, active shader/profile/config/history/resource/pass/rating change,
adoption question, commit or push follows.
