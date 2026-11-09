# Current state — 2026-11-09

Goal: richer light→midtone→deep-shadow progression, readable partial shadows,
subtle material color, cohesive look ([GOAL.md](GOAL.md)). Priorities are in
[PLAN.md](PLAN.md). The full Nov 7–8 narrative is preserved in the
[2026-11-08 root ledger](research/2026-11-08_root_document_history.md); older
removed detail is in the [2026-11-06 root ledger](research/2026-11-06_root_document_history.md).
No runtime is active. **Pending user choice:** the light-lift candidate's strength
(see Active candidate). Nothing is adopted from it.

## Active candidate (2026-11-09)

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
- **Next.** The user chooses strength by looking at review v5 (stills 2/3/4):
  - A (new lift only) at `SHADOW_LIGHT_LIFT` .5 is darker than production in
    three shadows;
  - B (both lifts) gives +.14–.33 stop in dark areas;
  - recommended: A at about 1.0.

  Then validate broader stills and repeats before any adoption request.
- **Do not** retry camera-motion separation, flat-fielding, keep-only-light colour
  edges or a frame-level UI gate; the report says why.

## Latest work (2026-11-08)

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

## Production

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

## Research readiness

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

## Resume evidence

- [Session index](research/2026-11-06_shadow_session_index.md) and
  [report inventory](research/2026-11-06_shadow_report_inventory.md).
- [Half-color validation](research/2026-11-06_shadow_color_half_validation.md) and
  [neutral alignment](research/2026-11-06_shadow_neutral_alignment.md). Their files
  are in `captures/shadow_color_half_review_20261106/`; `actual_after_adoption.py`
  is unrun.
- [Production ratings](research/2026-11-02_effect_ratings.md).

Captures, scripts and media remain local and ignored.
