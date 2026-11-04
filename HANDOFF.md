# Handoff — 2026-11-03

Read [startup-prompt-latest](startup-prompt-latest), [AGENTS.md](AGENTS.md),
[CODE_RULES.md](CODE_RULES.md), [GOAL.md](GOAL.md), [PLAN.md](PLAN.md) and
[TOOLS.md](TOOLS.md). The user resumed work, redirected it from small capture
screens to model design, and authorized the approach with the highest expected
return toward the visual goal. The shared tonal base is implemented and active.
Existing profiles/configs and prior user changes are preserved.

The preceding publication remains `4e2fbf4`; use git log/status/tracking for
current state. Stable `v1.0` remains `1724bb6`. The user explicitly authorized committing and pushing the completed shader,
prior November 1 work, documentation and updated ratings. Use current HEAD and
upstream tracking for publication state. No runtime process remains active.

## Current direction — 2026-11-04

The user wants clear, naked-eye improvements. Compare current full output and
source at native size across dark, daylight, vivid and highlight scenes; identify
a recurring visible loss before designing a shared-code candidate. Avoid small
numerical screens and preserve profiles. The [audit](research/2026-11-04_pipeline_leads.md),
[slow-key probe](research/2026-11-04_slow_key_sentinel.md), [hue ablation](research/2026-11-04_hue_direction_screen.md)
and [print screen](research/2026-11-04_print_chroma_screen.md) document the
latest work. None produced an adopted change or demonstrated a clear visible
improvement; their limitations and older profile epochs remain explicit.

The current external GZW profile has FILM_CURVE=0.70, SHADOW_TEMP=-0.05,
SHADOW_TINT=-0.010 and MID_TEMP=0.05. Preserve these choices. The November 3
GZW evidence predates them; match all identities before reusing baselines.
Use git status and upstream tracking for publication state.

## Latest adoption — shared-component color correction

The user explicitly authorized implementation. The
[shared-RGB CC decision](research/2026-11-03_neutral_component_cc_adoption.md)
is adopted in the shared grade and verified through both unchanged active
configs. Three added lines scale existing a/b offsets by min(linear RGB)/Y.
Gray-axis response is GPU-identical to the original; saturated primary faces
match zero correction. Profiles, headers, producers, histories/rates/resources
and passes remain; grade stays eight passes.

Selected foliage hue shift +2.962°→−0.131°, weak shelf color separation +15.1%,
Arc cool-upper/dark-metal separation +4.4%/+4.1%; white-core shape remains.
Blue-sky/field separation −6.5%/−2.1%, red-lamp −2.5%, warm-floor −1.6% and small
cloud/paving/quantization/transition costs remain. GZW dark source-neutral
shadows lose some cool tint but remain cool; exact helper-gray identity does not
mean source-neutral final images are identical. No universal palette claim.

Five candidate and five baseline pairs are exact. Direct GPU/CPU contracts,
two exact all-CC-zero pairs, both gradient charts, 192 exact measured same-update
motion controls over four independent replays and four actual-config exact
candidate matches pass. Sparse 15-pose/sec source, temporal repeats and small
step costs remain documented. All 22 tooling tests and whitespace checks pass.

Current identities: `captures/neutral_cc_20261103/adoption_verification.json`;
full artifact hashes: `artifact_manifest.json`; local review: `review.html` in
that directory. Older tonal-base outputs retain the pre-CC epoch. Chain/grade
stay 78; CC 75 is a retained provisional estimate, not a new effectiveness
re-score. At that historical checkpoint production shader/document changes were uncommitted;
use current git status and upstream for publication state. No runtime process remains active. This finite
adoption is complete; no mandatory sweep follows.

## Previous closed experiment — inverse transport

The user authorized the [precision-handoff experiment](research/2026-11-03_inverse_transport_decision.md).
**Rejected for adoption:** FP16 source-relative residual transport substantially
reduces numerical handoff error, but selected native/full-frame comparisons show
no useful visible return for the extra 28.125 MiB surface at 1440p. Two same-update
GPU probes and ten ordinary captures cover both current profiles plus a vivid
explicit-eight-bit handoff. Five held pairs are exact; completed captures have
zero drops/delays. Initial quantizer/transfer assumptions and an isolated include
compile failure remain documented. No motion/zero/chart/activation/performance
acceptance is claimed or needed to reject it.

At that rejection checkpoint production remained `738a6f6`, synced to
origin/master, and shader/profile/config hashes were unchanged. Chain/grade
remained 78. The subsequent CC adoption above supersedes its grade identity.
The transport selection/decision notes were uncommitted at that checkpoint;
use current git status and upstream for publication state. Local artifacts and review:
`captures/transport_candidate_20261103/`. No runtime remains active, mandatory
follow-up, score increase or parameter sweep. Do not reopen this representation
solely for better precision statistics.

## Current adoption

The [shared tonal-base decision](research/2026-11-02_tonal_architecture.md) is
adopted and active in both combined configs. Retinex, zone shaping and lift use
a common brightness base estimated from the existing full-resolution native
guide, with smooth source-range rejection and continuous overlapping-window
weights. Original corrected-pixel detail is carried through their combined gain.
The original relative Retinex spatial correction and prescribed chroma treatment
remain. No profile/config/header, inverse, history/rate/resource or pass change
is introduced; grade stays eight passes.

Selected local shade response improves about 2.2% bedroom cloth, 4.3% plaster,
3.8% floor and 3.3% interior cool window. Seven selected held pairs and current
baseline pairs are exact, with the original vivid baseline failure explicitly
retained. Two numerical GPU readbacks, two exact tonal-zero pairs, both chart
profiles, 192 exact measured candidate/ordinary controls and four actual-config
outputs matching the candidate exactly pass. Flat-face median edge L/C gaps
are zero in all 18 records. Road/paving contrast expansion, small vehicle/metal/
shelf/cloud/halo, quantization and transition costs remain. Temporal repeats
reach one code. The subsequent requested ratings review estimates chain/grade
at 78 and the joint tonal model at 80; individual effect scores remain retained.
Dense/high-refresh and performance claims remain limited.
The 70 fresh private GPU processes have zero drops/delays; the audit checks
307 files / 652 images. All 22 tooling tests and whitespace checks pass.

Current source/profile/config and old/new grade hashes are in
`captures/tonal_base_20261102/verification.json`; review is local
`captures/tonal_base_20261102/review.html`. The original vivid baseline pair
varies in 78 pixels by up to 16 codes. An incorrectly named refresh ran a
rejected prototype and is excluded; a separately captured preserved-original
reference pair is exact. Normalized baseline shader bodies are now checked
independently of labels. Both failures remain recorded. No universal repair is
inferred. No further mandatory screen is queued. The user authorized committing
and pushing this completed work with the ratings update; use HEAD/upstream
tracking for publication state.

## Prior candidate searches

**Current profile epoch:** Arc BLACKS changed 0.005→0.0025 and GZW 0→0.0025.
`captures/arc_black_20261101/activation_state.json` verifies that only these two
profile values changed and records that checkpoint. Post-edit actual-config
checks were deferred at wrap-up and completed on November 2. The current shared
code/activation record is above. The Arc trial alone does not validate GZW,
and old BLACKS=0 GZW images remain historical output.

The [Arc black-offset trial](research/2026-11-01_arc_black_trial.md) recommends
0.0025 on its measured scope. Selected metal/vehicle visible separation improves
about 15.9%/9.2%, with useful neighboring-shade gains in the interior/bedroom.
Four held trial pairs and both chart current/trial pairs are exact. Two measured
replays pass 96 exact candidate/ordinary-output controls on the common masked
support. Seventeen private GPU processes have zero drops/delays. The audit checks
142 files, 333 images and sixty new source-exact dark-fixture frames; 22 tooling
tests pass. Retain dark-gradient quantization, dark synthetic-blue hue and small
night/daylight-step/relative-contrast costs. Sparse source remains 15 poses/sec
doubled to 30; no dense/physical-high-refresh or new rating claim follows.
**Subsequent authorization:** both profiles now use 0.0025. The figures above
retain their Arc trial scope. Actual-config identities were refreshed on November 2. Artifacts:
`captures/arc_black_20261101/`, including a local interactive `review.html`.

The earlier reconstruction question was independently CPU-screened, then stopped
after two held solver observations with tiny mixed changes. No scalar-solver
GPU readback, temporal or adoption claim follows. The architecture above is a
separate implemented model. The preceding rejected scalar/strength/classifier
screens remain closed.

The [native Retinex soft core](research/2026-11-01_retinex_core.md) is rejected.
Lit-paving visible separation gains about 4.5% and cool-window neighboring
response about 4.6%; shaded paving/wall lose about 4.8%/2.7% visible separation,
with further interior/bedroom local-response costs. CPU checks confirm that a
gentler center moves compression into the old saturation transition. Four
private GPU processes have zero drops/delays. Eight verified baseline pairs,
the 80-file/20-image audit and 22 tooling tests pass. No candidate-repeat,
numeric GPU, temporal or adoption claim follows. Production/profiles/configs,
histories/rates/passes and scores remain unchanged. Artifacts:
`captures/retinex_core_20261101/`. No width/strength/directional sweep or mandatory
repair is queued.

The [zone/lift composition screen](research/2026-11-01_zone_lift_cooperation.md)
rejects scaling added lift from zone-shaped luminance. Paving/cool/cloth benefits
are small; both selected floors lose visible and neighboring-shade separation.
The candidate scales the zone contribution algebraically but does not consistently
preserve material contrast. Three candidate/repeat pairs are exact. Six private
GPU processes have zero drops/delays. The audit checks 88 files, 22 images and
eight exact reused baseline pairs; independent fixed-context CPU algebra and
all 22 tooling tests pass. No numeric GPU/temporal/adoption claim follows.
Production/profiles/configs, histories/rates/passes and scores remain unchanged.
Artifacts: `captures/zone_lift_cooperation_20261101/`. No half-strength sweep or
mandatory repair is queued.

The [tonal material screen](research/2026-11-01_tonal_material_selectivity.md)
separates the configured Arc near-black pedestal from automatic midtone
compression. A black-only bypass raises selected metal relative separation
1.5257→2.8374 stops (source 2.6367); that checkpoint preserved `BLACKS=0.005`.
Interior and fresh bedroom/menu bypasses identify Retinex/lift contributions to
midtone neighboring-shade compression. Two guided-base classifiers have negligible
benefit; two original-source lift classifiers worsen selected local response and
material separation. All four are rejected. Twenty-three private GPU processes
have zero drops/delays. Eight baseline pairs are exact; the audit checks 148
isolated files, 37 images and sixty source-exact bedroom clip frames. All 22
tooling tests pass. No candidate-repeat, numerical GPU, boundary, temporal or
adoption validation is claimed. Production/profiles/configs, histories/rates,
passes and scores remain. Artifacts: `captures/tonal_materials_20261101/`.
No further classifier sweep or mandatory repair is queued.

The [grade chroma headroom screen](research/2026-11-01_grade_chroma_budget.md)
rejects all four isolated limits on automatic chroma additions. Including the
fixed midtone expansion does not produce a useful selected material/hue gain.
Three held cases × four variants add twelve private GPU processes, all with zero
dropped/delayed frames. Seven current baseline pairs are verified exact; the
audit verifies 104 isolated files and 26 images. Candidate changes reach only
325 pixels in a 2560×1440 image, at most two codes overall. No new black/code-255
samples appear. This is an early held rejection, with no candidate temporal,
numeric GPU, boundary or adoption validation claimed. All 22 tooling tests pass.
Production shaders, profiles/configs, histories/rates/passes and scores remain.
Artifacts: `captures/grade_chroma_budget_20261101/`. No further limiter sweep is queued.

## Current implementation

Both active game configs use `general/pipeline/pipeline.fx` as one effect.
Grade remains eight passes. Explicit sRGB/linear-light boundaries, bounded SDR,
spatial output dither and the intentional 2×2 red marker remain. No HDR output,
auto-exposure, new effect or tuning surface is introduced.

- Guarded shared inverse-luma shadow gain retains selected shadow distinctions.
  [Decision](research/2026-10-29_shadow_stage_preservation.md).
- Inverse chroma preserves incoming C, limits reconstruction to 85% of the hue
  ceiling and budgets added C against per-pixel SDR gamut at fixed lightness.
  The fixed 14-step search avoids the earlier small ordering reversal.
  [Decision](research/2026-10-31_print_inverse_color_preservation.md).
- Print retains its density curve while using a shadow-protected RGB-ratio path.
  Actual FilmCurve loss relieves overlapping secondary print compression.
  Selected light-core separation improves about 9% in the latest highlight study.
  [Decision](research/2026-10-31_highlight_cooperation.md).
- Weak lower-tone colors retain more original print response based on C/L over
  0.03–0.12; protection fades out over linear Y=0.10–0.25. Selected blue-wall/
  cool-window color gaps improve about 3.85%/2.96%, with smaller material/hue and
  quantization costs. [Decision](research/2026-10-31_weak_material_colors.md).
- Combined tonal-gain limits were rejected for small mixed gains and shelf/wood
  losses. No further sweep of those limits is queued.
  [Decision](research/2026-10-31_tonal_cooperation.md).

## Profiles and ratings

Preserve both distinct profiles. GZW uses inverse chroma/luma 0.60/0.60, shadow
weight -0.075 temperature / -0.015 tint, BLACKS 0.0025 and FilmCurve 0.60. The inverse-
luma 0.60 and tint -0.015 were external edits preserved during assessment.
Arc retains inverse strengths 0.5/0.5, BLACKS 0.0025, FilmCurve 0.6, shadow
temperature -0.075, tint 0 and midtone temperature 0.05. Only creative profiles
are user-facing tuning surfaces. Shader headers and active configs are preserved.

The [current 0–100 board](research/2026-11-02_effect_ratings.md) estimates
chain/grade **78/100** (previously 75), with a new scoped joint tonal-model
estimate of 80. Individual effect estimates remain retained at 75–90; new joint
gains are not assigned independently to each child. Appearance uncertainty is
roughly 5–10 points. Parent/child rows overlap and must not be averaged. The
updated review is a qualitative synthesis of current held outputs and existing
attribution, without a new all-effect bypass campaign. Whole-chain 80 remains
an aim rather than a confident current estimate.

## Validation and baseline reuse

Use `captures/tonal_base_20261102/verification.json` for current source/profile/
config and initial/final grade hashes. Seven selected held pairs and current
baseline pairs are exact, with the original vivid failure and mislabeled
refresh retained separately. Baseline shader identity is checked against the
preserved original body. Both actual active configs match the applied candidate
exactly, including repeats. Source, include/producer, profile, config, clip and
normalized shader identities all matter; labels or grade identity alone are
insufficient for reuse. Experimental helpers are tied to frozen snapshots and
must not be blindly rerun against changed production code.

The prior weak-material checkpoint remains historical:
`captures/weak_color_20261031/verification.json`. Its profiles predate the
BLACKS edits and its grade predates the new shared base. Its own seven exact
pairs, numerical contracts, 192 exact controls and actual-config results remain
valid only at that checkpoint.

The preceding weak-color decision retains warm-floor color-gap loss (~0.84%), small foliage/hue/quantization and
night-step costs. Earlier highlight FilmCurve-zero testing retains one persistent
one-code GZW pixel with exact within-control repeats. No bit-exact cross-pair
identity or repair of that residual is claimed by the weak-color change.

All runtime testing stays private/headless. Use fresh processes, verified source/
profile/config/shader hashes, marker/tag masks and 20-second continuous settling.
Warmup alone is not proof of convergence. Ordinary screenshots contain no hidden
state telemetry. Temporal claims require explicit measured GPU update ages.
The cached Babylon source is 15 unique poses/sec doubled to 30 fps; sparse matches
do not establish dense native gameplay or physical high-refresh acceptance.

## Next work

All requested finite decisions are closed. No new mandatory repair, parameter
screen, effect, golden fixture or performance investigation is queued. Broader
games, dense motion, timing, aspects/resolutions and a fresh whole-chain rating
support stronger claims. Start new work from a concrete shortcoming and a coherent design; preserve
current profiles and use testing to assess that design. GPU profiling stays deferred.

Reports are versioned. Capture media, diagnostic scripts/configs, review pages
and logs remain ignored local artifacts; capture links require this workspace.
Do not blindly rerun historical scripts against changed shader signatures or
profiles. Preserve rejected candidates and their labelled observation epochs.
