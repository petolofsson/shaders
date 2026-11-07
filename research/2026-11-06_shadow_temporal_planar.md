# Shared motion and subpixel temporal refinement

The user requested improving the temporal lead. Sharing a projective motion
model across image features improves reconstruction of the tested moving forest
and clearing crops. Subpixel refinement reduces fine-material alignment error;
limited synthetic occlusion/parallax controls retain conservative fallback.
This is useful CPU correspondence progress, **not** an implementation-ready
brightness effect or evidence that the 75-point goal is reached.

Persistent surface grain remains indistinguishable from stable material variation
under the tested temporal information. Ideal full-grade material previews show
modest selected separation gains. Production and all provisional ratings remain:
new brightness ~45, unadopted half-color ~70–75, carried chain/grade 78 and tonal 80.

## Change in representation

The [previous temporal screen](2026-11-06_shadow_temporal_support.md) required
each block to establish its own motion; flat regions often rejected nearly all
history. The new model estimates one shared homography from reliable image
features and validates history photometrically at each pixel. This tests motion
support across space, rather than relaxing a noise or correspondence threshold.

[Szeliski’s alignment tutorial](https://www.microsoft.com/en-us/research/publication/image-alignment-and-stitching-a-tutorial/)
explains parametric alignment and its parallax/scene-motion limitations.
[Brown, Szeliski and Winder](https://www.microsoft.com/en-us/research/publication/multi-image-matching-using-multi-scale-oriented-patches/)
use Harris-based features, normalized patches and robust geometric matching.
Our small single-scale, unoriented patch implementation is not their full method.
A homography is not an arbitrary-depth game-motion field; shared support can
increase reuse in flat regions while fitting the wrong surface elsewhere.

## Fixed models and matched data

All work is CPU-only. Reuse exactly the prior three 256² material source crops,
their synthetic translations/noise seeds, and sixteen distinct cached Babylon
poses with native 512² crops. Clip/manifest/scene/HTML/image identities and all
17 production identities match. Babylon remains synthetic geometry at 15 source
poses/sec, not dense gameplay. Noise is added continuously in scalar code-Y;
it is not a measured game-noise distribution. No fresh render or old generator runs.

Three corrected epochs are kept separately:

1. **Feature model:** minimum-eigenvalue corners, fixed code-gradient floor 1,
   at most 256 spatially separated features, normalized 9² descriptors, mutual
   ratio matches, 512 deterministic four-point RANSAC draws and a normalized DLT
   refit. Matches and warped pixels stay within the previous ±19 native pixels.
   Require eight inliers, .35 inlier fraction, 1.5-pixel reprojection support and
   feature span at least one quarter of each crop dimension.
2. **Subpixel refinement:** eight fixed robust Gauss–Newton iterations on lightly
   smoothed image observations within the inlier hull. Bound each iteration’s
   predicted corner displacement to one pixel; reject ill-conditioned fits.
   Warp original history with bilinear sampling; retain the original pixel as
   the current observation. Temporal estimates supply only the later correction.
3. **Local support:** use the same feature/refinement/photometric criteria, but
   replace the whole-crop span rule with reuse restricted to the convex hull of
   supporting inliers. This permits a small supported plane without extrapolating
   it across the rest of the crop. It is not inferred material segmentation.

All retain the two-code local RMS and three-code point residual limits. These
remain exploratory rules for the fixed unit-code noise tests, not calibrated
real-game confidence. Local RMS now uses a 7² neighborhood rather than the old
nonoverlapping 16² block; the model comparison changes that support as well as
correspondence. No parameter sweep or threshold relaxation selects a winner.

## Correspondence results

| Moving source | Prior exhaustive block RMSE | Refined shared model | Refined local support |
| --- | ---: | ---: | ---: |
| Forest | .959 | .847 | .922 |
| Clearing | .946 | .851 | .886 |
| Corridor | .972 | .998 | .977 |
| Night-cut window | .992 | 1.005 | .991 |

Values are code-Y reconstruction RMSE against the known unnoised current source,
after adding the same synthetic noise. The shared model improves forest/clearing
error **11.68%/10.13%** relative to the prior exhaustive block reference. Mean
samples rise to 1.50/1.50, versus 1.25/1.37. Shared motion rejects corridor/cut
models for insufficient spatial support and falls back to the noisy current
sample; local support instead retains only about 1.12/1.05 samples there.
There is no uniformly superior variant or general motion-accuracy claim.

In the known translated-material controls, subpixel refinement reduces clean
alignment RMSE under changing white noise from .285/.220/.294 codes to
**.039/.015/.029** on wall/metal/timber. Reconstruction RMSE becomes
.548/.561/.556 codes, with about 3.90 samples. Correlated changing grain gives
.726/.700/.670 codes and greater alignment error. Bilinear interpolation can
reduce noise by smoothing, so these totals alone are not proof of detail retention;
the separated clean-signal measurements are essential. Local hull support gives
up much of this reuse, especially on wall.

## Carry the estimate into the same range benchmark

Use the previous scalar affine black mapping and half-missing-contrast correction,
with its weighted zero mean, two-code cap and SDR bound. Change only the temporal
estimate. Existing current-pixel detail stays in the baseline term; the temporal
mean is not substituted for the output image. This remains a scalar stage
benchmark on transformed stills, not the full grade or real game motion.

| Translated source | Selected 4-px clean-component gap gain | Enhanced clean-reference error / noisy baseline error, changing white / grain |
| --- | ---: | ---: |
| Wall | 1.22% / 1.10% | 1.000 / 1.000 |
| Metal | 8.50% / 8.42% | .991 / 1.019 |
| Held timber | 9.78% / 9.66% | 1.032 / 1.046 |

Gap columns show white/grain contexts separately. Error ratios include temporal
alignment, nonlinear/gate response and noise; they are **not pure noise-std
amplification measurements**. Alignment-only brightness error versus the ideal
clean enhanced reference is approximately .001–.019 code across these cases.
Frozen noise and persistent grain retain essentially the instantaneous correction
cost: approximately +0.9% wall, +5.6% metal and +9.8% timber in these error ratios.
No universal acceptable-noise percentage is inferred.

## Ideal native full-grade bound

To check whether better motion could buy visible return, use preserved same-update
512² source/current/half-color floats. Under ideal correspondence, redistribute
half of source-minus-output code-Y residual around its source-gated weighted mean.
Retain the same two-code cap and use one common reduction for RGB-ray SDR
headroom, so the complete crop’s mean code Y is preserved. This is a best-case
still reference, not temporal validation or a general optimal bound.

Selected current-output four-pixel gap gains are **3.54% wall, 4.83% metal,
8.64% timber**; half-color outputs are nearly the same. The source gate and cap
restrain wall/metal more strongly. Target-region mean code Y still rises by
.052/.029/.039 code: zero whole-crop code mean does not fix every material mean,
linear luminance or perceived density. Maximum corrections are 2/2/.959 codes.
RGB stays within SDR, and zero-gate error is only floating roundoff.

Native approximate RGB previews show a modest timber shading/texture change,
with less clear wall/metal benefit. They do not establish a clear cross-material
appearance improvement or a rating increase. Previews are CPU encodings without
added dither, not compiled shader screenshots. This residual transfer has not
been validated at full-scene boundaries, in moving RGB, across profiles or through
the ordinary output quantization path. Do not promote it solely from gap percentages.

## Persistent-grain budget and adversarial checks

Stable surface grain and intentional stable material variation can produce
exactly the same observed sequence. The input-equality control is exact; temporal
stability cannot certify that variation is useful shading.

At source code 16, local affine-stage derivatives are A=.79117 for the baseline
and B=.10441 for the half residual correction. For unit marginal noise variance,
let c be covariance of current noise with its four-frame mean, and v the mean’s
variance. The local enhancement noise-std ratio is

```text
sqrt(1 + 2*(B/A)*c + (B/A)^2*v)
```

Ideal independent observations predict **1.0346**; AR(1) correlation .9 predicts
**1.1146**; persistent noise gives **1.1320**, the instantaneous worst case.
Seeded Monte Carlo checks agree. This is a local scalar linearization, not a
game-noise estimator or a global guarantee for the nonlinear gated result.
It explains why the earlier 3–3.5% noise figure cannot be assumed when samples
remain correlated. The two-code amplitude budget does not remove this cost.

Additional fixed synthetic stresses use the held timber source: a moving
occluder, two independently moving half-planes, changing illumination, unrelated
cuts and a new thin bright feature. The refined shared reconstruction has
.560/.826/~1.002/.994/.571-code RMSE respectively; fallback, not recovery,
explains the illumination/cut cases. The tested new bright feature gets zero
brightness correction. These limited controls are not measured game motion,
universal disocclusion safety or dense temporal acceptance.

## Preserved failures and decision

`initial_unclamped/` preserves the initial model/report/arrays and square-root
warning. Integral subtraction can produce a slightly negative near-zero local
squared residual; the corrected reference clamps that variance to zero before
sqrt. This numerical fix changes some acceptance values and is not a noise-gate
relaxation. Use only corrected reports for the table above.

An initial audit also incorrectly required machine-precision image-feature
localization. It failed at .0513 pixel before refinement; refinement reaches
.0139 pixel. The failed script and values remain. Exact DLT fitting and bilinear
sampling have independent numerical tests; image-feature correspondence is checked
as subpixel and improved by refinement. No matching thresholds changed to pass it.

Retain shared subpixel motion as a **conditional CPU lead**. It is stronger than
independent blocks in the tested forest/clearing inputs, and the material stage
benchmark now uses estimated rather than ideal motion. Local support remains a
separate conservative tradeoff. Neither supplies reliable arbitrary-depth motion
or distinguishes persistent grain. Do not port the feature/RANSAC/Gauss–Newton
reference, add runtime resources or adopt the residual correction on this evidence.

Next progress needs representative changing game-source material/noise coverage,
a credible bounded motion producer, and worthwhile native full-chain appearance.
The feature fit itself has no implementation path in the current eight-pass HLSL
chain. Further matcher/gain sweeps or another GPU campaign are not justified merely
by these CPU improvements. No data recording, adoption question or publication
is pending.

Artifacts: `captures/shadow_temporal_planar_20261106/` contains corrected and failed
epochs, refined-global/local reports, the material brightness benchmark, ideal
native comparisons, correlation analysis, controls and verification. The audit
checks **158 new artifacts**, all **65 prior temporal artifacts**, matched input
identities/seeds and all **17 unchanged production identities**. No new GPU,
profiling, actual-config, shader/profile/config/header/history/resource/pass,
adoption, commit or push changes follow.
