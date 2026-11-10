# Current state — 2026-11-10

Goal and priorities: [GOAL.md](GOAL.md), [PLAN.md](PLAN.md). Earlier full text of this
file: [2026-11-10 ledger](research/2026-11-10_root_document_history.md), with older ledgers
for [2026-11-08](research/2026-11-08_root_document_history.md) and
[2026-11-06](research/2026-11-06_root_document_history.md). No runtime is active.

## Production

Both configs run one combined `ShaderPipeline`. Grade has 24 passes: base 9, shadow
surround tint 4, light map 11. Stage contracts are in [docs/pipeline.md](docs/pipeline.md).

Recently adopted (newest first):
- **2026-11-10, bug fixes:** scene-cut trigger, slow-key reset at cuts, per-frame scene
  context; capture tool now settles stills ([CHANGELOG](CHANGELOG.md)).
- **2026-11-10, warm restraint:** `WARM_RESTRAINT` 1.0 in both profiles (red..yellow get no
  chroma-stage boost; [report](research/2026-11-09_warm_hue_research.md)), and `SAT_*` are listed at 0.
- **2026-11-10, [light map review](research/2026-11-10_light_map_review.md):**
  - the shared spatial lane is a full 8×8 mean (GZW pan shimmer .042% → .000%), so the map's
    own lane pass is gone;
  - the paint step is a smooth ramp;
  - unused anchor work was removed.
- **2026-11-09, [3-way CC zones from the light map](research/2026-11-09_cc_light_map_placement.md):**
  - variant G with the pan fix (native luma + bilinear 1/8 correction);
  - new knob `SHADOW_CC_STRENGTH`, 2.5 in both profiles.
- **2026-11-09:** [cheaper shadow surround tint](research/2026-11-09_tint_optimization.md),
  output unchanged.
- **2026-11-08:** [shadow surround tint](research/2026-11-08_shadow_tint_candidate.md).

Identity (SHA-256 prefixes, 2026-11-10): `grade.fx` 16f5141a5965d3b6, `light_map.fxh`
9e0591d1a7c98079, `pipeline.fx` f451938b77a635d7, `analysis_frame.fx` 7969ecaa5e94d34a,
`corrective.fx` 932ce5274f20b0a9.
Configs are unchanged. Old grade hashes and older evidence epochs no longer apply;
match identities before reusing evidence.

| Profile | BLACKS / WHITES | Inverse chroma / luma | FilmCurve | Shadow temp / tint × strength | Mid / highlight temp | Shadow lift | Saturation | Print |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| GZW | .001 / .995 | .60 / .60 | .70 (inert) | −.15 / −.030 × 2.0 | .0875 / .10 | .50 | .075 | .5 |
| Arc | .0025 / .995 | .5 / .5 | .6 (inert) | −.225 / 0 × 2.5 | .0875 / .0875 | .75 | .075 | .5 |

`SHADOW_SURROUND_TINT` and `WARM_RESTRAINT` are 1.0 in both; `RETINEX_STRENGTH` .4 in both (user, 2026-11-10, from settled captures). FilmCurve is inert because print's shoulder
compensates ([effect visibility](research/2026-11-09_effect_visibility.md)).

## Open

- **Settled look:** stills before 2026-11-10 were unsettled. In game Retinex is about twice as
  strong and shade lift about a third weaker in foliage than those reviews showed
  ([recheck](research/2026-11-10_settled_capture_recheck.md)). Re-judge absolute strengths on
  settled captures before tuning.

- **User live-play check** of the 2026-11-09/10 adoptions. Validation so far is stills plus
  an 8-phase static pan ([TOOLS](TOOLS.md#matched-captures)). Look for:
  - shadow-edge crawl in slow pans;
  - UI-panel patches on Arc menus (the lane change touches ≤ 1.4% of menu pixels);
  - `SHADOW_CC_STRENGTH` and `WARM_RESTRAINT` per game.

  Known residual: a soft low-frequency patch beside the rifle on Arc 211202 (.03% of px),
  which comes from the map's coarse correction.
- **Light map limit:** in daylight it separates neutral or low-contrast dark materials from
  shade only slightly better than darkness does (oracle hard-case AUC .14 vs .08). Stronger veto
  rules were already screened. Using it for the surround tint was tested offline and is not
  supported ([review](research/2026-11-10_light_map_review.md)).

## Parked

- Motion/temporal work has no GPU producer and no visible benefit; the isolated motion
  build is unwired ([checkpoint](research/2026-11-07_motion_brightness_prototype.md)).
- Brightness recovery and the shadow-detection failures: see PLAN "Closed".
- Shade lift (light-map lift, shapes A/C) closed 2026-11-10: the user ranked production first
  ([report](research/2026-11-09_light_lift_broad_stills.md)).
- Do not retry camera-motion separation, flat-fielding, keep-only-light colour edges or
  a frame-level UI gate ([light lift report](research/2026-11-09_light_lift_candidate.md)).

Captures, scripts and media stay local and ignored.
