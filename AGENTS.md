# Repository instructions

Read [GOAL.md](GOAL.md) for visual direction, [PLAN.md](PLAN.md) for priorities,
and [HANDOFF.md](HANDOFF.md) for current state. [startup-prompt-latest](startup-prompt-latest)
is the sole startup prompt. Read [CODE_RULES.md](CODE_RULES.md) before shader
edits and [TOOLS.md](TOOLS.md) before validation. The [pipeline reference](docs/pipeline.md)
holds stage/resource contracts; consult the relevant sections before changing them.

## Hard rules

- Preserve existing profiles, active configs and adopted fixes during assessment.
  `creative_values.fx` is the only user-facing tuning surface. Do not edit
  `gzw.conf` or shader header comments unless explicitly asked.
- Output remains SDR in `[0,1]`, with `saturate()` as the ceiling. Decode/encode
  sRGB explicitly at processing boundaries; work internally in linear light.
  In-game HDR must be off. No HDR output or auto-exposure; `EXPOSURE` is manual.
- Use smooth arithmetic instead of dynamic branches on pixel properties (sole exception:
  output-preserving skips, see CODE_RULES).
- Runtime testing must be private and headless, with no desktop fallback,
  focus changes or physical-display changes. GPU/localhost work requires sandbox
  escalation. A failed private display stops the run.
- Preserve spatial dither and exact black/white endpoints. No temporal grain;
  analysis sampling retains `FRAME_TIMER`. The intentional 2×2 red marker must
  be masked in strict image comparisons.
- Do not restore diffusion, golden-image regression testing or GPU profiling.
  New effects require evidence of a relevant gap and authorization within scope.

## Work and evidence

Prioritize technical correctness and reliable intended behavior; personal palette
preference is not a blocker. Improve shared shader models rather than searching
profiles. Require a recurring visible loss in native source/full comparisons
before developing a candidate. Do not turn every small residual into a new task.

Verify source, normalized shader body, profiles, configs, includes and producers
before reusing evidence. Labels and grade hashes alone do not establish identity.
Preserve failed repeats, incorrect variants, empty/NaN exclusions and uncertainty;
never silently relabel them. Inspect old generators before importing or running:
some execute captures on import or require frozen identities.

Use matched captures, relevant bypasses and unchanged repeats. Numerical
correctness, darker means, saturation, entropy and delta-E do not establish visual
quality. GPU telemetry requires explicit readback; screenshots contain none.
Settling time is not convergence, and sparse source matches are not dense motion.

Keep durable rules here, code constraints in CODE_RULES, tool procedures in TOOLS,
current tasks in PLAN and transient state in HANDOFF. Put experiment details in
`research/`; do not append research diaries to root guides. Reports are versioned;
`captures/` stays local and ignored. Preserve existing uncommitted work; do not
force-add artifacts. Follow the current user authorization for adoption and publication.
