# Shadow-stage attribution and reconstruction preservation — 2026-10-29

Adopt the guarded inverse-luma shadow reconstruction change on its measured
scope. Direct GPU stage readback identifies a substantial contribution to the
selected GZW shadow-paving gap loss before Retinex. Using a shared darkening
reference through eligible shadows recovers selected paving separation without
increasing lift. The first unguarded candidate is rejected; near-black identity
and a no-relaxation guard remove its added black pixels and warm-floor cost.

This is a bounded enhancement, not a universal shadow repair. GZW shadow-paving
visible separation improves about 6.3%; Arc vehicle separation loses about 3.0%
as those shades become darker. Relative vehicle contrast is nearly unchanged.
Selected wood/metal have smaller absolute-gap costs. These are retained tradeoffs,
not hidden by a fidelity score. The broader shadow-richness goal remains open.

Only `general/grade/grade.fx` changes in production. Creative profiles, active
configs, shader header comments, original current-source inverse budget,
Retinex/lift/print implementations, authoritative histories, rates and eight
grade passes remain. No new texture, highway, control, effect, exposure target,
HDR output or performance work is introduced. Stable 1.0 remains available as
commit `1724bb6`, tag `v1.0`; this enhancement is subsequent working-tree work.

## Causal question and direct observations

The user requested identifying where existing stages reduce visible shadow
distinctions, then testing preservation rather than additional brightness. This
is a new, shadow-specific diagnosis following the closed
[lift-distribution screen](2026-10-28_shadow_richness_screen.md), not another
parameter pass on those rejected curves.

Five original sources under unchanged profiles receive two fresh numeric
readbacks each. Each readback contains sixteen RGBA32F stage records at 1,024
native sample addresses: a 16x16 source-fixed grid in each of four rectangles.
The records are displayed with explicit binary encoding for 24-bit readback;
ordinary screenshots are not treated as hidden telemetry. Original native RGB
is captured before inverse processing in the same technique. Every original
full/repeat numeric record is identical. Two additional readbacks evaluate the
guarded candidate independently under GZW and Arc profiles.

Source-selected grid locations and PNG-L quartiles are fixed across stages.
Masks for shelf, wood, dark metal and rear body require source L<45. Grid gaps
describe these samples, not full-region means. The stage chart and complete
twenty-region tables are local `stage_gaps.{png,svg}` and `trace_metrics.json`.

| Sampled region | Observed input L gap | After black/white affine | After inverse luma | After other corrective | After Retinex | After zone | After lift | After print/look |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| GZW shadow paving | 10.363 | 10.346 | 9.565 | 9.552 | 9.519 | 9.680 | 9.672 | 9.707 |
| Arc dark metal | 10.584 | 7.142 | 7.142 | 7.142 | 7.316 | 7.325 | 7.401 | 7.062 |
| GZW shelf | 4.377 | 4.370 | 4.370 | 4.370 | 4.370 | 4.367 | 4.745 | 4.273 |
| GZW shop wood | 10.096 | 10.079 | 10.079 | 10.078 | 10.106 | 10.120 | 11.006 | 10.767 |

The observations do not support one uniform tonal defect:

- In selected paving, inverse luma accounts for about 0.78 L of the loss; its
  sampled relative gap also drops 1.041→0.972 stops. This supplies the concrete
  cause for testing a shadow-specific reconstruction change.
- Arc's deliberate BLACKS=0.005 offset dominates the selected metal reduction:
  sampled relative gap falls 2.507→1.336 stops at that operation. The profile is
  preserved. This cannot be honestly attributed to Retinex or repaired by claiming
  another lift increase preserves the same relationship.
- In the shelf, lift increases visible separation before print darkens it again;
  print simultaneously increases relative contrast. A smaller visible gap alone
  does not establish erased information or an arithmetic defect.
- Retinex and lift compress some brighter ranges, while zone shaping often
  restores some separation. Film is identity on the selected dark samples.
  Later chroma and gamut work barely change their L gaps. These are cumulative
  observations, not additive counterfactual effect budgets.

The internal retinex/zone/lift records include both scalar tonal targets and
implied RGB at fixed Oklab chroma. The scalar targets are not mislabeled as
actual reconstructed RGB luminance. Tonal reconstruction agrees with its direct
GPU records within 0.000443 L on the original samples. Retinex mixing agrees
within 4.05e-7 linear Y. Final numeric outputs agree with ordinary full captures
within 0.694 sRGB code, including output quantization.

Decoded clip frames are byte-exact PNG sources. mpv's *rendered* incoming values
are not assumed to equal those file pixels: the observed maximum difference is
about 1.215 source code. The independent native-guide observation agrees with
the directly captured native RGB within its readback quantization bounds. The
analysis uses that actual observed incoming signal for cumulative stage values.

## Tested reconstruction change

The original per-pixel inverse ACES-derived reconstruction ratio, Gaussian bell,
manual INVERSE_LUMA and existing current-source span budget remain. The new block
computes a reference from the same inverse formula at a shared shadow anchor:

```text
anchor = clamp(zone_key * (WHITES-BLACKS) + BLACKS, 0.06, 0.12)
reference_ratio = original_inverse_ratio_evaluated_at(anchor)
window = smoothstep(0.001,0.005,input_Y)
       * (1-smoothstep(0.08,0.20,input_Y))
ratio = lerp(original_ratio, min(original_ratio,reference_ratio), window)
```

The anchor is in the affine input's linear-light domain. A shared ratio preserves
relative shades where it replaces the per-pixel ratio; where the original ratio
already darkens more, that original behavior stays. It is a bounded reference,
not an estimate of a material's reflectance or a target frame brightness.

The guards preserve the original reconstruction at/below Y=0.001 and at/above
Y=0.20, fade smoothly between ranges, and prevent relaxing the original gain.
The change never adds a new reconstruction gain above the original. It leaves
the manual ceiling and source-validity/budget behavior intact. The existing
INVERSE_LUMA=0 branch bypasses the entire block, verified pixel-identical in a
fresh off/candidate-off pair. No new spatial guide or strength fade is added.

The first candidate used a common ratio without the near-black/no-relaxation
guards. It added 21 exact-black shop pixels and reduced warm-floor separation
32.351→31.891 L. It is rejected. The guard removes those specific costs while
retaining the targeted paving gain; this is a closed two-candidate decision.

The CPU contract covers 112 fixed-key scenarios with two black offsets, seven
keys, four strengths and two source budgets. All tested guarded curves remain
monotonic, retain the original outer ranges and never raise the original gain;
minimum sampled derivative is 0.616. This is not a full adaptive-chain proof.
Actual candidate GPU reconstruction at 2,048 addresses under two profiles
agrees with the independent CPU oracle within 3.65e-7 RGB. Original-function
controls agree within 2.34e-7. Observed outer-range RGB identity is exact.

## Held-image results and accepted costs

The five stable 1.0 full/repeat pairs from the preceding screen are reused only
after exact source/profile/shader hash verification. The initial and guarded
candidates have five fresh held/repeat pairs each; vivid color adds a fresh
full/guarded/guarded-repeat. Original and modified dark boundary fixtures each
have fresh full/guarded captures under both profiles. There are ten source/profile
cases from eight distinct PNGs: six game screenshots, one cached native boundary
source and one explicitly modified diagnostic source.

Native regions and full-region fixed source masks follow the preceding screen.
These whole-region gaps therefore differ from the grid-sampled attribution
table above. Oklab L uses 0–100 units; relative gaps use log2 linear Y with 1e-8
floor. Delta-E, larger gaps and darker means are not quality scores.

| Region | Median L, baseline→guarded | Visible L gap, baseline→guarded | Relative gap, baseline→guarded (stops) |
|---|---:|---:|---:|
| GZW shadow paving | 40.985→40.574 | 9.892→10.515 | 1.064→1.142 |
| GZW lit paving | 57.839→57.839 | 16.927→17.102 | 1.396→1.417 |
| GZW shelf | 12.212→12.212 | 4.388→4.388 | 1.643→1.643 |
| GZW wood | 27.353→27.236 | 10.522→10.480 | 1.774→1.773 |
| GZW floor | 36.136→35.977 | 12.805→12.924 | 1.520→1.537 |
| Arc dark metal | 19.611→19.491 | 7.766→7.752 | 1.526→1.526 |
| Arc warm floor | 58.236→58.236 | 32.351→32.363 | 2.494→2.495 |
| Arc rear body | 21.891→21.119 | 13.868→13.449 | 2.416→2.423 |
| Arc road | 51.531→51.531 | 18.908→19.416 | 1.711→1.774 |

The paving result is preservation with deeper shading, not more shadow lift.
The vehicle result shows the limit: relative shades survive but their visible
lightness span shrinks about 3.0%. Wood and metal gaps shrink about 0.4%/0.2%.
These accepted appearance costs prevent claiming uniformly better shadows.
Visual crop/full review supports the bounded paving/road benefit and a darker,
more restrained vehicle treatment; it does not establish a universal preference.

The dark GZW source is pixel-identical to baseline. No guarded case adds an
exact-black or channel-255 pixel. Arc's positive black offset remains a positive
output floor, but subsequent processing can change its displayed code: source
black maxima are 14→14 in interior, 13→12 in vehicle/day and 13→11 in the original
boundary case. Profiles are preserved; exact source-black output identity is
not claimed. GZW source-black pixels in the vivid/boundary controls remain black.

Whole-frame baseline/guarded mean delta-E is 0.245/0/0.112/0.055/0.293 in the five
main cases; maximum channel changes are 4/0/1/1/7 codes. Vivid mean change is
0.129 delta-E with a four-code maximum. Source-smooth dark-pair delta-E p99 in
paving rises 0.756→0.836, while shelf stays 1.747 and vehicle falls 0.795→0.786.
This retains a quantized-gradient amplification cost; no noise-aware or general
banding-freedom claim is made. Mixed materials/lighting are not physical
same-reflectance tests, and mostly neutral dark samples do not prove rich
dark-color retention.

The vivid source's 172,811 selected blue pixels include 30,787 source-smooth
horizontal pairs. Their delta-E p99 rises 0.74660→0.75415, with maximum isolated
pair-amplification growth 0.94640. Median baseline/candidate hue shift is zero;
absolute hue shift p99 is 2.167 degrees and median C changes 7.663→7.635.
These finite blue/quantization costs are retained alongside the paving benefit;
the test does not establish palette identity or general banding freedom.

## Spatial and temporal controls

The original nine-color boundary patches are unchanged by the candidate and
therefore establish nonintervention, not active dark-boundary behavior. A second
explicitly modified fixture scales the nine most frequent source colors in the
patch region by 90/255: eight colored patches and a background color. It preserves
the geometry, white control and surrounding source. This is a
static diagnostic derivative, not native gameplay or motion evidence.

The modified fixture supplies sixteen actively changed dark-patch records and
two unchanged white controls. Largest median-L shifts are 0.979 GZW and 1.325
Arc. Baseline/candidate changes in median
edge-minus-far L and C are zero
for all eighteen. Maximum growth of block-averaged interior L95–L5 spread is
0.003570 L. The normal/dark fixtures add no black or clipped-white pixels.
This preserves the measured uniform-boundary behavior without claiming every
textured gameplay boundary is halo-free.

Two cached Babylon replays evaluate original, guarded and ordinary production
control in the same GPU updates. Each has 48 explicitly measured source/cut-age
keys; all 96 full/ordinary image controls match exactly on the common 12,984-sample
support. Source/atlas tags and calibration footprints are consistently masked.
Both runs report zero dropped/delayed frames. The candidate is exactly baseline
through the measured night window under both profiles.

First-return/maximum duplicate steps change GZW 0.756857→0.750254 delta-E and
Arc 0.764935→0.754082. Daylight maxima change 0.131203→0.131270 and
0.132039→0.132268. Maximum candidate/full return differences are 0.248/0.404
delta-E. These are bounded measured costs/changes, not a new transition repair.
The source is fifteen poses/sec duplicated at thirty fps; sparse measured-phase
samples do not establish dense continuity, high-refresh gameplay, hitches or
cross-run temporal repeats. No time constant is changed.

## Application and validation record

Production is byte-identical to the tested guarded canonical grade. Both actual
active configs are checked with fresh full/repeat captures against their isolated
candidate outputs; all four match exactly, as recorded in local `verification.json`.
These are private headless active-config tests, not claims about a running game
launcher or physical display. The sole production delta is the inverse-luma
block described above; active configs and creative profiles remain unchanged.

Local artifacts: `captures/shadow_attribution_20261029/` contains source/profile
hash manifests, all stage records and addresses, scalar/CPU contracts, full
images and repeats, rejected initial trial, source-container frame hashes,
normal/dark boundary derivation and metrics, measured-phase replays, runtime logs
and final actual-config verification. The audit verifies every frame in each
static sixty-frame clip against source RGB, not just elapsed warmup. Twenty-second
continuous settling and unchanged repeats remain a protocol, not a proof of full
long-history convergence.

The final audit passes 1,649 assertions across 557 unique artifacts, including
all 900 frames in fifteen static source containers, sixteen held unchanged
image pairs (five reused baseline pairs), the exact bypass pair, five original
numeric repeat pairs, two candidate GPU observations, 96 same-update ordinary
controls and four actual active-config captures. All remaining production
sources, game profiles and active configs match their initial hashes.

- [Stage attribution plot](../captures/shadow_attribution_20261029/stage_gaps.png).
- [Interactive image comparison](../captures/shadow_attribution_20261029/review.html).
- [Native material crops](../captures/shadow_attribution_20261029/crops.png).

Scripts/media remain ignored local artifacts; reports remain versioned. No golden
suite is restored. All 22 diagnostic tooling tests and whitespace checks pass.
This closes the attribution/common-gain candidate decision on its
measured scope; no new mandatory repair or effectiveness re-score follows.
