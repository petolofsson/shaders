# Tools

All tools live in `tools/`; many are also exposed as shell/fish functions.
Run Python tools with `--help`.

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
stage_isolate --game <game> --delay 5
analyze_delta before.exr after.exr
analyze_delta --colorchecker captures/session.exr
python3 tools/noise_floor.py before.exr after.exr --json-out noise.json
```

`compare_frame --all-effects` captures the full pipeline, zeroes each effect's
active knobs, measures full-minus-effect delta, and restores `creative_values.fx`.

Current effect list:

```text
INVERSE_STRENGTH INVERSE_LUMA EXPOSURE BLACKS_WHITES FILM_CURVE
3WAY_CC LUMA_CONTRAST CONTRAST ZONE_CONTRAST_STRENGTH SHADOWS
RETINEX_STRENGTH SHADOW_LIFT_STRENGTH
HUE_ROTATION VIBRANCE SATURATION PRINT_STOCK PRINTER_LIGHTS
```

`stage_isolate` measures cumulative gates:

```text
CORRECTIVE -> +TONAL -> +CHROMA -> +LOOK
```

## Baselines

```text
python3 tools/bless_all.py --check --game arc_raiders --delay 5
python3 tools/bless_all.py --game arc_raiders --rebless
python3 tools/test_golden.py list
python3 tools/test_golden.py check gradient tests/golden/gradient.exr
```

Do not rebless automatically. Current Arc Raiders output fails old `dcc712f`
goldens and needs visual review first.

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
means hue moves toward yellow.
