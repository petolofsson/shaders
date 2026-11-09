# Current plan

Work toward [GOAL.md](GOAL.md), preserving profiles and production. Current
identities and estimates are in [HANDOFF.md](HANDOFF.md); implementation history
is in [CHANGELOG.md](CHANGELOG.md). The previous full text is preserved in the
[2026-11-08 root ledger](research/2026-11-08_root_document_history.md).

## Done (2026-11-08)

- **Adopted:** [shadow surround tint](research/2026-11-08_shadow_tint_candidate.md)
  at 1.0. The character-halo limitation was accepted; depth is not usable (anti-cheat).
- **Queued follow-ups, no candidate:**
  - [Cue-map scoring](research/2026-11-08_cue_map_oracle.md): the tint weight is
    at chance in daylight (AUC .51).
  - [Yellow/orange re-test](research/2026-11-08_hk_chroma_retest.md): production
    adds ≤6% warm chroma and ~.3 L* of H-K brightening, so there is no gap.

## Active (2026-11-09) — light lift candidate

Reopened by the user. The [light lift report](research/2026-11-09_light_lift_candidate.md)
covers the v3 material-veto estimate and the zone-following lift. Its zones are
accepted; strength (A vs B, `SHADOW_LIGHT_LIFT`) is the user's open choice. Then:
1. Run broader matched stills (both games, more lighting) with repeats.
2. Check menu/UI frames and motion stability (cuts, pans) before any adoption request.
3. Keep production's lift until the user adopts a replacement.

## Closed — do not reopen without new evidence

(Brightness recovery and shadow detection below were reopened by the user as the
active candidate above. The listed failures still stand.)

- **Brightness recovery.** The [brightness oracle](research/2026-11-08_brightness_oracle.md)
  shows the benefit needs single-frame light/material separation.
  - Production's tonal base attributes light like a global curve.
  - The [Retinex screen](research/2026-11-08_retinex_light_screen.md) found no
    classical rule that closes the gap.
  - Lift is unchanged.
- **Shadow detection.** In the [oracle scene](research/2026-11-08_shadow_oracle_scene.md),
  even a perfect gate mainly amplifies the illumination cast; only unavailable
  material color enriches material. Earlier attempts all failed to give a runtime
  classifier or albedo:
  - [narrow-gate miss](research/2026-11-07_shadow_identity_color.md);
  - [surface relations](research/2026-11-07_shadow_surface_relation_screen.md);
  - [context prototype](research/2026-11-07_shadow_context_review.md) (no visible difference);
  - [online detectors](research/2026-11-07_online_shadow_detection.md).

  Do not equate brightness with shadow, or copy a lit neighbor's color as albedo.

## Tonal-progression assessment (open, not mandatory)

Fine gradient preservation supports the goal but is not the whole goal. Existing
scores predate the goal clarification. Motion is an unproven possible means and
not a required build; see HANDOFF for the parked motion evidence. The compact
spatial curve failed on held timber and is a comparison only.

1. Review matched native source/full comparisons across lit, partial and deeply
   occluded areas, warm/cool/neutral materials and representative lighting.
2. Attribute any consequential loss with relevant bypasses and unchanged repeats.
   Assess transitions and scene relationships, not only texture, black anchor,
   noise or color. Darker or more separated is not a target.
3. Develop a distinct model only if the visual evidence warrants it. Explain where
   the tonal range comes from, its costs and a runtime data path.
4. Compare surviving contributions on matched inputs, then run contracts and
   measured motion. Research does not authorize adoption.

Before choosing a model, read the retained failures:
- [session index](research/2026-11-06_shadow_session_index.md);
- [regional budget](research/2026-11-06_shadow_region_budget.md);
- [adaptive range](research/2026-11-06_shadow_adaptive_range.md);
- [RGB shading](research/2026-11-06_shadow_rgb_shading.md);
- [connected structure](research/2026-11-06_shadow_connected_structure.md).

Do not do any of the following:
- repeat rejected curve, filter or gain sweeps;
- widen spectral filters;
- loosen noise gates until materials engage;
- build segmentation to port weak references.

There is no universal acceptable-noise percentage.

## Optional confidence work

These would support stronger claims but are not a repair queue:
- broader game and lighting coverage;
- dense gameplay;
- physical high refresh;
- whole-chain hitches;
- remaining resolutions and aspects.

Reopen decisions only for a concrete new failure. GPU profiling stays deferred,
and no adoption is pending.
