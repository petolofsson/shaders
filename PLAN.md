# Current plan

Work toward [GOAL.md](GOAL.md) while preserving profiles and production. State and
identities are in [HANDOFF.md](HANDOFF.md); adopted history is in [CHANGELOG.md](CHANGELOG.md).
The previous full text is in the [2026-11-10 ledger](research/2026-11-10_root_document_history.md).

## Next

1. **User live-play check** of the light-map CC placement and the full-area lane, plus
   per-game `SHADOW_CC_STRENGTH`. Act only on a concrete reported failure.
2. **Shade lift side branch:** rebase the test copy onto production's light map, then
   recapture A vs C for the user's look. Before any adoption request, check menu/UI frames
   and pans. Keep production's lift until the user adopts a replacement.
3. Optional: hue-weighted warm saturation trim, if the user wants it.

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
hitches, and other resolutions and aspects. GPU profiling stays deferred.
