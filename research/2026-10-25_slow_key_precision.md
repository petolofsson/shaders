# Slow-key feedback precision — 2026-10-25

Continues the technical audit after
[metadata texel identity](2026-10-25_highway_resolution.md). The intentional
slow-key formula has a 20-second half-life, but quantizing the authoritative
feedback through half-float storage prevents that response from being reliable
across update rates. This is a storage correction, not faster adaptation tuning.

## Data flow and candidate

`ComputeSlowKey` previously read its old value from `ReadTexHwyChroma(0,7)`.
That publication is RGBA16F, and the preceding `ChromaHistoryTex` is also RGBA16F.
Small per-frame changes can disappear during feedback; falling values also show
a bias on the measured GPU path. A time-based coefficient does not by itself
make a quantized recurrence time-based.

The isolated candidate changes `ChromaHistoryTex` to RGBA32F and reads the prior
slow key directly from its own history sampler at column 7, row 0. Both changes
are needed: widening a texture while feeding back through the RGBA16F metadata
would still quantize the accumulator. Existing zone histories already use the
same self-history read/write pattern. The 8x4 layout and pass count remain;
the scalar highway and texture-highway publications keep their existing R16F
and RGBA16F formats for consumers. Only authoritative slow-key feedback gains
precision. No creative control is added or retuned.

The slow 20000 ms and fast 67 ms denominators, scene-cut coefficient blend,
initialization guard and `FRAME_TIME` formula remain exactly unchanged. This
does not reattribute the previous dark-return measurements to zone lag or
shorten the intentional half-life.

## Explicit GPU precision probes

A private diagnostic extracts the actual slow-key function from each isolated
shader. It substitutes known target, cut signal and time increment, and maps
three rate lanes and three scenarios to separate history cells. The original
uses actual RGBA16F history plus the actual RGBA16F highway publication/reader;
the candidate uses actual RGBA32F history and its direct feedback read. The
arithmetic and initialization guard are otherwise the working function.

Three scenarios run at fixed simulated 30, 60 and 144 updates/sec:

- Slow rise from 0.10 toward 0.20, scene-cut signal zero.
- Slow fall from 0.20 toward 0.10, scene-cut signal zero.
- Fast rise from 0.10 toward 0.20, scene-cut signal one.

Every actual GPU update writes the relevant history format; several updates are
not collapsed into a register-only loop. Seven milestones per scenario/rate are
retained, for 63 values per process. The publication remains 16-bit. An R32F
diagnostic snapshot and 24-bit binary-cell output avoid ordinary screenshot
quantization hiding the small candidate errors. A GPU update counter proves
that the final 2880-update milestone has completed. Earlier milestones use the
first update at or after their requested time and compare against the analytic
response at that actual simulated time.

Original, candidate and unchanged candidate-repeat processes replay a 640x360
60 fps lossless clip on a private headless display. All report zero
dropped/delayed frames. The rate lanes are controlled time-increment tests;
they do not claim physical 144 Hz presentation or in-game frame-rate validation.

### Slow paths at 20 simulated seconds

The analytic result is 0.15 for both rise and fall.

| Update rate | Original rise | Original fall | Candidate rise | Candidate fall |
|---|---:|---:|---:|---:|
| 30/sec | 0.125000 | 0.126709 | 0.150001 | 0.149999 |
| 60/sec | 0.099976 | 0.099976 | 0.150000 | 0.150000 |
| 144/sec | 0.099976 | 0.099976 | 0.150005 | 0.149995 |

Across all 63 milestones, original maximum absolute error is 0.0707351.
Candidate maximum absolute error is 0.000005171; its repeat is identical at the
24-bit readback precision. The fast 67 ms path also agrees with its analytic
response, including its early milestones. Its 20-second candidate values are
0.200000 / 0.200000 / 0.200000 to six decimals.

The observed original values differ from the earlier round-to-nearest float16
CPU model. That model identified a precision risk; it did not establish the
GPU's exact conversion behavior. The table above is the authoritative measured
result. No particular Vulkan rounding mode is inferred or asserted.
[Recorded response milestones](../captures/slow_key_precision_20261025/response.png).

## Six-scene held checks

Eighteen fresh private before/candidate/repeat captures use five-second compile
wait and 20-second continuous playback. No old image is reused as the baseline.
Shared source/profile/config hashes remain unchanged throughout the isolated
candidate batches. Vivid Arc input uses GZW tuning; clouds and lamps use the
Arc profile. This is a fixed warmup protocol, not proof that a 20-second-half-life
history has fully converged.

| Case | Before/candidate mean Delta E | Candidate/repeat mean Delta E |
|---|---:|---:|
| GZW dark | 0.000012 | 0.000016 |
| GZW sunset | 0.000036 | 0.000008 |
| Vivid Arc input, GZW profile | 0.000001 | 0.000003 |
| Arc clouds | 0.000011 | 0.000102 |
| GZW overcast | 0.000099 | 0.000098 |
| Arc lamps | 0.000359 | 0.000007 |

All eighteen processes report zero dropped/delayed frames. Full-raster tests
exclude the intentional 2x2 marker and find no newly black or white-clipped
pixels in any case. Exact-black coverage is unchanged in all six scenes;
source black remains zero where present. Static differences are tiny and often
near repeat variation; these do not establish an aesthetic improvement. The
demonstrated benefit is the history's intended accumulation behavior.

## Real-chain motion and explicit state readback

Three fresh private before/candidate/repeat replays use the verified cached
15-pose/sec source duplicated at 30 fps, with 20-second initial pre-roll.
They retain 27 / 28 / 28 unique identities and report zero dropped/delayed
frames. Twenty exact three-way identities match overall; eighteen fall in the
seven required assessment windows, including both sides of both cuts.

A temporary grade copy adds a binary readback strip only in image rows 2–7.
It reads the actual `ChromaHistory` slow key, the published metadata key, zone
key and frame time. The normal comparison's eight-pixel border exclusion masks
the strip; the activity marker and source-identity strip remain intact. Ordinary
output pixels are not decoded as telemetry. No diagnostic strip enters the
working shader.

Original retained and published keys match at all sampled positions. Candidate
retained keys differ from their publication by up to 0.000224829; repeat maximum
is 0.000224352, both within half-float publication precision. At source identity
360:91 the candidate retains approximately 0.199075353 and publishes 0.198974621.
This proves that the actual combined pipeline retains precision beyond its
publication, rather than only the extracted-function probe doing so.

| Window | Matches | Before/candidate mean Delta E | Candidate/repeat mean Delta E |
|---|---:|---:|---:|
| Foliage | 5 | 0.032150 | 0.001068 |
| Clearing | 3 | 0.062908 | 0.000169 |
| Before night cut | 1 | 0.084739 | 0.000308 |
| After night cut | 1 | 0.164934 | 0.003136 |
| Corridor | 5 | 0.268623 | 0.006146 |
| Before return cut | 1 | 0.339900 | 0.004486 |
| After return cut | 2 | 0.859248 | 0.033419 |

All twenty matched image interiors, excluding the eight-pixel border containing
the diagnostics and source labels, add no newly black or white-clipped pixels.
Inspected clearing/corridor/return comparisons retain scene structure without
a newly obvious artifact. Larger transition changes show that history behavior
engages; they are not fidelity scores. These remain sparse matched game poses,
not dense gameplay continuity, physical 144 Hz testing or universal cut recovery.
[Matched crops](../captures/slow_key_precision_20261025/motion_comparison.png),
[sparse key readback](../captures/slow_key_precision_20261025/motion_key.png).

## Adoption and final shared-path checks

The two-line format/read correction is applied in
`general/corrective/corrective.fx`. The shared file exactly matches the tested
candidate after normalizing include paths. Twenty diagnostic tests and
`git diff --check` pass. Two final fresh private captures through the shared
combined pipeline match the tested candidates exactly at capture precision on
vivid input with GZW tuning and clouds with Arc tuning. Both report zero
dropped/delayed frames. This does not assert universal output determinism.

Protected hashes show only the intended corrective shader differs across
validation/adoption. All prior fixes, profiles, active configs and shader header
comments remain. Only the internal 8x4 history format changes; published formats,
resource dimensions, pass count, initialization and half-life constants remain.

## Artifacts and limits

Ignored [captures/slow_key_precision_20261025/](../captures/slow_key_precision_20261025/)
retains shader/pipeline snapshots, extracted function probes, source/config/profile
hashes, binary readback images, independent analytic checks and JSON reports.
These are arithmetic contract probes, not a restored golden-image suite.
`probe_report.json` and `probe_metrics.json` retain the 63-value probes and
analytic checks; `regress_report.json` and `regress_metrics.json` retain fresh
six-scene checks; `motion_report.json` and `motion_metrics.json` retain identity,
readback and clipping details; `verify_report.json` retains shared-path checks.

The active four-effect resource-sharing defect remains separate. Corrective's
internal feedback precision can be repaired without making its data available
to a different effect instance. Broader live-game frame timing, dense gameplay
motion, other history precisions and unused analysis consumers remain separate
technical work. No effectiveness score, new effect, auto-exposure or HDR output
is implied by this correction.
