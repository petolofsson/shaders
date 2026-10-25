# Remaining authoritative histories — 2026-10-25

Continues the [consumer inventory](2026-10-25_history_consumers.md) and
[scene-chroma correction](2026-10-25_scene_chroma_precision.md). The current
instruction is to finish history precision/initialization/consumer work before
moving to signal and control contracts. Profiles, rates, measurements and
publications remain assessment constants.

## Independent recurrence evidence

A temporary diagnostic extracts each remaining recurrence from its actual
working function. Eight separate resources preserve each original format:
histogram R16F, entropy R16F, near-clip R16F, high-percentile RG16F, mode R16F,
zone RGBA16F, adaptive controls RGBA16F and percentile/Kalman RGBA16F. An
isolated candidate for each uses the corresponding 32-bit format. No output
of one tested history feeds another in this probe; each gets controlled raw
inputs, and its own storage error is measured independently.

The original update arithmetic is extracted rather than replaced with a
common EMA. Time-based formulas retain their own coefficients; percentile
Kalman remains per-update and retains the previously repaired nonpositive
covariance initialization rule. Five scenarios cover a small rise, reverse
fall, startup from zero, an input change with a hard cut at nominal one second,
and repeating frame-time factors `0,0.25,1.75,2`. Elapsed-time filters correctly
hold on zero dt; the per-update Kalman is compared with its actual rule.

Nominal 30/60/144 updates/sec and milestones 0/0.1/0.5/1/2/5/10 seconds produce
105 four-channel records per history, 840 records per process. Only channels
present in each native format enter its error metric. Every update writes the
actual GPU texture; reference calculations independently apply each recurrence
in double precision. Samples use RGBA32F and deliberate 24-bit binary output,
with a GPU counter proving completion of the 1440-update final milestone.

Three fresh private headless original/candidate/repeat processes replay the
same lossless 1536x1120 60 fps source. All report zero dropped/delayed frames.
Candidate and repeat records are identical. These simulated increments test
storage and arithmetic, not physical 144 Hz presentation.

| Authoritative history | Original max absolute error | Candidate max absolute error |
|---|---:|---:|
| Histogram | 0.015950461 | 0.000001013 |
| Entropy | 0.035038997 | 0.000002116 |
| Near-clip fraction | 0.001074864 | 0.000000073 |
| High percentiles | 0.013945241 | 0.000000834 |
| Mode | 0.013671815 | 0.000000895 |
| Zone levels | 0.005800733 | 0.000000367 |
| Adaptive controls | 0.007812295 | 0.000002354 |
| Percentile/Kalman | 0.002226490 | 0.000000358 |

For the small rise at 144 simulated updates/sec, histogram bin fraction ends
at 0.504883 instead of approximately 0.520833; entropy at 0.599609 instead of
0.620000; p90 at 0.706055 instead of 0.720000; mode at 0.509766 instead of
0.523438. Near-clip misses approximately 31% of its two-sample-fraction target
change. Percentile error also perturbs innovation and thus posterior covariance.
These are distinct measured failures to accumulate each chosen update, not
an assumption that every half-float resource must be widened.

The candidate therefore widens these eight authoritative accumulators only.
Raw histograms, current zone-level observations, scene-cut one-frame state,
neutral-illuminant estimates, spatial intermediates and published highways
retain their original formats. Direct feedback is already present in all eight
recurrences. Grade's separate declaration of the zone texture is kept consistent
with corrective's declaration, without repairing cross-effect resource sharing.
No helper formula, rate, sentinel, sampling pattern, pass or exposed knob changes.
[Response plot](../captures/history_completion_20261025/response.png).

## Initialization and retained one-frame state

All eight accumulators already read their private history directly. EMA zero
state is legitimate and is advanced normally; no small-value sentinel is added.
Percentile covariance keeps its nonpositive initialization rule and stays
positive under positive process/measurement noise. Adaptive controls seed only
when the previous channel sum is below 0.001; their raw gamut target is always
at least 0.75, so an initialized legitimate state cannot be mistaken for startup.
The five GPU scenarios verify startup alongside normal evolution, including
valid covariance and zero elapsed time.

`SceneCutTex` retains only previous p50 and raw entropy for one-frame differences;
its confidence channel is recomputed, not accumulated. A second diagnostic
extracts the actual comparison and retains the existing RGBA16F storage.
Eight lanes record 64 consecutive measurements each: zero, constant ordinary
values, constant near-black values, small sub-threshold changes, separate luma
and entropy steps, alternating large cuts, and precision-sensitive mid-threshold
steps. Independent references use the exact preceding measurement.

Two fresh private 20-second headless captures, including an unchanged repeat,
record 512 float4 states each. Both have zero dropped/delayed frames; binary
readback is identical. Maximum cut-confidence error is 0.004287448 and maximum
stored-measurement error is 0.000400559. All steady/sub-threshold lanes after
their first observation produce zero cut signal within readback precision.
The predeclared check budgets are 0.006 confidence and 0.0006 measurement:
the smoothstep derivatives can amplify a one-time half-float measurement error
by roughly 10–11, but that error does not compound over frames. Retain this
one-frame format and its bounded uncertainty.

Neutral-illuminant RGB is recomputed from current scene samples and passed
through metadata with a one-frame delay to inverse grade. It has no EMA
feedback; current grade's derived warmth field has no image consumer. Raw
histograms/current zone levels are observations, and scalar/texture highways
are publications rather than authoritative feedback for the repaired filters.
Their existing formats remain. The six unused per-hue filters remain untouched.

The initial one-frame diagnostic failed compilation on an inline shift-count
type; assigning the count to `uint` corrected the diagnostic. Its failed source,
report and `/tmp/shader-runtime-bytjxvu4/` log are retained separately and supply
no accepted evidence.

## Held scenes and individual attribution

Eighteen fresh private before/candidate/repeat captures use the existing six
sources and profiles with five-second compile wait and 20-second continuous
settling. Vivid Arc input uses GZW tuning; Arc cloud/emitter cases retain Arc
tuning. No old output is reused as the baseline. All eighteen processes report
zero dropped/delayed frames, and all candidate repeats are byte-identical at
capture precision. Fixed settling and repeat agreement do not prove complete
convergence of the separate, unchanged 20-second slow key.

| Input | Before→candidate mean Delta E | Candidate→repeat mean Delta E |
|---|---:|---:|
| GZW dark | 0.000294 | 0 |
| GZW sunset | 0.001247 | 0 |
| Vivid Arc / GZW profile | 0.001158 | 0 |
| Arc clouds | 0.000502 | 0 |
| GZW muted | 0.001011 | 0 |
| Arc emitters | 0.000434 | 0 |

Full-raster endpoint checks mask only the intentional 2x2 marker. No candidate
or repeat adds white-channel clipping; exact source black stays black. Vivid
input adds seven black pixels (source max-channel codes 5–10), and muted adds
one (source RGB 2/2/2). Every affected before value is RGB 0/0/1 and becomes
0/0/0 in both candidate and repeat. Source codes, coordinates and all output
codes are retained in `held_new_black_pixels.json`. Sunset loses two exact-black
pixels; the other cases retain their black coverage. These are recorded
one-code quantization costs, not zero-added-clipping claims. The inspected
[held overview](../captures/history_completion_20261025/held_overview.png)
retains scene structure without a newly apparent artifact.

Eight additional fresh 20-second captures revert exactly one history format
from the complete candidate, keeping every other correction active. Shared
source/profile/config hashes and reused candidate image hashes remain fixed.
All eight report zero dropped/delayed frames. This measures each intervention
in the combined chain; these non-additive changes are not effect-quality scores.

| Reverted history | Held case | Mean Delta E from full candidate |
|---|---|---:|
| Histogram | Arc clouds | 0.000089 |
| Entropy | GZW muted | 0 |
| Near clip | Arc emitters | 0 |
| High percentiles | GZW sunset | 0 |
| Mode | Arc clouds | 0 |
| Zone | Vivid Arc / GZW profile | 0.000211 |
| Adaptive controls | Vivid Arc / GZW profile | 0.000825 |
| Percentile/Kalman | GZW sunset | 0.000115 |

Several held sources do not expose a visible contribution from their individual
precision correction. The controlled GPU histories separately prove the update
defect; no visible intervention is forced where a source does not need it.

## Motion and real-chain state

Three fresh private replays verify the cached Babylon manifest, scene/clip
hashes and 15-pose/sec, duplicate-30-fps, 20-second-pre-roll protocol. Runs
retain 27/28/28 identities, with zero dropped/delayed frames. Sixteen exact
three-way matches enter comparisons, fourteen within the seven planned windows;
both sides of both cuts are covered.

A temporary binary strip at rows 2–7 reads each actual accumulator: histogram
bin 32, entropy, near-clip, p90, mode, one zone's median, adaptive gamut strength
and p50. Every original value lies on the half-float grid within 0.000000088
readback uncertainty. Each candidate field has sampled values off that grid:
maximum distance to its nearest half-float is approximately 0.000000924,
0.000243974, 0.000052016, 0.000162520, 0.000042006, 0.000060276,
0.000240845 and 0.000058337 respectively. This tests representability, without
assuming a GPU conversion rounding mode. Together with exact source equivalence
and the independent recurrence probes, it verifies the actual chain retains
the intended extra precision. No diagnostic strip enters shared shaders.

| Window | Exact matches | Before→candidate mean Delta E | Candidate→repeat mean Delta E |
|---|---:|---:|---:|
| Foliage | 4 | 0.018187 | 0.000214 |
| Clearing | 4 | 0.011847 | 0.001524 |
| Before night cut | 1 | 0.006322 | 0.000325 |
| After night cut | 1 | 0.007255 | 0.000545 |
| Corridor | 2 | 0.012683 | 0.004048 |
| Before return cut | 1 | 0.008613 | 0.001051 |
| After return cut | 1 | 0.001265 | 0.000738 |

Image measurements mask the eight-pixel border containing binary diagnostics,
activity marker and source labels. All sixteen interiors preserve exact source
black and add no white-channel clipping. One identity, `1044:262`, adds one
black pixel in both candidate and repeat: at (1153,811), source RGB 7/7/7 and
before RGB 0/1/0 become 0/0/0. Its full RGB record is retained. Other matches
add no black pixels. The inspected
[motion overview](../captures/history_completion_20261025/motion_overview.png)
retains scene structure without a newly apparent artifact. These are sparse
matched samples and bounded regression evidence, not dense native gameplay,
physical high-refresh acceptance or higher aesthetic effectiveness.

## Adoption and shared-path verification

The nine tested format declarations are applied to shared analysis/corrective/
grade sources: eight authoritative accumulators plus grade's separate zone
declaration. Shared executable sources exactly match the tested candidate
after include-path normalization. Earlier scene-chroma/slow-key repairs and
all formulas, rates, initialization, observations, publications, shader header
comments, profiles and active configs remain intact. Twenty diagnostic tooling
tests and `git diff --check` pass.

Four final fresh private 20-second captures check both shared combined trials
and the unchanged active GZW/Arc standalone configs. Shared vivid-GZW and
Arc-cloud outputs match their tested candidates exactly at capture precision.
Standalone controls compile, retain the activity marker and ordinary scene
content, and report no runtime errors. All four processes have zero dropped/
delayed frames. These standalone checks do not repair or certify their known
cross-effect data-sharing defect. Protected hashes show that only the three
intended shared shader files change across adoption; profiles and all active/
trial configs remain unchanged.

This closes the remaining accumulator/initialization/consumer audit in priority
1. The next work is priority 2: units, statistical/numerical contracts, bypasses,
endpoints and stage cooperation. Earlier deliberate slow-key startup behavior
and existing time constants remain preserved. Overall temporal and visual
acceptance is still broader than this arithmetic audit.

## Artifacts and limits

Ignored [captures/history_completion_20261025/](../captures/history_completion_20261025/)
retains exact function extraction, independent references, shader/pipeline
snapshots, configs, source hashes, binary readback and matched captures.
`probe_report.json` and `probe_metrics.json` retain every measured recurrence.
The scope of full-chain validation and adoption is recorded above as it
completes. No golden-image testing, GPU profiling, new effect, auto-exposure,
HDR output, profile change or effectiveness-score increase is introduced.
Active separate-chain integration, dense native motion, physical high refresh
and broader game acceptance remain separate priorities.
