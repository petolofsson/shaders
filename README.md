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

Both GZW and Arc active configs use the combined `ShaderPipeline` effect, sharing
analysis resources within one technique. Grade remains eight passes. Relaunch
the game to load shader changes; in-game HDR must remain off.

The latest [weak-material preservation](research/2026-10-31_weak_material_colors.md)
recovers selected blue-wall/cool-window color separation by about 3.85%/2.96%,
with guarded brightness eligibility preserving the earlier sky palette and
[highlight-cooperation](research/2026-10-31_highlight_cooperation.md) benefit of
about 9% more selected white-core separation. Guarded shadow reconstruction,
pixel-gamut-aware inverse chroma and gentler shadow CC are also retained.
The [combined tonal-gain limits](research/2026-10-31_tonal_cooperation.md) were
rejected for small mixed benefits and shelf/wood costs.

The latest implementation has seven exact held-image repeat pairs, independent
CPU/GPU contracts, 192 exact measured transition extraction controls and four
actual-config outputs matching the isolated candidate exactly. These are private
headless observations; dense native gameplay and universal acceptance remain
outside the measured scope. Material/hue, quantization and small transition costs
are documented, including the earlier highlight task's persistent one-pixel GZW
FilmCurve-zero residual.

The [0–100 board](research/2026-10-31_75_goal_report.md) retains provisional scores:
chain/grade 75 carried forward, other assessed blocks 75–90. The later focused
improvements have not received a fresh whole-chain effectiveness rating. Scores
are overlapping judgments with uncertainty, not a measured average or fidelity
percentage. No mandatory repair or further parameter screen is queued.

`creative_values.fx` remains the only tuning surface. Current profiles preserve
the authorized shadow CC changes and external GZW choices: inverse luma 0.60,
shadow temperature -0.075 and tint -0.015. Earlier 0.30 inverse-luma rating evidence
retains its original scope. Both profiles remain distinct. Stable `v1.0` at
`1724bb6` remains the earlier rollback checkpoint; use `git log -1` for the latest
publication. Historical reports describe their original experiment checkpoint,
including contemporaneous commit/push status.

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
