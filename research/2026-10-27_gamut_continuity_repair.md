# Blue-cusp gamut continuity repair — 2026-10-27

Follow-up status: [wall/sky attribution](2026-10-27_wall_sky_attribution.md) and
[current-set material/highlight coverage](2026-10-27_material_highlight_coverage.md)
are complete. Their assessments preserve this repair and its documented costs.
Next is temporal/resolution coverage; the remaining-work text below records the
order at completion of this repair.


The subsequent [wall/sky attribution](2026-10-27_wall_sky_attribution.md) is
complete without further production edits; its model-cooperation costs remain.

Follows the [color-continuity assessment](2026-10-26_color_continuity.md).
Fixed-lightness/hue chroma rays can leave and re-enter the SDR cube near blue.
The old neutral-origin bisection could discard a valid outer interval and
amplify a one-code source step. Selecting the highest valid interval alone
would still allow jumps where that interval appears or disappears.

## Mapping and contracts

The selected correction retains the radial search, its ten iterations and
strict [0,1] tests. The initial SDR-face guard remains exactly ±1e-6. Valid
original colors return the same saturated original RGB. Only genuinely
out-of-gamut colors in a localized blue region use the alternate path.

The full angular correction covers hue 264.13±0.5 degrees. A smooth cosine-space
transition reaches zero at ±6 degrees. Lightness coverage is full through
L=0.48 and fades to zero at L=0.52. The core covers the disconnected SDR matrix
geometry; the wider feather limits amplification on quantized hue ramps.
These are shared technical bounds, not per-game tuning or blue-saturation
controls. There is no new tuning surface, texture, pass or temporal history.

The alternate path bounds trial C/L at 0.70 to avoid cubic extrapolation far
beyond the relevant blue faces, converts to nonnegative RGB and restores target
Oklab lightness by uniform RGB gain. At the upper blue face, five bounded Newton
steps adjust green to recover lightness after bounding RGB. The derivative is
the analytic d(Oklab L)/d(linear G), using the same matrices as the conversion.
This avoids the hue-order bend caused by adding a gray pedestal.

Radial and corrected results blend in Oklab a/b at target L. Any tiny negative
RGB from that blend is removed, then lightness is restored with a strict
max-channel ceiling. The cube of a lightness ratio is intentional here: Oklab L
scales with the cube root of uniform RGB gain. This does not undo the earlier
[inverse-luma units repair](2026-10-25_inverse_luma_units.md), whose input ratio
was already a linear-light gain. Final output still uses `saturate()`.

Exact fixed hue is deliberately relaxed for out-of-gamut colors in this region;
retaining both fixed hue and the old radial projection cannot solve the
identified discontinuity. In-gamut identity and the original radial behavior
outside the support remain separate requirements. Signed RGB/positive overrange
remain internal; only the existing inverse/final-grade SDR boundaries call the
projection. Profiles, shader header comments, exposure, active configs, effect
order and prior signal/history/spatial repairs are preserved.

## Geometry and rejected partial repairs

An independent cubic-root oracle solves all RGB 0/1 faces along each chroma ray.
It checks 18,241 fixed-L/hue cases: a coarse full wheel at ten lightness values
and a fine blue-cusp region. The coarse 0.5-degree hue grid misses the narrow
island, illustrating why it is insufficient alone. Fine checks find disconnected
runs around 264.053–264.207 degrees. An additional 15,601-hue red-root sweep
finds the outer island up to sampled L=0.470524 near hue 264.2078. The retained
full-coverage limit of 0.48 includes margin. These sweeps support the scoped
bounds; they are not a formal proof for arbitrary floating-point inputs.

Local artifacts retain the intermediate variants:

- V1 faded above L=0.47. Its initial chart/probe checks passed, but the independent
  root check exposed the small missed lightness interval.
- V2 extended coverage but blended through RGB and contracted upper-face colors
  toward gray. It removed the large jump but added twelve hue backsteps greater
  than one degree over sixteen pixels in the brightest GZW row. Its otherwise
  passing eight-scene/motion batch is retained, not used as final acceptance.
- V3 used green-only upper-face restoration and perceptual blending. It removed
  those hue reversals, but its narrow angular feather amplified a secondary
  one-code step. Explicit GPU input/output tracing localized that amplification
  to the final projection.
- V4 retains that mapping with a wider smooth feather. The traced GZW code-128
  pair at x=1577/1578 falls from V3's 1.986794 to 0.173878 ΔE. Both profiles'
  bright chart rows have no added measured hue-order reversal.

No direct RGB-clipping bypass is promoted as a repair. A dense CPU sweep covers
14 lightnesses, 31 chromas and 14,001 hue samples per pair, including the full
feather. The old multi-ΔE jumps fall to at most 0.058625 ΔE between neighboring
0.001-degree samples. Remaining fine steps include the unchanged ten-iteration
radial search's finite resolution. Bounds and non-increasing chroma hold on
these samples. Near-black error from the retained face guard is recorded rather
than used to justify widening that guard. A separate seeded million-input
CPU sweep over coupled blue L/C/h values finds maximum projected L error
0.000000006527, no chroma increase, exact valid-input identity and bounded finite
RGB. Initial face-tolerated inputs are separated from projected inputs for
that L-error statistic.

## Matched two-profile charts and retained costs

Four fresh private headless candidate/repeat processes use unchanged source,
profiles and combined trials, five seconds for compilation and twenty seconds
continuous settling. Both repeats are byte-identical; all four processes report
zero dropped/delayed frames. Full-raster counts mask only the 2×2 activity marker:
there is no added black or white-channel clipping, and source black is preserved.

The selected adjacent source codes `(0,0,64)`→`(1,0,64)` change by 0.286109 ΔE.
Averaging the same 32 identical-source scanlines gives:

| Profile | Before | Candidate | Repeat |
|---|---:|---:|---:|
| GZW | 3.031499 | 0.112662 | 0.112662 |
| Arc | 2.731126 | 0.112251 | 0.112251 |

This reduces the diagnosed jump; a smaller derivative than source is not a
fidelity score. Full saturated hue-row maxima also constrain the assessment:

| Profile / maximum code | Before maximum adjacent ΔE | Candidate maximum |
|---|---:|---:|
| GZW / 64 | 3.031499 | 0.575406 |
| GZW / 128 | 2.808621 | 1.307523 |
| GZW / 255 | 2.519045 | 0.436159 |
| Arc / 64 | 2.731126 | 0.449505 |
| Arc / 128 | 2.815721 | 0.605624 |
| Arc / 255 | 2.532656 | 0.457640 |

The mapping does not eliminate all quantized ramp amplification. In GZW's
code-128 row, x=1531/1532 changes source `(0,53,128)`→`(0,52,128)` by
0.270592 ΔE. Before output changes 0.222091; candidate changes 1.307523.
That is a real secondary cost of the smooth transition, despite reducing the
row's former larger maximum. Preserve it in broader blue-gradient assessment;
do not describe the result as universally banding-free or source-equivalent.
Dark source rows already have large 8-bit hue steps. Their inherited hue-angle
instability is not evidence that all color ordering is certified.

## Direct GPU contracts and continuity

The final probe explicitly renders 1,410 RGBA32F records and encodes every field
for binary readback: 125 in-gamut RGB identities, eleven existing out-of-gamut
contracts, 64 scaled blue inputs and 1,210 dense cusp inputs. Dense inputs use
five lightnesses and two C/L ratios, with an extra L=0.4705 path at 0.001-degree
hue spacing around the upper boundary; other paths use 0.01-degree spacing.
Candidate/repeat readbacks are identical.

| Check | Result |
|---|---:|
| Maximum candidate linear-RGB CPU-oracle discrepancy | 0.000001634 |
| Maximum in-gamut identity discrepancy | 0.000001570 |
| Dense-path maximum adjacent ΔE, before | 2.843749 |
| Dense-path maximum adjacent ΔE, candidate | 0.005768 |
| Upper-boundary maximum adjacent ΔE, before | 0.160834 |
| Upper-boundary maximum adjacent ΔE, candidate | 0.000597 |

Every record passes finite/bounded-output checks. Lightness preservation and
non-increasing chroma pass independent eight-corner readback uncertainty bounds.
The existing fixed-hue contracts outside the cusp still pass. At zero, the
24-bit encoding's RGB quantum becomes a much larger cube-root L uncertainty;
decoded near-black error is not treated as actual shader error.

The old helper's added near-tangent path differs from the double oracle by
up to 0.003121 linear RGB: small float differences change which interval its
bisection retains. The original failed baseline-oracle check is retained.
That path is recorded as diagnosed misbehavior, rather than certified against
the double oracle; bounds/identity and other contracts still pass. Candidate
oracle tolerance remains strict at 0.00003 for every record. No baseline failure
relaxes candidate bounds, lightness or continuity requirements.

Localized hue change remains a cost: the final GPU dense set reaches 0.658085
degrees, and the broader CPU sweep reaches 3.685429 degrees on extreme
out-of-gamut inputs. These are not changes to valid input colors. The correction
adds branch-free arithmetic, including five Newton steps, to the existing
boundaries. Throughput is unprofiled under the standing profiling deferral.


The extreme fixed-L model can converge multiple out-of-gamut hues onto the
same blue edge. This is a retained color-separation cost, distinct from valid
input identity; no claim follows that every reconstructed blue shade remains
distinct. [CPU model illustration](../captures/gamut_continuity_20261026/cusp_models.png).

## Eight held scenes

Six existing dark/bright/vivid/muted/emitter inputs plus the two additional
barrel/wall views use fresh candidate/repeat processes, unchanged profiles and
the five-second compile / twenty-second continuous-settle protocol. Before
images are hash-verified current-code captures, not golden references. Vivid
Arc input retains the GZW profile; Arc cloud/emitter/wall cases retain the Arc
profile. No unified preset is introduced. The
preceding applied report matches current shared hashes; archived grade code is
compared after include/comment normalization, and all other relevant shared
helpers match. Source/profile/config/image identities remain explicit.

| Case | Before→candidate mean ΔE | Repeat maximum code difference |
|---|---:|---:|
| gzw_sunset | 0.000006015 | 0 |
| gzw_dark | 0.000000000 | 0 |
| gzw_vivid | 0.000962854 | 0 |
| arc_cloud | 0.000000214 | 0 |
| gzw_muted | 0.000007878 | 0 |
| arc_emitters | 0.000000000 | 0 |
| gzw_barrels | 0.000000820 | 0 |
| arc_wall | 0.000000768 | 0 |

All sixteen processes report zero dropped/delayed frames. Every repeat is
byte-identical. None adds black or white-channel pixels, and exact source black
is retained; full-raster endpoint counts mask only the 2×2 marker. Most changes
are negligible at whole-frame scale, so these cases constrain collateral costs
rather than establishing broad aesthetic benefit. Source/before/candidate
contact-sheet review shows no newly obvious material-boundary or lighting
change. The source-selected barrel/wall measurements remain in the local metrics.
The existing yellow-wall/sky separation questions are not resolved by this fix.

## Measured-phase motion

The verified Babylon cache retains its original lossless source prefix, all
source hashes and twenty-second pre-roll. It is fifteen poses/second duplicated
at thirty fps, not dense native gameplay. Two final candidate/repeat processes
reuse the verified fresh-process current-code baseline from the preceding
variant batch. Explicit GPU clocks freeze source pose/token and both source-
update and cut-update ages alongside point-sampled output. All fourteen keys
match across before/candidate/repeat, covering all seven requested windows.
Host mpv time is not used as render-phase evidence. All three processes report
zero dropped/delayed frames.

| Window | Phase matches | Mean before→candidate ΔE | Mean repeat ΔE |
|---|---:|---:|---:|
| foliage | 2 | 0.000406 | 0.000060 |
| clearing | 2 | 0.000371 | 0.000001 |
| before_night_cut | 2 | 0.000368 | 0.000002 |
| after_night_cut | 2 | 0.000906 | 0.001399 |
| corridor | 2 | 0.000966 | 0.000953 |
| before_return_cut | 2 | 0.000575 | 0.000600 |
| after_return_cut | 2 | 0.000655 | 0.000157 |

The atlas point-samples native `(5*i+2)` coordinates into 512×288 tiles, with
a two-pixel atlas border excluded. No matched sample adds black or white-channel
clipping, and exact source black stays zero. Maximum per-image mean unchanged-
repeat difference is 0.002741 ΔE. Some small before/candidate changes are
comparable to or below repeat variation and cannot establish a temporal benefit.
The selected flat-face lightness measurements remain in the motion report;
this does not certify all chroma boundaries. Dense continuity, physical high
refresh and acceptance of the existing Retinex cut handoff remain open.
## Applied shared code and final verification

`general/common.fxh` now contains the exact tested V4 helper. Its full source
matches the isolated candidate byte-for-byte, and the original file header is
unchanged. No other production shader, profile or config changes. Both inverse
reconstruction and final-grade projection consume this shared correction.

Four final fresh private headless processes verify the applied source. GZW and
Arc combined-trial chart outputs match their candidates pixel-for-pixel. The
unchanged active GZW sunset control differs by at most one code from its retained
before image; active Arc cloud matches exactly. Neither active control adds
black/white-channel clipping or loses source black. All four processes report
zero dropped/delayed frames. These active controls establish compatibility,
not repair or acceptance of the unavailable cross-effect analysis resources.

The read-only audit verifies 249 unique artifact hashes across seven final
reports, re-decodes GPU values, checks all eight held/two chart repeats and
requires fourteen measured phase matches covering seven windows. Current shared
hashes match the applied report. All 22 diagnostic tooling tests pass after
application, and `git diff --check` is clean. Tooling tests check diagnostics;
GPU readback and matched captures supply shader evidence.

## Retained artifacts and remaining work

Ignored `captures/gamut_continuity_20261026/` retains the run begun on October 26:

- `candidate_v4.fxh`, `candidate_common_v4.fxh`, `before.fxh`, `run.py`,
  `chart_v4_report.json`: source snapshots, two-profile charts and repeats.
- `geometry.py`, `geometry_report.json`, `explore.py`, `check_cpu.py`,
  `cpu_report.json`, `random_contract.py`, `random_contract_report.json`:
  independent roots, dense model sweeps and coupled invariant checks.
- `probe.py`, `probe_v4_report.json`, `probe_v2_before_oracle_failure.json`:
  explicit GPU values, strict candidate checks and the diagnosed baseline failure.
- `trace.py`, `trace_v3_report.json`: inverse RGB, final input Lab, old/new
  projection and final encoded-output fields for the secondary step.
- `regress.py`, `regress_v4_report.json`, `metrics.py`, `metrics_v4.json`,
  `held_contact_v4.png`: eight scene pairs and source-defined material metrics.
- `motion.py`, `motion.fxh`, `before_run/`, `candidate_v4_run/`,
  `repeat_v4_run/`, `motion_metrics.json`: verified media protocol, phase clocks,
  frozen native point samples and strict matching.
- `shared.py`, `applied_report.json`, `audit.py`, `audit_report.json`: final
  shared-source identity, active controls and retained-artifact verification.
- Earlier `candidate*`, `chart*`, `probe*`, `regress_report.json` and V2 motion
  reports retain superseded candidates. Shader/profile/config snapshots remain
  at each report's recorded paths, including earlier local capture directories.

The initial un-escalated private launch failed; its logs remain at
`/tmp/shader-runtime-k9zn1kdv/`. Successful runtime work used sandbox escalation
and never fell back to the desktop. Media/helper scripts remain local and
ignored; the report and shared correction are versioned worktree changes.

The disconnected-ray defect is repaired for the measured scope. Finite
quantized-gradient amplification, extreme out-of-gamut hue/edge convergence,
arithmetic cost and broader blue-material acceptance remain explicit limits.
Next is the separate yellow-wall/sky tonal/inverse attribution, then broader
material and colored-highlight checks. Dense gameplay/cuts, physical high refresh,
more games and active-chain integration remain open. No effectiveness re-score,
new effect, HDR, auto-exposure, golden-image suite or GPU profiling is introduced.
