# Root document history — 2026-11-11

Full text of HANDOFF.md and PLAN.md before the 2026-11-11 slimming (working-tree state at
the end of the look-target and cost-reduction session). Current state lives in the root files.

## HANDOFF.md

## Current state — 2026-11-10

Goal and priorities: [GOAL.md](GOAL.md), [PLAN.md](PLAN.md). Earlier full text of this
file: [2026-11-10 ledger](research/2026-11-10_root_document_history.md), with older ledgers
for [2026-11-08](research/2026-11-08_root_document_history.md) and
[2026-11-06](research/2026-11-06_root_document_history.md). No runtime is active.

### Production

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

### Open

- **Look target** (2026-11-11): user chose mock `mix_tsb` from reference-direction mocks of the
  untouched GZW frame. Knob profile H (settled headless capture) matches it on the
  building, paving and grass, but not on far-hill haze, sky chroma or dark-foliage lift
  ([look target](research/2026-11-11_look_target.md)). H is unadopted. On 7 overcast,
  interior and menu scenes it casts brown and drains green outdoors under overcast, so its
  sun warmth must depend on direct light. Production adds teal/blue chroma to dark UI and
  interiors (CC 2.25).
  Candidate code (uncommitted): `KEY_WARMTH` gates warm mid/highlight temperature by a
  warm-key/cool-fill cue from the light map. It defaults to 0, and production is bit-identical
  on 6 scenes. Profile H4 (H without global warmth, `KEY_WARMTH` .5) keeps overcast at source
  colour and gives the sunny wall cream. The cut check is clean (settled 0.5 s after a cut). In the
  8-phase pan the cue varies by up to ~25% of the warmth on mid-ramp frames (Δb ≈ .001 at
  `KEY_WARMTH` .5). Not yet checked on Arc profiles or in live play.
  Cost trims (uncommitted, user 2026-11-11): inverse-grade gamut bisection 14 → 10 steps,
  `NativeGuideLogTex` R32F → R16F. Static audit only (no GPU profiling). Vs previous build on
  7 scenes: max 1 code, 0.22–0.89% px changed, none > 1.
  Bit-identical cost cuts (uncommitted): 5 single-texel analysis passes merged into one
  (44 → 40 passes incl. new LLPoints and lane-sample cache; one highway copy instead of three), compile-time skips of zero-knob stages (luma contrast,
  hue rotation, Retinex; guided passes idle when unused). Inverse-grade gamut search now
  analytic (≤ 1 code on ≤ .004% px; blue-cusp overshoot risk offline, see pipeline.md).
  `OklabToSDR` early return for in-gamut colours (user-authorized output-preserving branch):
  0 codes changed on 7 scenes + Arc profile; static estimate −0.6 ms. 0 codes changed on 7 scenes
  (GZW profile) and Arc 210958 (Arc profile, Retinex .4). User FPS before: 92 on / 115 off.
  `SHADOW_FILL_FOLLOW` (uncommitted, default 0, bit-identical on 7 scenes) scales shadow CC by
  the same cue: at 1 sun frames keep cool shade unchanged, overcast/interior/menu shade returns
  to source colour (menu teal cast removed). Round 5 in the look-target note. Working tree GZW
  `creative_values.fx` has uncommitted user edits: `RETINEX_STRENGTH` 0.0,
  `SHADOW_CC_STRENGTH` 2.25, and (option A for live play, user 2026-11-11)
  `SHADOW_FILL_FOLLOW` 1.0, `KEY_WARMTH` 0.5, then `SHADOW_CC_STRENGTH` 2.25 → 1.25 (user,
  live sun: shaded wall read blue-teal 51 66 73; sunlit wall cream 160 160 136). Open: stepped
  bands in sunlit clouds (190853) need a shader-off screenshot. Forest-edge dark green line: user keeps
  `SAT_GREEN` 0; on 133729 the shader does not darken tree lines (likely game haze).

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

### Parked

- Motion/temporal work has no GPU producer and no visible benefit; the isolated motion
  build is unwired ([checkpoint](research/2026-11-07_motion_brightness_prototype.md)).
- Brightness recovery and the shadow-detection failures: see PLAN "Closed".
- Shade lift (light-map lift, shapes A/C) closed 2026-11-10: the user ranked production first
  ([report](research/2026-11-09_light_lift_broad_stills.md)).
- Do not retry camera-motion separation, flat-fielding, keep-only-light colour edges or
  a frame-level UI gate ([light lift report](research/2026-11-09_light_lift_candidate.md)).

Captures, scripts and media stay local and ignored.

## PLAN.md

## Current plan

Work toward [GOAL.md](GOAL.md) while preserving profiles and production. State and
identities are in [HANDOFF.md](HANDOFF.md); adopted history is in [CHANGELOG.md](CHANGELOG.md).
The previous full text is in the [2026-11-10 ledger](research/2026-11-10_root_document_history.md).

### Next

1. **User live-play check** of the light-map CC placement and the full-area lane, plus
   per-game `SHADOW_CC_STRENGTH`. Act only on a concrete reported failure.
   The same check covers `WARM_RESTRAINT` (1.0 = warm hues at about source chroma).
2. **Look target (user, 2026-11-11):** chosen mock `mix_tsb` (Toll .35 + Semler .35 +
   Burrows .30 on the untouched GZW frame). Work toward it with knobs first (from profile D),
   then shader work where knobs cannot reach (key/fill from the light map, amber sun; haze
   needs depth) ([look target](research/2026-11-11_look_target.md)).

### Closed — do not reopen without new evidence

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

### Tonal-progression assessment (open, not mandatory)

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

### Optional confidence work

Broader game and lighting coverage, dense gameplay, physical high refresh, whole-chain
hitches, and other resolutions and aspects. GPU profiling stays deferred.
