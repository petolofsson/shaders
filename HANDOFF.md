# Handoff — 2026-10-27

Read [startup-prompt-latest](startup-prompt-latest), [AGENTS.md](AGENTS.md),
[GOAL.md](GOAL.md), [PLAN.md](PLAN.md) and [TOOLS.md](TOOLS.md).

## Current state

The requested [Retinex material-preservation enhancement](research/2026-10-27_retinex_material_preservation.md)
is adopted. A 0.35 log-slope native response multiplies the original guided/native
gain ratio, retaining the old spatial correction and ±0.35-stop bounds. Selected
wall/paving separation improves. Direct gain substitution exposed a small purple
edge; the adopted ratio returns that held edge to zero. Seven real inputs and a
boundary source under both profiles have identical candidate repeats and no added
clipping. GPU contracts, measured cut controls, bypass and actual configs pass.
Retain shadow/cloud/sky costs and Arc's small daylight-step increase. No rating
increase or new mandatory repair follows. Preserve the user's current Arc
`BLACKS=0.005` and `FILM_CURVE=0.6`, alongside all prior edits.

The preceding inverse-luma selectivity enhancement is adopted and its finite screen
is closed: [source-aware inverse restraint](research/2026-10-27_tonal_selectivity.md).
Current trimmed p25/p75 ratios of two to four stops reduce inverse luma to half
its manual ceiling. That gate and lift remain unchanged by the later Retinex work.
Six held final cases/repeats from that prior checkpoint add no clipping;
selected interior gaps improve with modest cloud/warm-floor
costs. Source GPU probes and two-profile cut controls pass; four actual active-
config captures match the isolated candidate exactly. Preserve the existing
user-edited Arc profile. No new mandatory repair or effectiveness re-score follows.

The known technical repair pass is closed on the assessed set. Signal/history,
spatial/color and filter-spacing work remain in PLAN's completed evidence.
[Cut-gate recovery](research/2026-10-27_gate_recovery.md) and
[current-source lift](research/2026-10-27_lift_transition_repair.md) are applied.
Both active configs now use `general/pipeline/pipeline.fx` as one combined effect.
The user explicitly authorized “Activate both combined chains.” Both actual
active-config full/repeat pairs are pixel-identical; all runs are private/headless.
The earlier separate-effect resource-sharing defect is no longer active.

Grade remains eight passes. Profiles, shader headers, existing rates and SDR
bounds remain; no auto-exposure or HDR output. Creative profiles remain the
only user-facing tuning surface. Mask the intentional 2x2 red marker in metrics.

## New storage contracts

`PercHighTex`: three RGBA32F texels; old p90/p10 history at center 0.5/3,
current p25/p50/p90/mode at 1.5/3 and p10/mass/current p75/validity at 2.5/3.
Current lift observations publish normalized highways 212–217.
Slot 218 publishes current p75 for inverse restraint, alongside p25/validity in
212/217. It uses the existing raw CDF walk; original histories/rates remain.
`AdaptiveHistoryTex`: first record unchanged; second stores adaptation/ambient
recovery, flag b=1 (gates) or 2 (gates+source product), and product in alpha.
Source loss uses the original lift path; recovery seeds the current product.
Do not repeat the completed candidate, history, source or phase-alignment probes.

## Scope and remaining work

The lift candidate decision and active-chain activation are closed. The user
asked to stop treating broad confidence-building as mandatory repairs.
No new mandatory defect repair is queued. Remaining optional coverage supports
stronger claims: timing/motion, aspects/resolutions, broader games and ratings.
Retain incoming light/material/color and dark-quantization costs in the report;
small residual settling does not automatically create another investigation.
The older 75/100 estimate is provisional; no automatic re-score is made.

## Runtime/evidence

All runtime work stays private/headless: no desktop fallback or focus changes.
Use fresh processes, source/profile/config hashes, unchanged repeats and 20-second
continuous settling; warmup alone is not convergence. GPU/localhost needs escalation.
Ordinary screenshots have no hidden telemetry; require explicit output and
measured GPU phases for temporal repeat claims. Original Babylon cache is 15
poses/sec duplicated at 30 fps, not dense native gameplay or physical 144 Hz.
Latest enhancement artifacts: `captures/retinex_material_20261027/`;
technical lift closure: `captures/lift_validation_20261027/`; report links above.
All 22 tooling tests and whitespace checks pass. New effects, golden fixtures
and GPU performance profiling remain deferred.
