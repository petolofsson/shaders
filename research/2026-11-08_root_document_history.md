# Root document history — 2026-11-08 condensation

Verbatim HANDOFF.md and PLAN.md before the 2026-11-08 length reduction. The
root guides now point to the dated reports; this file preserves the removed
narrative. Earlier archived root detail: [root ledger](2026-11-06_root_document_history.md).
Relative links below were written from the repository root.

## HANDOFF.md (before)

### Current state — 2026-11-07

The user clarified the goal: richer tonal progression from light through
midtones to deep shadow, with readable partial shadows, subtle material color
and a cohesive look. See [GOAL.md](GOAL.md). Fine gradient recovery is only one
part of this; motion is an unproven possible tool, not the next mandatory build.
Current priority is the native whole-scene assessment in [PLAN.md](PLAN.md).
The [revised-goal review](research/2026-11-07_revised_shadow_goal_review.md)
reexamines existing GZW, Arc and held-timber views. The GZW shelf is a plausible
readability lead, but a recurring objectionable loss is not yet established;
continue with additional identity-verified native comparisons before a model.
Follow-up review covered held timber, daylight and half-color crops; no second
clear tonal-loss example emerged. All 17 current production identities match
the held-color report. The saved 100% GZW profile/pipeline/grade were inspected,
but its screenshot lacks a complete capture-time identity chain. Fresh matched
100% color/current repeats on warm material are now captured in
`captures/revised_goal_color_100_20261107/`; see the review for identities,
one-code repeat variation and limits. The candidate looks subtly warmer in that
still without an apparent tonal solution. Fresh Arc still/repeat captures are in
the same directory; repeat variation reaches two codes and the overview remains
subtle. The [full-color noise screen](research/2026-11-07_full_shadow_color_noise.md)
corrects the earlier evidence summary: prior bounded arithmetic and ramp checks
used the same 100% formula with BLACKS=.0025. A new same-update synthetic test
shows ~49% more code-16 chromatic variation than current in both profiles; real
noise, motion and the separate BLACKS=0 offset remain open. Half-strength checks
do not establish full-strength motion/noise behavior.
The requested lift .25 / BLACKS 0 color is now isolated from the rejected curve
and compared with a matched color-off still in
`captures/shadow_color_zero_black_20261107/`. See the full-color report for its
one-code repeats, signed-intermediate consideration and remaining validation limits.
Its compiled helper agrees with an independent numeric reference; a full-chain
synthetic RGB/neutral ramp shows positive mean luma steps but a small near-black
quantization cost. Details and repeat uncertainty are in the full-color report;
the [motion and shelf follow-up](research/2026-11-07_zero_shadow_color_motion.md)
adds two sparse replay/cut runs and a matched dark shelf still. Repeats stay within
one code; small step increases and the lack of dense gameplay remain. Real game
noise and dense motion are untested.
The [daylight follow-up](research/2026-11-07_zero_shadow_color_daylight.md)
retains two-code still-repeat variation and a failed all-ceiling sky patch. A
corrected foliage and masonry same-update readback repeats exactly at encoded
precision and shows a larger sampled color response in foliage; this remains
limited to one scene and does not establish visible quality.
The same report adds a red/white emitter still using an Arc source under the
GZW experimental profile; repeat variation reaches two codes. A local review
gallery is `captures/shadow_color_zero_black_20261107/review.html`.
The user subsequently asked for 10% stronger color and reported that the effect
felt concentrated in midtones. The [targeting screen](research/2026-11-07_shadow_color_target_110.md)
records an isolated 110% candidate and a shadow-focused 110% candidate. A sampled
dark shelf had a median original gate of .434; the focused candidate produces
more color there. Compare stills in
`captures/shadow_color_110_shadow_20261107/review.html`. Both remain experimental;
real noise, dense motion, direct numeric contracts and production adoption remain
open.
The user chose the shadow-focused variant, then reported that all versions were
hard to distinguish from source and requested a 200% visibility test. The
isolated 200% build and two stills are in
`captures/shadow_color_200_20261107/`; `review.html` switches source/110%/200%.
It is a visual test, not an adopted or motion/noise-validated change. A separate
110% numeric probe was interrupted before any result was obtained.
The user clarified that 110% was visible too and asked to focus the color on
black/gray-looking shadows. The [narrower-range test](research/2026-11-07_darkrange_shadow_color.md)
keeps the selected 110% deep-shadow response and fades out earlier. Same-update
samples preserve the selected dark shelf and reduce the brighter wall response;
it is not semantic shadow/material identification. Review source/prior/new in
`captures/shadow_color_darkrange_20261107/review.html`. Further noise, motion,
ramp and broader-material validation remains; nothing was adopted.
At the user's request the same gallery also includes a 200% darker-range
variant, in `captures/shadow_color_darkrange_200_20261107/`. Its still repeats
vary by at most one code; it is an isolated visual comparison.
The user now regards 110–115% as acceptable but finds shadow-focused and normal
110% similar, and asks to identify real shadows and underlying material color.
The [identity/color investigation](research/2026-11-07_shadow_identity_color.md)
finds a visible GZW paving shadow where the narrow brightness gate is zero on
216/256 valid same-update input samples. It sets out the available evidence,
ambiguity, and next representation test; no new implementation is selected.
The subsequent [surface-relation screen](research/2026-11-07_shadow_surface_relation_screen.md)
tests oracle-registered synthetic texture/color and temporal controls plus
manual GZW crops. Texture orientation falsely favors the wrong crop; different
physical causes can produce identical RGB observations. Temporal local-vs-global
change is conditional evidence, not a classifier; no shader candidate follows.
At the user's request for a review test before their remaining session budget,
an isolated [context-color prototype](research/2026-11-07_shadow_context_review.md)
was built and privately captured. It extends the color gate using nearby brighter
similar-RGB samples, without inferring albedo. Explicit signal visualization
shows response on the shadowed paving as well as nearby sun-paving/crate crops;
it is not a reliable shadow classifier. The review is
`captures/shadow_context_review_20261107/review.html`; no production adoption,
performance, dense motion or noise acceptance follows.
The user reports no visible difference for that context candidate and asked for
online shadow-identification research. The [online findings](research/2026-11-07_online_shadow_detection.md)
cover paired regions/edges and learned temporal masks, their limitations and an
offline detector-reference test. Treat the local-context visual result as
negative; no runtime detector or albedo access has been established.
The user requested the offline tester first. [The BDRAR tester and first results](research/2026-11-07_offline_shadow_detector.md)
are ready, CPU-only, with five stills in
`captures/shadow_detector_bdrar_20261107/final_review/review.html`. The model
highlights the paving shadow but also broad dark scene areas; visual masks are
an offline reference, not a validated game-time solution or material color.
On 2026-11-08 the user approved a known-answer test instead of scoring against
BDRAR. The [oracle scene](research/2026-11-08_shadow_oracle_scene.md) renders
exact albedo/illumination on CPU and compares the current helper with oracles;
review `captures/shadow_oracle_20261108/review.html`. A perfect shadow gate with
observed chroma amplifies the blue sky cast; only the true-material-color oracle
enriches material. The user then **closed shadow detection** and moved the
priority to brightness recovery (2026-11-08). Nothing adopted.
The [brightness oracle](research/2026-11-08_brightness_oracle.md) (SDR→SDR,
same 8-bit pixels and curve) shows that attributing gain to exact light instead
of pixel luminance avoids lifting lit dark materials and crushing shadowed dark
ones. A CPU replica of production's tonal base matches the global curve's attribution
(mean error vs oracle .212/.181 stops, identical to global) while smoothing texture
~25%; see `captures/brightness_oracle_prod_20261108/review.html`. The
[Retinex screen](research/2026-11-08_retinex_light_screen.md) (magnitude and
chromaticity edge rules) does not beat production on region-balanced error,
except a modest chromaticity gain; no candidate. Review
`captures/retinex_screen_20261108/review.html`. The user then **closed brightness
recovery** (2026-11-08); production lift is unchanged. The user froze the
darker-range 110% shadow color (amount tied to BLACKS, no new control) as the
[adoption candidate](research/2026-11-08_shadow_color_candidate.md): 20 matched
stills, output-noise and cut checks done; awaiting the user's adopt/reject
decision from `captures/shadow_color_candidate_20261108/review.html`. Review
`captures/brightness_oracle_20261108/review.html`. The user then rejected that
candidate's feel ("saturation of darker colours") and asked for a tint of the
surroundings' colour. The [shadow tint mockups](research/2026-11-08_shadow_tint_mockups.md)
reach an accepted CPU look (v9, strength 1.0):
- Oklch+ equal-perceived step toward the surroundings' hue;
- Helmholtz–Kohlrausch darkening, faded out near emitters;
- surface-only context.

Review `captures/shadow_tint_mockup9_20261108/review.html`. The isolated
[shader candidate](research/2026-11-08_shadow_tint_candidate.md) (grade
`bab1bac7…cb9`) has completed the following, after two defects found in
validation were fixed (lit spots, per-pixel noise amplification):
- 28 matched stills;
- both noise fixtures;
- the scene cut.

The user found a tinted halo around the character in Arc 210448. Four colour-only
cues failed to remove it. Depth is rejected because it is an anti-cheat flag.
The user **accepted** the limitation, and the tint was **adopted** into
production on 2026-11-08 (uncommitted). It was first set to .7; the user then chose
1.0 in both profiles (the fully validated strength). The .7 production captures matched
the .7 candidate within repeat variation (≤2 codes). Both queued follow-ups are done; neither produces a candidate:
[cue-map oracle scoring](research/2026-11-08_cue_map_oracle.md) and the
[yellow/orange re-test](research/2026-11-08_hk_chroma_retest.md).
Review fixes from the
[full-shader review](research/2026-11-08_ultrareview_fixes.md) are applied
(uncommitted).

The requested root-document cleanup is complete; it changed documentation only.
The root guides now separate rules, goals, priorities, state and procedures;
technical contracts live in [docs/pipeline.md](docs/pipeline.md), and removed
historical detail is preserved in the [root ledger](research/2026-11-06_root_document_history.md).
Shadow research resumed earlier today;
no runtime is intentionally left active and no adoption question is pending.

#### Production

Both active configs use one combined `ShaderPipeline`; grade has thirteen passes
(eight plus five shadow-surround-tint passes). Latest adopted code:
[shadow surround tint](research/2026-11-08_shadow_tint_candidate.md) (2026-11-08,
uncommitted), [shared tonal base](research/2026-11-02_tonal_architecture.md) and
[shared-component CC](research/2026-11-03_neutral_component_cc_adoption.md).

- HEAD at checkpoint: `b4c52e4d178fb535872dd6b93ec9df3697a5246d`.
  Local upstream matched then; no remote fetch was claimed. Check git for current state.
- Root grade SHA-256: `efea23e8c8e061a77619c8c42f89f1d73c35523623ea90a1f3ee4028e8f40c56`
  at the checkpoint; after the uncommitted 2026-11-08
  [review fixes](research/2026-11-08_ultrareview_fixes.md) it is
  `36f44c14961b4c7efa23976ac70a45fbba12d9c98380a9d385b78de9361f7180`. After the
  shadow surround tint adoption (strength 1.0): grade
  `111afeee85c0f29b11b2d8ec682efe232533d4155e7fd1508556177f870a17ea`, pipeline
  `bec87beced4ea7ace88191f72c912173a9c9ef828b3acfe9185843d927ad15b2`. Both
  `creative_values.fx` gained one line (`SHADOW_SURROUND_TINT 1.0`); configs are
  unchanged. The earlier 17-identity set no longer applies.
- The latest controlled-course audit verifies all 17 production identities
  unchanged. Shader/profile/config/header/history/resource/pass state is preserved.

| Profile | BLACKS / WHITES | Inverse chroma / luma | FilmCurve | Shadow temp / tint | Mid temp |
| --- | --- | --- | --- | --- | --- |
| GZW | .0025 / .995 | .60 / .60 | .70 | −.05 / −.010 | .05 |
| Arc | .0025 / .995 | .5 / .5 | .6 | −.075 / 0 | .05 |

`INVERSE_STRENGTH` controls chroma reconstruction. These profile values supersede
older evidence epochs; do not reuse old outputs by grade identity alone.

#### Research readiness

| Contribution | Provisional effectiveness | Decision |
| --- | ---: | --- |
| New brightness recovery | ~45/100 | Closed 2026-11-08: no viable single-frame light/material separation |
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

#### Visual candidates and motion build

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
brightness. The isolated build remains in
`captures/shadow_visual_pipeline_20261106/gzw_motion_100/`. Resume it only if
the revised visual assessment establishes a relevant need and plausible benefit.
The compact curve in the still build failed the held timber screen; it is not
an adoption candidate. The more extensive color controls concern 50% strength,
not the user's selected 100% isolated visual candidate.

#### Resume evidence

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

## PLAN.md (before)

### Current plan

Work toward [GOAL.md](GOAL.md), preserving profiles and production. Current
identities and estimates are in [HANDOFF.md](HANDOFF.md); implementation history
is in [CHANGELOG.md](CHANGELOG.md).

#### Adopted: shadow surround tint (2026-11-08)

The user accepted the CPU [shadow tint](research/2026-11-08_shadow_tint_mockups.md)
look (v9, strength 1.0). Isolated shader candidate:
`captures/shadow_tint_candidate_20261108/`, validated in the
[report](research/2026-11-08_shadow_tint_candidate.md). The user accepted the
character-halo limitation (no depth: anti-cheat), and it was adopted as
`SHADOW_SURROUND_TINT` 1.0 (uncommitted).

Queued after the tint review (user-approved 2026-11-08), CPU-only first:
1. Score the candidate's relative-darkness, near-light and lit-spot maps against
   the shadow/brightness oracles' exact shadow and light masks. These are cue
   maps, not a reopened shadow detector.
2. Mock up Helmholtz–Kohlrausch compensation on the existing chroma stages
   (inverse chroma, vibrance/saturation, print) for the testbed's yellow/orange
   over-saturation, using smooth-field application for noise safety.

Promote only what measurably helps; reuse the candidate's maps, with no new passes.

Both queued items are done (2026-11-08); neither produces a candidate:
- [Cue-map oracle scoring](research/2026-11-08_cue_map_oracle.md): the weight
  separates shade from light at chance level in daylight (AUC .51). No
  light/material signal; brightness recovery stays closed.
- [Yellow/orange re-test](research/2026-11-08_hk_chroma_retest.md): production
  adds ≤6% warm chroma and about .3 L* of H-K brightening. No gap, so no H-K
  chroma candidate.

#### Closed: brightness recovery (2026-11-08)

The user closed the new brightness-recovery effect after the
[brightness oracle](research/2026-11-08_brightness_oracle.md) and
[Retinex screen](research/2026-11-08_retinex_light_screen.md): the benefit needs
single-frame light/material separation that neither production's tonal base nor
classical methods provide. Production lift is unchanged. Do not reopen without a
new light/material signal. History follows. The
[brightness oracle](research/2026-11-08_brightness_oracle.md) identifies the
light/material split as the lever. Production's tonal base attributes light
exactly like a global curve (same error vs oracle). The
[Retinex screen](research/2026-11-08_retinex_light_screen.md) found no classical
single-image rule that closes the gap (balanced error; a uniform-lift control
explains the interior's apparent gain). No shader candidate; closed.

#### Closed: shadow detection

Closed by the user on 2026-11-08 after the
[oracle scene](research/2026-11-08_shadow_oracle_scene.md): even a perfect shadow
gate mainly amplifies the illumination cast; only unavailable material color
enriches material. Do not resume detector work without new evidence. History:
the user wanted a distinction between actual shadows and intrinsically dark
materials, and material-dependent shadow color. The
[identity/color investigation](research/2026-11-07_shadow_identity_color.md)
shows a real shadowed paving patch for which the current narrow brightness gate
is zero on 84.375% of measured grade-input samples. Investigate supported
surface/lighting relationships and confidence before another candidate; do not
equate brightness with shadow or copy the color of a lit neighbor as albedo.
The [surface-relation screen](research/2026-11-07_shadow_surface_relation_screen.md)
rejects standalone texture orientation and establishes temporal evidence only
under perfect correspondence. Seek independent correspondence and illumination
evidence rather than treating either cue as ground truth.
The user requested an immediate review test; the isolated
[context-color prototype](research/2026-11-07_shadow_context_review.md) and its
limitations were reviewed, and the user saw no visible difference. The
[online detector research](research/2026-11-07_online_shadow_detection.md)
identifies offline learned-mask and shadow-edge references; neither establishes
a runtime classifier or material color. Do not adopt the local-context prototype.

#### Brightness recovery context

The user wants a fuller light-to-dark tonal progression and subtly richer
material color in shadows, with readable partial shadows and deep occlusion.
Fine gradient preservation supports this goal but is not the whole goal. Judge
the combined appearance and each useful contribution against GOAL.md; existing
scores predate this clarification and are not a fresh assessment.

The [controlled JavaScript course](research/2026-11-06_temporal_course_results.md)
is built and supports the temporal mechanism under changing noise. A
[bounded affine producer](research/2026-11-06_shadow_bounded_motion.md) now replaces
feature matching in a CPU reference. Whole-frame estimation retains selected
material gains; persistent grain, invalid correspondence and support modulation
remain. GPU cost/equivalence and worthwhile full-grade benefit are unproven.
Target operation is 80–110 fps; source-clock tests are distinct from real GPU
cadence/performance validation. Require visible full-grade benefit before a shader
candidate. Real footage is later generality work, not the next-test prerequisite.

The 2026-11-07 isolated GZW build compiles coarse guide/history and a fixed-work
translation estimator, but has no readback, moving-scene validation or brightness
recovery connection. Motion is an unproven possible means, not a required
implementation. The compact spatial curve was rejected on held timber and is a
comparison only; it is not motion-aware recovery.

1. Review matched native source/full and available color/combined comparisons
   across lit, partially shadowed and deeply occluded areas, warm/cool/neutral
   materials and representative lighting. Start with the user's selected 100%
   color variant; distinguish shared arithmetic evidence from 50%-only controls
   and from the separately offset BLACKS=0 configuration.
2. Attribute a consequential loss using relevant bypasses and unchanged repeats.
   Assess the entire transition and scene relationships alongside texture, black
   anchor, noise, boundaries and color; darker or more separated is not a target.
3. Only develop a distinct model if the visual evidence warrants it. Explain where
   tonal range comes from, its costs, and a plausible runtime data path. Do not
   assume motion or another new effect is necessary.
4. Compare surviving contributions and their combination on matched inputs, then
   run appropriate contracts and measured motion. Finish an adopt/reject decision;
   research and isolated testing do not authorize production adoption.

Read the [investigation index](research/2026-11-06_shadow_session_index.md),
[regional budget](research/2026-11-06_shadow_region_budget.md),
[adaptive range](research/2026-11-06_shadow_adaptive_range.md) and
[RGB shading rejection](research/2026-11-06_shadow_rgb_shading.md) and
[connected-structure rejection](research/2026-11-06_shadow_connected_structure.md) before choosing
a model. These retain failures and limits, not implementation proposals.

Do not repeat rejected curve/filter/gain sweeps, widen spectral filters again,
loosen noise gates until materials engage, or build segmentation merely to port
weak references. Numerical correctness, darker means and quiet noise patches
are insufficient. No universal acceptable-noise percentage was established.

#### Optional confidence work

Broader game/lighting coverage, dense gameplay, physical high refresh, whole-chain
hitches, and remaining resolutions/aspects would support stronger claims. They
are not a mandatory repair queue. Reopen completed technical decisions only for
a concrete new failure. GPU profiling remains deferred.

The requested root-document cleanup is complete. Shadow research is next.
No shader/profile/config adoption, automatic re-score, commit or push is pending.
