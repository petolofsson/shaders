# Root document history (2026-11-10)

Full text of HANDOFF.md and PLAN.md before the 2026-11-10 slimming, preserved verbatim.
Current state lives in the root files; this ledger is evidence history only.

## HANDOFF.md as of 2026-11-10

## Current state — 2026-11-09

Goal: richer light→midtone→deep-shadow progression, readable partial shadows,
subtle material color, cohesive look ([GOAL.md](GOAL.md)). Priorities are in
[PLAN.md](PLAN.md). The full Nov 7–8 narrative is preserved in the
[2026-11-08 root ledger](research/2026-11-08_root_document_history.md); older
removed detail is in the [2026-11-06 root ledger](research/2026-11-06_root_document_history.md).
No runtime is active. **Adopted 2026-11-09:** 3-way CC zones from the light map (G fixed) with `SHADOW_CC_STRENGTH` 2.5 in both profiles; uncommitted. **Adopted 2026-11-10:** full-area shared spatial lane, smooth paint step and anchor cleanup ([review](research/2026-11-10_light_map_review.md)); uncommitted. **Pending user choice:** shade lift shape A vs C (side branch). Nothing is adopted from it.

### Active candidate (2026-11-09)

**Purpose, corrected by the user on 2026-11-09:** the light map is meant to drive
**3-way CC placement** (shadow/mid/highlight colour where light really is). The
lift replacement below is a side branch the user agreed to keep.
- **CC placement — adopted 2026-11-09:** [report](research/2026-11-09_cc_light_map_placement.md),
  contract in [pipeline](docs/pipeline.md#light-map-and-3-way-cc-zones). G placement with the
  pan fix (own full-area lane + native luma with bilinear correction); `SHADOW_CC_STRENGTH`
  2.5 in both profiles. Production = staged port = test copy within capture noise
  (`captures/light_lift_20261109/stills_prod`, `stills_port2/3`). Arc 211202 pan shimmer
  .03% vs .001% today, with one soft patch beside the rifle. Not yet seen in live play.
- **Side-branch caveat:** the shade-lift test copy (`captures/.../general/`) still defaults to
  the old bilateral upsample (`LL_UP_MODE 0`, `LL_LANE 0`). Use `LL_LANE 1`, `LL_UP_MODE 1`
  to match production's map before more lift work.

**Light lift v3, material veto:** [report](research/2026-11-09_light_lift_candidate.md),
in `captures/light_lift_20261109/` (ignored; production untouched).
- **Estimate.** Light = log luminance plus a local correction that removes only
  confident paint steps (colour change not explained by any light colour). A
  4-level pyramid keeps the correction's reach short.
- **Lift.** Follows frame-relative zones with smooth ramps: shadow full, mid up
  to 30%, light none.
- **Verdict so far.** The user called the zones "perfectly balanced". Synthetic
  error is .150 vs production .211 (luma-only control .208).
- **Cost.** 11 passes at 1/8 plus a 16-tap joint bilateral upsample in
  `ColorTransform`.
- **Strength and shape:** the user chose A (old lift off) and `SHADE_LIFT` 1.0
  (renamed from `SHADOW_LIGHT_LIFT`), then asked for more range and depth. Shape C
  (`SHADE_LIFT_SHAPE 1`, test profiles `prof_*_C`) reverses the zone weights:
  partial shade full, deep shade 30%. [Broad-stills report](research/2026-11-09_light_lift_broad_stills.md);
  artifacts "Light Lift Broad", "Shade Lift Strength", "Shade Lift Shape" (A vs C, 16 stills).
  C keeps lit→shadow depth near production in 12/16 stills (A lost .2–.6 stop);
  in dim interiors it flattens depth more but widens range inside shadows.
  **Pending user look** at "Shade Lift Shape", then PLAN step 2 (UI/motion).
- **Do not** retry camera-motion separation, flat-fielding, keep-only-light colour
  edges or a frame-level UI gate; the report says why.

### Latest work (2026-11-08)

- **Adopted:** [shadow surround tint](research/2026-11-08_shadow_tint_candidate.md),
  `SHADOW_SURROUND_TINT` 1.0 in both profiles. The look was accepted from the CPU
  [mockups](research/2026-11-08_shadow_tint_mockups.md) (v9). It uses an Oklch+
  equal-perceived step toward the surroundings' hue, plus H-K darkening that fades
  near emitters, with surface-only context. Validation: 28 matched stills, both
  noise fixtures and the scene cut, after the lit-spot and noise-amplification
  defects were fixed. Production at 1.0 matches the validated candidate within one code.
  **Accepted limitation:** a tinted halo on dark background behind bright foreground
  objects (Arc 210448 character). Depth was rejected (anti-cheat flag).
- **Profile change:** `PRINT_STOCK` 1.0→0.5 in both profiles, chosen by the user
  from the [print-strength comparison](research/2026-11-08_cool_chroma_print_strength.md).
  Warmth was then raised 3.5× after the old values proved below visibility, and
  eased to 1.75× on 2026-11-09 after user screenshots showed too much red/yellow
  (GZW mid/highlight temp .0875/.175, Arc .0875/.0875).
- **Effect visibility (2026-11-09):** the [knob-off and sweep report](research/2026-11-09_effect_visibility.md)
  finds `FILM_CURVE` inert, because print's shoulder compensates for it; it is
  commented "broken for now" in both profiles. The user then set `SATURATION` .15
  and shadow CC ×4, then eased both to `SATURATION` .075 and shadow CC ×3
  (GZW −.15/−.030, Arc −.225). Inverse chroma and
  contrast/Retinex/zone stay conditional by design.
- **Warm-hue research (2026-11-09):** [perception and attribution](research/2026-11-09_warm_hue_research.md).
  The chroma stage, not warmth, adds most warm chroma (13–18%). Option pending:
  hue-weighted saturation trimming orange/amber/yellow.
- **Light/material research (2026-11-09), reopened by the user:** the
  [colour-edge report](research/2026-11-09_colour_edge_light_material.md), continued
  as the active candidate above.
- **Follow-ups, no candidate:** [cue-map oracle scoring](research/2026-11-08_cue_map_oracle.md)
  (daylight AUC .51, no light/material signal) and the
  [yellow/orange re-test](research/2026-11-08_hk_chroma_retest.md) (≤6% warm chroma, no gap).
- **Review fixes:** [full-shader review](research/2026-11-08_ultrareview_fixes.md)
  findings applied.
- **Closed by the user on 2026-11-08, reopened 2026-11-09 as the active candidate:**
  - shadow detection, after the [oracle scene](research/2026-11-08_shadow_oracle_scene.md);
  - brightness recovery, after the [brightness oracle](research/2026-11-08_brightness_oracle.md)
    and [Retinex screen](research/2026-11-08_retinex_light_screen.md).
- **Superseded:** the darker-range 110% [shadow color candidate](research/2026-11-08_shadow_color_candidate.md).
  The user rejected its feel ("saturation of darker colours") in favour of the tint.
  The Nov 7 shadow-color variants (100/110/200%, darker-range, zero-black, context)
  were never adopted. They are listed in the
  [report inventory](research/2026-11-06_shadow_report_inventory.md) and the ledger.

### Production

Both active configs use one combined `ShaderPipeline`. Grade has twelve passes:
eight, plus four shadow-surround-tint passes. Latest adopted code:
- [cheaper shadow tint](research/2026-11-09_tint_optimization.md): same output,
  4 passes instead of 5 and 64 blur fetches instead of 530 (2026-11-09)
- [shadow surround tint](research/2026-11-08_shadow_tint_candidate.md)
- [shared tonal base](research/2026-11-02_tonal_architecture.md)
- [shared-component CC](research/2026-11-03_neutral_component_cc_adoption.md)

- Grade SHA-256 `6a5b7b24025ae86c0e1ec069a743a2cd1a794a9e3051323d9a1ad5d0714cff4e`.
- Pipeline `a20641fec412ca3e156f5a359abe242d57717d748155abd3f76e1af3b3b68474`.
- Both `creative_values.fx` gained `SHADOW_SURROUND_TINT 1.0` and now set
  `PRINT_STOCK 0.5`; configs are unchanged.
- The older 17-identity set and the earlier grade hashes (`efea23e8…`, `36f44c14…`, `111afeee…`)
  no longer apply. Check git for the current HEAD.

| Profile | BLACKS / WHITES | Inverse chroma / luma | FilmCurve | Shadow temp / tint | Mid / highlight temp | Saturation | Print |
| --- | --- | --- | --- | --- | --- | --- | --- |
| GZW | .0025 / .995 | .60 / .60 | .70 (inert) | −.15 / −.030 | .0875 / .175 | .075 | .5 |
| Arc | .0025 / .995 | .5 / .5 | .6 (inert) | −.225 / 0 | .0875 / .0875 | .075 | .5 |

`INVERSE_STRENGTH` controls chroma reconstruction. These profile values supersede
older evidence epochs; do not reuse old outputs by grade identity alone.

### Research readiness

| Contribution | Provisional effectiveness | Decision |
| --- | ---: | --- |
| Brightness recovery | ~45/100 | Closed 2026-11-08: no single-frame light/material separation |
| Shadow color helper | ~70–75/100 | Superseded by the surround tint; not adopted |
| Production chain / grade | 78/100 | Carried estimate, original scope; predates the tint |
| Production joint tonal model | 80/100 | Carried estimate, original scope |

Motion and temporal work is parked, with no shader candidate. The
[controlled course](research/2026-11-06_temporal_course_results.md) (`tools/temporal_course/`)
supports the temporal benefit under changing noise. Fixed grain and unreliable
history remain, and the user targets 80–110 fps. Further results:
- The [bounded-motion screen](research/2026-11-06_shadow_bounded_motion.md) shows
  8.8%/7.7% support-gated material-gap gains at .556-code source error.
- The [boundary check](research/2026-11-06_shadow_boundary_check.md) cuts
  occlusion unsupported history 6.39%→1.09% but reduces camera support .869→.796.

There is no GPU producer, readback or visible benefit. The isolated GPU motion
build (`captures/shadow_visual_pipeline_20261106/gzw_motion_100/`, see the
[checkpoint](research/2026-11-07_motion_brightness_prototype.md)) compiles a
translation estimate that is unwired and unvalidated. Resume it only for a
demonstrated need.

### Resume evidence

- [Session index](research/2026-11-06_shadow_session_index.md) and
  [report inventory](research/2026-11-06_shadow_report_inventory.md).
- [Half-color validation](research/2026-11-06_shadow_color_half_validation.md) and
  [neutral alignment](research/2026-11-06_shadow_neutral_alignment.md). Their files
  are in `captures/shadow_color_half_review_20261106/`; `actual_after_adoption.py`
  is unrun.
- [Production ratings](research/2026-11-02_effect_ratings.md).

Captures, scripts and media remain local and ignored.

## PLAN.md as of 2026-11-10

## Current plan

Work toward [GOAL.md](GOAL.md), preserving profiles and production. Current
identities and estimates are in [HANDOFF.md](HANDOFF.md); implementation history
is in [CHANGELOG.md](CHANGELOG.md). The previous full text is preserved in the
[2026-11-08 root ledger](research/2026-11-08_root_document_history.md).

### Done (2026-11-08)

- **Adopted:** [shadow surround tint](research/2026-11-08_shadow_tint_candidate.md)
  at 1.0. The character-halo limitation was accepted; depth is not usable (anti-cheat).
- **Queued follow-ups, no candidate:**
  - [Cue-map scoring](research/2026-11-08_cue_map_oracle.md): the tint weight is
    at chance in daylight (AUC .51).
  - [Yellow/orange re-test](research/2026-11-08_hk_chroma_retest.md): production
    adds ≤6% warm chroma and ~.3 L* of H-K brightening, so there is no gap.

### Done (2026-11-09) — 3-way CC placement from the light map

Adopted G (user-approved look) with the pan-shimmer fix and `SHADOW_CC_STRENGTH` 2.5
([report](research/2026-11-09_cc_light_map_placement.md)). Next: user check in live
play; tune `SHADOW_CC_STRENGTH` per game.

### Side branch (2026-11-09) — light lift candidate

Reopened by the user. The [light lift report](research/2026-11-09_light_lift_candidate.md)
covers the v3 material-veto estimate and the zone-following lift. Its zones are
accepted; the user chose A at `SHADE_LIFT` .5. Then:
1. Done: [broader stills](research/2026-11-09_light_lift_broad_stills.md). At .5 dim
   interiors darkened; the user raised `SHADE_LIFT` to 1.0, then asked
   for depth; shape C (partial shade most) is under review.
2. Check menu/UI frames and motion stability (cuts, pans) before any adoption request.
3. Keep production's lift until the user adopts a replacement. The test copy must
   use production's map (`LL_LANE 1`, `LL_UP_MODE 1`) for any further lift evidence.

### Closed — do not reopen without new evidence

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

### Tonal-progression assessment (open, not mandatory)

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

### Optional confidence work

These would support stronger claims but are not a repair queue:
- broader game and lighting coverage;
- dense gameplay;
- physical high refresh;
- whole-chain hitches;
- remaining resolutions and aspects.

Reopen decisions only for a concrete new failure. GPU profiling stays deferred,
and no adoption is pending.
