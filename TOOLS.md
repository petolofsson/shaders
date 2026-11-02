# Validation Tools

Use [PLAN.md](PLAN.md) for priorities and [AGENTS.md](AGENTS.md) for rules.
All runtime validation remains private and headless: no desktop fallback,
focus changes or physical display changes. Commands use repository entry points
rather than assuming local shell aliases.

## Diagnostic tests

```bash
python3 -B -m unittest discover -s tests -p 'test_diagnostics.py'
```

Twenty-two tests currently pass. They check tooling/error handling; GPU shader
contracts need runtime evidence. There is no golden-image suite.

## Matched captures and effect attribution

```bash
python3 -B tools/compare_frame.py gamespecific/gzw/analysis/reference/autof_20260515_133932.png --game gzw --config gamespecific/gzw/gzw_stronger_trial.conf --delay 5 --settle 20 --keep
python3 -B tools/compare_frame.py gamespecific/gzw/analysis/reference/autof_20260515_133058.png --all-effects --game gzw --config gamespecific/gzw/gzw_stronger_trial.conf --only FILM_CURVE RETINEX BLACKS_WHITES --delay 5 --settle 20 --keep
python3 -B tools/compare_frame.py gamespecific/gzw/analysis/reference/autof_20260515_133932.png --all-effects --game gzw --config gamespecific/gzw/gzw_stronger_trial.conf --only CORRECTIVE_GATE TONAL_GATE CHROMA_GATE LOOK_GATE --delay 5 --settle 20 --keep
```

For Arc use `--game arc_raiders`, an Arc reference, and
`--config gamespecific/arc_raiders/arc_raiders_pipeline_trial.conf`.
Both active configs now exactly match their verified combined trials. They use
one pipeline effect, so adaptive resources are available to their consumers.

The private backend requires Gamescope/gamescopectl and captures after vkBasalt.
Other dependencies include mpv, FFmpeg, ImageMagick and script Python libraries.
A failed private display must stop the run. Legacy visible tools (`tune`,
`capture`, `stage_isolate`) are not the unattended validation path. Use `--help`
for CLI options; do not select the desktop backend.

`--all-effects` creates byte-exact lossless 30 fps RGB clips, starts fresh mpv
processes for images/configurations, enforces equal gates, captures an unchanged
FULL repeat, ablates active knobs and restores the tuning profile. Access is
serialized. Preserve source/reference/config/profile hashes and inspect logs
and dropped/delayed counters.

Use `--delay 5 --settle 20` for small effects; the default settle is only five
seconds. Warmup is a fixed protocol, not proof of convergence, especially for
a 20-second-half-life history. Older paused-image claims are not convergence
evidence. Deltas near unchanged-repeat variation are inconclusive.

`--baseline` disables vkBasalt for a single-reference transfer check. Capture
dimensions must match the source/private display. The intentional 2x2 red
activity marker is required and masked in strict image tests.

## Motion and cuts

```bash
python3 -B tools/compare_frame.py gamespecific/gzw/analysis/reference/autof_20260515_133058.png --transition gamespecific/gzw/analysis/reference/autof_20260515_133932.png --game gzw --config gamespecific/gzw/gzw_stronger_trial.conf --delay 5
```

`--transition` plays first/second/first for 20/8/20 seconds at 30 fps, capturing
targets from fresh processes. Do not repeat the completed fixed-pair audit
without a new demonstrated need. Other cuts and dense motion remain open.

The [Babylon runner](tools/babylon_scene/README.md) provides private source export,
lossless replay and exact source matching. Cache:
`captures/babylon_scene_runs/20261024_160908/motion-source/`. Verify its manifest,
clip hashes, 20-second pre-roll and 15-pose/sec protocol before reuse. Duplicate
30 fps playback and sparse matches do not establish dense continuity.

Pose/token equality does not identify which duplicated presentation or GPU
history update was captured at a cut. Ordinary motion summaries label their
`identity_scope` as `source_pose_and_token`; they are not phase-aligned temporal
repeat evidence. With explicit GPU readback, supply each capture's integer
`render_phase = {"source_update": ..., "cut_update": ...}` and call
`matched_motion` / `summarize_motion` with `require_render_phase=True`.
Strict mode rejects missing or mismatched phases and still requires window
coverage. Never infer these ages from host mpv time. The
[return-cut audit](research/2026-10-26_return_cut_alignment.md) demonstrates why.

## GPU readback and measurements

Ordinary screenshot pixels cannot reveal offscreen highway/history data.
`capture --dump` and `--no-frame` are unsupported. Explicit diagnostic techniques
may render values, binary fields or histories for readback. Preserve source
equivalence, encoding/precision assumptions and masks; diagnostic strips must
not contaminate image metrics. See [slow-key](research/2026-10-25_slow_key_precision.md)
and [metadata](research/2026-10-25_highway_resolution.md) probes.

```bash
python3 -B tools/analyze_delta.py before.exr after.exr
python3 -B tools/noise_floor.py before.exr after.exr --json-out noise.json
```

Use noise-floor checks when dither/quantization changes warrant them. DeltaE
measures change, not quality. Positive DeltaL is brighter; positive DeltaC is
more chromatic. Hue is angular and needs source-material context. Report
clipping, separation and repeat uncertainty together. GPU profiling remains
deferred; do not run throughput/performance probes.

## Latest assessment evidence

The [shared tonal-base decision](research/2026-11-02_tonal_architecture.md) is
adopted and active in both combined configs. Retinex, zone shaping and lift use
a common brightness base estimated from the existing full-resolution native
guide, with smooth source-range rejection and continuous overlapping-window
weights. Original corrected-pixel detail is carried through their combined gain.
The original relative Retinex spatial correction and prescribed chroma treatment
remain. No profile/config/header, inverse, history/rate/resource or pass change
is introduced; grade stays eight passes.

Selected local shade response improves about 2.2% bedroom cloth, 4.3% plaster,
3.8% floor and 3.3% interior cool window. Seven selected held pairs and current
baseline pairs are exact, with the original vivid baseline failure explicitly
retained. Two numerical GPU readbacks, two exact tonal-zero pairs, both chart
profiles, 192 exact measured candidate/ordinary controls and four actual-config
outputs matching the candidate exactly pass. Flat-face median edge L/C gaps
are zero in all 18 records. Road/paving contrast expansion, small vehicle/metal/
shelf/cloud/halo, quantization and transition costs remain. Temporal repeats
reach one code. The subsequent requested ratings review estimates chain/grade
at 78 and the joint tonal model at 80; individual effect scores remain retained.
Dense/high-refresh and performance claims remain limited.
The 70 fresh private GPU processes have zero drops/delays; the audit checks
307 files / 652 images. All 22 tooling tests and whitespace checks pass.

Current source/profile/config and old/new grade hashes are in
`captures/tonal_base_20261102/verification.json`; review is local
`captures/tonal_base_20261102/review.html`. The original vivid baseline pair
varies in 78 pixels by up to 16 codes. An incorrectly named refresh ran a
rejected prototype and is excluded; a separately captured preserved-original
reference pair is exact. Normalized baseline shader bodies are now checked
independently of labels. Both failures remain recorded. No universal repair is
inferred. No further mandatory screen is queued. The user authorized committing
and pushing this completed work with the ratings update; use HEAD/upstream
tracking for publication state.

The user-set BLACKS=0.0025 values are preserved. The older Arc trial supports
its Arc scope; November 2 captures supply current-profile actual-config output
identities for both games. Do not reuse old weak-color or Arc-trial output as
current-grade output. For baseline reuse, compare actual normalized shader bodies
and complete source/profile/config/include/producer identities. Labels alone
are insufficient. Frozen experimental scripts retain their original baselines;
do not blindly rerun them against current production.

The latest [weak-material color decision](research/2026-10-31_weak_material_colors.md)
adds 41 ordinary captures, two GPU readbacks, four measured cut replays and four
actual-config outputs. Seven final held pairs and look-zero pairs are exact;
192 same-update extraction controls are exact. Actual outputs match candidates
exactly. Standard and dedicated low-saturation charts cover both profiles. CPU
helper sweeps and independent GPU reference checks pass. Unrestricted/half
candidates remain labelled separately; the brightness guard preserves the prior
cloud palette and core gain. Material/hue/quantization and small transition costs
are documented. Current hashes: `captures/weak_color_20261031/verification.json`.
No further mandatory test screen or score increase follows.

The [highlight-cooperation decision](research/2026-10-31_highlight_cooperation.md)
adds 28 ordinary captures (including two targeted zero repeats), two numeric
readbacks, four measured history replays and four actual-config outputs. Six
held pairs are exact; 192 same-update candidate/actual controls are exact. Actual
configs match candidates exactly. Arc zero pairs/GZW look-zero are exact; GZW
FilmCurve-zero retains one persistent one-code pixel with exact within-control
repeats. No bit-exact identity is claimed for that cross-pair. All processes have
zero drops/delays. Source/current profile epochs and scalar/hue-ramp/temporal
limits are documented. Use `captures/highlight_cooperation_20261031/verification.json`
for that checkpoint's grade/profile hashes; use the latest weak-material hashes
for that shared-shader checkpoint, subject to the profile epochs above. Earlier
helpers have different internal signatures.
No new score or mandatory follow-up is queued.

The preceding [print/inverse preservation decision](research/2026-10-31_print_inverse_color_preservation.md)
adds 46 ordinary captures, six numeric readbacks, four independent measured
history replays and four actual-config captures. Seven final held pairs and two
zero pairs are exact; 384 full/actual controls include 192 new and 192 verified
prior controls. Actual-config full/repeats match selected candidates exactly.
Both focused estimates are borderline 75; this is not a fresh chain rating.
Temporal repeats retain up to two codes, and material/palette/quantization costs
remain documented. The 10-step scalar failure, rejected blanket gamut margin,
print candidates and initial strict numeric oracle are preserved. Use
`captures/color_preservation_20261031/verification.json` for that checkpoint's
shader/profile hashes. Earlier inverse/print outputs are historical baselines, not current
outputs. All 22 tooling tests and whitespace checks pass. No new queue follows.

The [inverse-chroma decision](research/2026-10-31_inverse_chroma.md) adopts a
rich-color reconstruction budget after rejecting blanket half strength. Passing
validation includes 43 ordinary images, two 9,216-record numeric readbacks,
twelve independent history replays with 576 exact full/actual controls and four
actual-config outputs matching current candidates exactly. Source/profile epochs
are explicit: the original GZW-day repeat varies one code; current refreshed GZW
pairs and the other original pairs are exact. An external GZW tint -0.015 is
preserved; affected GZW evidence is refreshed, while the muted case remains
prior-tint evidence. The initial overly tight numeric identity check and explicit
no-expansion follow-up are retained separately; no shared-gamut repair is inferred.
Use `verification.json` and `refresh_report.json` in `captures/inverse_chroma_20261031/`
for that historical baseline scope; current reuse must also match the newest
verification above, including inverse, grade and profile hashes.
Small palette, quantization and Arc daylight-step costs remain. The finite task
is closed without a universal 75+ or dense-motion acceptance claim.

The [three-way CC decision](research/2026-10-31_three_way_cc.md) adopts authorized
half-strength shadow tuning in both creative profiles, with no shader changes.
Twenty-five fresh ordinary captures, seven exact selected held pairs, four
measured-phase cut replays and both actual-config full/repeats support it.
All 192 full/actual controls are exact on the common masked support; half temporal
repeats vary by at most one code (maximum mean ΔE 0.001289 GZW / 0.005196 Arc).
One-code near-black, blue-pair/palette and first-night-step costs remain. The
audit verifies CC-only profile scope and unchanged shaders/configs. Artifacts:
`captures/three_way_cc_20261030/`. Use its verification/profile hashes and half/
repeat images only for verified historical reuse: later shaders and profiles
require the latest baseline above.
The finite tuning decision is closed; no dense/native/new-game claim follows.

The [print/look decision](research/2026-10-30_print_look_preservation.md) adopts
only secondary shoulder restraint after rejecting the shadow-toe candidate.
Fourteen tone/color attribution captures, nineteen completed candidate captures,
seven exact final held repeat pairs, a 7,680-record GPU transfer probe, four
measured cut replays and both actual-config full/repeats support the decision.
All 192 extracted full/actual controls are exact on the common masked support;
phase-matched temporal repeats retain up to one code of variation. Selected dark
materials/halo are unchanged; blue quantization and daylight-step costs remain.
Artifacts: `captures/print_look_20261030/`. Profiles/configs are preserved and
the finite screen is closed; no dense continuity or new-game claim follows.

The [October 29 effect ratings](research/2026-10-29_effect_ratings.md) reassess the
existing code/profiles without tuning. Forty-two fresh ordinary captures and
three procedural dither diagnostics supplement five verified current-code scene
full/repeat pairs; two new scenes add fresh repeats. All seven scene pairs and
the dither pair are identical. Below-target inverse/CC/print quality estimates
remain explicit. The local `captures/effect_reassessment_20261029/` review has
source/full/bypass images, material metrics and an interactive comparison. These
are scoped visual judgments, not universal acceptance or a restored golden suite.

The [shadow-stage attribution/preservation decision](research/2026-10-29_shadow_stage_preservation.md)
uses five paired GPU stage readbacks and two guarded numeric observations to
separate reconstruction loss, manual black-offset costs and later print treatment.
The guarded common-gain candidate is applied on its measured scope, retaining
vehicle/wood/metal and quantized-gradient costs. Six real screenshots, original
and active dark boundary fixtures, repeats, exact zero-strength bypass, 96
same-update ordinary controls and both actual-config full/repeats pass. Clip
frames are source-exact; rendered input is independently observed rather than
assumed identical to file RGB. Artifacts: `captures/shadow_attribution_20261029/`.
No dense continuity, new game/resolution, performance result or re-score follows.

The [Retinex material-preservation decision](research/2026-10-27_retinex_material_preservation.md)
adopts a gentler native response with the original relative spatial correction.
Seven real cases plus a shared native boundary source under both profiles retain
identical candidate repeats and add no clipping. Separate gain/composition GPU
probes, 96 exact same-update full controls, a zero-strength bypass and actual
active-config full/repeats pass. Small shadow/cloud/sky and daylight timing costs
remain; sparse motion does not certify dense continuity. Local artifacts and
rejected direct curves remain in `captures/retinex_material_20261027/`.

The [tonal-selectivity decision](research/2026-10-27_tonal_selectivity.md) adopts
current-source inverse restraint after rejecting lift taper and joint restraint.
Six final held sources have pixel-identical baseline and candidate repeats; new
p75/publication/fallback GPU probes pass. Two-profile measured cut comparisons
show nonintervention in those windows, not moving engaged-restraint acceptance.
Both actual configs' full/repeats match the isolated candidate exactly. Current
p75 uses cache record-three B and highway 218; all original histories/rates remain.
Local artifacts and rejected variants stay under `captures/tonal_selectivity_20261027/`.

The [blue-cusp repair](research/2026-10-27_gamut_continuity_repair.md) combines
explicit GPU contracts, two-profile charts and measured-phase motion checks.
The [wall/sky report](research/2026-10-27_wall_sky_attribution.md) distinguishes
image ablations from explicit cumulative-stage readback. The
[material/highlight report](research/2026-10-27_material_highlight_coverage.md)
adds twenty fresh captures and revalidates eight prior held views; twelve held
full/repeat pairs are identical. These are completed evidence, not new golden
references. Dark/core/normalization/hue/blue costs remain recorded. Next work
covers motion/cuts, variable timing and remaining resolutions. The
[filter-spacing audit](research/2026-10-27_filter_kernel_resolution.md) checks
actual production functions at four compiled dimensions and repairs their
integer-texture tap offsets; held native controls and all five repeats are
pixel-identical. Retained sparse
phases do not establish dense continuity or physical high-refresh behavior.

The [consecutive cut report](research/2026-10-27_temporal_cut_coverage.md) adds
32 night and 30 return updates within the original clip, across both profiles.
Pose 2220 is only in the appended tail. Atlas tags can sit inside a tile: use a
common spatial mask for their footprint in every compared source/output image,
in addition to cropping borders. Route-trace reports mark overlapped early
timer channels invalid; their detector/source fields remain valid. The naive
raw-median cut alternative is rejected for false triggers during daylight motion.

The [night attribution](research/2026-10-27_night_settling_attribution.md) evaluates
read-only image interventions against the same current histories and inputs.
Its full diagnostic must reproduce the actual post-grade output; all 320 such
controls match exactly. Native stride-16 tiles use a common mask for both the
new and older comparison-atlas tags, leaving 12,984 samples. Control holds do
not freeze producers or replace the ordinary graded history update.

## Logs and retained artifacts

The [lift closure](research/2026-10-27_lift_transition_repair.md) adopts the
current-source lift consumer after the earlier point screen. Both active configs
now use the verified combined path. Native/held, source/state and actual-config
checks are complete; do not repeat them without a concrete new failure.

The [native gate-recovery follow-up](research/2026-10-27_gate_recovery.md) reads
full-resolution frozen images across selected measured cut phases. Its longer
readback tail preserves the original video packet prefix exactly. Mask browser
calibration patches as well as borders and tag footprints. Raw-target diagnostics
observe actual lift strength before smoothing. Synthetic gate cadence/hitch
checks verify the new packed history and recurrence; they do not certify
whole-pipeline hitch behavior or physical high-refresh presentation.

The [transition screen](research/2026-10-27_transition_screen.md) maintains
independent candidate control histories while ordinary full histories advance.
Its 192 full/actual controls are pixel-identical; 48 measured keys per replay
include both cuts and daylight 1428/1432. Complete-product filter relocation
is rejected as a complete repair; that screen left gate recovery unadopted.
The native follow-up above applies the validated gate-only repair. Preserve
the same native sampling and common masks when comparing those candidates.

Every runtime process prints a unique `/tmp/shader-runtime-*/` log directory.
`--keep` retains paired images under game analysis outputs. Standard JSON paths
include `compare_agg.json` and `full_analysis/latest.json` beneath
`gamespecific/<game>/`. Read each result's profile/config/source before comparisons.

Reports in `research/` are versioned. Local captures, diagnostic scripts/configs,
motion media and vendor cache under `captures/` are ignored and not pushed.
Do not force-add them or restore synthetic golden fixtures. GPU/localhost access
requires the appropriate sandbox escalation, even for a private display.
