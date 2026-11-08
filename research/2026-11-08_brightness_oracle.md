# SDR-to-SDR brightness oracle

After shadow detection was closed, the user asked for a brightness oracle that
respects the SDR-to-SDR constraint: every variant starts from the same 8-bit
frame, and nothing is recovered from HDR. [`tools/brightness_oracle.py`](../tools/brightness_oracle.py)
reuses the [shadow oracle renderer](2026-11-08_shadow_oracle_scene.md), now
parametrized by scene (daylight output verified byte-identical after the
refactor). Review: `captures/brightness_oracle_20261108/review.html`.

## Scenes and source

- **daylight:** the shadow-oracle scene (exposure 1).
- **interior:** a 6×8×3 m room with a west window (sky plus a sun patch on the
  floor), warm timber shelf, gray metal cabinet, blue pack, beige crate, dark
  leather box, a table with a dark box beneath, and a dark rug in the sun patch.
  Blocked hemisphere samples return a fill radiance that falls off with distance
  from the window and sun patch: a one-bounce stand-in, not global illumination.
  Exposure 5.

Both use per-channel ACES, 0.8-code Gaussian noise before 8-bit sRGB
quantization, 1280×720, 16 sun / 96 sky samples, seed 7 (3.5 min CPU). Tool
SHA-256 at run time differs from the committed caption fix; renderer
`d8aff3b71a120e7ba888fbeb661861d1e77756f0e15b10d6de5514451ddf3b18`.

## Variants

One tonal-allocation curve in stops: +.6 stop over the partial-shadow band
(display-linear ≈.02–.05, fading out by .004 and .3), −.4 stop below ≈.0015–.006,
zero for lit levels; black maps to black. Gain is applied to RGB with a
hue-preserving ceiling.

- **global:** curve evaluated on the pixel's own display luminance.
- **oracle:** the same curve evaluated on the display luminance the scene's
  median material would have under the pixel's exact illumination. Only this
  attribution uses ground truth; the pixel data and curve are shared.

## Results (mean gain in stops by region)

| Region | Daylight global | Daylight oracle | Interior global | Interior oracle |
| --- | ---: | ---: | ---: | ---: |
| lit dark material | +.51 | .00 | +.25 | .00 |
| partial shadow, bright material | +.54 | +.58 | +.41 | +.57 |
| partial shadow, dark material | −.38 | +.58 | −.40 | +.43 |
| deep occlusion | −.35 | −.36 | — (none) | — |
| lit bright | +.04 | .00 | .00 | .00 |

Observations:

- The global curve lifts dark materials in light (asphalt, dark red, rug) and
  **deepens dark materials in partial shade** (shadowed dark block, dark box,
  dark timber), crushing exactly the subtle dark shades GOAL asks to preserve.
- Its gain varies pixel by pixel with texture (grout, plank seams), changing
  material texture contrast; the oracle gain map is smooth and lighting-shaped,
  so material ratios are kept.
- The oracle lifts the whole shadowed region uniformly, keeps asphalt and the
  lit dark materials dark, makes shadowed dark materials readable, and deepens
  only the shelter interior.
- In the interior the overall brightness of both is similar; differences show
  mostly on dark objects (shelf, table, dark box), where the oracle keeps them
  readable.

## Interpretation and production relation

With identical 8-bit pixels and an identical curve, attributing the gain to
light rather than to pixel luminance avoids the main failure modes in both
scenes. The lever is the light/material split, not recovered information.

Production lift does not use raw pixel luminance: `ApplyTonal` evaluates it on
the shared tonal base `luma × exp2(illumination_log − native_log)`, a guided
log-luminance illumination estimate. Production therefore already sits between
the two variants. The next question is how close that estimate is to the
oracle: a CPU equivalent of the production base on these frames would show
whether large dark materials (asphalt, rug) leak into it and receive lift.

Limits: two synthetic scenes, an approximate bounce model, one curve chosen
before the run (no sweep), no production grade chain, stills only, no motion
or real game frames. Visual quality is the user's judgment.

## Production-base comparison

A CPU replica of `TonalIlluminationLog` (5×5 taps at 8-px stride, range weight
`1 − smoothstep(.5,1,|Δlog|)`, center/quadrant selection; tests pin flat-field
identity, 4-stop edge isolation and texture smoothing) supplies a third
attribution, `production`: the same curve on `luma × exp2(base − native)`.
Run: `captures/brightness_oracle_prod_20261108/` (same scenes and seed; the
oracle images are byte-identical to the first run). Retinex/zone/lift stages
and production's own lift curve are not applied; this isolates attribution.

| Metric (stops, surfaces) | Daylight global | production | oracle | Interior global | production | oracle |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| mean abs. error vs oracle gain | .212 | .212 | 0 | .181 | .181 | 0 |
| gain roughness (abs. dev. from 9×9 mean) | .021 | .016 | .006 | .028 | .020 | .010 |
| lit dark material | +.51 | +.52 | .00 | +.25 | +.25 | .00 |
| partial shadow, dark material | −.37 | −.37 | +.58 | −.40 | −.40 | +.43 |

The production base removes about a quarter of the texture-scale gain variation
but attributes light exactly like the global curve: its range weight stops at
material edges, so a large dark material becomes its own "dark light". The gap
to the oracle is the separation of large-scale material from lighting, which a
range-limited local average cannot provide. A candidate must cross material
edges while respecting lighting edges; established single-image intrinsic or
gradient-classification (Retinex) methods are the next thing to screen on these
frames before any shader work.
