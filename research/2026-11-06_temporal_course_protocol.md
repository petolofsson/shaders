# Next temporal test: use the existing JavaScript course

Execution: the [controlled-course report](2026-11-06_temporal_course_results.md)
records the isolated renderer, verified sources, matched noise controls and CPU
evaluation. The user subsequently specified 80–110-fps operation; timestamped
high-rate clocks and elapsed-time history selection are part of that follow-up.

The user pointed back to the Babylon moving-test engine. It is the correct
next controlled testbed; real game footage is a later generalization check,
not a prerequisite for this experiment. The recent temporal screens already
used sixteen of its cached source poses. Their limitation was the narrow cached
sample and controls, not absence of a moving-test engine.

## Concrete test

Use an isolated experimental scene derived from `tools/babylon_scene/`, preserving
the existing engine, cached source manifests and production identities. Build the
following controls before starting a new private headless source export:

- Dark textured surfaces with broad shading and fine detail, including held
  material references. Include near-black patches and thin bright features.
- A stationary-camera segment and a moving-camera segment, plus independently
  moving foreground objects that expose previously hidden surfaces.
- A controlled lighting change and hard cut. Scene state must depend on the
  commanded source frame, with repeatable frame/token labels.
- Matched clean, changing-noise, screen-fixed-grain and surface-fixed-grain source
  variants. Noise belongs to the test input; production output grain remains off.

Export **30 distinct source poses/sec**, supported by `--source-fps 30`, and
replay at 30 fps. The older cache has 15 poses/sec duplicated at 30 fps. Keep the
two protocols separate; neither establishes native high-refresh behavior.

Record camera/object transforms and known visible-surface correspondence where
available. Such ground truth evaluates RGB-estimated motion; it must not silently
be supplied to a candidate and presented as a production-available motion input.

## Comparison and decision

First compare known correspondence, RGB-estimated correspondence and no temporal
reuse on the same exported input frames. Separate clean-structure error from
known added noise; inspect occlusion boundaries, thin features, newly exposed
materials and changes in lighting at native size and ordinary playback speed.

Then compare the preserved full pipeline with an isolated bounded brightness
reference. Preserve profiles and include an unchanged repeat. Ordinary screenshots
are insufficient to claim matching GPU-history phases; read those explicitly
where the comparison depends on history updates.

Require visible shadow benefit with unobtrusive texture/noise and transition
costs, plus a credible runtime motion path, before implementing a shader candidate.
If known correspondence works but RGB correspondence fails, the motion producer
remains the gap. If even the known-correspondence output is not worthwhile, do
not build a more elaborate estimator merely to reproduce it.

This document records the test contract. Executed work and exact scope are in the
report above; no production change or adoption follows. Existing failed variants
and evidence remain.
