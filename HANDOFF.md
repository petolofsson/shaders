# Current state — 2026-11-08

Goal: richer light→midtone→deep-shadow progression, readable partial shadows,
subtle material color, cohesive look ([GOAL.md](GOAL.md)). Priorities are in
[PLAN.md](PLAN.md). The full Nov 7–8 narrative is preserved in the
[2026-11-08 root ledger](research/2026-11-08_root_document_history.md); older
removed detail is in the [2026-11-06 root ledger](research/2026-11-06_root_document_history.md).
No runtime is active and no adoption question is pending.

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
- **Follow-ups, no candidate:** [cue-map oracle scoring](research/2026-11-08_cue_map_oracle.md)
  (daylight AUC .51, no light/material signal) and the
  [yellow/orange re-test](research/2026-11-08_hk_chroma_retest.md) (≤6% warm chroma, no gap).
- **Review fixes:** [full-shader review](research/2026-11-08_ultrareview_fixes.md)
  findings applied.
- **Closed by the user:**
  - shadow detection, after the [oracle scene](research/2026-11-08_shadow_oracle_scene.md);
  - brightness recovery, after the [brightness oracle](research/2026-11-08_brightness_oracle.md)
    and [Retinex screen](research/2026-11-08_retinex_light_screen.md).
- **Superseded:** the darker-range 110% [shadow color candidate](research/2026-11-08_shadow_color_candidate.md).
  The user rejected its feel ("saturation of darker colours") in favour of the tint.
  The Nov 7 shadow-color variants (100/110/200%, darker-range, zero-black, context)
  were never adopted. They are listed in the
  [report inventory](research/2026-11-06_shadow_report_inventory.md) and the ledger.

## Production

Both active configs use one combined `ShaderPipeline`. Grade has thirteen passes:
eight, plus five shadow-surround-tint passes. Latest adopted code:
- [shadow surround tint](research/2026-11-08_shadow_tint_candidate.md)
- [shared tonal base](research/2026-11-02_tonal_architecture.md)
- [shared-component CC](research/2026-11-03_neutral_component_cc_adoption.md)

- Grade SHA-256 `111afeee85c0f29b11b2d8ec682efe232533d4155e7fd1508556177f870a17ea`.
- Pipeline `bec87beced4ea7ace88191f72c912173a9c9ef828b3acfe9185843d927ad15b2`.
- Both `creative_values.fx` gained `SHADOW_SURROUND_TINT 1.0`; configs are unchanged.
- The older 17-identity set and the earlier grade hashes (`efea23e8…`, `36f44c14…`)
  no longer apply. Check git for the current HEAD.

| Profile | BLACKS / WHITES | Inverse chroma / luma | FilmCurve | Shadow temp / tint | Mid temp |
| --- | --- | --- | --- | --- | --- |
| GZW | .0025 / .995 | .60 / .60 | .70 | −.05 / −.010 | .05 |
| Arc | .0025 / .995 | .5 / .5 | .6 | −.075 / 0 | .05 |

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
