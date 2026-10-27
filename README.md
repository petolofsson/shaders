# Shader Pipeline

vkBasalt HLSL post-processing for SDR games. The product goal is fuller color
relationships, nuanced shadow depth and convincing light with unobtrusive
automatic restraint. Preserve each game's palette and lighting; richness is
not a saturation or darkness target. Output stays SDR in [0,1], with explicit
sRGB boundaries and linear-light internal processing. In-game HDR must be off.

## Start here

- [Fresh-session prompt](startup-prompt-latest): the only startup prompt.
- [Pipeline rules](AGENTS.md) and [code rules](CODE_RULES.md).
- [Visual goal](GOAL.md): product direction and acceptance criteria.
- [Current plan](PLAN.md): technical priorities and completed evidence.
- [Handoff](HANDOFF.md): concise implementation state and next work.
- [Tools](TOOLS.md): private headless validation.
- [Changelog](CHANGELOG.md): recent changes; detailed history lives in research/git.

## Current status

Both GZW and Arc active configs now use the combined `ShaderPipeline` effect.
The user explicitly authorized activation. Required analysis resources and grade
consumers now share one effect; the earlier separate-effect sharing defect is fixed.
Profiles stay unchanged, and grade remains eight passes. Relaunch the game to load
these changes; in-game HDR must remain off.

The [latest closure report](research/2026-10-27_lift_transition_repair.md) adopts
current-source lift after native material checks, six held cases, independent GPU
source/state tests and actual shared-source checks. Both actual active-config
full/repeat pairs are pixel-identical. Gate recovery reduces the measured return
handoff; current-source lift removes the two dominant night settling peaks.
Incoming material/color and near-black quantization costs remain documented.

Signal/history, spatial/color, gamut and integer-dimension filter-spacing repairs
are indexed in [PLAN.md](PLAN.md). No new mandatory defect repair is queued.
Additional timing/motion, aspect/resolution and game coverage support broader
claims and do not block trying the fixes. Live gameplay and universal visual
acceptance remain distinct from the private validation; the old 75/100 estimate
has not been re-scored. `creative_values.fx` remains the sole tuning surface.

## Validation

```bash
python3 -B -m unittest discover -s tests -p 'test_diagnostics.py'
```

Twenty-two diagnostic tests pass. They validate tooling, not complete shader
correctness. Runtime work uses fresh private headless processes, matched sources,
unchanged repeats and explicit GPU readback when needed. Never use a desktop
fallback. Small-effect captures use 20 seconds of continuous settling; that
alone does not establish convergence. See [TOOLS.md](TOOLS.md).

Research reports are versioned. Media, diagnostic scripts/configs and runtime
artifacts in `captures/` remain local and ignored; links there require the
original workspace. New effects, GPU profiling and golden-image testing remain
outside the current work.
