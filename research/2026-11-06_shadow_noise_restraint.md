# Noise restraint for combined shadow reconstruction

The user requested continuing the combined brightness/color work and reducing
synthetic noise. Two fixed CPU model revisions substantially reduce the previous
brightness-noise amplification. Neither is ready for a shader port: the first
assumes independent noise, while the conservative version loses much of the
useful shading response. Step rims and some material shade reversals remain.
Production, profiles, configs and ratings are unchanged.

## Mechanism and scope

Reuse the [dense same-update GPU inputs](2026-11-06_shadow_dense_brightness.md)
without new runtime captures. Noise restraint multiplies only the proposed
brightness detail increments; it does not denoise or blur the existing output.
The half-color helper and its approximately 24% synthetic chromatic-noise cost
are unchanged. No new shader, resource, pass, history or user control is added.

The source log-luminance noise estimate uses a unit-energy 2×2 Haar diagonal,
local 9×9 median absolute magnitude divided by 0.67448975 (Gaussian MAD
calibration), and smoothing of its squared value. The independent-noise model
propagates that variance through exact squared-energy analysis kernels for all
four levels and four pyramid phases. Local band energy E and predicted noise N
give confidence `saturate((E-N)/max(E,1e-12))`, applied to the original
source-capped proposed increment. The remaining reconstruction, source gate,
RGB-ratio preservation and SDR headroom limit are unchanged.

This is an enhancement-confidence model, not an implementation of BayesShrink.
Adaptive noise-aware shrinkage has an established research basis, for example
Chang, Yu and Vetterli's [adaptive wavelet thresholding paper](https://graphsearch.epfl.ch/en/publication/7d413357-9bf7-4bdb-971c-57e0b1197bfa).
That paper does not validate this estimator or this SDR application. In
particular, a local diagonal statistic cannot establish whether game detail is
noise or intentional texture, and the Gaussian/independence assumptions are
limited.

A correlated-noise stress exposes that limit. A second fixed model therefore
adds conservative uncertainty within each source band: subtract its local
median, estimate the residual's local MAD variance, and take the maximum of
that estimate and the propagated independent-noise variance before confidence
calculation. This can count irregular material texture and shading as noise.
No strength, window-size or threshold sweep was performed.

## Same dense materials and noise patch

All percentages below compare combined output with **color-only**, keeping the
color contribution fixed. The previous report compared combined with current;
small numerical differences follow from that denominator choice. Noise is
continuous sRGB-code-equivalent luminance standard deviation on the same 64×64
center of the RGB code-16 ±1 fixture. The gap metric uses the same larger dense
material crops, source masks and overlapping 4-pixel pairs as the previous
report; it is not a quality score.

| Reference | Noise std | Noise increase | Wall gap gain | Metal gap gain | Timber gap gain |
| --- | ---: | ---: | ---: | ---: | ---: |
| Color-only | 0.472097 | — | — | — | — |
| Previous combined | 0.654114 | +38.6% | +9.9% | +15.3% | +18.6% |
| Independent-noise restraint | 0.483547 | +2.4% | +6.5% | +10.9% | +14.9% |
| Conservative band restraint | 0.473019 | +0.2% | +1.9% | +4.3% | +3.4% |

The first model removes approximately 94% of the previous *added standard
deviation*, preserving about 66–80% of its selected extra material response.
The conservative version removes about 99.5% of that added standard deviation
but retains only about 18–28% of the selected extra response. These percentages
describe this fixture and selected materials, not generalized noise removal.
Source noise std is 0.610043; both revised results remain below it here.

At 4 pixels, color-only → first → conservative reversal counts are wall
47→54→47, metal 301→450→351, timber 6→68→25. At 16 pixels timber is
16→515→119, versus 930 previously. Thus reduced noise does not establish
gradient-order preservation. Mean material L shifts are small, but native
previews do not establish a clear overall dimensional improvement; the more
conservative version has particularly subtle brightness impact.

## Controls and limitations

- Unit Gaussian noise gives estimated sigma 1.0042. Empirical-to-predicted
  phase-kernel energy ratios are 0.93–1.01 in one seeded 1024×1024 realization;
  finite coarse-level sample variation remains. This checks propagation, not
  game-noise calibration.
- Separate scalar controls use the configured affine black mapping, rather
  than the complete grade. For independent gray ±1/±3/±6-code noise, added std
  falls from approximately 46%/32%/14% previously to 7.2%/2.5%/1.0% with the
  first model, or 0.32%/0.20%/0.12% conservatively. These differ from the RGB
  fixture because the channels are correlated and the complete chain is absent.
- On blurred correlated grain, std amplification is 44.6% previous, 42.1%
  first, 7.3% conservative. On vertical banding it is 41.7% previous/first and
  10.1% conservative. The first model's excellent independent-noise result
  therefore does not generalize to correlated noise. The conservative model
  also leaves nonzero amplification.
- A clean periodic shading signal retains its approximately 24% std gain with
  the first model; conservative restraint reduces that gain to about 8%.
  Averaged noisy-shading response is also retained more strongly by the first
  model. A linear ramp barely changes. Both models preserve the tested constant
  black/flat inputs, but neither fixes small/large/soft-step rims. The first
  small-step correction still reaches 0.034 stops; conservative reaches 0.031.
- Applying the first model to independent wall/metal readback repeats gives
  exact output. Timber/noise maximum output differences are about 9.97e-7 /
  3.77e-7 linear RGB, close to the recorded nonzero input variation. Do not
  label those pairs exact.
- A one-pixel still translation changes 3,202/3,395/2,534 of 102,400 interior
  wall/metal/timber pixels after approximate 8-bit rounding, at most one code.
  A 16-pixel shift is exact in these examples. This checks decimation phase
  sensitivity, not temporal gameplay stability. No motion claim or equivalent
  conservative-model stability claim follows.

The initial scalar-control run had float32 variance-of-constant reduction
roundoff; its script/result are retained as `controls_initial_float32.*`.
Controls above use explicit float64 scalar inputs. This correction does not
change the dense GPU-input measurements. All previews use approximate CPU
encoding/dither, not compiled brightness output or swapchain-transfer evidence.

## State and artifacts

`captures/shadow_noise_estimate_20261106/` preserves `model.py`, `model_band.py`,
both run generators, reports/arrays/native PNGs, scalar/correlation controls,
the first model's repeat/shift proxy and a native-size interactive
[review](../captures/shadow_noise_estimate_20261106/review.html).
`band_uncertainty/` holds the conservative model's separate outputs. The artifact
manifest and verification retain current source/profile/config identities and
all reused input identities. No new GPU process or active-config capture was
necessary for this offline screen.

Retain the first model as evidence that most independent-noise amplification
can be avoided without losing all selected material response, and the second
as evidence of the correlated-noise/shading tradeoff. Neither is an adoption
proposal or a justification for more automatic threshold tuning. The next
design problem is retaining supported coherent shading while constraining the
reconstructed boundaries and neighboring shades. Color-only validation does
not close that brightness problem. No implementation approval is requested.
