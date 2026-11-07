# Shadow research: new-session checkpoint, 2026-11-06

## Latest continuation — 2026-11-07

The user resumed the work and asked for a finished motion-aware brightness
prototype. Read [the November 7 motion/color checkpoint](2026-11-07_motion_brightness_prototype.md)
first. A GPU guide/history and fixed-work global translation estimate now compile
in an isolated GZW candidate, but there is no estimate readback, moving-course
validation, warped full-resolution history, correspondence rejection or
brightness connection. Continue this build; it is not gameplay-ready. The user
visually selected 100% color, and currently requests lift .25 / BLACKS 0 in the
isolated GZW visual config linked from HANDOFF. The copied candidate decouples its
experimental color offset from BLACKS. Production remains unchanged.

Research resumed at the user’s request. The latest
[controlled JavaScript course](2026-11-06_temporal_course_results.md) adds rendered
clean/ID sources, known geometry and matched RGB8 noise, with timestamped clocks
for the user’s 80–110-fps operating range. Source-clock/CPU tests do not establish
actual GPU cadence or performance. Temporal benefit under changing noise remains
conditional. The subsequent [bounded-motion screen](2026-11-06_shadow_bounded_motion.md)
replaces feature matching with a fixed-grid affine CPU reference and checks
whole-frame estimation. It retains selected steady-motion benefit but leaves
fixed grain, invalid history, support modulation, modest native return and
unmeasured GPU cost. It does not establish an implementation proposal. Artifacts are
under `captures/shadow_temporal_course_20261106/`. The preceding
[shared-motion follow-up](2026-11-06_shadow_temporal_planar.md) and its failed
epochs remain unchanged. The prior
[temporal-support screen](2026-11-06_shadow_temporal_support.md), including its
coarse-search failure and exhaustive reference, remains unchanged. The preceding
[connected-level-set](2026-11-06_shadow_connected_structure.md) and
[RGB](2026-11-06_shadow_rgb_shading.md) representations remain rejected. All 17
production identities remain; brightness/color estimates stay ~45/~70–75.
The older stop instruction is historical and superseded by the 2026-11-07
motion-prototype continuation. Current root guides are consolidated.

This is the consolidated state after the user requested documenting everything
for a new session. The sole startup prompt remains
[startup-prompt-latest](../startup-prompt-latest). Read [GOAL](../GOAL.md),
[PLAN](../PLAN.md), [HANDOFF](../HANDOFF.md) and repository rules. The full previous
startup/handoff text is preserved in the [checkpoint archive](2026-11-06_shadow_checkpoint_archive.md).
Its pending leads and adoption language are historical, not current instructions.

## User objective and earlier stopping point

There are two experimental additions, both intended to approach at least 75/100:

| Part | Intended appearance | Provisional effectiveness | Current state |
| --- | --- | ---: | --- |
| Brightness-gradient recovery | Neighboring shades describe material shape and depth, retaining a convincing black anchor and lighting | ~45/100; ~30 below target | Main unfinished design work. A GPU motion prototype has begun; it does not yet recover brightness. |
| Subtle shadow color | Blue-black and brown/red-black material distinctions, without a conspicuous tint | ~70–75/100; 0–5 below target | The user visually selected 100% of the bounded correction for isolated testing. Production remains unchanged. |

The estimates are coarse judgments of visual usefulness, not completion,
fidelity, measured noise thresholds or points earned by passing more tests.
The existing production chain/grade **78** and joint tonal-model **80** retain
their older scope and profile epochs. No fresh whole-chain score is claimed.

The color choice authorizes isolated visual tests, not production adoption.
Continue motion-aware brightness work while preserving production.

## Production and profile identity

HEAD and upstream at checkpoint: `b4c52e4d178fb535872dd6b93ec9df3697a5246d`,
with zero commits ahead/behind in the local tracking refs. No remote fetch is
claimed. Production grade SHA-256:
`efea23e8c8e061a77619c8c42f89f1d73c35523623ea90a1f3ee4028e8f40c56`.
The 17 shader/include/profile/config identities are recorded in
`captures/shadow_region_budget_20261106/verification.json` and the documentation
checkpoint snapshot under `captures/shadow_handoff_20261106/`.

All experiments in this session leave production shaders, profile values,
active configs, shader headers, producers, histories/rates, resources and eight
grade passes unchanged. Both actual configs still use one combined pipeline.
No HDR, auto-exposure, temporal grain, new user control or active denoising is
introduced. Existing adopted shared tonal-base/CC/print/inverse work remains.

| Profile | BLACKS / WHITES | Inverse chroma / luma | FilmCurve | Shadow temperature / tint | Mid temperature |
| --- | --- | --- | --- | --- | --- |
| GZW | 0.0025 / 0.995 | 0.60 / 0.60 | 0.70 | −0.05 / −0.010 | 0.05 |
| Arc | 0.0025 / 0.995 | 0.5 / 0.5 | 0.6 | −0.075 / 0 | 0.05 |

`INVERSE_STRENGTH` is the profile's chroma-reconstruction control; do not invent
an `INVERSE_CHROMA` setting. Newer GZW values above supersede historical tint
epochs. Never reuse old full images by grade hash alone. Current documentation
and November 4–6 research are uncommitted; ignored capture media/scripts remain
local. Do not force-add them or discard existing untracked research.

## Preserved color option

Read [half-color validation](2026-11-06_shadow_color_half_validation.md) and
[source-neutral attribution correction](2026-11-06_shadow_neutral_alignment.md).
The fixed helper redistributes half of a bounded, source-gated neutral black
offset into the incoming RGB ratios, with ideal zero luminance change before
later grading. Gray, source black and BLACKS=0 have measured scoped bypass
evidence. It improves selected shelf/metal/timber/pack color subtly; brightness
gradients barely change. No stronger color or profile search is queued.

The completed review has 43 fresh private GPU processes, finite numeric/black/
zero/chart checks and 192 measured sparse-motion controls. Retained costs include
about +24% full-chain code-16 chromatic std versus current, chart/noise/temporal
repeat variation and palette/quantization costs. Float noise remains below the
incoming fixture; some quantized comparisons slightly exceed it. This is not
universal noise acceptance or dense motion coverage.

Exact grays and weak source colors are different populations. Selected weak
source colors already match grade input; inverse did not introduce them. Do not
repeat the earlier false attribution or suppress intentional weak colors.

Frozen artifacts: `captures/shadow_color_half_review_20261106/`, including patch,
review, verification and manifest. Compiled isolated grade hash:
`aa8439f1d7f7e4a243bca22a6002503aea6315529f7bc6c983784bf336d249fb`.
Would-be adopted root hash:
`2a49a3bd973b4adcd80299e2bdf878564c712ccbfb03089f902168173825d858`.
Neither is active. `actual_after_adoption.py` is prepared but not run; its
existence does not authorize activation. Leave the frozen review intact.

## Brightness investigation map

These decisions close their specific models, not every possible shading method.
Do not restart their parameter sweeps or mistake numerical execution for a
surviving visual candidate.

| Family | Evidence / result | Decision and retained limitation |
| --- | --- | --- |
| Controlled rendered course | [Engine evaluation](2026-11-06_temporal_course_results.md) | Verified source/geometry/noise controls support changing-noise temporal benefit; fixed grain and unreliable history remain. Source-clock tests target 80–110 fps; no real-time shader candidate or GPU performance claim. |
| Shared projective motion | [Temporal refinement](2026-11-06_shadow_temporal_planar.md) | Better forest/clearing and known-material correspondence; estimated-motion scalar range tests and modest ideal full-grade bounds. Local support costs reuse; persistent grain survives. Conditional CPU lead, no runtime proposal. |
| Temporal support | [Conditional screen](2026-11-06_shadow_temporal_support.md) | Ideal alignment separates changing noise; scalar range benchmark is not native benefit. Weak RGB block matching, few accepted moving samples and persistent grain prevent a runtime candidate. Initial search-control failure is preserved separately from the exhaustive reference. |
| Connected geometry | [Level-set screen](2026-11-06_shadow_connected_structure.md) | Fixed area base retains ramps/thin lines but loses fine material gaps and passes long grain/banding; one-pixel bridge changes 64 unchanged base samples. CPU representation only; no correction or port. |
| RGB-consistent gradients | [RGB cue](2026-11-06_shadow_rgb_shading.md) | Retains selected material evidence but passes all tested common-mode brightness noise. Not a standalone shading selector. |
| Fixed and compact curves | [Held timber](2026-11-06_compact_tone_held_material.md): selected shelf/metal/pack gains, ~15% loss in held timber shade bands | Rejected. A finite curve must pay for added slope elsewhere; fitted knots do not generalize. |
| Graph, plane and constrained slopes | [Local slope](2026-11-06_shadow_local_slope.md), [constrained model](2026-11-06_shadow_constrained_slope.md) | Clean/noisy ramp controls can improve, but rims/black leakage or constraints remove native material benefit. No solver port. |
| Dense local-Laplacian recovery | [Dense brightness](2026-11-06_shadow_dense_brightness.md), [noise restraint](2026-11-06_shadow_noise_restraint.md) | Some larger selected gaps, but synthetic/actual-fixture noise, reversals and boundaries remain; conservative guards lose useful response. |
| Noise structure and estimation | [Structure research](2026-11-06_shadow_noise_structure_research.md), [covariance](2026-11-06_shadow_covariance_estimation.md), [observations](2026-11-06_shadow_noise_observations.md), [local validation](2026-11-06_shadow_local_noise_validation.md) | Conditional synthetic progress, no credible real-material noise/texture separation. All 12 local material cells reject the tested observation model. Do not loosen gates until they pass. |
| Common source/output base | [WLS full-frame decision](2026-11-06_shadow_wls_fullframe.md) | Late PNG transfer has small/mixed absolute gains and material losses. Cheap guided versions trade fine response for noise. Finished output is unavailable in existing pre-grade passes. Do not port CG. |
| Stage-specific black cooperation | [Actual GPU screen](2026-11-06_shadow_black_cooperation.md) | Twelve private processes, exact measured still repeats; shelf absolute gap −4.88%, metal mostly darker density. CPU local-reference revision too weak. Rejected. |
| Sub-window edge model | [Screen](2026-11-06_shadow_subwindow_recovery.md) | Different boundary model still mostly buys noise or loses material response; negligible ramp recovery and small step rims. CPU only. |
| Scene-learned range allocation | [Adaptive range](2026-11-06_shadow_adaptive_range.md) | Rank mapping flattens shelf; forward-consistent spatial-pair fit gives only ~1–2% selected gains. Quiet median-base path loses fine benefit; independent ramps still lose range. |
| Regional ownership and joint spectral budget | [Latest screen](2026-11-06_shadow_region_budget.md) | Region point reference gives shelf/timber ~5–6% gains at unchanged mean code Y. Paying for broad shading with fine attenuation helps known noise but loses metal/detail and amplifies longer-range grain. No automatic segmentation or runtime candidate. |

## Latest result, precisely scoped

Supplied rectangular regions are ownership diagnostics, **not** verified material
boundaries or an ideal segmentation upper bound. Point contrast gains include
about +5.36% shelf/+5.74% timber at four pixels; mean code Y is preserved in CPU
arithmetic. Median-base metal can transfer a 15.5-code correction around thin
bright features. This invalidates treating that base as safe material geometry.

The joint white-noise budget attenuates some existing finest variation while
enhancing broader shading. Captured white-like noise std stays near unchanged
and timber's 64-pixel gap improves ~5.91%; short grain grows ~9.1%. The wider
three-spectrum budget protects its stated stationary white/short-grain/banding
models but metal's four-pixel gap falls ~2.18%. Timber's 64-pixel gain is ~4.95%.
Matched short-grain std is approximately unchanged in a dedicated control;
longer-range grain rises ~8.74%. A low-frequency noise sinusoid receives the same
gain as useful shading. This is not arbitrary-spectrum protection.

The spectral runner replaces the blur function: its main grain field uses two
**wide** blurs, unlike the first model's two small blurs. The separate matched
and holdout controls record both. Preserve this distinction when comparing
tables. Noise contexts reuse one GZW fixture at different region gains, not
independent game/material noise captures.

No fresh GPU process ran in the three latest CPU screens. Prior GPU readbacks
are inputs, not new numerical shader/temporal evidence. No candidate is adopted.
All foreground analysis runs completed; no runtime is intentionally left active.

## Reuse, failures and artifact locations

| Directory under `captures/` | Contents / limits |
| --- | --- |
| `shadow_dense_float_20261106/` | 256² same-update floating source/current/half-color wall, metal and noise observations; variants on axis 2 are source/current/color. |
| `shadow_dense_material_20261106/` | 512² wall/metal/held-timber observations. Target rectangles and source/clip/profile identities in `report.json`. |
| `shadow_black_cooperation_20261106/` | Actual isolated GPU screen, rejected patch, exact still repeats, CPU context/local-reference diagnostics; no activation. |
| `shadow_subwindow_20261106/` | 18 manifested artifacts; joint edge-model adaptation, independent rectangle checks. |
| `shadow_rank_base_20261106/` | 129 manifested artifacts; initial invalid extrapolation, six corrected rank proxies, incomplete and corrected pair fits, review/controls. |
| `shadow_region_budget_20261106/` | 49 manifested artifacts; supplied-region reference, `joint/`, `spectral/`, matched/holdout checks, native review/audit. |
| `shadow_handoff_20261106/` | Documentation checkpoint identities, worktree/publication state, document and manifest checks. |

Dense readbacks freeze all variants at one update and record encoding precision;
independent noise/timber repeats have small nonzero differences. Most full-scene
CPU work uses two separate 8-bit grade-input PNGs and four raw-source
approximations, not exact floating full-frame observations. No second dither is
added to already dithered PNG proxies. Native floating previews use approximate
CPU encoding/dither and are not shader screenshots.

Preserve failures: initial build include-prefix assertion in the GPU screen;
invalid constant interpolation beyond code 128 in the first rank model;
pair-budget fit omitting the final source gate; zero-count/NaN rank summaries;
all genuine repeat variation. Labels do not establish shader identity. Do not
import historical generators that execute at module scope or overwrite frozen
reports. In particular, AST-extract the color insertion from its script rather
than importing it. Keep rejected patches as evidence, not commands to apply.

## Next-session work contract

1. Confirm current identities and read the latest regional and adaptive-range
   decisions, together with native comparisons, before proposing a model.
2. Continue brightness design from a distinct supported material/shading
   representation. There is no selected next algorithm or guaranteed route to
   75. A proposal should explain where range comes from, how the black anchor
   and material lighting survive, and which variation it treats as expendable.
3. Challenge useful native appearance, absolute **and** relative separation,
   density, boundary leakage, thin features, fine-texture loss and correlated
   noise together. Do not set a universal acceptable noise percentage from one
   synthetic fixture, or treat darker means as recovered dimension.
4. Do not operationalize rejected models by adding segmentation, widening
   filters, raising gains or loosening confidence checks. The local mean/code
   constraints and spectral impulse contracts are benchmarks, not acceptance.
5. Require a worthwhile CPU/native case and a plausible runtime data path before
   a new GPU screen. Added current-output data is not a free reuse of pre-grade
   resources. If a candidate survives, compare current/color/brightness/combined
   under matched identities, then do appropriate contracts and measured motion.

Preserve profiles, shader headers, active configs and historical evidence. All
runtime remains private/headless, with no desktop fallback. GPU/localhost work
requires escalation; fixed settling alone does not prove convergence. Sparse
duplicated motion poses do not establish dense continuity. No automatic
effectiveness re-score, performance campaign, commit or push is queued.

## Complete report inventory

The companion [report inventory](2026-11-06_shadow_report_inventory.md) lists all
November 4–7 research reports and their titles. Each report retains its original
evidence epoch and detailed primary-source links; this checkpoint supersedes
only stale next-step instructions. Earlier adopted work remains in PLAN and
the November 2 ratings board.
