# Tools

All tools live in `tools/`; many are also exposed as shell/fish functions.
Run Python tools with `--help`. Assess changes against [GOAL.md](GOAL.md) and
follow [PLAN.md](PLAN.md): fuller color distinctions and nuanced shadow depth,
with unobtrusive behavior across games. Delta magnitude is not a quality score.
Runtime tests stay private and headless. The visible tools below are documented
for explicit interactive use; do not launch them as unattended validation.

## Capture / Tuning

```text
auto_capture --game arc_raiders --interval 20 --max-frames 24
screenshot arc_raiders
tune --game arc_raiders --delay 5
```

Reference PNGs are pre-pipeline screenshots in
`gamespecific/<game>/analysis/reference/`. `tune` opens them through
`mpv + vkBasalt` and restarts on `creative_values.fx` edits.

## Analysis

```text
compare_frame gamespecific/<game>/analysis/reference/frame.png --game <game>
compare_frame --all --game <game> --delay 5
compare_frame --all-effects --game <game> --max-frames 12 --delay 5
compare_frame --all-effects --game <game> --only FILM_CURVE EXPOSURE
compare_frame gamespecific/gzw/analysis/reference/frame.png --game gzw --config gamespecific/gzw/gzw_stronger_trial.conf
compare_frame gamespecific/gzw/analysis/reference/autof_20260515_133932.png --all-effects --game gzw --config gamespecific/gzw/gzw_stronger_trial.conf --only CORRECTIVE_GATE TONAL_GATE CHROMA_GATE LOOK_GATE --settle 20 --keep
compare_frame gamespecific/gzw/analysis/reference/autof_20260515_133058.png --transition gamespecific/gzw/analysis/reference/autof_20260515_133932.png --game gzw --config gamespecific/gzw/gzw_stronger_trial.conf
compare_frame gamespecific/gzw/analysis/reference/autof_20260515_133932.png --perf-probe --game gzw --config gamespecific/gzw/gzw_stronger_trial.conf
stage_isolate --game <game> --delay 5
analyze_delta before.exr after.exr
analyze_delta --colorchecker captures/session.exr
python3 tools/noise_floor.py before.exr after.exr --json-out noise.json
```

`compare_frame` now defaults to a private Gamescope headless GPU display.
It creates no desktop window, changes no focus or monitor mode, and captures
post-vkBasalt output with `gamescopectl`. You can use other applications while
it runs. It requires Gamescope/gamescopectl and refuses to fall back to desktop
capture. Use `--capture-backend desktop` explicitly for the old visible path.
`--baseline` disables vkBasalt for a single-reference transfer check. The
20-second settling protocol remains; background execution does not accelerate
time-based shader histories. Babylon now also defaults to a private display;
its [runner documentation](tools/babylon_scene/README.md) covers exact source
identities, cached lossless motion and repeat/coverage validation. `tune`,
`capture` and `stage_isolate` retain visible-desktop workflows.

`compare_frame --all-effects` captures the full pipeline, zeroes each effect's
active knobs, measures full-minus-effect delta, and restores `creative_values.fx`.
Both sides use stage gates at 100. An optional positional PNG selects one reference.
It converts each source PNG into a byte-exact lossless FFV1 RGB clip (requires
FFmpeg), restarts mpv per image, waits `--delay` for compilation and `--settle`
for continuous playback (default 5 seconds), and records source/reference
SHA-256 hashes. It rejects paused/stalled playback and pauses only at the
settled capture point before the private-display screenshot. This is a fixed startup
protocol, not a guarantee of steady state. Use `--settle 20` for small effects.
Older still-image `--settle` results did not have continuous rendered frames;
do not use them as evidence of temporal convergence. `--keep` retains paired
PNG captures under `full_analysis/.../captures_<timestamp>/`.
An unchanged FULL repeat measures capture/history variation before effect ablations;
small effect deltas near that baseline are inconclusive.

mpv is launched without user configuration, with an explicit sRGB/BT.709 target.
Diagnostics serialize capture/profile access, use a private IPC socket, and print
`/tmp/shader-runtime-*/` log paths. An absent activity marker or failed IPC command
fails the comparison. Use a reference with the same dimensions as the display.
`analyze_delta` masks the intentional top-left 2×2 marker and reports endpoint
occupancy. DeltaE measures change, not improvement in fidelity.

`capture` writes RGB EXRs only. HighwayTex is offscreen: `--dump` and `--no-frame`
fail explicitly instead of decoding scene pixels as telemetry. Deliberate
readback requires an instrumented technique that renders diagnostic values;
see [history attribution](research/2026-10-24_shadow_history_readback.md).

Current effect list:

```text
INVERSE_STRENGTH INVERSE_LUMA EXPOSURE BLACKS_WHITES FILM_CURVE
3WAY_CC MID_TEMPERATURE LUMA_CONTRAST CONTRAST RETINEX ZONE_CONTRAST
SHADOWS SHADOW_LIFT HUE_ROTATION VIBRANCE SATURATION PRINT_STOCK
PRINTER_LIGHTS CORRECTIVE_GATE TONAL_GATE CHROMA_GATE LOOK_GATE
```

`stage_isolate` measures cumulative gates:

```text
CORRECTIVE -> +TONAL -> +CHROMA -> +LOOK
```

`stage_isolate` uses the game's default config and paused PNG playback. For the
combined GZW trial and temporal stage checks, use `compare_frame --all-effects`
with the four `*_GATE` labels instead. Input black/white mapping and FilmCurve
sit outside those gates in `ColorTransformPS`.

`--transition` plays first/second/first references for 20/8/20 seconds at 30 fps,
capturing each target from a fresh playback paused only for the output screenshot.
It saves PNGs, same-source temporal deltas and mpv drop counters. GPU cost profiling is deprioritized; do not run it without a new request. The
existing `--perf-probe` stress-plays a 120 fps FFV1 clip with MangoHud; add `--perf-baseline` to disable
vkBasalt for a paired baseline. These mpv data do not measure in-game GPU time.

## Validation

There is no golden-image regression suite. Use matched captures, stage isolation,
effect attribution, and `tools/noise_floor.py` for validation.
Tool regression checks: `python3 -B -m unittest discover -s tests -p 'test_diagnostics.py'`.

## Outputs

```text
gamespecific/<game>/compare_agg.json
gamespecific/<game>/full_analysis/latest.json
gamespecific/<game>/analysis/YYYY-MM-DD/
gamespecific/<game>/captures/
```

## Delta Scale

| DeltaE_oklab | Meaning |
|--------------|---------|
| `< 1` | usually imperceptible |
| `1-3` | subtle |
| `3-6` | clearly visible |
| `> 6` | large error/change |

`DeltaL* > 0` is brighter. `DeltaC* > 0` is more saturated. `Deltah* > 0`
means positive angular rotation in the Oklab a/b plane; the destination hue
depends on the starting hue.
