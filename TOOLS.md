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
