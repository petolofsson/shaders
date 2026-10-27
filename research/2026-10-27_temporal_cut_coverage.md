# Consecutive GPU updates at cached cuts — 2026-10-27

Continues PLAN 4 after the [filter-spacing correction](2026-10-27_filter_kernel_resolution.md).
Six fresh private headless replays extend two-phase samples to consecutive
post-cut windows under both unchanged profiles. Two additional route traces
test a possible detector correction and reject the simple raw-median swap.
No production shader, profile or config changes follow from this continuation.
The measured cut handoff and night settling remain acceptance costs.

## Source and measured coverage

All runs verify the existing Babylon manifest, all 556 source-image hashes,
the original lossless clip and the diagnostic clip with its appended eight-second
readback tail. The retained prefix verification establishes identical packet
payloads and timestamps for all 1,710 original video packets. The original
20-second pre-roll, route and speed stay unchanged. Each run starts a fresh
private headless process with five seconds of compilation wait. No desktop
fallback, focus change or physical display change is used.

The source has 15 unique poses per second, duplicated at 30 fps. A GPU clock
reads the original pose/token label before analysis or inverse grading and
tracks source-update age and cut-update age. Immediately after ColorTransform,
before adaptive history advances, the diagnostic freezes 32 GPU updates after
each cut. A 2560×1440 RGBA32F atlas holds 64 tiles, each a 320×180 native point
sample at pixel `(8*x+4,8*y+4)`. Texel-center coordinates avoid blending adjacent
native pixels. Separate RGBA32F records retain source identity, context, native
histories, the controls used for that output and actual frame-time uniforms.
The appended tail displays the frozen images and 24-bit binary records.

The boundary check matters: the original clip ends at video frame 1709,
pose 2216/token 555. Pose 2220/token 556 first appears at frame 1710 in the
appended tail, although that source image is present in the cache manifest.
Fourteen freshly decoded boundary images match their cached RGB sources exactly.
Consequently, the night window has 32 original-clip updates, but the return
window has only 30. Its final two records are retained and explicitly labeled
as tail observations, excluded from motion summaries and plots.

| Runs | Original-clip updates per run | Frozen tail records per run | Role |
|---|---:|---:|---|
| GZW full + unchanged repeat | 32 night + 30 return | 2 | Current complete-chain response |
| GZW Retinex-off + unchanged repeat | 32 + 30 | 2 | Controlled bypass in temporary profile copies |
| Arc full + unchanged repeat | 32 + 30 | 2 | Second existing profile on the same source |

All 64 pose/token/source-update/cut-update keys match exactly across the six
replays; 62 are original-clip observations. The six runs retain 372 such images
and 12 separately labeled tail images. This is consecutive GPU-update evidence
on duplicated sparse source poses, not dense native gameplay. Both profiles
use the same Babylon input; this does not add another game's recording.

All eight runtime processes, including the two route traces below, report zero
dropped/delayed frames and completed vkBasalt logs. Original-clip window frame
times span 32.6427–34.2845 ms across the six replays. This measures modest real
jitter around 30 updates/sec; it does not test severe hitches, variable-refresh
presentation or physical high refresh. Recorded uniform elapsed spans are
approximately 1,033 ms for the night window and 966 ms for the return window.

## Temporal response and repeat uncertainty

Image measurements exclude a two-pixel atlas border plus the common readback-tag
footprint, leaving 55,232 native point samples at stride eight in every image.
The tag overlaps the interior of one tile, so a border crop alone is insufficient.
Its 64×6-pixel region is excluded from every source/output/variant comparison,
keeping the spatial support identical across adjacent updates. The border crop
also removes source labels and the marker. Initial unmasked summaries were
recomputed before assessment; the final JSON/CSV and plots use the common mask.
Distances use Oklab ×100. They measure change, not image quality or acceptance.
Adjacent records with identical source pose/token have byte-identical source
samples, so their image change comes from pipeline state rather than camera
movement. Steps between different poses are reported separately.

| Profile / window | First identical-pose step, full | Maximum later identical-pose step | Maximum same-phase image repeat mean ΔE |
|---|---:|---:|---:|
| GZW / night | 0.324375 | 0.641461 | 0.010946 |
| GZW / return | 1.443674 | 0.181165 | 0.002494 |
| Arc / night | 0.305401 | 0.649270 | 0.006075 |
| Arc / return | 1.446596 | 0.146178 | 0.002189 |

The return's first identical-pose step remains well above repeat variation.
GZW's controlled Retinex bypass reduces it to 0.037816, with bypass repeat
0.037998 for that step. Full unchanged repeat gives 1.443582. This extends the
older [phase-alignment audit](2026-10-26_return_cut_alignment.md) with the current
Retinex/blue/spacing code and a longer recovery window; it does not reclassify
the real handoff as capture noise. Cut confidence falls from one to zero on the
second identical input, and the adaptation gate returns from zero to one.
No perceptual certification of that transition follows from these point samples.

The night response is different. Its later identical-pose peak is approximately
0.64 ΔE in full and Retinex-off runs. At update four, full/repeat are
0.641461/0.642750 and bypass/repeat 0.637228/0.641320. By update thirty they
fall to approximately 0.008–0.010. That settling survives the Retinex bypass;
it should not be addressed by weakening Retinex globally.

Source mean L falls 20.667→19.531 over the night window, while GZW output mean L
rises 19.136→21.228 and Arc output 19.051→21.206. These are measured transient
relationships, not a preference judgment. Used shadow-lift strength rises
0.443→1.5 and film strength falls approximately 0.718→0.426 in the GZW trace;
percentiles and the deliberate slow key also evolve. Those concurrent records
do not isolate every causal contribution. Further stage attribution is needed
before changing any control or rate. The earlier slow-key precision and
fixed-pair history audits remain complete; their time constants are preserved.

All sampled exact source-black pixels remain black, and no sampled output
channel reaches 255 after the diagnostic tag is masked. This observational
audit is not a new before/candidate clipping regression or a guarantee about
unsampled pixels.
Point-sampled contact sheets and response plots retain the measured transitions
and repeat uncertainty. No effectiveness re-score follows.

## Delayed cut pulse and rejected raw-median alternative

The consecutive records expose a secondary confidence pulse at night update
four, while pose 1444 is on its second identical presentation. It ranges
0.148315–0.151978 across the six window replays. The detector compares p50 from
the temporally smoothed histogram and percentile filter. Its stored p50 changes
approximately 0.240→0.104 between these identical source images, exceeding the
existing 0.10 luma-delta threshold. Raw entropy does not have a new input change
on that duplicated pose. Thus the pulse reflects delayed statistic evolution,
rather than a newly observed source transition.

Two additional fresh route traces independently record a counterfactual detector
that uses the fresh raw-histogram median, retaining the entropy arm, thresholds,
CDF convention and native RGBA16F previous-observation storage. The diagnostic
recovers exact 576-sample counts, walks the CDF in integer-count units and
interpolates within the selected bin. It only observes the proposal: the real
detector, histories and grade continue to run unchanged.

Each trace checks 1,108 original-clip updates, covering both measured phases of
every moving pose from 4 through 2216. The two pose-zero rows are deliberately
unrecorded during startup/pre-roll and excluded; the two pose-2220 rows belong
to the tail. All fresh-median/entropy/confidence/delta records repeat identically.
The trace tag also overlaps unused FRAME_TIMER bits in rows 2–5, field 3/channel
3. Those channels are explicitly marked invalid in the reports and never used
for route metrics. Source identities, detector observations and all window
timing records are unaffected.

| Source event | Current detector | Fresh-median alternative |
|---|---:|---:|
| Continuous daylight motion, pose 1428 update 1 | 0 | 0.595664 |
| Continuous daylight motion, pose 1432 update 1 | 0 | 0.360552 |
| Actual night cut, pose 1440 update 1 | 1 | 1 |
| Identical night pose 1444 update 2 | 0.147705–0.150513 | 0 |
| Actual return cut, pose 2160 update 1 | 1 | 1 |

The raw median jumps approximately 0.249824→0.434375→0.595215 as the daylight
camera moves across the material/sky populations. The source sequence remains
continuous; the scripted cuts are at 1440 and 2160. A fresh median can cross
between separated distribution modes when their mass passes 50 percent.
Removing temporal lag therefore removes the delayed pulse but introduces two
larger noncut triggers. The simple raw-median substitution is rejected. It is
not a validated shader candidate, and no actual full-chain output is attributed
to that counterfactual detector.

## Verification and next work

The read-only audit verifies 1,058 artifacts: all source frames, clips,
config/profile/grade/diagnostic hashes, decoded records, every frozen image's
exact atlas extraction, phase keys, boundary evidence, reports and plots.
Protected production/profile/config hashes remain unchanged across all eight
runs and the audit. All 22 diagnostic tooling tests pass, and the whitespace
check passes. The previous filter-spacing repair remains intact.

Ignored [captures/cut_windows_20261027/](../captures/cut_windows_20261027/) retains
`run.py`, `diagnostic.fxh`, six window-run reports, `analyze.py`, `metrics.json`,
`metrics.csv`, contact sheets and temporal plots; `trace.py`, `trace.fxh`, two
route reports and `trace_metrics.json`; decoded source-boundary evidence and
`audit.py`/`audit_report.json`. Media and helper scripts stay local.

Next is conservative temporal attribution and detector/handoff work that keeps
the daylight 1428/1432 motion cases as rejection controls. Do not adopt the
raw-median shortcut, infer GPU age from mpv time, or accelerate the intentional
slow key by association. Large timing variation, physical high refresh, dense
unique gameplay poses, full-resolution temporal perception and broader-game
acceptance remain open. Active separate-chain resource sharing remains broken;
combined-trial evidence does not certify that path.

Follow-up: [same-update night attribution](2026-10-27_night_settling_attribution.md)
now isolates the scoped night response. Its diagnostic holds are not repairs;
current priorities and transition-assessment order are in PLAN.
