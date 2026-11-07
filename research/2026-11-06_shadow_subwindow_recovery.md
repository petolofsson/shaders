# Brightness-gradient recovery: sub-window edge-model screen

The user explicitly prioritized bringing both experimental contributions close
to at least 75/100, with brightness-gradient recovery the unfinished work.
The conversational estimates are now recorded separately: brightness recovery
approximately **45**, subtle shadow color **70–75**. These are provisional visual
effectiveness judgments, not completion percentages. The existing chain/grade
78 and joint tonal-model 80 estimates retain their original scope. This screen
does not raise any rating or change production.

## Distinct mechanism and research

Wong's [local statistical edge model](https://arxiv.org/pdf/2105.01951)
uses overall and sub-window variances to distinguish important edges from small
detail. Its preservation factor is the maximum whole/sub-window variance
divided by the minimum sub-window variance plus epsilon, capped at one. The
filter blends the input with its patch mean and averages overlapping patch
estimates. The paper reports gradient-preserving decomposition and applications
to detail enhancement. This motivates testing an alternative boundary model;
it does not establish noise restraint or effectiveness in our SDR pipeline.

Our fixed CPU adaptation operates in continuous sRGB-code-equivalent luminance.
Source observations determine preservation factors at radii 4 and 16 pixels,
with epsilon fixed at four squared codes. Four overlapping quadrant windows
include the center, rather than claiming an exact reproduction of the paper's
equal subdivision. Using the same factors for source and current output gives
a linear joint filter of their code difference. This joint extension and its
enhancement objective are ours, not a published guarantee.

Two factored alternatives test the key noise tradeoff without a parameter sweep:

* Detail recovery: half of `difference − filtered16(difference)`.
* Band recovery: half of `filtered4(difference) − filtered16(difference)`.

Both retain the existing source-shadow eligibility window and apply a common
RGB gain with SDR headroom. Color-only is the comparison output. These are late
offline references requiring finished-output data; no existing-pass runtime
reuse or production implementation is claimed.

## Actual preserved inputs and material results

Reuse the verified same-update pre-dither floating GPU source/current/half-color
readbacks for wall, metal, held timber and noise. All recorded input/clone hashes
and the 17 production identities pass. This work runs CPU calculations on those
inputs; it launches no new GPU process. Historical capture precision and repeat
limits remain those of the dense-readback reports.

Native target rectangles match the earlier dense material selections. Generic
source-signed neighboring pairs use L 12–65, log-Y differences 0.02–0.5 stops,
ab distance below 2 and both axes at four pixels. Report absolute code and L
gaps alongside relative gaps. Overlapping pairs are descriptive, not independent
quality observations. These results compare each variant with the same half-color
baseline, not with the older screenshot or GPU shader candidates.

| Target | Detail: log gap gain | Detail: absolute code gap gain | Band: absolute code gap change |
| --- | ---: | ---: | ---: |
| Wall | +1.55% | +1.73% | −0.39% |
| Metal | +0.41% | +0.34% | −1.31% |
| Held timber | +0.11% | +0.10% | −1.38% |

Native-size metal comparison does not establish visible dimensional improvement.
Larger padded-interior summaries and target-specific metrics are kept separately;
they use different populations and should not be interchanged. The band variant
also adds some selected metal ordering reversals.

## Noise, shading and boundary controls

On the original captured RGB noise fixture, continuous luminance code std rises
**13.24%** for detail recovery and **0.30%** for the band version. The quiet
band version's reduced material separation is not a useful restoration result.

Separate scalar affine-stage fixtures retain the configured black mapping and
use fixed code-domain white and box-correlated noise. Detail raises their std
11.18%/10.56%; band raises it 0.29%/1.87%. Clean period-64 shading increases
7.40%/6.58%, but the smooth ramp remains essentially unchanged (about −0.009%
std change). Synthetic std gains are not real material gains.

Both versions create small reversing rims around a code-16→18 step and its
softened counterpart. Maximum step corrections are about 0.076/0.043 codes.
Source-black remains exactly unchanged in the tested mixed black step. Negative
derivatives on noisy/sinusoidal fields are expected; only the originally
nondecreasing step/ramp controls are used for new-reversal findings.

Independent brute-force rectangle averages agree with the summed-area routine
within 1e-8. Constant and linear-ramp filter checks pass within 1e-9. These verify
finite CPU arithmetic, not shader, temporal or universal ordering behavior.

## Decision

Reject both references for shader work. Replacing the boundary model alone does
not resolve the missing contribution: detail recovery mostly buys noise, while
removing the finest band loses material response. Preserving smooth gradients
in a decomposition base does not mean the extracted detail layer will restore
their brightness range. This distinction helps explain the favorable sine and
unhelpful ramp/material results; it is not a rejection of the published filter.

Further brightness work must explicitly address the **base shading range** and
where its additional contrast budget comes from, while retaining material
endpoints and black behavior. Another interchangeable detail extractor, stronger
gain, or relaxed noise threshold is not justified by this screen. No surviving
implementation proposal or numerical path to 75 follows yet.

Artifacts: `captures/shadow_subwindow_20261106/` contains the model, native
comparisons, full reports, target-specific absolute metrics, independent checks,
dependency identities and manifest. Existing production shaders, profiles,
configs, headers, histories, resources and passes remain unchanged. No active
runtime, adoption request, commit or push is pending.
