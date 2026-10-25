# Handoff — 2026-10-25

Start with [startup-prompt-latest](startup-prompt-latest), [AGENTS.md](AGENTS.md),
[GOAL.md](GOAL.md) and [PLAN.md](PLAN.md). Keep this handoff below 60 lines.

## Current mandate

Prioritize technical correctness, reliable intended behavior and robust signals.
Personal palette preference is not a blocker. Preserve profiles, shader headers,
prior fixes and SDR output; no auto-exposure or HDR output. `creative_values.fx`
is the only user-facing tuning surface and profile source of truth.

## Pipeline and integration defect

Active GZW/Arc configs: `analysis_frame : inverse_grade : corrective : grade`.
Explicit analysis resources do not cross effect instances in vkBasalt.
Use `gzw_stronger_trial.conf` / `arc_raiders_pipeline_trial.conf` for assessment;
both run `general/pipeline/pipeline.fx`. Do not edit/switch `gzw.conf` without
an explicit request. Combined-trial evidence does not certify the active chain.

Grade: LFDownscale1 → LFDownscale2 → NeutralIllum → GuidedCoeff → GuidedBase →
ColorTransform → AdaptiveHistory → TexHwyWrite. Diffusion/grain are removed;
the 2x2 red activity marker is intentional.

## Latest completed fixes

- [Slow-key precision](research/2026-10-25_slow_key_precision.md): RGBA32F internal
  history and direct feedback; publications remain half-float. The 20-second and
  67-ms half-lives are unchanged. GPU max error 0.000005171 at simulated
  30/60/144 updates/sec, identical repeat. Eighteen fresh held captures and twenty
  matched motion interiors add no clipping; eighteen matches span all seven windows.
- [Metadata coordinates](research/2026-10-25_highway_resolution.md): integer
  texture width; all 40 slots read without error across five tested sizes.
- [Percentile initialization](research/2026-10-25_percentile_initialization.md):
  no false cold starts on valid covariance; controlled-cut response retained.
- [Chroma median](research/2026-10-25_chroma_median_contract.md): all 576 samples
  count. Inverse-luma, Retinex guide, conservative zone confidence and earlier
  shadow/endpoint fixes remain intact; the evidence index is in PLAN.

## Next work

Audit remaining history precision/initialization and live per-band consumers,
then numerical/bypass contracts, zone gradients, hue/gamut continuity, denser
temporal coverage and broader games. Do not repeat completed probes, capture
conversion, stage attribution or the fixed-pair shadow-history audit.

## Validation and limits

Twenty diagnostic tests pass; they validate tooling, not full shader acceptance.
Use private headless fresh processes, exact identities, unchanged repeats and
20-second continuous settling for small effects. GPU/localhost access needs
appropriate sandbox escalation. Never use a desktop fallback or take focus.
Ordinary screenshots contain no highway telemetry; explicit output is needed.
Motion cache: `captures/babylon_scene_runs/20261024_160908/motion-source/`.
It is 15 poses/sec duplicated at 30 fps, not dense native gameplay.
Reports are versioned in `research/`; `captures/` scripts/media are local and ignored.
Physical 144 Hz, dense continuity and cross-game acceptance remain unproven.
The dated 75/100 combined-chain estimate is provisional and has not been re-scored.
New effects, golden-image testing and GPU cost profiling remain deferred.
