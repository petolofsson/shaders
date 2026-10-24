# Session pause — 2026-10-24

Historical pause, now resumed. Its next commands and pending checks below are
superseded by [startup-prompt-latest](../startup-prompt-latest), [HANDOFF.md](../HANDOFF.md)
and [PLAN.md](../PLAN.md). Preserve this note as the original pause record.

The user explicitly requested a pause and a fresh-session prompt. No GPU capture
or scene server is active. The last attempted browser smoke test failed at
localhost socket creation inside the sandbox, before launching a compositor.
Do not start more work in this session.

## Completed and validated

- Local contrast now has a smooth luminance-relative shadow toe. GZW sunset
  selected shadows collapsing to black fell from 4.31% to about 0.11%.
  See `2026-10-24_contrast_shadow_toe.md`.
- Zone statistics now use 64 squared-edge bins with linear-light decoding.
  Controlled dark-patch GPU median error fell from a maximum of 33 to 2
  equivalent codes. See `2026-10-24_shadow_zone_precision.md`.
- `compare_frame.py` CLI defaults to headless Gamescope; native 1440p captures,
  post-vkBasalt activity marker, full/repeat, saturation bypass and disabled
  transfer were validated. Transfer error is at most one code, black/white
  preserved. See `2026-10-24_background_capture.md`.
- Shader history settling remains unresolved. Latest desktop static cut probe
  has residual about 0.340 ΔE at 6.5 seconds and 0.015 at 18 seconds after
  returning to dark. Do not blindly change adaptation rates or blame a filter.
- At the pause, all 16 existing diagnostic tests pass and `git diff --check`
  is clean. These tests do NOT yet validate the new browser/motion functions.

## Priorities

The user asked for an ordered list and then execution; the durable list is in
`PLAN.md`: (1) unattended matched motion, (2) shadow history settling,
(3) moving shadow detail/halos, (4) highlights/vivid hues, (5) effect
interactions, (6) prepare combined-chain live review. Only item 1 was started.

## Work in progress — not yet runtime validated

- `tools/babylon_scene/run.py`: default backend changed to headless; legacy
  desktop path retained only behind explicit option. Added `/control` endpoint,
  pose-event predicate, `--motion-only`, `--source-fps`, `--stop-frame`, and
  `--reuse-source`. It dispatches headless work to `background.py`.
- `tools/babylon_scene/scene.js` and `index.html`: controlled camera poses,
  WebGPU queue completion plus two RAF callbacks, static controlled UI, and a
  complementary black/white frame label at bottom-left (256×4 pixels).
  Payload is frame:12 bits, command token:12 bits, checksum:8 bits.
  The Babylon engine `_device.queue.onSubmittedWorkDone()` path is untested.
- New `tools/babylon_scene/background.py`: raw browser capture on a private
  display; held source repeat hash excluding label strip; graded full/repeat
  via the existing mpv headless backend; deterministic PNG route export to a
  lossless RGB FFV1 clip; baseline/trial/repeat moving captures joined ONLY on
  decoded matching source identities. It excludes an 8-pixel border and uses
  4× sampling for sequence summaries. Cached sources validate clip and scene
  hashes. Default source is 15 poses/sec, replay is 30 fps with duplicates;
  do not describe this as native 60 fps motion evidence.
- `tools/headless_display.py`: now creates a short private runtime directory
  with `TemporaryDirectory(prefix="shader-display-")` under /tmp and cleans
  it on close. This fixes a real startup failure: putting the socket below a
  long retained browser-log path exceeded the Unix 108-byte socket limit.
  All 16 existing tests still pass; a real browser run after this fix is pending.

## Exact restart point

1. Read root instructions, this note, `PLAN.md`, and the background capture
   report. Inspect the WIP diff before changing anything.
2. Run this plumbing smoke test **with sandbox escalation**:
   `python3 -B tools/babylon_scene/run.py --frames 420 --settle 1 --capture-backend headless`
   It needs the GPU and a localhost server outside the restricted sandbox.
   Use exec_command `sandbox_permissions="require_escalated"`; a requested
   prefix was `["python3", "-B", "tools/babylon_scene/run.py"]`, but ordinary
   sandbox calls still failed. Do not repeatedly rerun it inside the sandbox.
3. First earlier elevated attempt produced
   `captures/babylon_scene_runs/20261024_155324/report.json`; its log shows the
   now-fixed long Wayland socket path failure. No browser source was validated.
4. Once held source works, smoke-test a short motion export/replay:
   `python3 -B tools/babylon_scene/run.py --motion-only --stop-frame 48 --source-fps 15 --settle 1`
   One-second smoke tests are plumbing tests, not settled shader evidence.
5. Before full validation, add tests for label checksum/corruption and mismatch
   exclusion. Strengthen per-window coverage: `summarize_motion` currently
   requires only a nonempty three-run intersection, not foliage/corridor and
   both sides of each cut. Sampling might need an automated retry strategy.
6. Check cache protocol compatibility: `load_motion` verifies hashes but does
   not yet reject a cached pre-roll/settle different from the requested value.
   Do not reuse a one-second smoke clip as a claimed 20-second settled test.
7. Then run the full private course with `--motion-only --source-fps 15
   --stop-frame 2220 --settle 20`; retain matching frames, report limits and
   update the checklist. Fix runtime bugs as demonstrated; do not assume it works.
8. Only after item 1 is proven, investigate history state with an explicitly
   instrumented diagnostic pass. No history instrumentation was implemented yet.

## Persistent constraints

Keep the user's desktop free; no foreground browser/player fallback. Preserve
all working-tree changes, including staged deletion of `startprompt-2026-10-23.md`.
Keep both creative profiles, shader header comments and `gzw.conf` unchanged.
Use `gamespecific/gzw/gzw_stronger_trial.conf` for GZW assessment. Active GZW
still uses the four-effect chain with broken cross-effect resource sharing.
No golden suite, no shader GPU cost profiling, no external messages. Shared
shader changes require Arc checks. Handoff stays under 60 lines. Source/graded
change magnitude is not a visual-quality score.
