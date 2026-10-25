# Scene-chroma feedback precision — 2026-10-25

Continues the [history-consumer audit](2026-10-25_history_consumers.md).
Unlike the six unused per-hue histories, all four channels of `MeanChromaTex`
have live consumers. Explicit GPU probes demonstrate a precision defect in
their half-float recurrence. An isolated candidate widens only this 1x1
authoritative history, preserving the existing update formula and publications.

## Contract and isolated correction

`MeanChromaPS` measures all-pixel median Oklab C, the colored-sample a/b
centroid, and achromatic fraction. It reads previous state directly from
`MeanChromaSamp` and updates each channel with
`alpha = lerp(saturate(frametime * 0.001), 1.0, scene_cut)`.
There is no startup sentinel: initial zero state follows that same formula,
with cuts increasing the coefficient toward one.

Median C drives inverse slope and grade's chroma/print/gamut restraint; a/b
drives inverse-grade hue alignment; achromatic fraction drives inverse chroma
gating and grade confidence. Quantization in the accumulator can therefore
change both the magnitude and direction of live color adaptation. A time-based
coefficient cannot preserve its intended recurrence if each small update is
lost in storage.

The candidate changes only `MeanChromaTex` from RGBA16F to RGBA32F. Feedback
already reads that texture directly, so no reader change is necessary.
`TexHwyTex`, `HighwayTex`, the median histogram population/bins, colored
centroid selection, measurement grid, pass order, rates, cut handling and
profiles remain unchanged. In particular, the update is not replaced with a
different exponential-time formula. This repairs precision of the chosen
formula rather than claiming to improve its discretization or artistic model.

## Explicit GPU probes

A temporary technique extracts the exact four-channel recurrence from the
working `MeanChromaPS`. It replaces measured targets, cut signal, time increment
and history address with controlled inputs. The original and candidate perform
the same arithmetic, using actual RGBA16F/RGBA32F state respectively, updated
once per actual GPU update. A separate RGBA16F publication remains in both.
Milestones are stored in RGBA32F, then explicitly rendered as binary cells.
Signed channels use the reversible diagnostic mapping `(value + 0.5) / 2`;
no negative state is clamped out before encoding.

Six scenarios run at nominal simulated 30, 60 and 144 updates/sec:

1. Small rise: `(0.10,0.04,-0.04,0.50)` → `(0.12,0.06,-0.02,0.55)`.
2. Small fall: the reverse of the first scenario.
3. Signed centroid reversal: a/b `(-0.04,+0.04)` → `(+0.04,-0.04)`.
4. Startup: zero → `(0.10,0.05,-0.05,0.75)`.
5. Small rise with a hard cut at simulated one second.
6. Small fall with repeating frame-time factors `0.25,1.75,0.50,1.50`.

These independently controlled channels test the recurrence; real jointly
measured statistics are assessed in the full-chain checks.

Milestones are 0, 0.1, 0.5, 1, 2, 5 and 10 nominal seconds. Each fixed-cadence
milestone uses the first update at or after its requested time; the variable
case uses the same update indices and records the actual summed time. Independent
double-precision reference calculations apply every coefficient and the cut
at its actual index. Each process records 126 four-channel retained states and
126 four-channel publications, not only final values. A GPU counter proves
completion of the 1440-update final milestone.

Original, candidate and unchanged candidate-repeat are fresh private headless
processes playing the same lossless 960x840 60 fps source. All report zero
dropped/delayed frames. Simulated time increments test arithmetic/storage;
they do not certify physical 144 Hz presentation or dense gameplay continuity.

| Small-rise achromatic fraction at ten simulated seconds | Original | Candidate | Formula reference |
|---|---:|---:|---:|
| 30 updates/sec | 0.535645 | 0.549998 | 0.549998 |
| 60 updates/sec | 0.520996 | 0.549998 | 0.549998 |
| 144 updates/sec | 0.500000 | 0.549996 | 0.549998 |

Across all retained channels and milestones, maximum original absolute error
is 0.069791266; candidate error is 0.000002159. Candidate repeat is identical
at binary readback precision. Maximum candidate retained/publication difference
is 0.000466824, showing that publication stays half-float while accumulation
retains more precision. The original state/publication pair matches exactly.

Signed channels show the defect too: at ten seconds in the 144-update reversal,
original a/b are approximately `(+0.035614,-0.035614)`, candidate
`(+0.039997,-0.039996)`, versus the formula's approximately
`(+0.039996,-0.039996)`. Startup, reset and variable-timing candidate samples
also satisfy the same maximum-error check. No GPU rounding mode is inferred
from these observations. [Response plot](../captures/scene_chroma_precision_20261025/response.png).

The first temporary probe used a reserved identifier and failed compilation.
It was corrected in the diagnostic only; its failure report and runtime log
are retained separately. It supplies no measurement or acceptance evidence.

## Held scenes

Eighteen fresh private headless before/candidate/repeat captures cover six
existing inputs with five-second compilation wait and 20-second continuous
settling. No old output is reused as the baseline. Shared source/profile/config
hashes remain unchanged throughout the isolated batch. Vivid Arc input uses
the GZW profile; clouds and emitters use Arc tuning. This is a fixed settling
protocol rather than a claim that every history has fully converged.

| Case | Before→candidate mean Delta E | Candidate→repeat mean Delta E |
|---|---:|---:|
| GZW dark | 0.0000000 | 0.0000019 |
| GZW sunset | 0.0000039 | 0.0000000 |
| Vivid Arc / GZW profile | 0.0000018 | 0.0000021 |
| Arc clouds | 0.0000030 | 0.0000193 |
| GZW muted | 0.0000130 | 0.0000000 |
| Arc emitters | 0.0000110 | 0.0000122 |

All eighteen processes report zero dropped/delayed frames. Full-raster
endpoint comparisons mask only the intentional 2x2 marker: no candidate or
repeat adds a newly black pixel or newly white-clipped channel pixel relative
to its before image. Exact-black coverage is unchanged, and source black
stays zero wherever present. The inspected
[held overview](../captures/scene_chroma_precision_20261025/held_overview.png)
retains scene structure without a newly apparent artifact. Static differences
are tiny and frequently near repeat variation; they establish no visible
quality improvement. The independent GPU probe establishes the storage defect.

## Motion and real-chain state

Three fresh private before/candidate/repeat runs replay the verified Babylon
cache: 15 source poses/sec duplicated at 30 fps, with 20-second initial
pre-roll. Manifest, clip, scene sources and matched PNG hashes are verified.
The runs retain 27/27/28 identities and report zero dropped/delayed frames.
Sixteen exact three-way matches enter comparisons; fourteen fall within the
seven requested windows, covering both sides of both cuts.

A temporary grade copy renders actual `MeanChromaSamp` and published
`ReadTexHwyMeanChroma()` values in a binary strip at image rows 2–7. All image
metrics exclude an eight-pixel border, masking this strip, the activity marker
and source identity labels. No diagnostic output enters the shared shader.
Original retained/published channels match at every sampled position;
candidate differences reach 0.000384927, repeat 0.000429511. This confirms
that the real combined pipeline retains precision beyond the half-float
publication, independently of the extracted-function probe.

| Window | Exact matches | Before→candidate mean Delta E | Candidate→repeat mean Delta E |
|---|---:|---:|---:|
| Foliage | 5 | 0.003562 | 0.001008 |
| Clearing | 3 | 0.004241 | 0.000441 |
| Before night cut | 1 | 0.005133 | 0.000429 |
| After night cut | 1 | 0.010269 | 0.001506 |
| Corridor | 2 | 0.000006 | 0.006101 |
| Before return cut | 1 | 0.000014 | 0.003388 |
| After return cut | 1 | 0.000741 | 0.001028 |

All sixteen matched interiors add no white-channel clipping and preserve exact
source black. Four identities add newly black pixels: `1020:256` (1),
`1068:268` (1), `1408:353` (14), and `1428:358` (38). Candidate repeat counts
relative to the original are 1/1/15/20; 35 positions are common to both
candidate captures. Every affected before pixel has max-channel code 1 and
becomes code 0; verified source max-channel codes are 6–9. The maximum increase
in exact-black coverage is approximately 0.001049 percentage points in one
matched interior. Coordinates, source hashes and all RGB codes are retained in
`motion_new_black_pixels.json`. Adoption retains this small one-code shadow
cost; it does not justify raising a visual-effectiveness score.

The inspected [motion overview](../captures/scene_chroma_precision_20261025/motion_overview.png)
retains scene structure without a newly apparent artifact. Sunny/cut changes
exceed their repeat scale; corridor/return differences are often below it.
These sparse matches verify engagement and bound the assessed regressions;
they do not establish dense gameplay continuity, universal cut recovery or
physical high-refresh acceptance.

## Adoption

The single format declaration is applied in
`general/analysis-frame/analysis_frame.fx`. After include-path normalization,
the shared file matches the GPU-tested candidate exactly. Protected source
hashes show no other shader, profile or active/trial config changed. Shader
header comments, prior corrections, sampling, initialization and coefficients
remain intact. Twenty diagnostic tooling tests and `git diff --check` pass.

Two final fresh private captures run the shared combined pipeline with GZW
tuning on vivid input and Arc tuning on clouds. Applied/candidate mean Delta E
is 0.000008759 and 0.000011431 respectively; both report zero dropped/delayed
frames. The GZW difference exceeds its particular candidate-repeat delta, so
these captures do not establish universal output determinism. Exact source
equivalence is checked separately, and the remaining capture/history variation
is retained in `verify_report.json`.

## Artifacts and limits

Ignored [captures/scene_chroma_precision_20261025/](../captures/scene_chroma_precision_20261025/)
retains isolated shader/pipeline snapshots, diagnostic sources, scripts, lossless
clips, configs, hashes, captures and JSON records. `probe_report.json` retains
all readback values; `probe_metrics.json` checks the independent recurrence;
`response.png` plots representative channels. `regress_report.json` and
`regress_metrics.json` retain held captures and clipping; `motion_report.json`,
`motion_metrics.json` and `motion_new_black_pixels.json` retain exact matching,
readback and the one-code shadow cost; `adoption_hashes.json` records exact
candidate equivalence and protected-file identity; `verify_report.json` retains
final shared-path checks. This is a contract probe, not a golden-image suite
or GPU performance measurement.

The active separate effects' resource-sharing defect remains distinct. A correct
history inside analysis does not make its resources available to a separate
effect instance. No profile merge, active config switch, auto-exposure, HDR
output, score increase or universal color/temporal acceptance is implied.
