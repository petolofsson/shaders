# Surface and temporal cues: first falsification screen

The user requested a better distinction between actual shadow and dark material,
and material-dependent color. This is a fixed CPU representation screen, not a
shader, image enhancement, or choice of new profile. Production remains
unchanged. It follows the concrete brightness-gate counterexample in the
[identity investigation](2026-11-07_shadow_identity_color.md).

## Surface-pair evidence

The deterministic probe `captures/shadow_surface_relations_20261107/screen.py`
constructs simple linear-RGB textured patches with known reflectance and light.
It gives the comparison **perfect pixel registration** as an oracle, which is
more information than a runtime shader has. It examines normalized luminance
correlation, gradient-orientation distributions and luminance-normalized RGB.
These are descriptive cues; no tuned detector, threshold or output correction
is implemented.

An identical material under a scalar shadow has correlation 1.0 and identical
normalized RGB. The same material under a differently colored shadow also has
correlation 1.0, but its normalized RGB differs from the lit sample. Copying the
lit color therefore removes a real lighting difference in this controlled case.
An intrinsically darker material with the same texture can produce **exactly
the same two images** as the scalar-shadow case, and obtains the same correlation
and color result. An independently textured field has near-zero pixel
correlation but a .999 gradient-histogram cosine: coarse texture-orientation
similarity alone cannot establish material correspondence.

The same fixed orientation diagnostic was applied to manual, independent 8-bit
GZW source crops identified in the prior report. The shadow-paving versus
sun-paving histogram cosine is .948; shadow-paving versus dark-crate cosine is
.959. A simple orientation match ranks the visibly different crop as more
similar. Crops are not verified segmentation or albedo and have different
positions, so their unregistered per-pixel correlation is not a correspondence
measure. Source hash, rectangles and values are recorded in `report.json`.
This is a finite failure of these cues as standalone identity evidence, not a
claim that all surface matching is impossible.

## Temporal evidence

The companion `temporal.py` compares a given rectangular region's per-pixel
log-luminance change with the surround median. It uses known perfect registration
and a known query region; neither is a runtime producer. In its synthetic
control, a local two-stop shadow gives a −2-stop relative change, an unchanged
dark material gives zero, and a uniform two-stop illumination change gives zero
after surround subtraction. A local shadow on top of a uniform global change
still gives −2 stops. These show a potential cue, not an appearance result.

However, local reflectance change and an occluding object constructed to produce
the same observed pixels also give exactly −2 stops. No RGB-only algorithm can
distinguish these identical observations. The single changing-noise fixture
has a near-zero median relative change but approximately −.045 to +.049 stop
5th–95th percentile pixel variation; it is not representative real game noise.
Colored illumination also changes chromaticity, so an earlier brighter RGB
sample is not automatically the correct color for the current lighting.

The existing rendered temporal course supplies motion and diagnostic surface
IDs but its textures have baked lighting and its lighting phase changes broad
illumination; it does not provide known material albedo and cast-shadow ground
truth. It cannot by itself validate the user's distinction. Building a temporal
history or classifier from these tests would overstate the evidence. Geometry,
occlusion rejection and temporal correspondence would also have real resource
and cost implications that have not been established.

## Decision

Reject a standalone brightness threshold, a standalone texture-orientation
match, and unqualified lit-color copying as solutions to this goal. The temporal
relative-change cue is conditional evidence only: a physically stationary,
confidently matched surface that changes lighting provides useful information,
but cannot establish the cause by itself and supplies nothing for a permanently
shadowed area. It would need independent correspondence/occlusion confidence,
colored-light restraint and a fallback for unsupported cases. No next shader
candidate, production change or effectiveness increase follows from these tests.

Both standalone scripts and their JSON results are local under
`captures/shadow_surface_relations_20261107/`; neither imports historical
generators or runs a GPU. Synthetic assumptions and the deliberately identical
observations are explicit, and the manually selected source crops remain
diagnostics rather than material labels.
