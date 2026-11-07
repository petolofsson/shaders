# Revisit the two parts of shadow richness

The user asked to revisit both parts after the half-color adoption proposal.
The overall task remains open. A technically supported, small color contribution
does not establish the intended combined improvement in shadow dimension.
No adoption authorization was given and production remains unchanged.

| Part | Intended appearance | Current evidence | State |
| --- | --- | --- | --- |
| Brightness gradients | Fine neighboring shades describe texture, curvature and depth while retaining a convincing black anchor and lighting | Compact curve improves selected shelf/metal/pack response but loses about 15% separation in held timber bands. Spatial/slope references introduce artifacts or retain almost no native benefit after constraints | No viable implementation candidate; primary unfinished design work |
| Subtle dark colors | Blue-black, brown/red-black and nearby material shades remain distinct without an apparent tint or exaggerated saturation | Fixed half-color candidate restores some shelf/timber/pack color. Numeric, bypass and measured controls support its scoped behavior; noise and quantization costs remain. Brightness response is essentially unchanged | Preserve as an isolated, optional color contribution; adoption is not the current prerequisite for further work |

## What the shared mechanism explains

The positive early black offset contributes to both selected losses. Adding the
same linear RGB constant raises low luminance, reducing relative brightness
differences and relative channel differences. That attribution does not establish
that removing the offset is preferable: the user chose the current black anchor,
and the bypass darkens materials substantially.

The color candidate redistributes some neutral offset into existing color ratios
at essentially the same early-stage luminance. Its success on color therefore
does not supply a brightness-gradient mechanism. The fixed brightness curves
redistribute contrast across tones; the held timber failure prevents adopting
their selected shelf/metal gains as a general improvement. Local reconstruction
can introduce rims/noise or suppress the desired signal. These rejected versions
remain closed rather than becoming automatic parameter sweeps.

## Current priority and decision criteria

Resume brightness design from an explicit mechanism in the shared pipeline.
Preserve the existing profiles and black anchor. A new model needs evidence for
useful native material shading with acceptable effects on nearby warm/cool
materials, smooth transitions, noise and lighting. The current evidence does
not identify a ready replacement model; do not present more validation of the
color helper as progress on this missing design.

Keep the fixed half-color variant available as context. When a worthwhile
brightness model exists, compare current, color-only, brightness-only and their
combination on the same inputs and source epoch. Judge whether each contribution
helps the combined appearance, including appropriate restraint in neutral or
deliberately muted materials. This does not require every material to gain
contrast or chroma, or require both contributions to be one function.

The immediate task is no longer obtaining approval for the small color patch.
Its adoption proposal and measured costs remain available for a later decision;
no approval should be inferred from the request to revisit both parts. No new
shader, profile, config, runtime test, rating or publication follows from this
review.

Evidence: [color validation](2026-11-06_shadow_color_half_validation.md),
[held brightness decision](2026-11-06_compact_tone_held_material.md),
[constrained slope reference](2026-11-06_shadow_constrained_slope.md).
