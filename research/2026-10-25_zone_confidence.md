# Zone confidence and uniform surfaces — 2026-10-25

Continues [Retinex flat-face attribution](2026-10-25_flat_face_attribution.md).
The remaining purple outline follows zone contrast's coarse-edge strength fade.
The spatial zone median/IQR field also contributes a smaller interior gradient.
Both contributions are isolated before changing the shared shader.

## Attribution and rejected stronger correction

Six fresh private headless captures use exact source pose 1044/token 262,
five-second compile wait, and 20-second continuous settle. Full/repeat and
zone-off are compared with independent interventions: remove only the local
confidence fade, hold zone median/IQR at the purple face's center UV, or do both.
The fixed-field variants are diagnostics, not proposals to freeze adaptation.
All six captures retain identity/marker and report zero dropped/delayed frames.

| Purple measurement | Full | Zone off | Global confidence | Fixed field | Fixed field + global confidence |
|---|---:|---:|---:|---:|---:|
| Interior L95−L5 | 1.066 | 0.281 | 0.522 | 1.047 | 0.260 |
| Edge minus center L | 0.734 | 0.000 | 0.000 | 0.734 | 0.000 |

Exact source colors, eight-pixel interior erosion, and four-pixel edge versus
24-pixel interior bands follow the preceding report. Full-raster source masks
avoid false crop boundaries. The confidence fade creates the rim; freezing
only the interpolated zone statistics does not remove it.

A first candidate retains uniform global confidence at the previous stronger
budget. Fifteen before/candidate/repeat held captures cover the source pose and
four GZW/Arc cases. It removes rims but increases exact black: GZW sunset
0.442→0.502%, vivid Arc input under GZW tuning 0.263→0.396%. Newly black pixels
come from source max-channel codes 2–13 and 3–20 respectively. GZW dark adds
165 black pixels, all from codes 2–3. This is a measurable shadow cost, not an
acceptable universal improvement inferred from flatter target faces. The
stronger candidate is not adopted.

## Conservative candidate

Use the existing minimum confidence budget, 0.65, uniformly for zone contrast.
This removes the boundary-dependent strength variation without increasing the
zone adjustment's magnitude at any pixel for otherwise identical state. Scene
statistics still choose zone strength, IQR scaling and the slope cap; the
negative arm keeps its luminance-relative smooth toe. Local zone histories,
Retinex's native-resolution guide, shadow lift, profile values and adaptation
rates remain unchanged. No new tuning surface or effect is introduced.

| Held measurement | Current | Conservative candidate | Candidate repeat |
|---|---:|---:|---:|
| Purple interior spread L | 1.066 | 0.344 | 0.344 |
| Purple edge gap L | 0.734 | 0.000 | 0.000 |
| Orange interior spread L | 0.743 | 0.311 | 0.311 |
| Cyan interior spread L | 0.607 | 0.334 | 0.334 |
| Magenta edge gap L | 0.391 | 0.070 | 0.070 |

This is a deliberate conservative calibration of the existing zone stage.
It can reduce useful contrast away from boundaries; real-scene and motion
checks must assess that cost. It does not eliminate the remaining coarse zone
field or establish subjective effectiveness.

## Artifacts and state

Ignored [`captures/zone_field_attribution_20261025/`](../captures/zone_field_attribution_20261025/)
holds all scripts, isolated shaders/configs, source/profile/image hashes and
captures. `report.json` records attribution, `regressions/report.json` the
stronger rejected candidate, and `conservative_regressions/report.json` the
conservative candidate. The latter reuses the unchanged, fresh-process
20-second before captures from the immediately preceding batch after verifying
identical shared-source hashes; candidate and repeats are fresh processes.
`conservative_metrics.json` and `conservative_edge_metrics.json` hold the
source-selected face measurements.

## Conservative regression and motion results

Ten fresh candidate/repeat processes cover the held pose and four real-game
inputs. All have zero dropped/delayed frames. Before images come from the
verified unchanged preceding batch, not a golden-image acceptance suite.

| Case | Before→candidate mean ΔE | Candidate/repeat mean ΔE | Exact black %, before→candidate |
|---|---:|---:|---:|
| Held Babylon | 0.223026 | 0.000001 | 0.035726→0.033963 |
| GZW dark | 0.009403 | 0.000008 | 0.006592→0.005941 |
| GZW sunset | 0.114079 | 0.000480 | 0.441841→0.436226 |
| Vivid Arc input, GZW profile | 0.168807 | 0.000019 | 0.263482→0.252360 |
| Arc cloud, Arc profile | 0.096590 | 0.000003 | 0.005425→0.005235 |

Source black remains zero where present and no case adds white-channel clipping.
The inspected matched real-scene contact sheet retains the expected lighting
and material structure. Lower black coverage alone does not establish fidelity.

Four fresh candidate/repeat motion processes initially lacked an old baseline
foliage identity, despite matching clearing/corridor frames. The failed report
is preserved. One additional fresh unchanged shared-shader replay supplies the
missing exact reference identity; all earlier image hashes are verified intact.
Cache protocol remains 15 poses/sec, duplicate 30 fps, 20-second initial pre-roll.
[Accepted continuation](../captures/zone_field_attribution_20261025/conservative_motion/coverage_retry_report.json).

| Window | Exact assessment matches | Before→candidate mean ΔE | Candidate/repeat mean ΔE |
|---|---:|---:|---:|
| Foliage | 1 | 0.12451 | 0.00018 |
| Clearing | 6 | 0.21501 | 0.03190 |
| Corridor | 8 | 0.00296 | 0.00215 |

All five motion processes report zero dropped/delayed frames. Across the six
clearing poses, purple's edge gap falls from 0.734 to 0.000–0.088 L in candidate
and repeats. The three exact-color orange selections move −0.302→0.000 L;
magenta gaps fall from 0.270–0.382 to 0.049–0.116 L. The preceding correction's
purple boundary regression is resolved on these matched poses. Coarse-field
interior gradients remain. Sky gaps still vary with position/history, and the
corridor change is comparable to repeat uncertainty. No dense-continuity or
complete matched-cut claim follows from these sparse samples.

## Adoption

The conservative candidate is applied in `general/grade/grade.fx`; executable
code matches its isolated tested copy after normalizing include paths/comments.
The prior Retinex guide correction, zone history precision, shadow toe, manual
profiles, active configs and shader header comments are preserved. Twenty
diagnostic tests and `git diff --check` pass. Three fresh shared-path captures
verify GZW sunset and Arc cloud against the candidate at 0.000480 and 0.000005
ΔE, within their repeat scale. Active Arc matches its retained unchanged output
at 0.000026 ΔE; that control still has the known cross-effect resource limitation.
All three have zero dropped/delayed frames.
[Applied-path report](../captures/zone_field_attribution_20261025/applied_report.json).
