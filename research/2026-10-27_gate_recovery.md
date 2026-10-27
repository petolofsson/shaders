# Direct cut-gate recovery and lift-target coherence — 2026-10-27

Continues the [transition screen](2026-10-27_transition_screen.md) with full-resolution
images and held real-game inputs. Filtering direct cut-gate recovery with the
existing adaptive coefficients roughly halves the measured first return step.
It preserves the first cut image and held output, while spreading recovery to
later updates. It does not repair the dominant early night lift transition.

## Full-resolution method

Six fresh private headless motion replays freeze native 2560×1440 images at
explicit GPU phases. GZW and Arc profiles each retain full/repeat entry runs at
night and return updates 1/2. GZW adds full/repeat recovery runs at updates 3/4.
These are selected full-resolution phases, not consecutive full-resolution
video or physical high-refresh acceptance. All runs preserve the existing
15-pose/sec source duplicated at 30 fps, five-second compilation wait, original
20-second continuous pre-roll, profiles, original scene statistics and ordinary
history updates.

The diagnostic evaluates full and gate-only images before the ordinary color
pass and samples actual full output immediately afterward. The independent
RGBA32F gate state advances once per update; image interventions never replace
ordinary full history updates. The same shared helpers, native pixel positions
and dither are used. Frozen RGBA32F images are read out at their native raster.

All images use a common mask: outer eight pixels, the prior point-atlas tag's
native footprint at `[1664:2176,32:64]`, and the browser calibration patches plus
a small guard at `[2264:2552,1398:1430]`. This leaves 3,597,056 samples. Current
readout tags, activity marker and source identity strip lie inside the excluded
border. Contact sheets mask the same support. Distances below use Oklab ×100;
changes on duplicate presentations compare byte-identical source images.

The first replay exhausted the earlier eight-second readback tail before all
13 views were captured. Its failed report and images are retained separately;
it is not a completed motion run. The corrected clip appends eight copies of
the verified tail. Original video packet payloads, sizes, PTS/DTS and durations
match exactly; the 64-second appended readback tail is excluded from motion
claims. All measured entry/recovery images remain inside the original prefix.

## Measured benefit and recovery cost

| Identical-source step | GZW full | GZW gate recovery | Arc full | Arc gate recovery |
|---|---:|---:|---:|---:|
| Night update 2 | 0.324223 | 0.312013 | 0.304165 | 0.301290 |
| Night update 4 | 0.643339 | 0.640179 | — | — |
| Return update 2 | 1.438631 | 0.762650 | 1.441608 | 0.759831 |
| Return update 4 | 0.045340 | 0.197477 | — | — |

The direct gates still suppress immediately on a confident cut. All first-cut
candidate/full images in the entry runs are pixel-identical on valid samples.
Recovery toward the original direct gate then follows the existing 32.4-ms
rising half-life. The first return change is substantially reduced, while the
next measured duplicate step is larger. This redistributes an existing
transition; it does not remove the steady-state Retinex/chroma/tint treatment
or certify that the remaining response is visually unobtrusive.

All 24 full/actual controls across these six runs are pixel-identical. Maximum
matched gate-repeat mean distance is 0.006061 ΔE. No measured gate image adds
exact-black samples relative to full or a channel at code 255; exact source
black remains black. These constraints apply to the measured native phases.
Prior daylight 1428/1432 same-update rejection controls remain identical to full
in the preceding screen, and the detector itself is unchanged.

Six further fresh held processes use GZW dark, vivid Arc input under the GZW
profile, and Arc clouds under the Arc profile, with unchanged repeats. Freeze
occurs after 30 seconds of accumulated GPU frame time and at least 20 seconds
of continuous playback after restart. Every candidate/full/actual comparison
is pixel-identical, and all three full/repeat pairs are pixel-identical on the
common support. GPU gate records are exactly one at freeze. This proves image
identity for these held inputs at these measured states, not universal temporal
convergence. All twelve completed motion/held runs report zero dropped/delayed
frames.

## Why the early night lift target moves

The isolated grade records its actual raw lift strength immediately before
adaptive smoothing. Thirty-two consecutive original-prefix night records per
motion replay include this raw target, published mode and p10, p25, zone spread,
previous adaptive history, elapsed frame time, cut confidence and used strength.
Independent CPU evaluation reproduces the raw formula and recurrence; no new
units, precision or initialization defect is demonstrated.

| Night update, primary GZW entry run | p25 | Mode | p10 | Raw strength | Used strength |
|---|---:|---:|---:|---:|---:|
| 1 | 0.180664 | 0.242188 | 0.062683 | 0.443127 | 0.443127 |
| 2 | 0.042114 | 0.242188 | 0.053558 | 0.662315 | 0.554049 |
| 3 | 0.024597 | 0.203735 | 0.045685 | 0.955279 | 0.756372 |
| 4 | 0.015121 | 0.146362 | 0.038666 | 1.302142 | 1.077381 |
| 16 | 0.006889 | 0.023331 | 0.006599 | 1.500000 | 1.499838 |

Zone-standard-deviation suppression is zero throughout the measured night
window. The p10 guard changes only modestly near entry. The larger raw-strength
rise follows the changing p25/mode inputs to the quintic strength target. At
update four, holding only first-update p25 in the target formula yields 0.517886;
holding only first-update mode yields 0.797350, versus actual 1.302142. These
are independent numerical target interventions, not rendered image fixes or
additive contribution fractions.

The first confident cut snaps used strength to the then-current 0.443127 target;
the target is not yet the eventual 1.5. At update four the delayed cut pulse is
0.147705. Using the same previous state, target and elapsed time with only that
current cut blend removed gives used strength about 1.038429 instead of 1.077381:
the pulse adds approximately 0.038952 to the control coefficient. This is a
same-update recurrence counterfactual, not a replay with earlier cuts removed
and not an image ΔE. It is too narrow to claim that removing the detector pulse
would solve the dominant target transition.

Source inspection explains the mixed settling: the histogram smooths before
the percentile/mode consumers, percentile Kalman state has its own response,
mode resets from the already smoothed histogram, and p10 has its own EMA. A
grade cut reset therefore receives still-changing statistics. This identifies
consumer timing coherence for further assessment; it does not authorize changing
those rates, resetting all histories, using the rejected raw-median detector,
or accelerating slow key. The current gate-only treatment leaves these targets,
their producers and the existing adaptive-strength recurrence unchanged.

## Applied storage and validation

The applied correction uses a two-texel RGBA32F `AdaptiveHistoryTex`: the first
record retains film/lift/print/gamut values, and the second stores the direct
adaptation gate, ambient gate and explicit initialization flag. Reads use the
actual record centers 0.25 and 0.75. The existing adaptive-history pass writes
both records, preserving the grade's eight passes and all other history formats.
The detector and fractional cut-reset blend remain unchanged. No manual control
or profile change is introduced.

The existing 32.4/186.7-ms elapsed-time coefficients govern gate recovery and
restraint, with immediate suppression at confident cuts and raw-target startup.
`scene_cut` remains the original detector value for all existing adaptive
producers. The filtered adaptation gate reaches its existing direct Retinex and
chroma-scene-scale image consumers; the filtered ambient gate reaches ambient
tint. The original four adaptive target recurrences remain separate.

Two additional native replays compile the packed candidate while maintaining
an independent gate-state witness. All eight packed/independent/actual image
controls are pixel-identical. A synthetic GPU probe executes the actual
`BuildSceneCtx` and `AdaptiveHistoryPS` with injected observations and elapsed
times. It records both history texels over 256 updates: simulated 30/60/144
cadences and a variable sequence including zero dt and 250-ms hitches, startup,
confident cuts, fractional cuts and recovery. Independent CPU recurrence error
is at most 0.000000127 across both records; a fresh repeat is pixel-identical.
These tests validate record addressing, cold-start flags, recurrence and the
retained first record. They do not certify whole-pipeline hitch behavior or
physical high-refresh presentation.

The applied source is byte-identical to the canonical tested candidate.
Profiles, active configs, header comments, previous tap-spacing/spatial fixes,
all existing history rates and SDR output remain. The additional gate state
is internal; `creative_values.fx` remains the only user-facing tuning surface.

Two final fresh replays compile the actual shared `general/grade/grade.fx` include
under GZW and Arc profiles. All eight native shared/full/independent/actual
controls match exactly, and both runs have zero dropped/delayed frames. One
earlier shared-include diagnostic failed because a readback helper was declared
after use; its failed report/config/log are retained separately. Moving that
diagnostic declaration fixed the harness without changing the shared candidate.

The final read-only audit passes 653 checks across 605 unique artifacts. Sixteen
successful native/held replays plus two synthetic probe runs report zero
dropped/delayed frames. All 46 native full/actual controls and 16 packed/shared
independent-state controls are pixel-identical. Both failed diagnostics remain
separate. All 22 tooling tests and the whitespace check pass. This supports
the scoped gate repair; early/later lift settling and complete-chain acceptance
remain open.

Local artifacts under
[captures/gate_fullres_20261027/](../captures/gate_fullres_20261027/) retain runners,
source-prefix verification, isolated candidates, native frozen images, context
records, raw-target/recurrence checks, plots and masked contact sheets.

Remaining work includes early lift-target coherence, later specular-protection
release and smaller zone settling. Preserve useful steady-state lift, profiles,
existing time constants and spatial repairs. Larger timing variation, dense
unique gameplay, physical high refresh, remaining aspects/resolutions, broader
games and active separate-chain resource sharing remain open. No effectiveness
re-score or complete temporal acceptance follows.

Follow-up: the [current-observation lift-consumer screen](2026-10-27_lift_consumer_screen.md)
now reduces the measured night peaks with consumer-local observations while
retaining the detector and producer histories. Its changed incoming image needs
native material/held/noncut checks; no lift candidate is adopted.
