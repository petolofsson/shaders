# Handoff — 2026-10-31

Read [startup-prompt-latest](startup-prompt-latest), [AGENTS.md](AGENTS.md),
[CODE_RULES.md](CODE_RULES.md), [GOAL.md](GOAL.md), [PLAN.md](PLAN.md) and
[TOOLS.md](TOOLS.md). The user requested updating the documentation and committing
and pushing the completed work. This handoff accompanies that publication;
`git log -1`, `git status` and the upstream tracking state identify the checkpoint.
Stable `v1.0` remains at `1724bb6` as the earlier rollback point.

## Current implementation

Both active game configs use `general/pipeline/pipeline.fx` as one effect.
Grade remains eight passes. Explicit sRGB/linear-light boundaries, bounded SDR,
spatial output dither and the intentional 2×2 red marker remain. No HDR output,
auto-exposure, new effect or tuning surface is introduced.

- Guarded shared inverse-luma shadow gain retains selected shadow distinctions.
  [Decision](research/2026-10-29_shadow_stage_preservation.md).
- Inverse chroma preserves incoming C, limits reconstruction to 85% of the hue
  ceiling and budgets added C against per-pixel SDR gamut at fixed lightness.
  The fixed 14-step search avoids the earlier small ordering reversal.
  [Decision](research/2026-10-31_print_inverse_color_preservation.md).
- Print retains its density curve while using a shadow-protected RGB-ratio path.
  Actual FilmCurve loss relieves overlapping secondary print compression.
  Selected light-core separation improves about 9% in the latest highlight study.
  [Decision](research/2026-10-31_highlight_cooperation.md).
- Weak lower-tone colors retain more original print response based on C/L over
  0.03–0.12; protection fades out over linear Y=0.10–0.25. Selected blue-wall/
  cool-window color gaps improve about 3.85%/2.96%, with smaller material/hue and
  quantization costs. [Decision](research/2026-10-31_weak_material_colors.md).
- Combined tonal-gain limits were rejected for small mixed gains and shelf/wood
  losses. No further sweep of those limits is queued.
  [Decision](research/2026-10-31_tonal_cooperation.md).

## Profiles and ratings

Preserve both distinct profiles. GZW uses inverse chroma/luma 0.60/0.60, shadow
weight -0.075 temperature / -0.015 tint, blacks 0 and FilmCurve 0.60. The inverse-
luma 0.60 and tint -0.015 were external edits preserved during assessment.
Arc retains inverse strengths 0.5/0.5, blacks 0.005, FilmCurve 0.6, shadow
temperature -0.075, tint 0 and midtone temperature 0.05. Only creative profiles
are user-facing tuning surfaces. Shader headers and active configs are preserved.

The [0–100 board](research/2026-10-31_75_goal_report.md) retains provisional
chain/grade 75 and assessed blocks 75–90. Appearance uncertainty is roughly
5–10 points. Parent/child rows overlap and must not be averaged. Later highlight/
weak-color gains do not constitute a fresh whole-chain rating. Earlier GZW
inverse-luma 0.30 and CC tint -0.025 evidence retain their historical scope.

## Validation and baseline reuse

Latest artifacts: `captures/weak_color_20261031/verification.json` and `audit.json`.
Seven baseline and selected held pairs are exact; look-zero controls are exact.
Independent CPU/GPU contracts, four chart/profile fixtures, 192 exact measured
same-update motion controls and four actual-config outputs matching candidates
exactly pass. The complete screen has 51 fresh private GPU processes, zero
frame drops/delays, and 252 isolated files / 664 images verified. All 22 tooling
tests and whitespace checks pass.

Retain warm-floor color-gap loss (~0.84%), small foliage/hue/quantization and
night-step costs. Earlier highlight FilmCurve-zero testing retains one persistent
one-code GZW pixel with exact within-control repeats. No bit-exact cross-pair
identity or repair of that residual is claimed by the weak-color change.

All runtime testing stays private/headless. Use fresh processes, verified source/
profile/config/shader hashes, marker/tag masks and 20-second continuous settling.
Warmup alone is not proof of convergence. Ordinary screenshots contain no hidden
state telemetry. Temporal claims require explicit measured GPU update ages.
The cached Babylon source is 15 unique poses/sec doubled to 30 fps; sparse matches
do not establish dense native gameplay or physical high-refresh acceptance.

## Next work

All requested finite decisions are closed. No new mandatory repair, parameter
screen, effect, golden fixture or performance investigation is queued. Broader
games, dense motion, timing, aspects/resolutions and a fresh whole-chain rating
support stronger claims. Start new work from a concrete shortcoming.

Reports are versioned. Capture media, diagnostic scripts/configs, review pages
and logs remain ignored local artifacts; capture links require this workspace.
Do not blindly rerun historical scripts against changed shader signatures or
profiles. Preserve rejected candidates and their labelled observation epochs.
