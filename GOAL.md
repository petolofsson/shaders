# Visual goal

Agreed with the user on 2026-10-24. This is the product direction for the
game-agnostic tool; implementation priorities live in [PLAN.md](PLAN.md).

> Give SDR games a fuller, more dimensional color appearance, with deep,
> nuanced shadows and convincing highlights—evoking some of HDR's richness
> while preserving the game's visual identity.

The intended response is that the game looks considerably better without the
viewer immediately recognizing an effect. Switching the processing off should
feel like losing depth and richness; switching it on should remain unobtrusive.

## Current work mandate

On 2026-10-25 the user prioritized technical correctness and reliable intended
behavior. Personal palette/print preference is not a prerequisite for progress.
Preserve profiles while auditing units, statistics, precision, bounds, controls
and spatial/temporal stability. The direction below remains the long-term goal;
it does not require taste tuning during this technical pass. Current work and
evidence are maintained in [PLAN.md](PLAN.md).

## What richness means here

- **Color:** retain meaningful differences within colored materials across
  brightness levels. Dark greens should have subtle distinctions; bright
  oranges should keep their character rather than washing toward white.
  Preserve credible neutrals and relationships between neighboring colors.
- **Shadows:** combine a convincing black anchor with dark-surface separation,
  subtle color and texture. Deepening shadows must preserve their internal
  structure. Lifting them must avoid a gray pedestal.
- **Light and dimension:** maintain useful relationships between shadows,
  midtones and highlights. Bright areas should feel luminous and retain shape.
- **Restraint:** preserve lighting intent, palette and atmosphere. Avoid visible
  halos, exaggerated texture, conspicuous color casts, pumping and flicker.

The user's phrase "a fuller color spectrum, closer to HDR" describes the
desired appearance. It is not a request to maximize saturation, hue coverage,
contrast, darkness, or the number of colors in every scene. A deliberately
restrained palette should stay restrained.

Output remains SDR in [0,1]. We can improve the use of the available tonal and
color range; we cannot reproduce HDR brightness or wider display gamut, or
recover information already clipped out of the source. No HDR output or
auto-exposure is introduced by this goal.

## Game-agnostic automation

Aim for one coherent visual direction with automatic restraint across games
and scenes, without requiring users to tune each effect or configure each
game. Adapt intervention to measured headroom, structure and confidence.
Back off smoothly where evidence is weak or the source already works well.
Keep spatial behavior and temporal transitions stable.

Statistics cannot reliably determine artistic intent or preferred taste.
Internal calibration and representative visual review remain necessary even
when the eventual user experience has no manual configuration.

GZW and Arc are current assessment inputs, not the definition of the product.
Existing per-game profiles are retained during assessment. The product direction
does not authorize merging profiles, switching active configs or moving controls
out of `creative_values.fx`; current implementation priorities live in PLAN.

## How to judge progress

1. Compare matched source, full output, unchanged repeat and relevant bypasses
   across dark, bright, vivid and intentionally muted scenes from several games.
2. Inspect source-selected materials and boundaries for retained color shades,
   shadow separation, highlight shape, credible neutrals and unobtrusive edges.
3. Check movement and cuts for stability. Repeat variation bounds claims about
   small effects; sparse matched frames cannot establish dense continuity.
4. Use clipping, separation, hue/chroma changes and edge measurements to explain
   observed benefits and costs. Larger delta-E, more saturation, higher entropy,
   fewer black pixels or more occupied color bins are not fidelity scores.
5. Prefer changes that improve the agreed appearance across varied inputs.
   Record regressions and scene-specific tradeoffs. Overall aesthetic
   acceptance remains distinct from demonstrated technical correctness.

## Effectiveness target: 75+

Aim for at least 75/100 effectiveness for the complete chain and every retained
effect in its intended role. The complete chain must earn its rating separately;
individual effect scores do not establish the quality of their combination.

A score of 75 means a repeatable, useful contribution to this visual goal across
representative scenes, with unobtrusive behavior, acceptable tradeoffs and
automatic restraint when intervention is unnecessary. An effect can meet its
role by contributing nothing when the source does not need it. Do not force
visible engagement in every scene to satisfy a score.

Support ratings with matched comparisons, unchanged repeats, varied game inputs,
motion/cut checks where relevant, and visual review against the agreed goal.
Record supporting evidence, uncertainty and regressions. Scores are provisional
judgments, not measured fidelity percentages; do not raise them merely to meet
the target. Current estimates are not validated acceptance results.

Novelty has no minimum: established techniques are welcome. Improvement potential
has no minimum either; it describes remaining opportunity, not achievement.
Simplify, merge or remove an effect if that better serves the complete chain.
The objective is a game-agnostic experience that earns 75+ effectiveness, rather
than preserving every existing effect or maximizing any individual score.

## Scope of new effects

First make the existing tonal, chroma and print stages cooperate toward this
goal. The earlier proposals for automatic sharpening/detail enhancement,
debanding and noise-aware processing are exploratory ideas, not approved
implementation priorities. Add an effect only after demonstrating a relevant
gap that the current stages cannot address adequately.

Continue to follow [AGENTS.md](AGENTS.md): private headless testing, preserved
creative profiles and shader headers, no active GZW config switch without an
explicit request, and no restoration of golden-image testing or GPU cost work.
