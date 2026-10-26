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
Use combined trials for adaptive behavior: default active configs retain the
known unavailable cross-effect resources.

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

## Logs and retained artifacts

Every runtime process prints a unique `/tmp/shader-runtime-*/` log directory.
`--keep` retains paired images under game analysis outputs. Standard JSON paths
include `compare_agg.json` and `full_analysis/latest.json` beneath
`gamespecific/<game>/`. Read each result's profile/config/source before comparisons.

Reports in `research/` are versioned. Local captures, diagnostic scripts/configs,
motion media and vendor cache under `captures/` are ignored and not pushed.
Do not force-add them or restore synthetic golden fixtures. GPU/localhost access
requires the appropriate sandbox escalation, even for a private display.
