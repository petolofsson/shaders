# Shared tonal base and material separation — 2026-11-02

**Adopted in the shared grade and verified through both actual configs.**
The user redirected work toward the approach with the highest expected return
for the visual goal. The resulting change addresses repeated classification of
material shading by the tonal stages: Retinex, zone shaping and lift now evaluate
a common source-derived brightness base, then carry the original corrected
pixel variation through their combined gain. Selected local shade relationships
improve, with small material, road/sky, quantization and transition costs retained.

Only `general/grade/grade.fx` changes in production. Both creative profiles,
including BLACKS=0.0025, configs, shader header comments, inverse reconstruction,
analysis, histories/rates/resources and eight grade passes remain. No new user
control, auto-exposure, HDR output or effect is introduced. No new effectiveness
score or universal material/game acceptance is claimed.

## Why change the model

The preceding [material attribution](2026-11-01_tonal_material_selectivity.md)
isolates neighboring-shade compression from Retinex and lift in several floor,
cloth and plaster selections. Changing only lift eligibility or composing its
amplitude with zone contrast did not retain those relationships consistently.
The new design assigns the coupled tonal decisions a common brightness signal.

Let Y be corrected pixel luminance, I the original native source luminance
observation, and Bs the estimated source base. The implementation uses:

```text
B = Y * (Bs / I)
gain = 1 + (F(B) - B) / B
scalar target = Y * gain
```

The existing near-zero floors and nonnegative gain guard remain. F contains the
Retinex native response, zone shaping and lift. The original relative guided/
native Retinex correction remains a separate field, retaining prior protection.
At a fixed base and correction context, the scalar mapping carries pixel detail
with unit log response. The estimate and context vary in actual images, and
subsequent chroma/print/gamut processing still matters. This is an empirical
brightness decomposition, without physical illumination/albedo ground truth.

The final reconstruction retains the existing Oklab L cube-root scaling, Hunt
coupling and ambient tint. The earlier exact-linear-Y solve is not adopted:
its two held observations were tiny and mixed. Its independent CPU color grid
establishes an approximation difference, not a confirmed defect in the intended
chroma treatment. No numerical GPU, temporal or adoption claim follows for that
stopped solver. Its local artifacts remain in `captures/tonal_reconstruction_20261102/`.

## Source base and restraint

The new helper samples the existing R32F native source guide at 25 positions on
an eight-native-pixel stride, spanning 32 pixels. It computes one full-neighborhood
mean and four overlapping nine-tap quadrant means. Every window includes the
center. Sample weights are one through half a stop from the center, fading
smoothly to zero at one stop. Strongly different neighbors therefore cannot
make a narrow bright feature inherit a dark background's classification.

The five estimates blend by proximity to the center. Product-form weights
`w_i = product(d_j^2, j != i)` implement inverse-square proximity without division
by an individual distance. A matching window anchors the result, ties blend
continuously, and multiple exact matches return the source value through the
bounded denominator. The source range and all loops are fixed; there are no
branches on pixel properties, new textures, passes or temporal state.

Ideal straight steps have a homogeneous quadrant. Smooth linear ramps have
the center as their full-window mean. Both are identity cases for the estimator.
The independent numerical model covers 100,000 supplied window contexts,
anchor/convexity/tie-continuity checks, 111 ideal step/ramp contexts and isolated
high-contrast features. These properties do not prove every native boundary,
spatial gradient or moving texture is artifact-free.

## Held material and light observations

Both current profiles remain distinct, with GZW inverse chroma/luma 0.60/0.60
and tint -0.015 preserved. Arc trial images are reused only after matching the
current profile, normalized shader body, source, clip and isolated-file hashes.
GZW baselines are refreshed for BLACKS=0.0025. Both actual configs were also
verified before this code change, completing the preceding pending activation
checks; Arc matched its saved 0.0025 trial exactly.

Regions, source-L quartile groups and neighboring pairs remain fixed from the
material attribution. The local response is the median signed output/source
log-Y difference at four native pixels. Visible gaps are Oklab L ×100. These
selections contain lighting/object boundaries and are not pure-reflectance
measurements or fidelity scores.

| Region | Previous local response | Selected | Change | Visible L gap |
|---|---:|---:|---:|---:|
| Arc interior floor | 0.9590 | 0.9754 | +1.70% | 32.6785 → 32.7047 |
| Arc cool upper | 0.9980 | 1.0143 | +1.63% | 20.3708 → 20.3829 |
| Arc cool window | 0.8925 | 0.9220 | +3.30% | 31.9572 → 31.9735 |
| Bedroom cloth | 0.9054 | 0.9256 | +2.22% | 38.9314 → 38.9993 |
| Bedroom plaster/rack | 0.8983 | 0.9367 | +4.27% | 16.8821 → 16.9375 |
| Bedroom floor | 0.8819 | 0.9154 | +3.80% | 17.6884 → 17.9522 |
| GZW shadow paving | 1.0723 | 1.0796 | +0.68% | 10.0541 → 10.2661 |
| GZW lit paving | 1.1062 | 1.1275 | +1.92% | 17.0891 → 17.5847 |
| GZW blue wall | 0.9625 | 0.9784 | +1.64% | 9.4652 → 9.4793 |

The main gains retain supplied shade variation without a broad change of the
look. Native floor, cloth and plaster crops support the selected direction.
The field does not recover information already clipped or quantized in the
source. GZW paving was already above source local response, so its additional
contrast is also a restraint cost rather than universal restoration.

Arc road response rises 0.9901→1.0409, with relative whole-region separation
1.8149→1.8363 stops against source 1.7703. Vehicle local response falls
0.9861→0.9847; dark metal 0.7546→0.7538; dark shelf 0.6286→0.6278. Arc cloud
visible separation falls 5.5809→5.5469, and selected halo separation
20.4715→20.4495. These small costs remain. White-core separation increases
5.8347→5.8589, retaining the preceding highlight cooperation; red-lamp
separation increases 18.4902→18.5156. Vivid blue sky/field changes remain small
and source-dependent, without a general palette-fidelity claim.

All seven selected held pairs are exact. No selected real case adds black or
code-255 channel pixels. Maximum channel changes are 13 interior/bedroom,
5 GZW daylight/dark, 17 Arc daylight, 8 emitters and 8 vivid. Strongest local
changes need native inspection; an average delta alone is not acceptance.

## Boundary and gradient costs

The same native constant-color fixture is evaluated under both profiles.
All 18 selected median edge-minus-far L and C gaps are zero. The largest growth
of block-averaged interior L95−L5 spread is about 0.00233 L. This is a scoped
boundary observation, not universal halo freedom. Both profiles retain the
original native observation and relative Retinex correction.

Two hue/brightness charts add no black or code-255 channel samples and change
at most two codes. Averaging 32 rows, the largest source-selected adjacent-pair
DE growth is about 0.04231 Arc / 0.05177 GZW; largest row-p99 growth is about
0.00798 / 0.00595. These are finite quantization costs. Chart observations are
single baseline/candidate captures, without a chart-repeat or improved-banding
claim. Output dither is unchanged. Tonal-strength-zero pairs are exact under
both profiles. The older GZW FilmCurve-zero one-pixel/one-code observation is
not re-tested or claimed repaired here.

## GPU and temporal evidence

Two explicit 256-point GPU readbacks observe each helper's 25 native guide
samples and the tonal scalar reconstruction. An independent weighted-window
reference agrees within 0.000002373 stops; scalar detail recomposition agrees
within 0.000000417 linear Y. These are explicit RGBA32F diagnostic outputs;
ordinary screenshots contain no hidden state telemetry.

Four independent private replays provide 192 exact selected/ordinary extraction
controls at measured source/token/source-update/cut-update identities. The
common mask retains 12,984 samples after excluding borders, the marker and both
atlas-tag footprints. Appended pose 2220 is excluded. Each replay covers 24
night updates, 20 return updates and four daylight updates at poses 1428/1432.

Across-run temporal repeats reach one code, with maximum mean repeat change
about 0.02635 DE Arc / 0.01153 GZW; the corresponding baseline variation is
about 0.02630 / 0.01144. Small night-step growth remains: first-run maxima
0.119499→0.119797 GZW and 0.119870→0.119884 Arc. Return/daylight maxima change
slightly in either direction. These observations support the measured control
and bounded-cost claims, not a general transition improvement. The cached
source remains 15 unique poses/sec duplicated at 30 fps; dense native gameplay,
physical high-refresh behavior and GPU profiling remain unassessed.

## Rejected representations and retained failures

The initial coarse range-mean base restores more local response but creates up
to about 0.89 L of false edge shading. Median/residual reconstruction and
continuous overlapping-window variants reduce that error but retain problems
from mixing source materials before upsampling. Hard nearest-window selection
also has a tie discontinuity and is rejected. A full-resolution version without
source range rejection restores material detail but changes thin bright
features by up to 125/164 codes in the interior/bedroom views. Those candidates
are not production and their larger gains must not be attributed to the
selected guarded version.

The original vivid baseline pair differs in 78 pixels, maximum 16 codes. A
refresh was initially mislabeled: its `baseline_refresh` prefix accidentally
selected the rejected coarse prototype. That pair is retained as
`mistaken_coarse_refresh` and excluded from baseline claims. A separate capture
uses the explicitly preserved original shader; its reference pair is exact.
The final audit verifies normalized baseline shader bodies independently of
labels. The original failure remains in `vivid_baseline_variation.json`; no
general stability repair is inferred from the corrected pair.

## Activation, scope and artifacts

Both actual configs' full/repeat outputs match the selected candidate exactly:
four exact matches. The final audit verifies 307 files and 652 images,
including rejected representations. There are 70 fresh completed private GPU
processes and ten verified reused baseline processes, all with zero dropped/
delayed frames. This count includes the retained erroneous refresh, which has
no baseline role. All 22 diagnostic tooling tests and whitespace checks pass.

Static captures use fresh processes, five seconds compile wait and twenty
seconds continuous settling. Warmup is not universal convergence proof. Only
the shared grade body/helper changes; all other production dependencies and
both active-config hashes match the initial scope. Current initial/final hashes
are in `captures/tonal_base_20261102/verification.json`. The source estimate adds
texture reads; zero drops at the tested 30 fps do not establish its cost in
actual games or at higher resolutions/rates. Profiling remains deferred.

The finite model decision is closed. At its implementation checkpoint, ratings
were carried forward. The subsequent user-requested [ratings review](2026-11-02_effect_ratings.md)
estimates chain/grade at 78 and the joint tonal model at 80, with individual
rows retained. No mandatory parameter screen or repair follows. The user also
authorized committing and pushing the completed work; use git tracking for
publication state. Captures, scripts, copied
configs and review media remain ignored local artifacts.

- [Interactive source/previous/selected review](../captures/tonal_base_20261102/review.html).
- [Current verification](../captures/tonal_base_20261102/verification.json).
- [GPU reference observations](../captures/tonal_base_20261102/probe_report.json).
- [Measured motion](../captures/tonal_base_20261102/motion_metrics.json).
