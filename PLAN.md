# Pipeline Plan

Work toward [GOAL.md](GOAL.md) with technically correct, restrained SDR processing.
Preserve the game-specific profiles, shader headers and prior corrections.

## Current status

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
4. Reassess complete-chain and retained-effect effectiveness when stronger claims
   are needed, retaining measured material/color/quantization costs. No automatic
   score increase follows from these correctness fixes.

Do not expand this list merely because a measurement changes. Prioritize concrete
reported failures; finish a finite adopt/reject/accept decision for any new candidate.

## Completed Evidence

| Correction | Evidence and scope |
|---|---|
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
- Preserve profiles, shader headers, prior fixes and SDR output. No auto-exposure,
  HDR output, new effect, golden suite or GPU profiling is introduced.

## Acceptance Status

The long-term target remains 75+ effectiveness for the complete chain and each
retained effect in its intended role, as defined in [GOAL.md](GOAL.md).
[The dated ratings](research/2026-10-25_effect_ratings.md) estimated the combined
chain at 75/100 before these technical audits. This is not accepted target
achievement, a current active-chain rating or a measured fidelity percentage. Correctness
fixes do not automatically raise effectiveness or novelty. Broader technical
coverage and overall acceptance remain open; taste review need not block this audit.
Current-set spatial/color coverage is complete, with material/light normalization,
bright-core compression, foliage hue shifts and quantized blue-gradient costs
retained for acceptance. Completing coverage does not declare those costs solved.
