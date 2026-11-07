# Isolated temporal course

Extends the existing Babylon private source backend without changing its scene,
cached exports, production shaders or profiles. See the
[test protocol](../../research/2026-11-06_temporal_course_protocol.md).

The 1280×720 fixture renders two baked game-source material panels, a procedural
cloth floor/occluder, a thin bright line and black/near-black targets. The default
30-fps clock exports 96 commanded states over 3.2 seconds, covering stationary
view, camera motion, occlusion, lighting and a cut. The first historical export
used 60-Hz route labels; new exports record explicit source timestamps.
Each clean image has a same-state visible-surface-ID image plus projected mesh
corners/world/camera matrices. Identity images are diagnostic; they are not fed
to the tested RGB motion estimator.

```bash
python3 -B tools/temporal_course/export.py --prepare-only --output captures/temporal_course_preflight
python3 -B tools/temporal_course/export.py --smoke --output captures/temporal_course_smoke
python3 -B tools/temporal_course/export.py --output captures/temporal_course_source
python3 -B tools/temporal_course/export.py --source-fps 100 --output captures/temporal_course_100
```

Rendering requires GPU/localhost escalation. All runtime stays private/headless
with no desktop fallback. Preflight writes assets and checks identities without
opening a server or display. No source noise, candidate output, lossless replay
clip or measured GPU-history phase is implied by this clean-source exporter;
those are subsequent controlled processing steps. Original material lighting is
baked into the test textures and is not claimed as recovered albedo. Subsequent
`prepare_inputs.py`, `evaluate.py`, `verify.py` and `summarize.py` provide matched
RGB8 noise controls, CPU reference evaluation and source/geometry checks. Use
their `--help` options and keep output epochs separate.

The timestamped clock also supports `--source-fps 80`, `100`, or `110`, and
`--cadence variable` (80–110-fps intervals). These are offline source samples,
not achieved render performance or GPU-history cadence validation. Existing
30-fps exports retain their own clock/identity epoch. The evaluator uses
`--history-ms 100` by default, so high-rate tests do not silently shrink the
history to four adjacent frames. `--targets matched-30` selects corresponding
physical times for comparison with the original 30-fps windows.

`bounded_motion.py` adds a CPU reference with a fixed 24×16 sample grid, two
box-averaged guides and six affine updates. It replaces feature detection,
matching and RANSAC; it does not establish GPU cost. `evaluate.py` accepts
`--motion-method bounded --motion-domain full-frame --support-gate` to compose
adjacent estimates over the same elapsed-time history and fade unsupported
brightness enhancement. The default remains the original feature reference.
Surface identities and clean images remain diagnostic only. See the
[bounded-motion screen](../../research/2026-11-06_shadow_bounded_motion.md).
`audit_bounded.py` freezes that screen separately from the earlier course epoch.
