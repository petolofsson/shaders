# Visual goal

Agreed 2026-10-24:

> Give SDR games a fuller, more dimensional color appearance, with deep,
> nuanced shadows and convincing highlights—evoking some of HDR’s richness
> while preserving the game’s visual identity.

Processing should feel unobtrusive; switching it off should reveal a loss of
depth and richness. Preserve palette, lighting and deliberately restrained scenes.

## Desired appearance

- **Color:** meaningful shades within materials, including subtle dark colors;
  bright colors retain character and neutrals remain credible.
- **Shadow tonal depth:** a fuller, smooth progression from lit areas through
  midtones into darkness, preserving subtle shading and surface detail. Deep
  occlusion may approach black while partially shadowed areas remain readable.
  Avoid crushed blacks, muddy midtones and indiscriminate scene darkening. This
  concerns tonal gradation, not softening shadow edges.
- **Shadow color:** preserve and subtly enrich material color in shadow, with
  restrained, harmonious differences between lit and shadowed areas that reflect
  the available surface color and lighting. Avoid a uniform gray, black or blue
  tint, neon saturation and artificially bright shadows.
- **Light:** convincing relationships between shadows, midtones and highlights;
  bright areas retain shape and feel luminous.
- **Restraint:** avoid halos, exaggerated texture, conspicuous casts, pumping
  and flicker. Richness is not a saturation, darkness or hue-coverage target.

Output remains SDR in `[0,1]`; there is no HDR output or auto-exposure.
Information already clipped out of the source cannot be recovered.
The image alone does not reliably identify physical materials or separate their
color from illumination; judge any approximation by its visible result.

## Game-agnostic behavior

Aim for one coherent direction across games, with automatic restraint based on
headroom, structure and confidence. Back off where evidence is weak or the source
already works. Statistics cannot determine artistic intent; representative visual
review remains necessary. Arc and GZW are assessment inputs, not the definition
of the product. Preserve their distinct profiles during assessment.

First improve cooperation among existing tonal, chroma and print stages.
Sharpening, debanding and noise-aware effects remain exploratory; a new effect
needs a demonstrated gap that the existing stages cannot adequately address.

## Acceptance: 75+ effectiveness

Aim for at least 75/100 for the complete chain and each retained effect in its
intended role. A 75 means a repeatable, useful contribution across representative
scenes, unobtrusive behavior, acceptable tradeoffs and automatic restraint when
unneeded. Correctly contributing nothing can satisfy an effect’s role.

Judge native-size source/full/bypass comparisons with unchanged repeats across
dark, bright, vivid and muted scenes. Check materials, boundaries, color shades,
black levels, texture, highlights, movement and cuts together. Measurements
explain visible benefits and costs; they are not fidelity or aesthetic scores.

Scores are provisional judgments, with evidence scope and uncertainty. Component
scores do not establish the combined score; technical tests do not earn rating
points. Established methods are welcome, and effects may be simplified, merged
or removed if the whole result improves. Current priorities and scores belong
in [PLAN.md](PLAN.md) and [HANDOFF.md](HANDOFF.md).
