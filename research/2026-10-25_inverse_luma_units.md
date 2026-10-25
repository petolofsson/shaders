# Inverse-luma gain units — 2026-10-25

The [stage review](2026-10-25_stage_review.md) traced substantial sunset
darkening to inverse luma. Its computed gain is a linear-light luminance ratio,
but the implementation multiplied Oklab coordinates by that ratio. Since
Oklab→RGB cubes its intermediate coordinates, the resulting RGB gain was cubed.
The corrected stage applies the computed ratio directly in linear RGB.

## Contract and GPU isolation

Let `k` be the existing weighted linear-luma ratio, including INVERSE_LUMA and
the unchanged Gaussian bell. Previous output was approximately `RGB * k³`;
the selected reconstruction calls for `RGB * k`. Proportional RGB scaling also
preserves Oklab hue and C/L. No cube-root reconstruction is needed when applying
the ratio in RGB directly. The partial ACES inverse, its existing assumptions,
manual strength and EXPOSURE order remain intact.

A temporary diagnostic copies ApplyCorrective and returns immediately after
the inverse-luma step, before exposure, DIR and three-way correction. Twelve
neutral inputs are generated arithmetically in the diagnostic shader and
explicitly rendered as gray bars. This is function readback, not scene fidelity,
highway telemetry, a golden reference or a restored fixture suite.

Two fresh private headless probes use INVERSE_LUMA=0.6 and compare the previous
and corrected implementations. At input Y=0.2066, the weighted ratio is 0.8776:
expected linear output is about 0.1813; measured previous output is 0.1384 and
corrected output 0.1812. Both behaviors match their respective CPU models within
two captured channel codes, including compositor/quantization uncertainty.
Exact black and white endpoints are preserved. An independent direct linear
blend is bounded and monotonic over 10,001 sampled input luminances.
[Curve comparison](../captures/inverse_luma_units_20261025/curve.png).

The first temporary probe failed compilation because it left unreachable code
after the diagnostic return. Removing the unused function tail resolved it;
no shared shader change was needed for that diagnostic failure. Its failed
report/log remains separate from the two successful captures.

## Six-scene validation

Twelve fresh private candidate/repeat processes use five-second compile wait and
20-second continuous settle. Before/repeat captures reuse the verified current
zone-corrected shader from the preceding batches; source/profile hashes and
executable code equivalence are checked. Existing profile differences remain
explicit: vivid Arc input uses GZW tuning; cloud and emitter cases use Arc tuning.

| Case | Previous→candidate mean ΔE | Candidate/repeat mean ΔE |
|---|---:|---:|
| GZW dark | 0.13981 | 0.00000 |
| GZW sunset | 1.12649 | 0.00049 |
| Vivid Arc input, GZW profile | 1.73987 | 0.00000 |
| Arc clouds | 1.04952 | 0.00005 |
| GZW overcast | 0.46294 | 0.00000 |
| Arc emitters | 0.32320 | 0.00001 |

All twelve processes report zero dropped/delayed frames. Aggregate exact-black
coverage is unchanged in each case; no new white-channel clipping is introduced.
Source black remains zero where present. These counts constrain regressions,
not aesthetic success. The inspected [source/previous/candidate/repeat overview](../captures/inverse_luma_units_20261025/review_overview.png)
and material crops show restored midtone brightness without a newly obvious rim.

## Benefits and retained tradeoffs

- **Sunset ground:** median L 38.82→41.46 against source 47.38; C 8.28→8.75
  against source 6.94. Source-defined group separation 27.46→30.70 L, source
  34.61. Facade separation 34.91→38.79 L, source 41.77. The correction reduces
  excess density while the print/tonal treatment and manual saturation remain.
- **Deep shelf:** median L=12.26/C=0.45 and 4.24 L group separation stay unchanged
  at capture precision. The cool-shadow preference identified in the stage review
  remains separate; this correction does not silently replace that tuning.
- **Overcast:** selected neutral sky L 67.39→69.40, source 72.73. Its group gap
  10.40→8.70 L is less exaggerated relative to source 6.70. Dark foliage median
  remains L=26.06/C=4.03. The documented green hue shift still needs visual review.
- **Lights:** red lamp L/C 46.20/17.83→49.91/18.74, source 51.77/19.22. White
  cores remain median L=93.84; their halo rises 69.48→71.07, source 73.47.
  Already clipped white-core source samples do not gain recoverable detail.
- **Blue-sky contrast cost:** selected vivid sky L rises 58.61→61.92, source
  67.45, but its source-defined group gap narrows 9.61→6.94 L against source
  9.71. This is a real remaining print/tonal calibration tradeoff, not a claim
  that all local contrast measures improve when gain units are corrected.

## Matched motion

Two fresh candidate/repeat replays use the verified cached 15-pose/sec source,
duplicate 30 fps playback and 20-second initial pre-roll. Eleven exact assessment
matches cover foliage (1), clearing (3), and corridor (7); both processes report
zero dropped/delayed frames.

| Window | Previous→candidate mean ΔE | Candidate/repeat mean ΔE |
|---|---:|---:|
| Foliage | 1.64171 | 0.03057 |
| Clearing | 2.18591 | 0.02531 |
| Corridor | 0.05843 | 0.00522 |

On the three matched clearing poses, orange edge gaps stay zero, purple gaps
remain within −0.086…+0.031 L in candidate/repeats, and magenta within
0.073–0.182 L. Sky gaps fall from 0.37–0.61 to 0.05–0.27 L on these samples.
This preserves the preceding spatial fixes on the assessed poses. Sparse matches
and repeat variation do not establish dense stability or complete cut coverage.

## Active chains and adoption

Six additional fresh before/candidate/repeat captures test the unchanged active
GZW sunset and Arc cloud four-effect configs. The pointwise correction engages:
mean changes are 1.00422 and 0.88434 ΔE; repeats 0.000020 and 0.000023. All six
processes report zero dropped/delayed frames. These tests do not repair or
validate the active chains' unavailable cross-effect analysis resources.

The validated correction is applied in `general/grade/grade.fx`. Normalized
executable code matches the tested candidate. Previous Retinex/zone fixes,
profiles, active configs, header comments and manual exposure remain intact.
Twenty diagnostics and `git diff --check` pass. Four final fresh shared-path
captures match the tested candidates: combined GZW sunset 0.000502 ΔE, combined
Arc cloud 0.000000, active GZW sunset 0.000000, active Arc cloud 0.000001.
All four report zero dropped/delayed frames.
[Applied-path verification](../captures/inverse_luma_units_20261025/applied_report.json).

Ignored [`captures/inverse_luma_units_20261025/`](../captures/inverse_luma_units_20261025/)
retains the previous shader snapshot, candidate/probe sources, configurations,
scripts, curve, source/image/profile hashes and all captures. `probe_metrics.json`
records readback; `regressions/report.json` and `regressions/metrics.json` record
six-scene checks; root `metrics.json` records source-selected material results;
`active_regressions/report.json` and `motion/report.json` record the remaining
checks. This corrects the chosen reconstruction's units; it does not prove that
the partial ACES model suits every source game or establish 75+ effectiveness.
