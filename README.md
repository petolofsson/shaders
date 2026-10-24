# Shader Pipeline

A vkBasalt HLSL post-process pipeline for SDR games. The goal is fuller,
more dimensional color, deep nuanced shadows and convincing highlights with
unobtrusive processing that preserves each game's visual identity.

The product direction is game-agnostic automatic restraint, without requiring
per-game or per-effect tuning. Existing GZW and Arc Raiders profiles are current
assessment inputs. Richness is not a target for higher saturation or crushed
blacks. Output remains SDR; this does not reproduce HDR brightness or recover
source information already clipped away.

## Start here

- [Visual goal](GOAL.md): agreed appearance and acceptance criteria.
- [Current plan](PLAN.md): ordered work and completed evidence.
- [Handoff](HANDOFF.md): implementation state and remaining limits.
- [Startup prompt](startup-prompt-latest): sole continuation entry point.
- [Pipeline rules](AGENTS.md) and [code rules](CODE_RULES.md).
- [Tools](TOOLS.md) and [matched motion runner](tools/babylon_scene/README.md).

## Current assessment

The active game configs use `analysis_frame : inverse_grade : corrective : grade`.
vkBasalt does not share the required explicit render targets across those
separate effects, so grade's cross-effect statistics are zero in that chain.
Assessment uses the combined technique in `gzw_stronger_trial.conf` and the Arc
pipeline trial. The active GZW config has not been switched.

Internal processing is linear-light with explicit sRGB boundaries and an SDR
output ceiling. In-game HDR must be off. `creative_values.fx` is the only
user-facing tuning surface; existing profiles are preserved during assessment.

## Validation

```bash
python3 -B -m unittest discover -s tests -p 'test_diagnostics.py'
```

Runtime validation uses private headless GPU displays, matched source identities,
fresh processes and unchanged repeats. Small-effect comparisons use 20 seconds
of settling; elapsed time alone does not prove convergence. See the tool docs
for commands and dependencies. GPU and localhost access may require sandbox
escalation. No runtime test may silently fall back to the user's desktop.

Research notes retain measured findings and tradeoffs. Capture media, vendor
cache and runtime logs are local ignored artifacts, so links into `captures/`
require those files on the current machine. Sparse matched motion and selected
game inputs do not establish universal fidelity; live visual review remains open.
