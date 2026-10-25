# Pipeline Plan

Work toward [GOAL.md](GOAL.md) by making each retained stage perform its intended
role correctly and reliably. The current user priority is technical quality;
personal palette/print preference is not a blocker. Preserve existing profiles
and fix demonstrated issues individually, with evidence and unchanged repeats.

## Current Priorities

1. **History precision, initialization and consumers — audited.** Audit remaining histories
   and per-band chroma analysis. Determine which produced values have live
   consumers. Check valid state is never mistaken for startup and that storage
   can accumulate the intended update. Slow-key precision and percentile
   initialization are fixed; do not repeat them or blanket-widen textures.
   The [consumer audit](research/2026-10-25_history_consumers.md) separates unused
   per-hue histories from live scene-chroma state. `MeanChromaTex` precision is
   now [GPU-verified and repaired](research/2026-10-25_scene_chroma_precision.md).
   The [remaining-history audit](research/2026-10-25_remaining_histories.md)
   independently proves and repairs eight remaining accumulators, checks
   initialization and retains bounded one-frame scene-cut precision. Rates,
   observations and publications remain. Recorded one-code endpoint costs stay
   part of assessment; broader temporal/visual acceptance remains open.
2. **Signal and control contracts — audited.** Verify producer/consumer units, pass order,
   numerical stability, bounded output, endpoint preservation and clean bypasses.
   Assess reconstruction assumptions and inverse/tonal/chroma/print interactions
   using isolated GPU probes and matched ablations.
   The [signal-contract audit](research/2026-10-25_signal_contracts.md) proves
   and repairs raw histogram count loss, unstable zone moments and numerical
   gamut-face misclassification. GPU helper and complete-bypass probes pass;
   matched scene/motion evidence records one-code shadow costs. Existing stage
   gate semantics remain. Broader model/spatial acceptance stays under 3–5.
3. **Spatial and color behavior — next.** Attribute remaining coarse-zone interior
   gradients, blue-sky shade-separation loss and overcast-green hue shifts.
   Check hue/gamut continuity, colored highlights, dark materials and illumination
   boundaries. Address technical artifacts without preference-driven retuning.
4. **Temporal and resolution coverage.** Broaden dense gameplay motion, cuts,
   variable timing and physical high-refresh checks. Simulated 30/60/144 update
   rates are not physical 144 Hz validation. Metadata addressing is fixed;
   other filter-kernel spacing still needs assessment where relevant.
5. **Cross-game robustness.** Use the same candidate logic on more dark, bright,
   vivid, muted and already-balanced inputs. Disclose profile differences; do not
   optimize each test frame separately or block on new recordings.
6. **Active-chain integration.** Separate effects still cannot share required
   analysis resources. Combined trials are the working assessment path. Do not
   edit/switch `gzw.conf` without an explicit request. A validated combined trial
   does not certify the active separate chain.

## Completed Evidence

| Correction | Evidence and scope |
|---|---|
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
achievement, an active-chain rating or a measured fidelity percentage. Correctness
fixes do not automatically raise effectiveness or novelty. Broader technical
coverage and overall acceptance remain open; taste review need not block this audit.
