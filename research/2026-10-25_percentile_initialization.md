# Percentile history initialization — 2026-10-25

Continues the technical producer/consumer audit after the
[all-pixel chroma-median correction](2026-10-25_chroma_median_contract.md).
The percentile Kalman filter repeatedly misclassifies valid covariance as
uninitialized. This is distinct from intentional slow-key adaptation.

## Contract and isolated candidate

`CDFWalkPS` stores its posterior variance in `PercTex.a` (RGBA16F). Initialization
used `prev.a < 0.001`, but R=0.005 and minimum Q=0.00005 permit legitimate
posterior variance below that threshold. For zero innovation, the analytic
fixed point is `(-Q + sqrt(Q*Q + 4*Q*R))/2`, approximately 0.000476.
Consequently a stable filter repeatedly replaces its valid covariance with 1.0,
raising its gain almost to one and restarting the decay.

The isolated candidate changes only the initialization condition to
`prev.a <= 0.0`. Positive variance is valid history. With positive R and Q,
the computed posterior is positive; the steady-state values measured here are
normal representable half floats, well above zero. Startup still seeds from
zero. Process/measurement noise, innovation weighting, histogram smoothing,
scene-cut logic, percentile targets and slow-key rates are unchanged.

## Explicit GPU history readback

A temporary combined technique duplicates the actual `CDFWalkPS` calculation
immediately before its real pass. It records P, K and the initialization flag,
then compares the duplicate P against the real pass's stored P. A diagnostic
history retains the first 128 updates and the latest 128 updates. Deliberate
output bars render those histories for readback; ordinary screenshot pixels
are not interpreted as hidden telemetry.

Four fresh private headless captures use a lossless constant gray input,
five-second compilation wait and 20-second continuous playback: original and
candidate, each with an unchanged repeat. All report zero dropped/delayed
frames. Duplicate and actual covariance channels match exactly at capture
precision at all 256 recorded positions in each process.

| Measurement | Original / repeat | Candidate / repeat |
|---|---:|---:|
| Resets in first 128 updates | 21 / 21 | 1 / 1 |
| Resets in latest 128 updates | 22 / 21 | 0 / 0 |
| Latest covariance range | 0.000908–0.004969 | 0.000561–0.000561 |
| Latest gain range | 0.181–approximately 1 | 0.112–0.112 |

Original startup resets occur at updates 1, 9, 15, 21, then every six updates.
Candidate startup resets only at update 1. Latest-history original/repeat
counts differ by phase within the six-update cycle. Candidate variance differs
from the minimum-Q analytic fixed point because half-float percentile storage
leaves a small nonzero innovation, and captured values have encoded 8-bit
quantization. The contract is positive valid covariance, not exact agreement
with a zero-innovation limit.

[GPU trace](../captures/percentile_initialization_20261025/covariance_trace.png).
No new user control, texture or pass is added to the working pipeline; the
extra resources exist only in the ignored diagnostic technique.

## Six-scene held checks

Twelve fresh private headless candidate/repeat processes use five-second compile
wait and 20-second continuous settling. Before images are the verified current
candidate captures from the preceding chroma-median batch, with identical
sources/profiles/configs and settling protocol. That batch's analysis candidate
is compared byte-for-byte to the current shared analysis after include-path
normalization; all other retained shared-source hashes match. Each cached image
hash is checked. No older pre-median shader is used as this change's baseline.

| Case | Before/candidate mean Delta E | Candidate/repeat mean Delta E |
|---|---:|---:|
| GZW dark | 0.000006 | 0.000000 |
| GZW sunset | 0.000578 | 0.000496 |
| Vivid Arc input, GZW profile | 0.000178 | 0.000003 |
| Arc clouds, Arc profile | 0.000003 | 0.000001 |
| GZW overcast | 0.000434 | 0.000000 |
| Arc lamps, Arc profile | 0.000066 | 0.000084 |

All twelve processes report zero dropped/delayed frames. No case adds a newly
white-clipped pixel; source black stays zero where present. Full-raster endpoint
checks exclude the intentional 2x2 marker. One overcast pixel changes from
output RGB=(0,0,1) to (0,0,0) in both candidate/repeat; its source is (2,2,2).
This is a recorded one-code quantization cost, not zero added black clipping.
Two sunset pixels become zero only in the first capture and return to RGB=(1,0,0)
in the unchanged repeat, within its temporal/capture variation. Pixel coordinates,
source codes and all three outputs are retained in `new_black_pixels.json`.
No visually significant static-image benefit is inferred from these tiny deltas;
the demonstrated correction is stable filter state rather than a stronger look.

## Dense controlled-cut history

Six additional fresh private processes use an explicitly instrumented combined
technique on lossless gray-128 / gray-220 / gray-128 playback for 20 / 8 / 20
seconds. Separate before/candidate/repeat runs capture each transition, at
21.700 seconds and 29.700–29.733 seconds. The latest 128 consecutive GPU updates
retain covariance, gain, initialization flag, actual p50/p75 and scene-cut
signal. This is dense filter-state readback on two controlled cuts, not a claim
of dense gameplay image continuity. Duplicate/actual covariance checks pass.
All six processes report zero dropped/delayed frames.

| Measurement | Rise before | Rise candidate/repeat | Return before | Return candidate/repeat |
|---|---:|---:|---:|---:|
| Resets in recorded 128 updates | 19 | 0 / 0 | 20 | 0 / 0 |
| Peak gain | approximately 1 | 0.913 / 0.913 | approximately 1 | 0.913 / 0.913 |
| Peak scene-cut signal | 0.913 | 0.922 / 0.922 | 0.913 | 0.913 / 0.913 |
| Updates from median departure to target band | 3 | 3 / 3 | 3 | 3 / 3 |

The target band is +/-0.01 linear luma around the known histogram median;
latest readings agree within encoded capture uncertainty. Recorded p75 stays
at or above p50; both trajectories remain monotonic within that uncertainty.
The candidate's gain still increases with real innovation, then decays without
unrelated reseeding. "Three updates" starts at the first measured p50 departure,
not the source cut; it excludes the histogram's own smoothing delay and is not
an end-to-end cut-latency claim. Intentional slow-key history is unchanged.
[Dense transition trace](../captures/percentile_initialization_20261025/transition_trace.png).

## Matched game motion

Three fresh before/candidate/repeat processes replay the verified cached Babylon
15-pose/sec source duplicated at 30 fps with 20-second initial pre-roll. Each
captures 27 unique identities and reports zero dropped/delayed frames. Six
exact three-way identities enter comparisons:

| Window | Matches | Before/candidate mean Delta E | Candidate/repeat mean Delta E |
|---|---:|---:|---:|
| Foliage | 2 | 0.030203 | 0.029965 |
| Clearing | 1 | 0.016305 | 0.001204 |
| Corridor | 1 | 0.003571 | 0.009782 |
| Before return cut | 2 | 0.003154 | 0.003018 |

The night-cut windows and post-return window have no three-way matches and
remain explicit empty coverage. Most window deltas are at or below repeat
variation; these do not establish improved game-motion stability. The dense
controlled-cut readback separately proves the filter-state behavior on its
known inputs. Neither test establishes dense gameplay continuity or universal
cut recovery.

## Adoption

The one-line initialization condition is applied in
`general/analysis-frame/analysis_frame.fx`. The shared file exactly matches
the tested candidate after include-path normalization. Twenty diagnostic tests
and `git diff --check` pass. The preceding all-pixel median correction, shader
headers, profiles, configs, slow-key history and other adaptation rates remain
intact. No shader file besides analysis changes in this validation/adoption.

Two final private captures through the shared combined pipeline give
applied/candidate mean Delta E of 0.000001 on vivid input with GZW tuning and
0.000074 on clouds with Arc tuning; both report zero dropped/delayed frames.
The latter exceeds that scene's particular candidate/repeat delta, so these
captures are not claimed to prove exact output determinism. Source equivalence
is established separately by exact shader comparison and protected hashes;
small remaining capture/history variation is retained rather than relabeled
as zero. Only the intended analysis file differs across validation/adoption.

## Artifacts and scope

Ignored [captures/percentile_initialization_20261025/](../captures/percentile_initialization_20261025/)
retains shader snapshots, diagnostic techniques, scripts, source/profile/config
hashes, captures, trace plots and JSON reports. `probe_report.json` retains the
full histories and `probe_metrics.json` their assertions and summaries.
`transition_report.json` and `transition_metrics.json` retain dense controlled
cuts; `regress_report.json` records verified baseline reuse and twelve fresh
captures; `regress_metrics.json` and `new_black_pixels.json` retain clipping
detail; `motion_report.json` records sparse exact identities and repeat limits.
`verify_report.json` retains final applied-path images and measured differences.

The active separate effects still lack shared resources. Correcting analysis
history does not repair the missing data flow to their downstream consumers.
No score increase, taste adjustment, auto-exposure, HDR output, GPU profiling
or golden-image suite follows from this technical correction.
