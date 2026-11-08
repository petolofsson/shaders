# Full-shader review fixes

The user ran a cloud multi-agent review over all of `general/`. It was presented
as a temporary draft PR (#8, closed; branches deleted) whose base removed
`general/`. Six findings were reported and each was verified in code before the
user authorized fixing all of them. Profiles, configs and `gzw.conf` are unchanged.

## Findings and fixes

| # | Finding (verified) | Fix |
| --- | --- | --- |
| 1 | R60 context `exp2(log2(slow_key/zone_key)*.4)` unbounded (up to ~15.8×). The 20 s slow key (R200) is reset only by scene cuts, so a gradual bright→dark walk multiplies shadow lift ~3–5× for tens of seconds. | Clamp the log ratio to ±log2 3 (the R60 tunnel case): ×0.64–1.55. R60's table states ×1.90 for that case, but `exp2(1.585*.4)` is 1.55. |
| 2 | `inverse_grade_debug.fx` reads slots 194–197 from BackBuffer; they live in `HighwayTex`. | Retired the file. The suggested `ReadHWY` fix cannot work: a separate vkBasalt effect cannot share render targets (CODE_RULES), so it would read its own empty highway. No config/tool referenced it. |
| 3 | 19 optional color defaults behind one `#ifndef LUMA_CONTRAST_RED`. | One `#ifndef` per control. |
| 4 | Spatial-lane mapping open-coded; unclamped sites (e.g. chroma Kalman Halton samples) could blend data row 0 below ~970 px height. `ZoneLuma` unused. | `SpatialLaneUV`/`ReadSpatialLane` in common.fxh replace `ZoneLuma`; seven sites use it. LFDownscale/GuidedCoeff already clamped with offsets and are unchanged. Clamping equals CLAMP addressing at every other edge, so values change only where the leak occurred. |
| 5 | `HWY_LIFT_VALID` is always 1 when analysis runs (raw histogram mass is exactly 1), so the fallback lift was computed per pixel and discarded. | Removed fallback lift, `shadow_lift_str`, `specular_contrast`, `shadow_floor`; lift is `product × detail_protect × valid` (zero lift if ever invalid). Adaptive record one G is written as zero to keep the layout. |
| 6 | Per-hue chroma Kalman (ChromaHistory cols 0–5) has no reader; its cold-start sentinel sits above steady-state P. | Removed `UpdateChromaKalman`, Halton helpers and their constants; cols 0–5 are written as zero. |

## Validation

Four private headless `compare_frame.py` runs on GZW
`autof_20260515_133058.png`, `gzw.conf`, 5 s compile delay, 20 s settle: two with
the fixed tree and two with a `git archive HEAD general` copy under
`captures/review_fix_20261108/before/` via a copied config. All four vkBasalt
logs report zero errors; ordinary PipeWire setup warnings appear. Marker-masked:

| Pair | Differing pixels | Max |
| --- | ---: | ---: |
| after repeat | 8,019 | 1 code |
| before repeat | 5,281 | 1 code |
| before vs after (0) | 41,055 | 1 code |
| before vs after (1) | 43,780 | 1 code |

Before/after differences exceed repeat counts but stay at one code, consistent
with float rounding from replacing `lerp(fallback, product, 1)` by `product`.
Fixed grade SHA-256 `36f44c14961b4c7efa23976ac70a45fbba12d9c98380a9d385b78de9361f7180`.
`test_diagnostics.py` passes.

Not runtime-tested: the gradual-transition case of finding 1 (the `--transition`
protocol is a hard cut that fires the scene cut), resolutions below ~970 px for
finding 4, and Arc. No dropped-frame telemetry was collected.
