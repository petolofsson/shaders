# Tools Reference

All tools live in `tools/` and are exposed as fish functions. Run any tool with `--help` for full options.

---

## Collection

### `auto_capture`
Automated reference frame collection during gameplay.

Runs in the foreground, screenshots every `--interval` seconds, rejects loading screens and
near-duplicate scenes, and saves keepers to `gamespecific/<game>/analysis/reference/autof_<ts>.png`.
Stop with Ctrl-C.

```
auto_capture                        # auto-detect game from SHADER_GAME env var
auto_capture --game gzw             # explicit game
auto_capture --interval 10          # faster capture (default: 20s)
auto_capture --max-frames 24        # prune oldest beyond this limit (default: 24)
auto_capture --min-diff 12          # min pixel diff to accept a frame (default: 12)
```

### `screenshot [game]`
Single reference frame via spectacle. Auto-detects game from `SHADER_GAME` if not passed.
Saved to `gamespecific/<game>/analysis/reference/<timestamp>.png`.

---

## Tuning

### `tune`
Live visual tuning. Opens all reference frames as an mpv playlist with vkBasalt active.
Watches `creative_values.fx` — restarts mpv automatically on every save (~3 s SPIR-V compile).

```
tune                                # default game: arc_raiders
tune --game gzw
tune --delay 5                      # longer SPIR-V wait for slow machines
tune --no-watch                     # disable auto-restart; reload manually
```

Controls in mpv: `>` / `<` to cycle frames · `q` to quit.

---

## Analysis

### `compare_frame`
Before/after perceptual analysis. Renders a reference PNG through the current pipeline,
captures the result, and reports ΔE_oklab with ΔL* / ΔC* / Δh° per tonal zone and hue band.

```
compare_frame gamespecific/gzw/analysis/reference/frame.png
compare_frame --all --game gzw           # batch over all reference frames
compare_frame --all --game gzw --keep    # also save EXRs to analysis/YYYY-MM-DD/frames/
compare_frame --all-effects --game gzw   # per-effect isolation (see below)
compare_frame --delay 5                  # longer SPIR-V wait
```

Aggregate output: `gamespecific/<game>/compare_agg.json` (also archived to `analysis/YYYY-MM-DD/`).

`--all-effects` captures FULL pipeline once, then for each named effect zeroes its knobs to
passthrough and diffs the two outputs (incremental subtraction). ΔE = how much that individual
effect changes the image in full-pipeline context. Effects with ΔE < 0.5 flagged as silent.
Effects whose knobs are already at passthrough are skipped automatically.
~22 effects tested: INVERSE_STRENGTH, INVERSE_LUMA, EXPOSURE, BLACKS_WHITES, DIR_COUPLER,
HALATION, FILM_CURVE, 3WAY_CC, CLARITY, LUMA_CONTRAST, CONTRAST, SHADOWS, HIGHLIGHTS,
SHADOW_CAST, HUE_ROTATION, VIBRANCE, SATURATION, PRINT_STOCK, BLEACH_BYPASS, PRINTER_LIGHTS,
DIFFUSION, GRAIN.
Results written to `gamespecific/<game>/full_analysis/effects_YYYY-MM-DD_HHMMSS.json` (timestamped)
and `latest.json`. Each file includes per-effect stats, zone/hue-band deltas, and a snapshot of
`creative_values.fx` at run time — intended for AI-assisted analysis.

### `stage_isolate`
Additive stage attribution. Runs four cumulative configurations and measures each stage's
perceptual contribution. Saves and restores creative_values.fx gate values on exit (even on Ctrl-C).

```
stage_isolate --game gzw
stage_isolate --game gzw --delay 5
```

Stages: CORRECTIVE → +TONAL → +CHROMA → +LOOK.
Output: `grade_callsheet.txt` at game root + archived copy in `analysis/YYYY-MM-DD/`.

### `analyze_delta`
Low-level ΔE_oklab comparison between two EXR files. Also supports absolute ColorChecker mode.

```
analyze_delta before.exr after.exr
analyze_delta --colorchecker captures/session.exr   # absolute vs. BabelColor D65
analyze_delta --colorchecker                         # uses most recent capture
```

---

## Baselines

### `bless_all`
Promote current pipeline output to golden baselines for all four test images
(gradient, colorchecker, highlights, skintones). Runs mpv once for the full set,
then verifies each result against the freshly written golden.

```
bless_all --game gzw
bless_all --game gzw --rebless      # overwrite existing goldens
```

### `check_all`
Compare current output against existing goldens. Exits non-zero on any failure.

```
check_all --game gzw
```

---

## Utilities

### `capture`
EXR snapshot of the current screen. Used internally by analysis tools; rarely called directly.

```
capture --game gzw --screen right
```

Saves to `gamespecific/<game>/captures/`.

### `make_test_images`
Generate synthetic input images for the baseline suite: gradient ramp, 24-patch ColorChecker,
highlight patches, and Fitzpatrick skin tone patches. Output to `tests/inputs/`.

```
python3 tools/make_test_images.py
```

---

## ΔE_oklab scale

| Range | Perception |
|-------|-----------|
| < 1.0 | Imperceptible |
| 1 – 3 | Subtle / acceptable |
| 3 – 6 | Clearly visible |
| > 6   | Gross error |

ΔL* > 0 = brighter · ΔC* > 0 = more saturated · Δh° > 0 = hue toward yellow.

---

## Analysis file layout

```
gamespecific/<game>/
  analysis/
    reference/              ← pre-pipeline PNGs collected by auto_capture / screenshot
    YYYY-MM-DD/
      compare_agg.json      ← archived aggregate delta for that session
      grade_callsheet.txt   ← archived call sheet for that session
      frames/               ← EXRs from compare_frame --keep
  compare_agg.json          ← latest aggregate (overwritten each run)
  grade_callsheet.txt       ← latest call sheet (overwritten each run)
  captures/                 ← raw EXR snapshots
```
