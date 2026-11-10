# Shader Pipeline

vkBasalt HLSL post-processing for SDR games: fuller color relationships, nuanced
shadows and convincing light, with automatic restraint that preserves the game’s
palette and lighting. Internal processing is linear-light; output stays SDR.
Disable in-game HDR and relaunch the game after shader changes.

Arc Raiders and GZW use one combined `ShaderPipeline` effect. Their profiles
remain distinct; `creative_values.fx` is the only user-facing tuning surface.

## Documentation

| File | Purpose |
| --- | --- |
| [startup-prompt-latest](startup-prompt-latest) | Sole entry point for a new working session |
| [AGENTS.md](AGENTS.md) | Repository rules and working constraints |
| [GOAL.md](GOAL.md) | Visual direction and acceptance criteria |
| [PLAN.md](PLAN.md) | Current priorities and next-step requirements |
| [HANDOFF.md](HANDOFF.md) | Current production identity and research state |
| [CODE_RULES.md](CODE_RULES.md) | HLSL/vkBasalt implementation checklist |
| [TOOLS.md](TOOLS.md) | Private headless validation workflow |
| [Pipeline reference](docs/pipeline.md) | Stages, resources and technical contracts |
| [CHANGELOG.md](CHANGELOG.md) | Concise record of adopted changes |

Dated research reports hold evidence, rejected experiments and limitations.
Current work: [light-map CC placement](research/2026-11-09_cc_light_map_placement.md)
and the [light map review](research/2026-11-10_light_map_review.md); older shadow work is
indexed in the [shadow investigation index](research/2026-11-06_shadow_session_index.md). Media and diagnostic scripts under `captures/`
are local and ignored; their links require the original workspace.
