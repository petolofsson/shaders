# Pipeline Plan

Work toward [GOAL.md](GOAL.md) with technically correct, restrained SDR processing.
Preserve current game-specific settings, shader headers and prior corrections;
the authorized CC profile update is recorded below.

## Current status

The documentation and completed implementation are being published together at
the user's request. Use `git log -1` and upstream tracking for the exact checkpoint.
Current baseline reuse starts from the weak-material verification below; older
entries retain their original experiment/profile epochs.

The [weak-material color enhancement](research/2026-10-31_weak_material_colors.md)
is adopted and validated. Print ratio weight now accounts for weak input Oklab
C/L (0.03–0.12) only in lower tones, fading protection out over linear Y=0.10–0.25.
Selected blue-wall/cool-window color gaps improve about 3.85%/2.96%; shaded paving
and wall improve about 4.8%/5.2%. Bright palette and prior light-core gain remain.
The unrestricted variants are not adopted because of cloud hue costs. Warm-floor
color-gap loss (~0.84%), small foliage/hue and quantization costs remain documented.
Seven exact held pairs, GPU/CPU contracts, exact look-zero controls, four chart/
profile fixtures, 192 exact measured motion controls and four actual-config
outputs matching candidates exactly pass. Only the print-helper weight changes;
profiles/configs/headers/inverse/history/rates/resources/passes remain. GZW inverse
luma stays 0.60 and tint -0.015. No fresh effectiveness score or mandatory screen
follows. Current artifacts/hashes: `captures/weak_color_20261031/verification.json`.
No commit/push was made at that experiment checkpoint.

The [highlight-cooperation enhancement](research/2026-10-31_highlight_cooperation.md)
is adopted and validated. Actual per-pixel FilmCurve luminance loss now relieves
overlapping secondary print-shoulder compression. FilmCurve, the print toe and
all profiles remain. Selected white-core separation improves 5.33386→5.81497
(~9%), with exact selected halo/red-lamp and dark-material preservation. Six
held/repeat pairs are exact; GPU/CPU contracts, two-profile boundary charts,
192 exact same-update motion controls and four actual-config outputs matching
candidates exactly pass. Arc zero pairs and GZW look-zero are exact; GZW
FilmCurve-zero has a reproducible one-pixel/one-code numerical residual, with
each zero control repeating exactly. Preserve that observation. Chart quantization
and small bright-cloud/window changes remain documented. No new score is awarded.
Only grade body/functions and internal arguments change; headers/profiles/configs,
inverse shader, histories/rates/resources and eight grade passes remain. GZW
inverse luma stays 0.60. Thirty-eight new private GPU processes have zero frame
drops/delays. No further mandatory repair or parameter screen follows. Artifacts:
`captures/highlight_cooperation_20261031/`; its original baseline reuse required matching
verification hashes and grade signature; the later weak-material change supersedes it. No commit/push was made at that experiment checkpoint.

The [combined tonal-correction screen](research/2026-10-31_tonal_cooperation.md)
is closed with both candidates rejected. Smooth 0.5/1-stop limits on the combined
Retinex/zone/lift log correction give small, mixed material changes: the stronger
guard gains about 0.27% lit-paving separation but loses 1.47% shelf and 1.90% wood
separation. Sixteen fresh headless outputs plus four verified prior Arc baselines
cover five scenes; all five baseline pairs are exact. No production shader change
or score increase follows. An external GZW INVERSE_LUMA edit 0.30→0.60 is preserved;
all GZW baselines are refreshed at 0.60. Prior 0.30 rating evidence is historical.
Artifacts: `captures/tonal_cooperation_20261031/`. No new mandatory screen is queued.

The user-requested [print/inverse color-preservation follow-up](research/2026-10-31_print_inverse_color_preservation.md)
is adopted and closed. Print preserves its density curve's luminance while blending
toward preserved RGB ratios over linear Y=0.01–0.10; deep shadows retain the
original path. Inverse caps added chroma against per-pixel SDR headroom with a
14-step search, retaining the original hue ceiling when it is valid. Selected
sky palette and warm-floor/red-lamp variation improve; shelf pixels and light
structure remain. Cool-material, warm-hue, synthetic-primary, quantization and
small transition costs are retained. Both focused estimates are now borderline
75/100, with roughly 5–10 point uncertainty; no fresh chain/grade re-score.
Seven exact final held pairs, independent CPU/GPU contracts, exact zero pairs,
four new measured history replays against four verified baselines (384 exact
controls), and four actual-config outputs matching the selected candidate exactly
pass. Sixty new private GPU processes have zero dropped/delayed frames. Temporal
repeats reach two codes; held repeats are exact. Profiles (including GZW tint
-0.015), configs, headers, prior work, histories/rates/resources and eight passes
remain. Only print/inverse body code changes. No commit/push or further mandatory
screen is queued. Artifacts: `captures/color_preservation_20261031/`; that checkpoint
requires its original `verification.json` and both shader hashes; use the newest
verification above for current production.
Earlier 70 judgments below are historical and superseded only for these blocks.

The preceding [inverse-chroma decision](research/2026-10-31_inverse_chroma.md) is closed and
adopted. Reconstruction uses `max(0.85*HueCeil(hue),C)`, preserving incoming C and
abstaining above its budget. Blanket half expansion is rejected. Selected red-light
variation improves about 15.7%, with blue/warm-material and small Arc daylight-step
costs retained. Scalar/GPU/bypass checks, labelled held repeats, twelve independent
history replays with 576 exact controls and both actual active-config full/repeats
pass; actual outputs match the candidates exactly. An external GZW tint change to
-0.015 is preserved and affected held/motion evidence refreshed; Arc and other
settings remain. The initial GZW-day pair varied one code; current refreshed GZW
pairs are exact. Only inverse body code changed at that checkpoint, with its estimate still 70.
The latest focused follow-up above supersedes that estimate and implementation;
no further mandatory repair or search is queued. Broader confidence work below remains optional. Baseline
reuse must check current inverse verification/refresh hashes and profile epochs.

The [three-way CC task](research/2026-10-31_three_way_cc.md) is closed. The user's
explicit permission covers the selected profile-only update: shadow temperature
is -0.075 in both profiles and GZW shadow tint is -0.025. Other tuning, every
shader, active configs, headers, histories/rates and passes remain. Half strength
retains cool neutrals while preserving more shelf warmth/variation and reducing
selected foliage hue shifts about 11–12°→4.5–4.8°. Quarter is not selected.
Seven exact selected held pairs, 192 exact same-update controls and both actual
active-config full/repeats pass. Palette, one-code black/blue-pair and small
first-night-step costs remain. Focused CC estimate is now borderline 75; no chain
re-score. The subsequent inverse task above completes the planned queue. Its
verification/profile epochs now supersede older CC full images for baseline reuse.

The [bounded print/look improvement](research/2026-10-30_print_look_preservation.md)
is closed: secondary shoulder 1.5→0.75 is adopted after tone/color attribution;
the shadow-toe candidate is rejected. Selected white-core separation improves
about 15.4%, with unchanged selected dark materials/halo and retained small
bright-blue/quantization/daylight-step costs. Seven exact held repeat pairs,
numeric GPU contracts, 192 same-update full controls and both actual configs pass.
Profiles/configs, headers, prior work, histories/rates and eight passes remain.
Print/look stays estimated 70; no score-driven extension of the toe screen.
Its following CC and inverse tasks are complete; the latest print/inverse
follow-up above supersedes the two earlier 70 estimates.

The user-requested [effectiveness reassessment](research/2026-10-29_effect_ratings.md)
is complete without changes in that review. Its chain/grade estimates remain
borderline 75/100; inverse chroma, CC and print/look were estimated 70 then.
The later focused CC judgment above supersedes only that CC entry. Other blocks
are estimated 75–90 in their assessed roles. These are coarse quality judgments,
not measured fidelity percentages or universal acceptance. Forty-two fresh
ordinary captures, three dither diagnostics and verified current-code baseline
reuse support the review. Neutral optional controls are unrated. Below-target
rows identify quality/cooperation limits, not a new mandatory defect-repair queue.

The requested [shadow-stage attribution and preservation test](research/2026-10-29_shadow_stage_preservation.md)
is complete. A guarded shared inverse-luma darkening reference is adopted on its
measured scope. Selected shadow-paving separation improves about 6.3% without
additional lift; Arc vehicle visible separation loses about 3.0% with deeper
shades. Smaller wood/metal/gradient costs remain. GPU stage/numeric readback,
six real screenshots, normal/active dark boundaries, repeats, exact bypass,
two-profile measured cut controls and actual active-config full/repeats pass.
Only grade code changes; current profiles/configs, original inverse budget,
histories/rates and eight passes remain. The first unguarded candidate is
rejected and this decision is closed. No universal shadow claim or re-score.

The first [shadow-richness lift-distribution screen](research/2026-10-28_shadow_richness_screen.md)
is closed without adoption. Thirty fresh two-profile captures and ten exact repeat
pairs show modest wood/vehicle/metal benefits alongside shelf/paving/floor costs.
Both broad and narrow redistribution are rejected as general defaults. At that
checkpoint stable 1.0 (`1724bb6`, `v1.0`) shaders and profiles remained. This closes that
hypothesis, not the user's broader shadow goal. No new mandatory repair is queued.

The requested [Retinex material-preservation enhancement](research/2026-10-27_retinex_material_preservation.md)
is adopted on its measured scope. A gentler native response retains the original
relative spatial correction and gain limits. Selected paint/paving separation
improves; held-face protection remains, with documented shadow/cloud/sky and small
daylight timing costs. Seven real inputs, a two-profile boundary source, independent
GPU contracts, measured cut controls, bypass and actual-config checks pass.
Profiles/configs, prior work, history rates and eight grade passes remain.
The direct/refined candidate decision is closed; no new mandatory repair follows.

The preceding inverse-luma cooperation enhancement is closed on its measured scope:
[current-source inverse-luma restraint](research/2026-10-27_tonal_selectivity.md)
is adopted after rejecting the lift taper and joint inverse/Retinex restraint.
Six held baseline/candidate repeats, new-field GPU contracts, two-profile cut
controls and actual active-config checks pass. Benefits are modest, with retained
cloud/warm-floor separation costs; this is a first enhancement, not complete
model selectivity or a new effectiveness rating. Profiles and configs remain.

The known technical repairs in this pass are complete on the assessed set:

- Signal units, statistics, history precision/initialization and consumers are audited.
- Current two-game spatial/material/color coverage and integer filter spacing are assessed.
- Cut-gate recovery and the current-source lift transition repair are applied.
- Both active game configs now use the verified combined pipeline. The user explicitly
  authorized this switch; the old separate-effect sharing defect is no longer active.

The [lift/activation closure report](research/2026-10-27_lift_transition_repair.md)
records the decision, native material costs, six held cases, unchanged repeats,
producer/state probes, actual-source verification and actual-active-config tests.
Do not reopen that completed candidate decision or repeat its attribution/probes
without a concrete new failure. Smaller settling and documented color/quantization
costs are limitations for assessment, not automatically new repair tasks.

## Remaining confidence work

These support stronger claims about generality; they do not block using the repairs.
No additional mandatory defect repair is currently queued.

1. Broader timing/motion: whole-pipeline hitches, dense native gameplay and physical
   high refresh. Existing simulated cadence/hitch contracts and sparse/point imagery
   do not establish all of these. Private/headless restrictions remain.
2. Remaining aspects/resolutions and visual scaling beyond the measured matrix.
   Metadata addressing and integer-texel spacing are already repaired and verified.
3. Broader game/lighting/palette coverage without per-frame profile tuning.
4. The current user-requested effectiveness reassessment is recorded above.
   Broader acceptance can revisit its uncertainty with new evidence; no automatic
   score increase follows from correctness fixes or this limited coverage.

Do not expand this list merely because a measurement changes. Prioritize concrete
reported failures; finish a finite adopt/reject/accept decision for any new candidate.

## Completed Evidence

| Correction | Evidence and scope |
|---|---|
| Print/inverse color preservation | [Decision](research/2026-10-31_print_inverse_color_preservation.md): shadow-protected print color ratios and a 14-step per-pixel inverse gamut budget. Both focused estimates reach borderline 75. Seven exact held pairs, independent contracts, zero bypasses, 384 exact motion controls including verified baselines, and four actual-config exact matches pass. Retained material/palette/quantization and transition costs remain. Profiles/configs/headers/histories/rates/passes are preserved. |
| Prior inverse chroma restraint | [Decision](research/2026-10-31_inverse_chroma.md): 85% hue-ceiling reconstruction budget preserves incoming C above the budget. Selected red-light color separation +15.7%; modest blue/warm-material and Arc daylight-step costs remain. Numeric/bypass/labelled held checks, twelve independent history replays with 576 exact extraction controls and four actual-config matches pass. The external GZW tint -0.015 is preserved and relevant evidence refreshed. Profiles/headers/configs/grade/history rates/passes remain; inverse stays 70 and this finite decision is closed. |
| Retinex material preservation | [Decision](research/2026-10-27_retinex_material_preservation.md): native log-gain slope 0.35 plus the original guided/native gain ratio preserves bounded spatial correction. Wall relative gap 0.865→0.879 stops, sunlit paving 1.402→1.448; shadow/cloud/sky costs remain. Seven real cases and two-profile native boundaries/repeats pass; new purple edge from direct substitution is removed. Independent GPU probes, 96 exact same-update full controls, exact zero-strength bypass and both actual-config full/repeats pass. Profiles, rates, formats, textures and pass counts remain. |
| Source-aware inverse restraint | [Decision](research/2026-10-27_tonal_selectivity.md): current trimmed p25/p75 span restrains inverse luma to half its ceiling across two to four stops, retaining existing Retinex/lift. Interior cool-upper relative gap 2.290→2.330 stops; dedicated cloud 0.893→0.880. Six final held cases add no clipping; all twelve baseline/candidate repeat pairs are identical. New p75 uses spare cache B and highway 218, with no history/pass/rate change. Two-profile measured cut controls preserve baseline, and both actual configs match the candidate exactly. |
| Closed lift repair and activation | [Report](research/2026-10-27_lift_transition_repair.md): current-source complete-product lift is adopted; night point peaks ~0.64–0.65→0.12–0.16 ΔE. Native material checks, six production held identities, state/publication probes and exact independent controls pass. Both active configs are switched with explicit user authorization; their actual full/repeats are pixel-identical. Grade remains eight passes; profiles and existing rates remain. |
| Current-observation lift screen | [Report](research/2026-10-27_lift_consumer_screen.md): four two-profile point replays, 192 exact full controls, 960 images and unchanged return/daylight candidates. Current complete-product filtering reduces night peaks ~0.64–0.65→0.12–0.16 ΔE but changes incoming images ~3.49 ΔE. No adoption at that stage; the closure report above completes the decision. |
| Direct gate recovery | [Report](research/2026-10-27_gate_recovery.md): native first-return duplicate step about 1.44→0.76 ΔE, with larger subsequent recovery steps. Six motion and six held runs preserve exact controls; three held repeats are identical. Two-record RGBA32F adaptive storage retains eight passes; independent-state and simulated cadence/hitch GPU checks pass. Early lift-target p25/mode settling remains; no producer-rate/profile changes. |
| Transition candidate screen | [Report](research/2026-10-27_transition_screen.md): four two-profile replays, 960 frozen images, 192 exact full-output controls and unchanged daylight 1428/1432 candidates. Complete-product filter relocation retains the early night peak and extends later settling; rejected as a complete repair. No production change at this stage; the native follow-up above applies gate recovery. |
| Night-settling attribution | [Report](research/2026-10-27_night_settling_attribution.md): ten same-update replays, 2,560 point images and 320 pixel-identical full-output controls. Separates early lift-strength and late specular-guard changes, smaller zone settling and ambient cut-gate color response. Both profiles and unchanged repeats; 3,274 artifacts verified. No production changes or bypass adoption. |
| Consecutive cut coverage | [Report](research/2026-10-27_temporal_cut_coverage.md): six replays, 372 original-clip frozen images, explicit source/update/cut phases, plus two 1,108-update route traces. Eight runs have zero dropped/delayed frames; 1,058 artifacts verified. Return handoff and night settling remain; raw-median detector shortcut rejected. No production changes or acceptance re-score. |
| Filter-kernel spacing | [Report](research/2026-10-27_filter_kernel_resolution.md): integer-dimension tap spacing in four passes; nine GPU captures at four resolutions and fifteen held captures across both profiles. Five identical repeats, unchanged 2560×1440 controls; 48–144 one-code pixel changes at 1366×769, no new clipping. Temporal/cut/high-refresh coverage stays open. |
| Material/highlight coverage | [Report](research/2026-10-27_material_highlight_coverage.md): four fresh views × five variants, eight verified prior views, twelve identical full/repeat pairs; retained nine-color boundaries at two measured phases. Records dark structure, colored highlights, daylight restraint and remaining normalization/core/blue costs. No production edits; current two-game coverage pass complete. |
| Wall/sky attribution | [Report](research/2026-10-27_wall_sky_attribution.md): eleven ordinary captures and two final 1,326-record GPU traces; identical repeats. Inverse-luma bypass restores wall separation but worsens sky; lift bypass restores sky's absolute gap but overshoots relative contrast. No production edits; broader model selectivity remains open. |
| Blue-cusp projection | [Report](research/2026-10-27_gamut_continuity_repair.md): localized continuous bounded mapping, unchanged in-gamut identity/face guard; 1,410 GPU records, two-profile ramps, eight held repeats and fourteen measured-phase motion matches. Selected GZW blue step 3.031499→0.112662 ΔE. Finite quantized-gradient and out-of-gamut hue/separation costs remain; no general color acceptance claim. |
| Color continuity assessment | [Report](research/2026-10-26_color_continuity.md): two-profile ramps and two additional gameplay views; twenty headless captures, four identical image repeats and identical numerical readback. Identifies the disconnected-blue-gamut defect repaired above. Additional yellow-wall/sky separation costs remain for attribution. |
| Retinex sky/guide domain | [Report](research/2026-10-26_retinex_sky.md): original-source R32F observation, conditioned native residual and bounded sum-normalized gain. Sky gap 7.376501→9.646211 (source 9.708699), no restored measured held rims or added clipping. Six held repeats, two GPU probes, 14 phase-matched motion samples and five shared/active-path checks. Dense continuity and existing cut handoff remain open. |
| Return-cut phase alignment | [Report](research/2026-10-26_return_cut_alignment.md): same pose had two GPU-update phases; direct frozen outputs/state reproduce 1.588 ΔE between phases, with 0.000426 maximum same-phase repeat. Strict motion matching rejects absent/conflicting measured phases; no production shader retuning. |
| Zone field and black tail | [Report](research/2026-10-26_zone_scene_pivot.md): scene-adaptive pivot/span, bounded relative shadow debt; actual GPU curves, held scenes and exact motion matches. Prior rims remain removed; tonal costs and first-return cut uncertainty are explicit. |
| Spatial/color attribution | [Report](research/2026-10-26_spatial_color_attribution.md): current-code zone-field and sky/foliage ablations separate spatial model limitations from existing color correction. Shared shaders/profiles remain unchanged; repairs and broader coverage remain open. |
| Signal/control contracts | [Report](research/2026-10-25_signal_contracts.md): native fixed-population histogram decoding, stable zone moments and SDR-face guard; signed/gamut/film/dither probes and two-profile 768-patch bypass pass. Matched scene/motion checks retain quantified shadow costs. |
| Remaining histories | [Report](research/2026-10-25_remaining_histories.md): eight independently probed accumulators repaired, max candidate error 0.000002354; one-frame cut storage retained. Eighteen held captures, eight individual reversions, sixteen exact motion matches and four final shared/standalone checks. One-code black costs are recorded. |
| Scene-chroma precision | [Report](research/2026-10-25_scene_chroma_precision.md): RGBA32F 1x1 authoritative history, unchanged coefficients/publications. Three GPU probes, max candidate error 0.000002159; eighteen held captures and sixteen motion matches. Four motion frames retain a small one-code black cost. |
| History consumers | [Audit](research/2026-10-25_history_consumers.md): remaining-state inventory and isolated GPU perturbations of the six unused per-hue records. Its follow-up repairs the live scene-chroma history. |
| Slow-key precision | [Report](research/2026-10-25_slow_key_precision.md): RGBA32F authoritative history, direct feedback; publications and 20-second/67-ms half-lives unchanged. Three 63-value GPU probes, eighteen fresh held captures, twenty exact motion matches, two final shared-path checks. |
| Metadata addressing | [Report](research/2026-10-25_highway_resolution.md): actual integer texture width; eleven probes at five resolutions recover all 40 slots. Twelve full-chain comparisons retain unchanged native controls. |
| Percentile initialization | [Report](research/2026-10-25_percentile_initialization.md): valid covariance no longer triggers six-update cold-start cycles. GPU histories/cuts verify behavior; one-code overcast quantization cost is recorded. |
| All-pixel chroma median | [Report](research/2026-10-25_chroma_median_contract.md): all 576 samples count; colored hue-centroid filtering remains separate. GPU readback and six-scene checks verify the contract. |
| Inverse-luma gain units | [Report](research/2026-10-25_inverse_luma_units.md): linear-light gain applies in RGB rather than being cubed by Oklab scaling. Inverse-model assumptions and sky tradeoffs remain open. |
| Zone-confidence rims | [Report](research/2026-10-25_zone_confidence.md): uniform existing 0.65 confidence removes false rims without the stronger candidate's shadow cost. Interior gradients remain. |
| Retinex guide | [Report](research/2026-10-25_flat_face_attribution.md): native-luma guide reconstruction reduces flat-face rims. The later zone fix resolves the report's purple-edge regression. |
| Earlier foundations | [Halo correction](research/2026-10-24_retinex_edge_halo.md), [zone precision](research/2026-10-24_shadow_zone_precision.md), [shadow toe](research/2026-10-24_contrast_shadow_toe.md), [matched motion](research/2026-10-24_background_motion_resume.md). |

The [stage review](research/2026-10-25_stage_review.md) and
[review pack](research/2026-10-25_review_pack.md) retain dated attribution/crops;
they are not current preference blockers or fresh-session task lists. The
[fixed-pair history audit](research/2026-10-24_shadow_history_readback.md) is
complete; do not repeat it or blindly accelerate slow key.

## Validation and Decision Rules

- Follow [AGENTS.md](AGENTS.md), [CODE_RULES.md](CODE_RULES.md) and [TOOLS.md](TOOLS.md).
  Runtime work is private and headless, with no desktop fallback.
- Shared changes require relevant Arc/GZW regressions, fresh processes,
  unchanged repeats and source/profile/config identity. Use 20-second continuous
  settling for small effects; disclose remaining convergence uncertainty.
- Use explicit output for GPU telemetry. Ordinary screenshots contain no hidden
  highway readback. Retain rejected runs and coverage failures separately.
- Prove defects in units, statistics, precision or timing individually. Do not
  compensate for storage defects by retuning rates.
- Delta-E, saturation, entropy and fewer black pixels are not quality scores.
  Report separation, hue changes, clipping and uncertainty. An effect may
  correctly contribute nothing when its intervention is unnecessary.
- Preserve current profiles, shader headers, prior fixes and SDR output. No auto-exposure,
  HDR output, new effect, golden suite or GPU profiling is introduced.

## Acceptance Status

The [consolidated 75/100 report](research/2026-10-31_75_goal_report.md) collects the
latest recorded estimates and their scope; it is not a fresh all-effect re-score.

The long-term target remains 75+ effectiveness for the complete chain and each
retained effect in its intended role, as defined in [GOAL.md](GOAL.md).
[The October 29 reassessment](research/2026-10-29_effect_ratings.md) estimated the
combined chain at borderline 75/100, with three blocks at 70 and others at 75–90.
The [focused CC decision](research/2026-10-31_three_way_cc.md) estimates CC as
applied at borderline 75. The latest [print/inverse preservation decision](research/2026-10-31_print_inverse_color_preservation.md)
now estimates both remaining blocks at borderline 75. All currently rated blocks
therefore reach 75+ on their assessed scope; chain/grade are carried forward,
not freshly re-scored. The earlier hue-only inverse decision stayed 70 at its
checkpoint. Both the earlier queue and latest user-requested follow-up are closed.
These judgments are not measured fidelity percentages or
universal acceptance; neutral optional controls have no new standalone score.
The [October 25 table](research/2026-10-25_effect_ratings.md) remains historical.
Correctness fixes do not automatically raise effectiveness or novelty. Broader
technical coverage and overall acceptance remain open; taste review need not
block technical work.
Current-set spatial/color coverage is complete, with material/light normalization,
bright-core compression, foliage hue shifts and quantized blue-gradient costs
retained for acceptance. Completing coverage does not declare those costs solved.
