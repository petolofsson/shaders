# Background Babylon motion continuation — 2026-10-24

Resumed from the saved pause with the existing working tree preserved. All
runtime tests use private headless Gamescope displays. No host window, desktop
capture, focus change, creative-profile edit or shader edit was needed.

## Completed plumbing evidence

- Held source/frame 420: two independent Firefox processes produce identical
  scene hashes (excluding the four-row command label). Two fresh combined-trial
  mpv replays differ by mean ΔE 0.000010 after a one-second settle. This checks
  plumbing, not full settling. [Report](../captures/babylon_scene_runs/20261024_160503/report.json).
- A 13-pose short source export reproduces its first pose exactly after
  traversing the route. The original replay then hung at EOF: `--keep-open`
  holds the final time position, so `position > end` never becomes true. The
  run was interrupted and cleaned up; replay now checks `eof-reached` and has
  an explicit per-window timeout.
- Reusing that source with the same one-second protocol completes baseline,
  trial and repeat with one shared source identity. All three have zero mpv
  dropped/delayed frames. The matched trial/repeat difference is 0.00564 ΔE;
  this one-sample smoke is not settled motion evidence.
  [Report](../captures/babylon_scene_runs/20261024_160843/report.json).
- Cache reuse now rejects mismatched pre-roll, route, sample/replay rates or
  resolution before accepting the clip/scene hashes. Coverage requires matched
  identities in foliage, clearing, corridor and each side of both cuts covered
  by the route. Mismatched identities are excluded from pixel conclusions.
- Twenty diagnostic tests pass, including new complementary-label/checksum
  corruption, mismatch exclusion, missing cut coverage and incompatible cache
  protocol checks, plus preservation of captures/playback counters across retries. `git diff --check` passes.

## Full course

The 556-pose source export passed its exact first-pose repeat. The initial
baseline/trial/repeat course produced 45/26/26 unique identities, all with zero
mpv dropped/delayed frames. Its 12 shared identities lacked required matches
before/after the night cut, so coverage validation rejected it. The report and
captures remain intact. [Initial report](../captures/babylon_scene_runs/20261024_160908/report.json).

One additional baseline/trial/repeat pass completed coverage. The runner accumulates up to four fresh
passes and retains every attempt's image paths and playback counters; it never
relaxes identity or window requirements. A local continuation script reuses the
already-verified source and first-pass images after checking preserved-file
hashes. It writes a separate report rather than overwriting the failed result.
The source is 15 poses/sec with 20-second pre-roll, replayed at 30 fps. This
duplicates source poses and is not native 60 fps motion. Matching source frames
is necessary but does not prove matching temporal filter state; unchanged
repeats measure that uncertainty.


## Accepted matched motion evidence

[Coverage report](../captures/babylon_scene_runs/20261024_160908/coverage_retry_report.json):
17 shared identities, including 14 in the seven required windows. The other
three lie just outside a sampling window because screenshot presentation can
lag the IPC time position; their identities still match exactly. All six
fresh replay processes report zero mpv dropped/delayed frames. Two source
browser runs in the held smoke and the full route's first-pose repeat are
exact scene matches. Config/tuning hashes and preserved-file hashes match.
The continuation report also retains shared shader/tool source hashes.

| Window | Matched identities | Mean trial/repeat ΔE | Mean source/trial ΔE |
|---|---:|---:|---:|
| Foliage | 3 | 0.04673 | 7.4409 |
| Clearing | 1 | 0.00124 | 7.7680 |
| Before night cut | 2 | 0.00058 | 7.7394 |
| After night cut | 1 | 0.00002 | 1.5040 |
| Corridor | 4 | 0.00469 | 2.0603 |
| Before return cut | 2 | 0.00270 | 1.7920 |
| After return cut | 1 | 0.00020 | 7.3459 |

The mean repeat difference across all 17 identities is 0.01003 ΔE; the
largest foliage sample is 0.08459. Replayed source identity is exact, while
adaptive shader state is not pixel deterministic. Subtle effects need their
own repeat comparison. Sparse exact matches establish the automated plumbing
and window coverage, not dense temporal continuity or subjective fidelity.
Matching also does not establish a complete absence of cut ghosts. Captures
were inspected for the expected scenes and visible trial processing. Local
edge halos on clearing targets merit later attribution; no shader change is
justified solely by these full-chain images.

The accepted course uses 15 camera poses/sec with duplicate 30 fps playback
and 20 seconds of initial pre-roll. Later scenes deliberately retain temporal
history through cuts. The first failing report is preserved separately from
the accepted coverage report. All work remained headless. No GPU cost profile,
creative value change or active-config switch was performed.
