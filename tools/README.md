# Shader Tuning Tools

Three-step workflow: collect reference frames → tune visually → measure the delta.

---

## Setup

Add to Steam launch options (right-click game → Properties):

```
SHADER_GAME=gzw ENABLE_VKBASALT=1 VKBASALT_CONFIG_FILE=/home/pol/code/shaders/gamespecific/gzw/gzw.conf VKBASALT_LOG_FILE=/tmp/vkbasalt.log gamemoderun %command%
```

`SHADER_GAME` lets the tools auto-detect which game is running.

---

## Step 1 — Collect reference frames

Reference frames are raw game screenshots **before** vkBasalt — the pipeline input.

Press `Home` in-game to toggle vkBasalt off, then:

```
auto_capture                  # runs in foreground; saves frames as you play (Ctrl-C to stop)
screenshot gzw                # single shot (game auto-detected if SHADER_GAME is set)
```

Frames are saved to `gamespecific/<game>/analysis/reference/`.

---

## Step 2 — Tune visually

```
tune --game gzw
```

Opens all reference frames as a playlist in mpv with vkBasalt active. Edit
`creative_values.fx`, save — mpv restarts automatically (~3 s).

Controls: `>` / `<` to cycle frames · `q` to quit.

---

## Step 3 — Measure the delta

```
compare_frame gamespecific/gzw/analysis/reference/frame.png   # single frame
compare_frame --all --game gzw                                 # all reference frames
```

Renders each reference frame through the current pipeline, captures the result, and
reports ΔE_oklab perceptual delta with directional ΔL*, ΔC*, Δh° per tonal zone and
hue band. `--all` runs every PNG in `analysis/reference/` and writes an aggregate
summary to `gamespecific/<game>/compare_agg.json`.

Options: `--game gzw` (auto-inferred from path; required with `--all`) · `--delay 5`
(longer SPIR-V wait) · `--keep` (save EXRs to `analysis/YYYY-MM-DD/frames/`).

---

## Step 4 — Stage isolation + call sheet

```
stage_isolate --game gzw
```

Runs four cumulative configurations (CORRECTIVE → +TONAL → +CHROMA → +LOOK), measures
each stage's perceptual contribution, and writes `grade_callsheet.txt` combining the
current knobs, delta analysis, and plain-language attribution. Knobs restored on exit.

---

## All aliases

| Alias | Description |
|-------|-------------|
| `auto_capture [--game <name>]` | Background frame capture during gameplay. Auto-detects game from `SHADER_GAME`. |
| `screenshot [game]` | Single reference frame. Auto-detects game or pass name: `screenshot gzw`. |
| `tune [--game <name>]` | Live mpv viewer, restarts on `creative_values.fx` save. |
| `capture` | EXR snapshot of current screen (used internally by analysis tools). |
| `compare_frame <png>` | Full before/after ΔE_oklab analysis on one reference frame. |
| `compare_frame --all --game <name>` | Batch analysis over all reference frames + aggregate JSON. |
| `stage_isolate --game <name>` | Additive stage attribution + grade call sheet. |
| `bless_all --game <name>` | Accept current output as new golden baseline for all test images. |
| `check_all --game <name>` | Compare current output against blessed baselines. |

---

## File layout

```
gamespecific/<game>/
  shaders/creative_values.fx   ← only tuning surface; all knobs live here
  analysis/reference/          ← pre-pipeline PNGs (input to tune + compare_frame)
  analysis/YYYY-MM-DD/         ← date-stamped analysis archive (compare_agg.json, call sheet, EXRs)
  captures/                    ← EXR snapshots written by capture.py
  compare_agg.json             ← latest aggregate delta (overwritten each compare_frame --all run)
  grade_callsheet.txt          ← latest call sheet (overwritten each stage_isolate run)
  <game>.conf                  ← vkBasalt chain config (do not edit without asking)
```
