# Current plan

Work toward [GOAL.md](GOAL.md) while preserving profiles and production. State and
identities are in [HANDOFF.md](HANDOFF.md); adopted history is in [CHANGELOG.md](CHANGELOG.md).
The previous full text is in the [2026-11-11 ledger](research/2026-11-11_root_document_history.md).

## Next

1. **Look target (user, 2026-11-11):** mock `mix_tsb` ([look target](research/2026-11-11_look_target.md)).
   - Shade colour: get a shader-off screenshot of the sunny GZW house view, then set
     `SHADOW_CC_STRENGTH` from the measured paint/fill vs tint split.
   - Live play of `KEY_WARMTH` / `SHADOW_FILL_FOLLOW`: pans, sun↔shade walks, interiors. Act
     only on a concrete failure (pan breathing → denser cue sampling).
   - Arc: try the knobs on the Arc profile; check the cue miss on 211131.
   - Remaining gaps need evidence first: dark-foliage lift, sky vs shade hue. Haze needs depth.
2. **Cost (optional):** ~1.15 ms remains. Options and estimates in the
   [cost report](research/2026-11-11_cost_reduction.md); stop unless the user wants more FPS.
3. **Earlier live-play items:** shadow-edge crawl, Arc menu patches, `WARM_RESTRAINT` per game.

## Closed — do not reopen without new evidence

- **Light map for the surround tint:** the map does not separate lit dark material in
  daylight better than the tint's cue
  ([review](research/2026-11-10_light_map_review.md)).
- **Brightness recovery:** the gain needs single-frame light/material separation
  ([brightness oracle](research/2026-11-08_brightness_oracle.md),
  [Retinex screen](research/2026-11-08_retinex_light_screen.md)). The light map is the
  current best separator; it is good on colour paint edges and weak on neutral dark
  materials.
- **Shadow detection as albedo/classifier:** see the [narrow-gate miss](research/2026-11-07_shadow_identity_color.md),
  [surface relations](research/2026-11-07_shadow_surface_relation_screen.md),
  [context prototype](research/2026-11-07_shadow_context_review.md) and
  [online detectors](research/2026-11-07_online_shadow_detection.md). Do not equate
  brightness with shadow, or copy a lit neighbour's colour as albedo.
- **Light-map routes:** camera-motion separation, flat-fielding, keep-only-light colour
  edges and a frame-level UI gate
  ([light lift report](research/2026-11-09_light_lift_candidate.md)).
- **Shade lift from the light map** (shapes A/C): the user prefers production's lift, which
  keeps more texture. A flattens texture in shade by 9%, and both shapes shimmer in pans
  ([report](research/2026-11-09_light_lift_broad_stills.md)).
- **Shadow color helper** (darker-range 110%): superseded by the surround tint.

## Tonal-progression assessment (open, not mandatory)

Develop a new tonal model only after matched native source/full comparisons show a
recurring, attributed loss across lit, partial and deep areas
([AGENTS](AGENTS.md#work-and-evidence)). Read the retained failures first:
[session index](research/2026-11-06_shadow_session_index.md),
[regional budget](research/2026-11-06_shadow_region_budget.md),
[adaptive range](research/2026-11-06_shadow_adaptive_range.md),
[RGB shading](research/2026-11-06_shadow_rgb_shading.md) and
[connected structure](research/2026-11-06_shadow_connected_structure.md). Do not repeat
rejected curve, filter or gain sweeps, widen spectral filters, loosen noise gates or
build segmentation to port weak references.

## Optional confidence work

Broader game and lighting coverage, dense gameplay, physical high refresh, whole-chain
hitches, and other resolutions and aspects. GPU profiling stays deferred; cost work uses
static models plus user-read FPS.
