# Color and shadow baseline — 2026-10-25

Offline review of retained private headless captures establishes a first
goal-led baseline without new GPU work, shader changes or profile tuning.
The most concrete remaining spatial issue is added shading inside uniform
colored surfaces. Shadow color retention and strong palette changes need
attribution, while these samples do not demonstrate a new highlight-shape gap.

## Evidence and protocol

Artifacts and reproducible offline scripts are in ignored
[`captures/visual_baseline_20261025/`](../captures/visual_baseline_20261025/):
[`assess.py`](../captures/visual_baseline_20261025/assess.py),
[`flat_targets.py`](../captures/visual_baseline_20261025/flat_targets.py),
[`report.json`](../captures/visual_baseline_20261025/report.json), and
[`flat_targets.json`](../captures/visual_baseline_20261025/flat_targets.json).
Run the scripts in that order from the repository root. They record source,
full and repeat image hashes, source-selected rectangles and exact-color masks.

Four held cases reuse the adopted halo candidate's fresh-process, 20-second
GZW dark/sunset, vivid Arc input under GZW tuning, and Arc cloud under Arc
tuning captures. Candidate executable code matches current grade after
normalizing include paths/comments. Every hash in the applied-path report
still matches the workspace, including GZW tuning/config and shared shaders.
Source image hashes also match. The Arc profile hash is recorded now; profile
differences remain part of the comparison. These are combined techniques,
not the active four-effect chain with broken cross-effect resource reads.

Babylon uses exact identities 440:111 (foliage), 1044:262 (clearing), and
1640:411 (corridor) from the adopted candidate/repeat motion runs. Clearing
also has an exact-identity shader-disabled replay baseline. Its target crop
differs from the exported source by at most one channel code. Motion has
15 poses/sec duplicated at 30 fps, initial 20-second pre-roll and retained
history through later scenes. These sparse poses do not prove dense stability.

Held whole-frame repeat mean differences are 0–0.000486 Oklab units ×100;
selected material repeats are at most 0.000582. The clearing target crop's
repeat mean is 0.001705. Whole-frame comparisons crop eight pixels and sample
every fourth pixel; material crops use all pixels and avoid marker/labels.
Game sources are original PNGs, without new shader-disabled per-source replays.
The earlier transfer test found at most one code of error; subtle near-black
chroma comparisons therefore remain provisional. No scores are assigned.

## Prioritized demonstrated gaps and tradeoffs

1. **Attribute remaining spatial shading on flat colored surfaces.**
   [Native target crops](../captures/visual_baseline_20261025/colored_targets.png)
   show the same exactly matched source/full/repeat pose. On exact source-RGB
   masks eroded eight pixels from boundaries, magenta's L95−L5 spread is
   source 0, shader-disabled replay 0.187, full 1.763, repeat 1.763. Purple is
   0 / 0.079 / 1.066 / 1.066; green is 0 / 0 / 0.853 / 0.853.
   Magenta's output repeat is pixel-identical on that mask. The processing
   introduces spatial structure into uniform input beyond transfer/dither
   uncertainty. It is smaller than the removed broad sky halo but visible in
   the crops. Attribute existing local tonal stages before proposing a fix;
   this does not identify Retinex, zone contrast or another stage as the cause.
   Preserve the adopted Retinex halo fix.
2. **Check dark material color without discarding useful depth.**
   [GZW shelf](../captures/visual_baseline_20261025/shelf_and_pipe.png):
   the backboard median L goes 13.57→12.19 and C 0.99→0.45. Its pixels below
   max-channel code 5 rise 5.00%→22.80%, without exact black. Source-defined
   low/high luminance groups retain their median separation, 4.16→4.24 L.
   This supports checking reduced subtle warmth and near-black visibility,
   not claiming universal shadow crushing. Low-code color is transfer-sensitive.
   [Dark green facets](../captures/visual_baseline_20261025/dark_green_facets.png)
   deepen 26.57→20.60 L with C 5.76→5.16 and median hue shift +8.27°;
   group separation increases 11.89→13.78 L with no exact black in the mask.
   Determine whether that tradeoff preserves material identity across motion.
3. **Attribute strong tonal/color redistribution before automatic restraint.**
   [Sunset ground](../captures/visual_baseline_20261025/sunset_ground.png)
   median L falls 47.38→39.21 while C rises 6.94→8.25. Source-defined group
   separation falls 34.61→30.19 L; exact black rises 0→0.199% in this crop.
   [Facade](../captures/visual_baseline_20261025/sunset_facade.png) group
   separation falls 41.77→35.82 L. These heterogeneous regions include lighting
   and geometry, so the gaps describe redistribution, not recovered detail or
   a measured fidelity score. The crops appear richer but also more orange.
   [Arc sky under GZW tuning](../captures/visual_baseline_20261025/vivid_sky.png)
   changes 67.45→58.47 L, 10.23→12.81 C and +4.92° median hue.
   Flat clearing targets are affected unevenly: orange C 16.67→13.00 with
   −5.13° hue, cyan C 14.42→11.20, purple C 21.88→25.38. Greater saturation
   is not a suitable general remedy. Assess tonal/chroma/print bypasses with
   the same candidate logic across inputs; keep both existing profiles intact.

## Useful behavior to preserve

[Arc clouds](../captures/visual_baseline_20261025/cloud_shape.png) under the
Arc profile lower median L 94.92→91.02 while source-defined group separation
increases 18.61→20.15 L. Neither source nor output clips a channel in this
crop. Cloud structure remains visible; this sample provides no evidence for
adding a highlight effect or claiming recovered clipped detail.

[Dark corridor wall](../captures/visual_baseline_20261025/dark_corridor_wall.png)
goes 11.44→12.08 L and C 0.69→1.72 without exact/near-black pixels in the mask.
Colored floor pools lift 21.96→24.38 L and C 1.86→3.32. This differs from the
shelf's response and argues against a blanket shadow lift or global color boost.
The wall gains a blue cast; its aesthetic acceptability remains for live review.

## Next work and limits

Start with matched clearing attribution for the flat-face shading, then shelf
shadow/color and sunset stage interactions. Use fresh full/repeat and independent
Retinex/zone/lift gates, keeping temporal state and source identity matched.
Do not infer the responsible stage from this full-chain baseline. Shared shader
changes still need Arc regressions and matched motion/repeats.

This is a first baseline across two games plus the synthetic course, not broad
cross-game acceptance. Small emitters, genuinely restrained palettes from more
games, dense continuity, live preference and 75+ effectiveness remain unvalidated.
Statistics explain visible tradeoffs; none establishes aesthetic success alone.
No runtime test, tuning/config switch, golden suite or GPU profiling was added.
