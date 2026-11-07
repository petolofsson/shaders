# Temporal shadow evidence: conditional benefit, no runtime candidate

The user asked to continue the temporal-persistence lead. Four correctly aligned
observations distinguish changing noise from persistent material structure in
controlled tests. An ideal-alignment scalar benchmark recovers **13.30%** of its
selected absolute shadow gap while adding approximately **3.3–3.5%** changing-noise
standard deviation. It preserves mean code brightness, not linear luminance or
perceived density. This is conditional mechanism evidence, not a native material
improvement or a new full-chain brightness candidate.

The tested RGB block correspondence is insufficient on the cached moving scene.
Even an exhaustive reference retains few usable samples; persistent surface grain
receives no temporal rejection. No GPU implementation, adoption or rating increase
follows. Brightness remains ~45, color ~70–75 and unadopted; production ratings
retain their earlier scope.

## Research and test limits

[Kong, Gehler and Black](https://files.is.tue.mpg.de/nkong/eccv2014/IntrinsicVideo.pdf)
use temporal albedo/shading assumptions, optical flow, occlusion and boundary
information for intrinsic video decomposition. Their
[supplement](https://files.is.tue.mpg.de/nkong/eccv2014/IntrinsicVideo_supp_lowres.pdf)
describes the correspondence/decomposition evaluation. Neither their intrinsic
solver nor their optical-flow method is reproduced here. Our narrower inference
is that aligned repeated observations can add evidence unavailable in a single
RGB frame; this does not separate persistent nuisance from persistent shading.

All new work is CPU-only. There are three distinct evidence scopes:

1. Preserved post-inverse source floats from wall/metal/held timber, cropped to
   256². Generate four integer-translated views at `(y,x)=(t,2t)` with known
   correspondence and synthetic unit-code noise. Interior masks exclude wrapping.
   These are transformed stills, not independently captured game motion.
2. Sixteen **distinct** cached Babylon poses across forest, clearing, corridor
   and the night cut. Use native 512² crops, raw-source code-Y and optional added
   synthetic unit-code noise. This is synthetic-scene motion, with no ground-truth
   flow, game-noise measurement or shader-history readback. Source sampling is
   15 poses/sec; duplicated 30-fps playback is not additional evidence.
3. A scalar affine black-mapping benchmark with ideal aligned observations.
   This is not the full grade, material RGB or a captured output comparison.

The source manifest, original 629-MB clip, scene/HTML and all selected PNG hashes
are verified. Poses stop at 1600; the appended pose-2220 tail is not used. Crops
exclude identity/calibration strips. All three material arrays match frozen
metadata. No old capture generator runs or imports.

## Known motion versus estimated motion

Four-observation averaging with exact alignment reduces changing white/grain
error from roughly one code RMSE to .496–.511 codes across the three materials.
Surface-locked longer grain and identical frozen noisy frames remain unchanged.
Repeated stills therefore cannot validate the desired temporal distinction.

The first estimator uses 16² blocks, quarter-resolution ±4 search followed by
full-resolution ±3 refinement, for a maximum ±19-pixel range. It samples block
cost sparsely, tests forward/backward agreement within one pixel and block RMSE
within two codes, and averages only accepted history plus the current sample.
Those fixed criteria are an exploratory correspondence rule, not a calibrated
confidence/noise model.

Two failures are retained separately:

- Block-only acceptance misses per-pixel boundaries: the noisy forest mean has
  **1.415-code RMSE**, worse than its .998-code noisy current frame. Clearing and
  night likewise worsen. These are source-reconstruction errors on known added
  noise, not shader temporal repeats or proof that all differences are ghosting.
- An independent fine random-texture translation control recovers the exact
  one-by-two-pixel displacement at only **37%** of evaluated pixels. The original
  `>95%` assertion fails. Keep `audit_initial_failed.py` and
  `audit_initial_failure.json`; the coarse model is not a passing motion contract.

Add one explicit **three-code per-pixel residual guard**, retaining all other
settings and exactly the same seeds. It removes large mismatch tails, but leaves
only 1.05–1.30 usable samples on average in the moving-scene tests. Its threshold
is specific to these unit-code noise controls, not a real-game noise estimate.
No threshold is relaxed to increase coverage.

An exhaustive reference then searches the same ±19 range using every pixel in
each 16² block, with the same forward/backward, block and point gates. It achieves
100% correct motion on the failed translation control. Dense cost and exhaustive
search change together; these results do not isolate their separate contributions.
This reference is computational machinery for diagnosis, not a proposed shader.

| Moving source crop | Noisy current RMSE | Exhaustive temporal RMSE | Mean samples |
| --- | ---: | ---: | ---: |
| Forest | .998 | .959 | 1.251 |
| Clearing | 1.003 | .946 | 1.366 |
| Corridor | .998 | .972 | 1.167 |
| Night-cut window | 1.005 | .992 | 1.073 |

In translated material controls, exhaustive reconstruction instead reaches
.562–.575 white-noise RMSE and .609–.731 changing-grain RMSE, with 3.04–3.90
samples on average. It is useful in that restricted translation setting; its
native moving-scene return remains small. Increasing search radius, changing
block sizes or dropping correspondence gates is not justified by these results.
For the cut window, both pre-night histories are rejected on the evaluated mask;
this single source-window result is not an adopted GPU scene-cut policy.

## Explicit range benchmark under ideal alignment

For known scalar source code `s`, use the configured affine black stage
`f(s)=255*sRGBEncode(.9925*sRGBDecode(s/255)+.0025)`. Let `z` be the average of
four ideally aligned source observations. Use:

```text
d = z − f(z)
p = sum(g*d) / sum(g)
delta = .5*g*(d−p)
result = f(s) + delta
```

The smooth current-source gate `g` rises over codes 4–12 and fades over 64–96.
A common scalar reduction caps the whole correction at two codes and SDR
headroom, retaining zero weighted correction sum. This redistributes code range
around a weighted pivot: positive corrections are paid for by negative ones.
It is not auto-exposure or a claim of unchanged linear-Y/perceptual means. The
frame-wide reduction and motion/history inputs have no implemented runtime path.

On a clean code-16, amplitude-three, period-64 field, mean signed four-pixel code
gap changes **.602032→.682096**, or +13.30%; relative log gap changes
.059039→.066945 stops. Mean code correction is below 2e-16 and maximum correction
.329 code. These small absolute changes do not establish a naked-eye improvement.

Measure noise against each method’s enhanced clean counterpart, so recovered
shading is not counted as noise. Instantaneous residual restoration adds
13.25%/13.36% white/changing-grain std; ideal temporal restoration adds
**3.47%/3.33%**. Surface-locked grain still adds **13.45%**, exactly matching the
instantaneous method. This is one seeded scalar benchmark per condition, not
universal noise acceptance or a candidate ranking against earlier GPU outputs.

Noiseless source black/white get zero correction. Tested black and shadow steps
have no reversing rows; random range controls retain SDR bounds and mean code
balance. The baseline black code is 8.2365 because this affine model deliberately
contains the profile’s black offset. These limited controls do not validate noisy
occlusions, chroma, full-grade boundaries, arbitrary ordering or moving lights.

## Decision and next requirement

Temporal evidence remains a **conditional lead**, not a selected implementation.
It buys a signal/noise distinction when changing observations can be aligned;
the tested economical correspondence loses that advantage on moving geometry,
and even the exhaustive block reference gives little native-scene benefit.
Persistent nuisance remains fundamentally outside this distinction.

Do not port this block matcher, restore runtime denoising, add temporal resources,
or adopt the brightness benchmark. The existing eight-pass chain has no exported
motion/depth input, and storing/aliging observations plus obtaining the pivot is
not free reuse of its scalar histories. A future motion path needs independent
evidence, not another parameter sweep justified by the ideal result.

Before revisiting runtime, require a representative changing game-source sequence
with native material/noise/occlusion coverage and a credible correspondence path.
Establish whether the nuisance actually varies in time, how much stable material
support survives, and whether the final range allocation gives visible native
benefit. More repeated stills, sparse Babylon poses or synthetic noise alone
cannot establish those properties. No new recording or GPU campaign is started
merely to validate this weak block model.

Artifacts: `captures/shadow_temporal_support_20261106/` contains the standalone
models, failed audit, corrected audit, separated reports, exhaustive reference,
scalar budget, native scalar previews, arrays and manifest. Warp sampling matches
independent enumeration; exhaustive known translation and frozen-source identity
pass. All 17 production/include/profile/config identities remain unchanged.
No measured GPU phase, dense gameplay, performance, full-chain effectiveness,
adoption, commit or push is claimed.
