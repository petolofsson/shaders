# Retinex edge halo attribution — 2026-10-24

The accepted private motion course exposed outlines around clearing structures
and colored targets. Held-frame attribution uses the exact cached source pose
1044/token 262, five fresh private processes, a 20-second continuous settle,
and full/repeat, Retinex-off, zone-contrast-off and both-off captures. Bypasses
use temporary profile copies; both user tuning profiles are unchanged.

The source sky is exactly RGB (89,140,199). A source-selected crop at
(x,y)=(700,200)–(1800,950) excludes foliage-heavy regions and contains the
structures and targets. Bands measure Chebyshev distance to a non-sky source
pixel. All selected source pixels have Oklab L=62.9419. This uniform source
makes the added border shading directly visible, independent of whole-frame
change magnitude or preferred global grade.

| Output | Median L, 0–4 px from edge | Median L, >96 px | Gap |
|---|---:|---:|---:|
| Full | 52.2868 | 55.8476 | 3.5608 |
| Full repeat | 52.2868 | 55.8476 | 3.5608 |
| Retinex off | 51.6304 | 52.2226 | 0.5921 |
| Zone contrast off | 52.5508 | 56.0715 | 3.5207 |
| Both off | 52.2868 | 52.2868 | 0.0000 |
| Candidate | 55.4778 | 55.8476 | 0.3698 |

The visible broad outline largely follows Retinex's edge-dependent strength
fade. Its disagreement mask suppresses normalization near an edge, while a
neighboring uniform part of the same sky receives it. The full pipeline thereby
adds a border to a flat field. Disabling zone contrast does not remove it;
Retinex-off largely does. Remaining zone shading is smaller and separate.

## Candidate and adopted change

Keep the existing bounded log illuminant gain, highlight protection, scene
statistics and manual gate. Use the existing global confidence/settling factors
for Retinex strength, without its coarse-edge disagreement fade. Zone contrast
keeps its existing local confidence. This changes no creative value or gain
bound. The candidate's distant sky median is unchanged while the border gap
falls from 3.5608 to 0.3698 L. The candidate/repeat images are pixel identical;
full/unchanged-repeat mean difference is 0.00152 ΔE. The whole-frame candidate
change is 0.7394 ΔE, which is not itself a quality score.

The candidate was evaluated as an isolated shader copy. GZW dark/sunset/vivid and Arc
combined/active regressions are being checked with fresh 20-second before,
candidate and unchanged-repeat captures. GZW dark is unchanged at capture
precision; sunset/vivid and Arc cloud add no white-channel clipping and reduce
whole-frame exact-black coverage. Source black remains black where present.
These counts alone do not establish quality: inspected dark/sunset/vivid/cloud
pairs show expected scenes without a newly obvious edge artifact. The sunset
bright selection moves −1.28 L on average and its vivid selection has median
hue change −0.41 degrees. Those are material tradeoffs to retain in review,
not zero-change claims. Matched motion validation is recorded below.

Preparation/capture/analysis scripts, copied profiles/configs, full images,
[attribution report](../captures/halo_attribution_20261024/report.json),
[edge-band measurements](../captures/halo_attribution_20261024/sky_edge_metrics.json)
and [visual crops](../captures/halo_attribution_20261024/sky_edge_crops.png) remain
in ignored `captures/halo_attribution_20261024/`. Source identity labels, marker
and outer raster borders are excluded from comparison summaries. Source sky
selection uses original pixels, never the graded result.


## Completed held regressions

All 15 before/candidate/repeat captures completed in fresh private processes
with 20-second settling and zero dropped/delayed mpv frames. Both creative
profiles and all shared shaders/configs remain unchanged during these tests.
[Run report](../captures/halo_attribution_20261024/regressions/report.json),
[region measurements](../captures/halo_attribution_20261024/regressions/metrics.json)
and [inspected contact sheet](../captures/halo_attribution_20261024/regressions/contact_sheet.png).

| Case | Exact black %, before → candidate | Candidate repeat ΔE | Whole-frame change ΔE |
|---|---:|---:|---:|
| GZW dark | 0.006592 → 0.006592 | 0.000007 | 0.000007 |
| GZW sunset | 0.498563 → 0.456652 | 0.000486 | 0.901641 |
| Vivid Arc input, GZW profile | 0.356039 → 0.263971 | 0.000004 | 0.704493 |
| Arc cloud, combined trial | 0.006972 → 0.005724 | 0.000000 | 1.016492 |
| Arc cloud, active chain | 0.002469 → 0.002469 | 0.000024 | 0.000023 |

No case adds white-channel clipping; source-black pixels remain black where
present. The active Arc chain's Retinex is effectively bypassed by its broken
cross-effect resource reads, so its near-zero change is expected and does not
validate combined adaptive behavior. The separate Arc combined test does.
These are scoped regression checks rather than universal fidelity claims.


## Matched moving edges and adoption

The exact accepted lossless source (15 poses/sec, duplicate 30 fps playback,
20-second initial pre-roll) was replayed in two fresh candidate/repeat processes.
Before frames come from the earlier unchanged shared shader's retained motion
runs. Only decoded three-way source-identity matches are compared. Required
coverage includes foliage, clearing and corridor; cut windows were also
captured but this attribution run does not claim complete matching cut coverage.
Both candidate processes report zero dropped/delayed mpv frames.

| Window | Matched identities | Before→candidate ΔE | Candidate repeat ΔE |
|---|---:|---:|---:|
| Foliage | 1 | 0.86143 | 0.00042 |
| Clearing | 4 | 0.68987 | 0.03159 |
| Corridor | 6 | 0.00192 | 0.00022 |

On the four matched clearing poses (1044,1068,1092,1116), the source-selected
sky border gaps fall from 3.50–3.61 to 0.37–0.88 L. Candidate repeats retain
the reduction (0.43 rather than 0.37 on the last two poses), despite measurable
history variation. The matched crops visibly remove the structures' broad sky
outlines; dark corridor output stays close to the original at this sample.
This is sparse moving-pose evidence, not proof of dense flicker-free motion.

[Motion report](../captures/halo_attribution_20261024/motion/report.json),
[moving sky measurements](../captures/halo_attribution_20261024/motion/sky_edge_metrics.json),
and [identity-matched contact sheet](../captures/halo_attribution_20261024/motion/matched_contact_sheet.png).

The validated strength expression is now adopted in `general/grade/grade.fx`.
Shader header comments, the existing shadow-toe change, zone precision change,
both creative profiles and active configs are preserved. No history rate,
output transfer, dither or exposed tuning value is changed. The compiled
candidate and adopted code are compared after normalizing include paths and
removing comments; they are otherwise identical. Fresh 20-second captures of the actual shared path match the tested candidate
to 0.000027 ΔE (GZW sunset) and 0.000035 (Arc cloud), with zero mpv
dropped/delayed frames. [Applied-path report](../captures/halo_attribution_20261024/applied_report.json).
Twenty diagnostic tests and `git diff --check` pass.

Remaining review includes broad GZW highlights, vivid-hue/gamut continuity,
other moving shadow and illumination edges, print/tonal interactions, and live
combined-chain preference. Do not infer a universal fidelity gain from ΔE or
black occupancy. The normal GZW active four-effect chain is not switched.
