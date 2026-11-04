# Inverse-to-grade transport decision — 2026-11-03

**Do not adopt the floating residual transport.** The isolated implementation
preserves inverse reconstruction more accurately, but the selected full-frame
comparisons show no useful visible improvement toward [GOAL.md](../GOAL.md).
That return does not justify a full-resolution RGBA16F surface: 28.125 MiB at
2560×1440 before allocation/copy overhead, plus image traffic. Performance was
not profiled. Production remains `738a6f6`; shaders, profiles, configs, headers
and runtime state are unchanged. Chain/grade remain **78/100**, with all other
[November 2 estimates](2026-11-02_effect_ratings.md) carried forward.

The user authorized pursuing the [selected representation](2026-11-03_next_code_candidate.md).
This finite experiment is closed. No sweep, motion campaign, activation or
mandatory replacement investigation follows from its rejection.

## What was built

An isolated combined pipeline keeps original encoded BackBuffer RGB intact.
Its existing inverse pass writes `inverse_encoded - source_encoded` into
RGBA16F. Grade reconstructs `saturate(source_encoded + residual)`, retaining the
source alpha and its original explicit sRGB decode. The inverse and grade
artistic bodies were factored into explicit-input helpers; an automated text
check verifies their bodies against production. Standalone entry wrappers
remain in the isolated copies. The combined pass count is unchanged and grade
still has eight passes. Source analysis, native guide, histories and rates are
unchanged by source inspection; no independent history-equivalence acceptance
is claimed for this rejected prototype.

A separate diagnostic mode stores absolute inverse RGB in a full-resolution
RGBA8 target before the same grade helper. This checks an eight-bit handoff
while the private mpv swapchain remains ten-bit UNORM. It does not establish
physical eight-bit game output, capture transfer, or display behavior.

## Same-update numerical evidence

Two explicit GPU readbacks sample 1,024 native locations each in GZW-profile
vivid content and Arc interior. The vivid input is Arc content processed with
the GZW profile. A source observation, intended floating inverse result,
explicit RGBA8 result, actual BackBuffer result, and small RGBA16F residual
surface are evaluated at the same update. The original grade is also evaluated
on each input. An ordinary post-grade readback validates the diagnostic grade
against the actual output.

The following errors are measured **after the full grade**, before final UNORM
export, relative to the same-update floating inverse input. Units are one
8-bit channel code. These are precision errors, not appearance scores.

| Input / profile | Explicit 8-bit RMS | Actual 10-bit RMS | Residual RMS | Residual maximum |
|---|---:|---:|---:|---:|
| Vivid / GZW | 0.165767 | 0.051956 | 0.000596 | 0.004681 |
| Interior / Arc | 0.095387 | 0.022358 | 0.000246 | 0.007584 |

The residual precision oracle accounts for the diagnostic's 24-bit readback
quantizer. Both probes pass. Actual inverse and ordinary grade outputs fit an
empirical FP16-toward-zero then nearest-UNORM export model within 8.22e-8 encoded
RGB. This is an observed conversion fit, not a compiler/driver root-cause claim.
The independent Arc probe confirms the model inferred from GZW. The small
residual readback establishes representation precision; it is not a numerical
oracle for the separately compiled full-resolution prototype.

## Appearance and repeat decision

Fresh unchanged production and residual captures use both current profiles,
identical verified sources/clips, five-second compile wait and twenty-second
settling. This is a fixed capture protocol, not proof of universal convergence.
All four current/prototype held pairs are exact. A fifth exact pair uses the
vivid explicit-eight-bit mode. All ten ordinary captures have zero reported
frame drops/delays; both diagnostic captures also completed their enforced
zero-drop/delay capture checks. All work was private/headless.

The intentional 2×2 red marker is excluded from strict image metrics. Output
changes below are channel-code differences in ordinary screenshot captures.

| Comparison | Changed pixels | Maximum code change | RMS code change |
|---|---:|---:|---:|
| Vivid residual vs current 10-bit | 135,879 | 1 | 0.115233 |
| Arc interior residual vs current 10-bit | 19,060 | 2 | 0.043207 |
| Vivid residual vs explicit 8-bit handoff | 1,054,123 | 1 | 0.331737 |

Only one Arc pixel differs by more than one code, at (26,12), in the top UI
area. Native sky, broad-field, dark-metal, warm-floor, cool-upper and cool-window
crops and both overviews show no clear improvement in material separation,
light, palette or gradient quality. More accurate values and large counts of
one-code changes do not establish a useful visual contribution.

Selected material statistics are correspondingly small/mixed: vivid sky L-gap
10.5544→10.5534, broad-field L-gap 27.3797→27.3947; Arc warm-floor L-gap
32.7047→32.7112 and cool-window L-gap 31.973474→31.973475. These selected gaps
are not optimization targets. They supply no basis for a rating increase.
The eight-bit comparison gives a more relevant transport context than ten-bit
alone, but likewise does not demonstrate enough benefit to adopt this surface.
The conclusion is scoped to this design and these cases, not a claim that
higher internal precision can never help another game or implementation.

## Retained failures and limits

- The first GZW readback rejected a simple nearest-UNORM error bound. Raw data
  are retained. The later export model explains the observations and passes the
  independent Arc probe; the original failure is not presented as a passing test.
- Arc's initial assumed PNG-to-rendered-source bound of 1.1 codes failed at
  1.214065 codes. That unsupported transfer bound is withdrawn. Both numerical
  contracts use measured GPU source values; no file-to-rendered bit identity
  is claimed. This does not alter the ordinary-output control.
- The first isolated prototype did not compile because copied inverse includes
  retained their old relative paths. The copy paths were corrected; failed
  runtime logs are retained and excluded from successful capture counts.

No inverse-zero, endpoint/chart, full-resolution numerical residual oracle,
motion/cut, physical eight-bit, actual-config activation or performance
acceptance was attempted for the rejected implementation. There is no reason
to broaden validation after failing the appearance/cost decision. No new
production defect, universal stability fix or score is inferred.

## Artifacts and state

Local ignored artifacts: `captures/transport_candidate_20261103/`.
`boundary_contracts.json` links both raw arrays and diagnostic configurations;
`boundary_report.json`, `boundary_v2_report.json` and `setup_failures.json`
retain initial failures. `screen_report.json` records all ten full-frame
captures, source/clip/config/profile/include identities and runtime paths.
`screen_metrics.json` records native regions and exact repeats. `audit.json`
checks unchanged root hashes, capture provenance, artistic body identity and
pass count. `verification.json` hashes the archived files.

Review the [local comparison sheet](../captures/transport_candidate_20261103/review.html).
The [active ratings board](2026-11-02_effect_ratings.md) is unchanged. Production
remains the preceding published commit, synced to origin/master at inspection;
this decision and handoff documentation are uncommitted and not pushed.
