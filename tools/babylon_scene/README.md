# Automated Babylon shader course

This seeded Babylon WebGPU scene supplies forest foliage, a bright clearing,
saturated targets and a night corridor with colored emitters. It is a synthetic
stress course; GZW and Arc gameplay remain necessary for look calibration.
Judge results against [GOAL.md](../../GOAL.md): fuller color distinctions,
nuanced shadow depth and convincing light with unobtrusive processing. Use
[PLAN.md](../../PLAN.md) for the next assessment; capture tooling is validated.

The default backend renders Firefox on a private headless Gamescope display.
It opens no desktop window and never falls back to desktop capture. Raw source
poses carry a complementary frame/token/checksum label. Motion export caches
PNG poses and a lossless RGB FFV1 clip, then replays that same clip in three
fresh private mpv processes: baseline, GZW combined trial, and unchanged trial
repeat. Source comparisons require identical decoded source identities;
temporal repeats additionally need aligned presentation/history-update phase.

```bash
# Held source repeat and graded repeat; one second is only a plumbing check.
python3 -B tools/babylon_scene/run.py --frames 420 --settle 1
# Short motion plumbing check.
python3 -B tools/babylon_scene/run.py --motion-only --stop-frame 48 --settle 1
# Full motion course with 20 seconds of initial scene pre-roll.
python3 -B tools/babylon_scene/run.py --motion-only --source-fps 15 --stop-frame 2220 --settle 20
```

The browser/server needs GPU and localhost access outside the restricted
sandbox. `--reuse-source <motion-source-directory>` avoids source regeneration;
cache reuse verifies scene/HTML and clip hashes, resolution, pre-roll, route and
frame rates. A one-second smoke source cannot serve a 20-second assessment.
Retained images, manifests, events and logs go to ignored
`captures/babylon_scene_runs/<timestamp>/`.

Frame indices describe a 60 Hz route, sampled at `--source-fps` (default 15).
Replay duplicates those poses at 30 fps; this is not native 60 fps evidence.
The two presentations share a pose/token label. At cuts they can have different
scene/history state and output. Host playback time does not identify the GPU
update captured by the compositor. See the
[return-cut readback](../../research/2026-10-26_return_cut_alignment.md).

| Route frames | Scene |
|---|---|
| 0–719 | Forest approach and foliage edges |
| 720–1439 | Clearing, white rock and saturated targets |
| 1440–2159 | Hard cut to night corridor and colored emitters |
| 2160–2639 | Hard cut back to forest |

Motion reports require a three-run intersection in foliage, clearing, corridor,
and on each side of both cuts whenever the requested route covers them.
Unmatched identities are excluded. Up to four fresh baseline/trial/repeat
passes can accumulate coverage; reports retain each attempt and its playback
counters. Sampling summaries crop eight border pixels
and sample every fourth pixel, excluding both activity marker and identity
strip. Change magnitude measures neither fidelity nor visual preference.
Twenty seconds of pre-roll warms up the initial scene without proving full
temporal convergence; later scenes deliberately
retain cut history. Held tests use two fresh raw browser sources with an exact
scene hash repeat, followed by two fresh graded replays.

Ordinary summaries explicitly report `identity_scope=source_pose_and_token`.
They count `render_phase_verified_frames` separately; ordinary screenshots
provide no hidden phase data. Diagnostic callers with GPU-decoded integer
`render_phase` fields (`source_update`, `cut_update`) can require strict matching
using `matched_motion` or `summarize_motion(..., require_render_phase=True)`.
This rejects different updates of the same pose and cannot be satisfied by
supplying only mpv timestamps. The ordinary CLI remains a source-pose comparison.

Requirements: Firefox WebGPU, Gamescope with headless backend, gamescopectl,
vkBasalt, mpv, ffmpeg, and Python NumPy/Pillow/OpenEXR. Firefox uses a temporary
profile. The pinned Babylon.js build is verified in the ignored vendor cache.
Config/profile hashes before and after each run must match. The runner uses
`gzw_stronger_trial.conf` and never edits tuning or switches `gzw.conf`.

The legacy visible course is available only through explicit
`--capture-backend desktop`; it uses SDL Gamescope, KWin and Spectacle. Headless
`--motion-check` adds motion to the held tests; `--motion-only` skips held tests.
