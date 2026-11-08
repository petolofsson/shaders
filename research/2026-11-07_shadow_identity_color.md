# Identifying shadows and underlying color

The user considers 110–115% of the experimental color strength acceptable,
but reports that the shadow-focused and ordinary 110% appearances are hard to
distinguish. The goal is color associated with genuinely shadowed surfaces,
not a generic dark-pixel effect. The prior brightness-window variants remain
isolated; neither a strength choice nor this investigation authorizes adoption.

## What the pipeline actually knows

The configured combined vkBasalt effect receives the rendered color BackBuffer
and builds luminance guides, global/zone statistics and histories from it. The
active pipeline does not receive an authoritative per-pixel shadow mask,
material ID, albedo, geometry normal or lighting decomposition. Existing native
guide data is luminance, not material color. Different material/illumination
combinations can produce the same RGB: the earlier [RGB shading control](2026-11-06_shadow_rgb_shading.md)
demonstrates an exact ambiguity. Exact input gray contains no pixel-local hue to
recover, and clipped black contains none. A model may infer plausible color from
other evidence, but must not claim that inferred color is ground truth.

Research on [paired lit/shadow regions](https://dhoiem.web.engr.illinois.edu/publications/cvpr11_shadow.pdf)
uses spatial and appearance evidence to relate regions of the same material;
the paper's shadow-removal objective is not this project's objective. Even
intrinsic decomposition is [ambiguous](https://ojs.aaai.org/index.php/AAAI/article/view/33151),
particularly with colored or mixed illumination. No cited technique establishes
a cheap game-agnostic shader implementation or justifies copying lit color into
shadow unchanged.

## Concrete failure of brightness as a shadow label

The GZW daylight source `Screenshot_20260516_101035.png`, SHA-256
`22c2d89b3df7caa5eb81af0c8cc97e83809beb27e4166e6ae92a1b9d8691db6e`,
visibly shows paving across sun and shadow. The source-image reference regions
`(550,1100)-(700,1230)` and `(900,1100)-(1050,1230)` show cool shadowed paving
and warmer sunlight on similar-looking paving; a nearby dark crate is a
different-looking material. These are human-selected visual examples, not
verified material IDs or source-transfer calibrated color. Their color difference
is compatible with different illumination and surface variation, so the lit
patch is not an albedo or correct shadow-color reference. A nearest-neighbor
enlarged contact sheet is `captures/shadow_surface_evidence_20261107/patches.png`;
the original source must be examined at native size for appearance.

An explicit same-update GPU readback observes actual post-inverse grade input
over the 64×64 portion `(550,1100)-(614,1164)` of the visible shadowed paving,
under the isolated GZW lift .25 / BLACKS 0 profile. All 256 sampled points are
inside the encoded [0,.25] range and repeat exactly at readback precision in two
private headless captures with no reported dropped/delayed frames. Their linear
input Y median is .08252, range .02350–.14492. In 216/256 samples (84.375%) the
last darker-range candidate's upper luminance gate is exactly zero; its median
upper gate is zero. Thus this visibly shadowed surface receives no color effect
at most sampled points despite being in shadow. This is a concrete counterexample
to treating its narrower absolute-brightness gate as a shadow classifier, not a
prevalence statistic for all games. The source/input/output diagnostic clones
share a single ordinary history. Data, image/clone/config hashes, and logs are in
`captures/shadow_surface_input_20261107/`; all 17 production identities match.

## A defensible next design

Start from relationships rather than absolute pixel darkness. Look for evidence
that a dark and a brighter region are portions of the same surface under different
lighting: coherent texture across a light boundary, spatial continuity, or a
reliable matched view across time. Compare the shadowed region with its own
context; use agreement and uncertainty to restrict the treatment and fade it out
where there is no credible match. Preserve existing shadow luminance and the
game's cool/warm illumination. A lit neighbor is contextual evidence, not a
color to paste into a dark region. Repeated texture on a different object,
different-colored lights, speculars, depth edges, black materials, noise and
occlusion can all invalidate this inference.

The existing controlled temporal course contains surface IDs and clean states
for diagnostic checking, but its source textures already include baked lighting;
they are not ground-truth albedo. A useful next offline representation test must
therefore include explicitly constructed, known-color surfaces under different
light colors, plus wrong-material neighbors and identical-observation ambiguity
controls. Check missed real shadow, wrong-object support and temporal changes,
and inspect native source/full/color comparisons before constructing a shader
candidate. Do not simply broaden the brightness window, blindly propagate color
across edges, or build segmentation to port previous weak references. Runtime
pass/resource needs and performance have not been established.
