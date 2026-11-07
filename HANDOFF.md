# Current state — 2026-11-07

The requested root-document cleanup is complete; it changed documentation only.
The root guides now separate rules, goals, priorities, state and procedures;
technical contracts live in [docs/pipeline.md](docs/pipeline.md), and removed
historical detail is preserved in the [root ledger](research/2026-11-06_root_document_history.md).
Shadow research resumed earlier today;
no runtime is intentionally left active and no adoption question is pending.

## Production

Both active configs use one combined `ShaderPipeline`; grade remains eight
passes. Latest adopted code: [shared tonal base](research/2026-11-02_tonal_architecture.md)
and [shared-component CC](research/2026-11-03_neutral_component_cc_adoption.md).

- HEAD at checkpoint: `b4c52e4d178fb535872dd6b93ec9df3697a5246d`.
  Local upstream matched then; no remote fetch was claimed. Check git for current state.
- Root grade SHA-256: `efea23e8c8e061a77619c8c42f89f1d73c35523623ea90a1f3ee4028e8f40c56`.
- The latest controlled-course audit verifies all 17 production identities
  unchanged. Shader/profile/config/header/history/resource/pass state is preserved.

| Profile | BLACKS / WHITES | Inverse chroma / luma | FilmCurve | Shadow temp / tint | Mid temp |
| --- | --- | --- | --- | --- | --- |
| GZW | .0025 / .995 | .60 / .60 | .70 | −.05 / −.010 | .05 |
| Arc | .0025 / .995 | .5 / .5 | .6 | −.075 / 0 | .05 |

`INVERSE_STRENGTH` controls chroma reconstruction. These profile values supersede
older evidence epochs; do not reuse old outputs by grade identity alone.

## Research readiness

| Contribution | Provisional effectiveness | Decision |
| --- | ---: | --- |
| New brightness recovery | ~45/100 | Main gap; no viable implementation proposal |
| New subtle-color helper | ~70–75/100 | User selected 100% for isolated visual testing; not adopted |
| Production chain / grade | 78/100 | Carried estimate with original scope |
| Production joint tonal model | 80/100 | Carried estimate with original scope |

The [controlled course](research/2026-11-06_temporal_course_results.md) is built
under `tools/temporal_course/`, with verified clean/ID sources and RGB8 noise
controls. Temporal benefit survives changing noise; fixed grain and unreliable
history remain. The user targets 80–110 fps. Timestamped source clocks and CPU
references do not establish real GPU cadence or a viable runtime motion path.
Full 30/100-fps-clock references and 80/110/variable-cadence smoke tests are complete;
all runs are closed. The subsequent
[bounded-motion screen](research/2026-11-06_shadow_bounded_motion.md) supplies a
fixed-grid, six-update affine CPU producer, tested from whole-frame observations.
Selected steady motion reaches .556-code source error; support-gated selected
material gaps improve about 8.8%/7.7%. Two dense 320-state references retain the
less favorable intervals. Persistent grain, invalid correspondence and support
modulation remain; no GPU producer or full-grade benefit is established.
The [boundary-check ablation](research/2026-11-06_shadow_boundary_check.md)
reduces unsupported history in selected occlusion and lighting windows while
also rejecting useful support; cut handling and persistent grain remain open.
Its dense 320-state follow-up confirms the tradeoff: occlusion unsupported
history 6.39%→1.09%, camera support .869→.796, persistent-grain error still
about 1.085× baseline. Visible temporal stability and GPU costs remain untested.
No shader candidate or rating increase follows; failures remain.

## Visual candidates and motion build

The user selected 100% of the experimental shadow-color correction after
reviewing the 75% and 100% GZW captures. The current requested visual test uses
shadow lift 0.25 and BLACKS 0.0:
[`gzw_lift_025_black_000.conf`](../captures/shadow_visual_pipeline_20261106/gzw_lift_025_black_000/gzw_lift_025_black_000.conf).
Its isolated copied profile keeps the color correction active with a separate
`EXPERIMENTAL_COLOR_OFFSET=0.0025`; this is not a production control. The combined
still candidate includes the compact spatial brightness curve, not motion-aware
recovery. Captures and comparisons are in
[the November 7 checkpoint](research/2026-11-07_motion_brightness_prototype.md).

The isolated GPU motion build compiles current/previous coarse luminance guides
and a fixed-work global translation estimate. An initial matrix-indexing SPIR-V
assertion was fixed with row-vector Schur math. The estimate has no GPU readback
or moving-course validation and is not wired to warped image history or
brightness. Continue toward a finished visual prototype in
`captures/shadow_visual_pipeline_20261106/gzw_motion_100/`. Next: read back
estimates on matched course motion, then add warped full-resolution history,
local correspondence rejection and detail-preserving brightness recovery.

## Resume evidence

- [Session index](research/2026-11-06_shadow_session_index.md): experiment map,
  reusable inputs, failures and continuation contract.
- [Report inventory](research/2026-11-06_shadow_report_inventory.md): November 4–7
  investigation reports, including the latest representation tests.
- [Half-color validation](research/2026-11-06_shadow_color_half_validation.md) and
  [neutral alignment](research/2026-11-06_shadow_neutral_alignment.md): frozen
  unadopted option and corrected source-color attribution. Review/patch/verification:
  `captures/shadow_color_half_review_20261106/`. `actual_after_adoption.py` is unrun.
- [Production ratings](research/2026-11-02_effect_ratings.md): retained individual
  rows, uncertainty and profile epochs.
- [Motion/color prototype checkpoint](research/2026-11-07_motion_brightness_prototype.md):
  current GPU build status, compiler fix, candidate visual selection and next
  motion-history/recovery steps.

Research documents remain uncommitted; captures/scripts/media remain local and
ignored. No publication is authorized. Historical checkpoint instructions are
superseded by [PLAN.md](PLAN.md) and the current user request.
