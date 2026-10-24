# Automated Babylon shader course — 2026-10-24

The [test world](../tools/babylon_scene/README.md) is a deterministic Babylon.js
WebGPU course run in isolated Firefox inside Gamescope SDL. Its seeded scene
has a 150-tree low-poly forest, textured ground, rocks, a sunlit clearing with
seven saturated blocks and neutral steps, and a dark corridor with colored
emitters, dim light pools, a black target, and a white target. The camera's
44-second route cuts to night at frame 1440 and back to forest at 2160. A
held `?frame=N` pose makes fresh-process screenshots directly comparable.

The runner starts a localhost server, temporary Firefox profiles, and
2560×1440 Gamescope instances. For each pose it captures shader-disabled
baseline, `gzw_stronger_trial.conf`, and a second shader-disabled baseline.
It waits for a WebGPU-ready event, settles for 20 seconds by default, focuses
Gamescope, captures with Spectacle, and checks the trial's 2×2 red marker.
Color comparisons use the existing linear-light Oklab routine with the marker
masked. It checks GZW tuning/config hashes before and after.

## End-to-end evidence

The initial daylight clearing at frame 1080 produced a matched baseline,
trial, and exact baseline repeat: mean trial ΔE 8.315; repeat ΔE 0.000. The
settled forest at frame 420 yielded trial ΔE 7.773 and repeat ΔE 0.000.
Both rendered the intended tree silhouettes, shaded rock edges, sky, white
surfaces, and saturated targets. The night design initially crushed nearly
all surfaces to code values around 3–8; this was a **test-world lighting
problem**. Increasing night ambient and adding dim colored light pools gave
visible grays and emitter context. The revised frame 1620 at 20-second settle
yielded trial ΔE 1.881 and repeat ΔE 0.000. Screenshots and raw reports are
under ignored
[`captures/babylon_scene_runs/20261024_085246/`](../captures/babylon_scene_runs/20261024_085246/),
[`20261024_085349/`](../captures/babylon_scene_runs/20261024_085349/), and
[`20261024_085745/`](../captures/babylon_scene_runs/20261024_085745/).

The automated moving-route run reached both cuts at exactly frames 1440 and
2160 for baseline and trial, then stopped at frame 2220. Browser median FPS
was 60.0 baseline and 59.88 trial, with 16 samples each. That checks playback
continuity; GPU cost is outside this course's acceptance criteria at the
user's direction. The real-time synthetic course checks rendering and
repeatability; it does not establish GZW or Arc Raiders look quality.

The trial red marker was exact in every checked capture. `gzw.conf`,
`gzw_stronger_trial.conf`, and `creative_values.fx` hashes remained
`77b33ac8…`, `82d2b63e…`, and `ed371ec3…`; no shader code or tuning was
changed. The runner stopped its temporary browsers/server and unloaded its
temporary KWin focus script.
