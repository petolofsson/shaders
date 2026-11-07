# Source-common brightness reconstruction

The user requested work on brightness gradients and combining that improvement
with the isolated subtle-color change. Two fixed CPU references preserve output
RGB ratios while using the common source component to restore brightness.
Neither warrants a GPU port. Production, profiles and configs are unchanged.

For source RGB `s`, output RGB `o`, output luminance `y` and
`z = 0.9925 * max(min(s), 0)`, the broad reference requests
`y + (0.5*z/(1+2*z)) * (1-smoothstep(0.08,0.50,y))`, capped at `1.5*y`.
A common RGB gain and common SDR headroom limit follow. This retains the
source-zero anchor algebraically but lifts wall/window/floor medians by roughly
3.7–5.1 Oklab L in the screenshot proxy. Warm-floor separation falls 13.6% and
white-halo separation falls 26.8%. The selected shadow gains do not justify that
broad lighting change.

The bounded reference uses `C = 16*max(BLACKS,0)` (0.04 here),
`q = 0.5*z*C/max(C+0.5*z,1e-10)` and
`requestedY = min(y + q*saturate(1-y/max(C,1e-10)), 1.5*y)`.
It is identity above C, retains zero source and has a monotone scalar response
in y/z with fixed other inputs. Below C its requested luminance stays below C.
For valid nonnegative SDR RGB and these profile values, C is below the smallest
luminance coefficient, so an eligible requested color cannot exhaust RGB
headroom. These scalar properties do not establish the final spatial appearance.
The bounded proxy still raises selected shelf/metal medians by 0.8/1.6 L, while
foliage/wall source-quartile lightness separation falls about 18%/10%. Selected
timber neighboring-shade response also falls. Reject this version rather than
searching its constants.

Artifacts are `captures/shadow_source_component_20261106/` and
`captures/shadow_bounded_source_component_20261106/`: `model.py`,
`float_model.json`, `images.py`, `images.json` and native comparisons. Each
compares current, color-only, brightness-only and combined. Sparse same-update
floating inputs support the small-patch arithmetic. Full-frame previews operate
on separately captured 8-bit images: first scenes use a grade-input diagnostic;
held/day/vivid/emitter scenes approximate it with original source PNGs. Their
second quantization and missing intermediate precision prevent treating them as
compiled shader output or a full noise/endpoint/ordering contract. No new GPU
process was run for these two references. Later identity checks are recorded in
`captures/shadow_dense_material_20261106/verification.json`.

The next, denser pre-dither experiment is documented in the
[combined brightness reference](2026-11-06_shadow_dense_brightness.md).
