# Handoff — 2026-10-26

Start with [startup-prompt-latest](startup-prompt-latest), [AGENTS.md](AGENTS.md),
[GOAL.md](GOAL.md) and [PLAN.md](PLAN.md). Keep this handoff below 60 lines.

## Current mandate

Prioritize technical correctness; palette taste is not a blocker. Preserve profiles, shader headers,
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

PLAN 1/2 audits are complete; preserve the signal/history repairs and their costs.
[Zone follow-up](research/2026-10-26_zone_scene_pivot.md) retains its bounded curve.
[Cut alignment](research/2026-10-26_return_cut_alignment.md) resolves the 1.588 ΔE
outlier: it mixed GPU updates 1/2. Same-phase repeats stay within 0.000426 ΔE.
Strict temporal matching now requires measured phase ages; 22 tooling tests pass.
[Retinex sky repair](research/2026-10-26_retinex_sky.md) is applied; six held repeats,
GPU probes, 14 phase-matched samples and five final checks pass. Next: PLAN 3's
broader hue/gamut, dark-material, colored-highlight and lighting-boundary checks.

## Validation and limits

Twenty-two tooling tests pass; full shader acceptance remains open.
Use private headless fresh processes, exact identities, unchanged repeats and
20-second continuous settling for small effects. GPU/localhost access needs
appropriate sandbox escalation. Never use a desktop fallback or take focus.
Ordinary screenshots contain no highway telemetry; explicit output is needed.
Motion cache: `captures/babylon_scene_runs/20261024_160908/motion-source/`.
It is 15 poses/sec duplicated at 30 fps, not dense native gameplay.
Reports are versioned in `research/`; `captures/` scripts/media are local and ignored.
Physical 144 Hz, dense continuity and cross-game acceptance remain unproven;
the dated 75/100 estimate is provisional and has not been re-scored.
New effects, golden-image testing and GPU cost profiling remain deferred.
