# Validation workflow

All runtime work is private and headless. GPU/localhost access requires sandbox
escalation. Never change focus or physical displays or fall back to the desktop.
A failed private display stops the run. [PLAN](PLAN.md) selects work;
[HANDOFF](HANDOFF.md) identifies current code and profiles.

## Tooling check

```bash
python3 -B -m unittest discover -s tests -p 'test_diagnostics.py'
```

This checks tooling/error handling, not GPU shader correctness. Golden-image
testing is retired. Do not run GPU throughput/profiling probes.

## Matched captures

```bash
python3 -B tools/compare_frame.py gamespecific/gzw/analysis/reference/autof_20260515_133058.png --all-effects --game gzw --config gamespecific/gzw/gzw_stronger_trial.conf --only FILM_CURVE RETINEX BLACKS_WHITES --delay 5 --settle 20 --keep
```

For Arc, use `--game arc_raiders`, an Arc reference and
`--config gamespecific/arc_raiders/arc_raiders_pipeline_trial.conf`.
Check config identity before reuse. `--only CORRECTIVE_GATE TONAL_GATE CHROMA_GATE
LOOK_GATE` isolates stages; omit `--all-effects` for a simple pair. `--baseline`
disables vkBasalt for a source transfer check. Use `--help` for current options.

The private backend uses Gamescope/gamescopectl, mpv, FFmpeg, ImageMagick and
script Python dependencies. Legacy visible `tune`, `capture` and `stage_isolate`
commands are not the unattended validation path. Access is serialized.

`--all-effects` uses byte-exact lossless 30-fps RGB clips, fresh processes,
equal gates, an unchanged FULL repeat and active-knob ablations; it restores
the profile. Verify restoration and preserve all identities and logs.

Use `--delay 5 --settle 20` for small effects; default settling is only five
seconds. Continuous warmup is a protocol, not proof of convergence. Changes near
repeat variation are inconclusive. Dimensions must match source/private display;
mask the activity marker and any diagnostic footprint consistently. Also mask the
last row: headless captures can carry a corrupt bottom row (2026-11-09: 2048 px, row 1439).
Single captures occasionally land a whole-frame offset of a few codes (2026-11-09/10:
2.4 codes on all bright pixels of Arc 211202); repeat before attributing it to code.
**Single-PNG mode does not settle temporal state** (found 2026-11-10). mpv shows a still
image without a steady frame stream, so frame-time EMAs stall: after 20 s, smoothed entropy
read .04–.16 instead of .75 and the adaptation gate .38–.44 instead of 1.0, varying per run
(0.1–0.9 code tonal noise; Retinex, zone and film strengths below their in-game values).
Single-PNG mode now plays the still as a lossless looping 30-fps clip (`_make_loop_clip`,
as `--all-effects` and `--transition` do); repeats are bit-identical. Single-PNG comparisons
before 2026-11-10 compared two equally unsettled states.

**Pan check (no motion source needed):** feed the same still shifted 0–7 px (all phases
of the 1/8 lane), shift each capture back and compare with shift 0; changes are what a
slow pan shows as shimmer. Scripts: `captures/light_lift_20261109/analyze_pan*.py`,
refs in `pan_refs/`. It is a static 8-phase simulation, not dense motion.

Before interpreting results, match source, normalized shader body, profile,
config, includes and producers. Historical labels alone are insufficient. Keep
failed repeats and incorrect variants separate. Inspect old scripts before
importing/running; never overwrite frozen evidence.

## Motion and cuts

```bash
python3 -B tools/compare_frame.py gamespecific/gzw/analysis/reference/autof_20260515_133058.png --transition gamespecific/gzw/analysis/reference/autof_20260515_133932.png --game gzw --config gamespecific/gzw/gzw_stronger_trial.conf --delay 5
```

`--transition` plays first/second/first for 20/8/20 seconds at 30 fps with fresh
processes. Do not repeat completed fixed-pair audits without a concrete new need.

The [Babylon runner](tools/babylon_scene/README.md) provides private export/replay.
Cached source: `captures/babylon_scene_runs/20261024_160908/motion-source/`.
Verify manifest, hashes, 20-second pre-roll and 15-source-poses/sec protocol.
Duplicated 30-fps poses and sparse matches do not establish dense continuity.

Pose/token equality can cover different GPU updates at a cut. Source-only
summaries use `identity_scope=source_pose_and_token`. For temporal repeats, read
integer `render_phase={source_update, cut_update}` explicitly on GPU and use
`matched_motion`/`summarize_motion` with `require_render_phase=True`. Reject
missing/conflicting ages; host mpv time cannot supply them. See the
[phase-alignment audit](research/2026-10-26_return_cut_alignment.md).

For cached cut diagnostics, pose 2220 belongs only to the appended tail. Mask
atlas tags, borders and calibration patches on common support. Overlapped timer
channels are invalid. Diagnostic holds/bypasses do not freeze ordinary histories.
Consult the [cut coverage](research/2026-10-27_temporal_cut_coverage.md) and
[night attribution](research/2026-10-27_night_settling_attribution.md) before reuse.

## Offline shadow-mask review

The local BDRAR tester uses CPU inference on still images; it does not access a
display, GPU or network. With the isolated environment and inspected model in
the current workspace, run into a **new** output directory:

```bash
captures/shadow_detector_env_20261107/bin/python -B tools/shadow_detector.py --vendor captures/shadow_detector_bdrar_20261107/vendor --weights captures/shadow_detector_bdrar_20261107/model.pth --output captures/shadow_detector_bdrar_20261107/new_review
```

Optional positional image paths replace the five defaults. The output contains
the input, raw floating-point probability, an 8-bit visualization, a red overlay,
a .5 threshold preview, hashes and a local HTML review. Do not interpret .5 as
a calibrated threshold, masks as material color, or still-image inference as
gameplay performance. Model provenance, local compatibility changes and observed
limitations are recorded in [the offline detector report](research/2026-11-07_offline_shadow_detector.md).

## Readback, measurements and artifacts

Screenshots contain no offscreen highway/history telemetry. Use an explicit
diagnostic render/readback when needed; preserve encoding, precision and source
identity. `capture --dump` and `--no-frame` are unsupported.

```bash
python3 -B tools/analyze_delta.py before.exr after.exr
python3 -B tools/noise_floor.py before.exr after.exr --json-out noise.json
```

Delta-E measures change; positive delta-L is brighter and positive delta-C more
chromatic. Interpret hue, separation, clipping and noise with material context
and repeat uncertainty. Noise checks do not establish universal acceptance.

Each runtime prints `/tmp/shader-runtime-*/` with mpv/vkBasalt logs; inspect
frame-drop/delayed counters. `--keep` retains paired images in game analysis
outputs. Typical JSON outputs are `compare_agg.json` and `full_analysis/latest.json`.
Read each result’s identities. Reports are versioned in `research/`; captures,
diagnostic configs/scripts, media and caches remain local and ignored.
