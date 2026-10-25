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

## Latest completed audits

- [Remaining histories](research/2026-10-25_remaining_histories.md): eight
  independently proved accumulators now use 32-bit history; rates/formulas remain.
  GPU max error 0.000002354, identical repeat. Eighteen held captures, eight
  individual reversions, sixteen exact motion matches and four final checks pass.
  One-code black costs: seven vivid/one muted held pixels and one motion pixel.
  One-frame scene-cut RGBA16F is retained with measured bounded error.
- Earlier slow-key, scene-chroma, metadata, covariance, median, inverse-luma,
  Retinex, zone-confidence and shadow corrections remain; see PLAN's evidence.
- Six per-hue histories have no ordinary image consumer; leave them untouched.

## Current work order

User-requested PLAN 1 then 2 are complete for the current audit.
[Signal contracts](research/2026-10-25_signal_contracts.md) repairs raw histogram
count loss, unstable zone moments and numerical SDR-face contraction. GPU helper
and two-profile 768-patch complete bypass pass; held repeats are identical.
Zone correction retains quantified one-code shadow costs. No profile retuning.
Next: PLAN 3 spatial/color attribution; broader motion/game coverage follows.
Do not repeat completed probes or fixed-pair audits; preserve prior corrections.

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
