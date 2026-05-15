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
auto_capture                  # runs in background; saves frames as you play
screenshot gzw                # single shot (game auto-detected if SHADER_GAME is set)
```

Frames are saved to `gamespecific/<game>/reference_frames/`.

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
compare_frame gamespecific/gzw/reference_frames/frame.png
```

Renders the reference frame through the current pipeline, captures the result, and
prints CIEDE2000 perceptual delta with directional ΔL*, ΔC*, Δh° per tonal zone and
hue band. No manual steps.

Options: `--game gzw` (auto-inferred from path) · `--delay 5` (longer SPIR-V wait) ·
`--keep` (keep temp EXRs for manual inspection).

---

## All aliases

| Alias | Description |
|-------|-------------|
| `auto_capture` | Background frame capture during gameplay. Auto-detects game from `SHADER_GAME`. |
| `screenshot [game]` | Single reference frame. Auto-detects game or pass name: `screenshot gzw`. |
| `tune` | Live mpv viewer, restarts on `creative_values.fx` save. |
| `compare_frame <png>` | Full before/after pipeline analysis on a reference PNG. |
| `analyze_delta <before.exr> <after.exr>` | Manual CIEDE2000 delta on any two EXRs. |
| `analyze_delta --colorchecker [exr]` | Absolute accuracy vs. BabelColor D65 ColorChecker. |
| `capture` | In-game EXR snapshot (RGB + pipeline scalars). Auto-detects game. |

### Regression tests

| Alias | Description |
|-------|-------------|
| `make_test_images` | Render ColorChecker + gradient test images through the pipeline. |
| `bless_all` | Accept current output as new golden baseline. |
| `check_all` | Compare current output against blessed baseline. |
| `test_golden` | Run a single golden test by name. |

---

## File layout

```
gamespecific/<game>/
  creative_values.fx       ← only tuning surface; all knobs live here
  reference_frames/        ← pre-pipeline PNGs (input to tune + compare_frame)
  captures/                ← EXR snapshots from capture
  <game>.conf              ← vkBasalt chain config (do not edit without asking)
```
