# Ground-truth shadow scene and oracle test

The user asked whether correct shadow identification would improve the
experimental shadow-color helper before any runtime detector is pursued.
[`tools/shadow_oracle.py`](../tools/shadow_oracle.py) renders a deterministic
CPU scene with exact per-pixel material albedo and illumination, then applies
the current luminance-gated helper and two oracle variants to the same 8-bit
display image. It uses no GPU, display or network. Output:
`captures/shadow_oracle_20261108/review.html` (keys 1–9; click toggles source).

## Scene and identities

A sun (elevation ≈41°, 1° soft cone, warm) and blue sky plus warm ground bounce
light a paved ground. A 5 m wall casts a shadow over bright red, blue and green
blocks and a dark red block; the same bright red and dark red, dark navy, dark
green and an asphalt patch stand in sun. A three-sided shelter gives deep
occlusion over a beige block. HDR radiance is mapped by a per-channel ACES fit
at exposure 1 and quantized to 8-bit sRGB, mimicking a game backbuffer.

Truth `shading = 1 − illumination luma / (full sun + full sky) luma`, so form
shading and cast shadow both count; a cast-only map is also saved. Regions:
bright/dark albedo (luma >.15 / <.05) × lit/shadow (shading <.55 / >.8).
Run: 1280×720, 16 sun and 48 sky samples, seed 7, 45 s CPU. Tool SHA-256
`b9005993370bf9fefe6dd8c8f17ef45e21eb2622ccd53856d2aab15d01af43d0`; source PNG
`7981438347dbedc6e87b7310566b6771789e8bfff2974a0b7a82f1a68429875e`.
`report.json` holds the full metrics.

## Variants

All apply after the isolated profile's BLACKS 0 / WHITES .995 remap with the
shader headroom budget; the rest of the grade chain is **not** applied.

- **current**: the darker-range shader formula, `1.10 × .0025 × lumgate ×
  (rgb/y − 1)`, verified against the shader text by a unit test.
- **oracle_observed**: `.25 × gate × (rgb − y)` with `gate =
  smoothstep(.55,.85,shading)`; .25 equals the current helper's relative amount
  at y=.011. Same chroma direction as current, perfect shadow knowledge.
- **oracle_material**: same gate and amount, chroma direction from the true
  albedo, `y × (albedo/y_albedo − 1)`. Not observable at runtime.

Each is also rendered at 2× amount for visibility.

## Results (Oklab ×100, mean ΔE / mean ΔC; 100%)

| Variant | bright lit | bright shadow | dark lit | dark shadow |
| --- | --- | --- | --- | --- |
| current | .12 / 0 | .20 / +.15 | .20 / +.16 | .94 / +.85 |
| oracle observed | .12 / 0 | .75 / +.74 | .04 / 0 | .44 / +.33 |
| oracle material | .12 / 0 | .18 / −.01 | .04 / 0 | .35 / +.23 |
| current gate mean | 0 | .14 | .84 | .38 |

The .12 bright-lit ΔE is the shared WHITES remap, not helper action.

Observations (2× stills, single deterministic render):

- The current gate reproduces the GZW paving failure: brightly lit-material
  shadow sits above its .01–.04 fade (gate .14), while dark materials in sun are
  mostly inside it (gate .84). The lit dark-red block becomes visibly redder.
  Within shadowed paving the gate follows dark grout lines, so the response is
  texture-modulated rather than shadow-shaped.
- With perfect shadow knowledge but observed color, shadowed paving and the
  shaded wall turn visibly **bluer**: in shadow the observed chroma is mostly sky
  illumination, so a correct gate amplifies the illumination cast. GOAL lists a
  uniform blue tint as a failure.
- Only the material-color oracle enriches material in shadow; it shifts shadowed
  paving from blue toward neutral and reds toward red with near-zero mean ΔC.
  That information (albedo) is exactly what a single SDR frame does not provide.

## Interpretation and limits

In this scene, a correct shadow mask alone does not produce the desired result
with the current observed-chroma form; it is a necessary but insufficient part.
The useful component is the material-color direction, which runtime does not
have. This supports pausing further shadow-detector work unless a runtime
estimate of illumination color in shadow (for instance, the shadowed-vs-lit
color ratio of the same surface across a shadow edge) can be shown to approach
the material oracle on this scene.

Limits: one synthetic scene, one sky color (blue skylight exaggerates the
cast; a game with neutral ambient would differ), no indirect color bleeding
beyond a constant bounce, no grade chain, no noise or motion, no real game
frames. The .55–.85 oracle gate and .25 amount are single chosen values, not a
sweep. Metrics describe change, not visual quality; the visual judgment is the
user's.

## Decision

After reviewing these results on 2026-11-08 the user closed shadow-detection
work and moved the priority to brightness recovery. The shadow-edge
illumination-color estimate above was not pursued.
