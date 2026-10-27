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

Current work prioritizes technical correctness, signal preservation, reliable
history and spatial/temporal stability. Personal palette preference is not a
blocker. Existing profiles remain assessment inputs; `creative_values.fx` is
the sole user-facing tuning surface.

Active GZW and Arc configs still use four separate effects:
`analysis_frame : inverse_grade : corrective : grade`. Required explicit render
targets do not cross effect instances in vkBasalt, leaving dependent grade reads
unavailable. Assessment uses the combined technique in
`gamespecific/gzw/gzw_stronger_trial.conf` and
`gamespecific/arc_raiders/arc_raiders_pipeline_trial.conf`. Active configs have
not been switched; changing `gzw.conf` requires an explicit request.

Completed audits cover live history precision, numerical contracts and metadata
addressing. The latest [zone repair](research/2026-10-26_zone_scene_pivot.md)
removes coarse pivot gradients, and the [Retinex repair](research/2026-10-26_retinex_sky.md)
restores measured sky separation while retaining tested rim and lighting behavior.
[Motion phase alignment](research/2026-10-26_return_cut_alignment.md) distinguishes
GPU updates of duplicated source poses; temporal repeat claims require measured
phase identity. Profiles remain unchanged.

The [blue-cusp repair](research/2026-10-27_gamut_continuity_repair.md) removes
measured disconnected-ray projection jumps while retaining valid-color identity
and SDR bounds. The [wall/sky attribution](research/2026-10-27_wall_sky_attribution.md)
and [material/highlight assessment](research/2026-10-27_material_highlight_coverage.md)
complete current two-game spatial/color coverage: twenty fresh captures supplement
eight verified prior views; twelve full/repeat pairs are identical. Material/light
normalization, bright-core compression, foliage hue and blue quantization costs
remain explicit. Profiles and active configs remain unchanged.

Next are denser motion/cuts, variable timing, relevant resolution checks and
cross-game coverage. Active-chain integration remains open. These assessments
do not establish universal acceptance or dense gameplay continuity. The older
75/100 combined-chain estimate remains provisional and has not been re-scored.
See [PLAN.md](PLAN.md) for evidence and order.

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
