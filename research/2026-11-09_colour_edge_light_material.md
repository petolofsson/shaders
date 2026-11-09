# Colour edges for light/material separation (2026-11-09)

The user asked to improve light/shadow detection: "if there is extremely differing
colors, that's probably an edge", even when both sides are lit. Production's
illumination estimate (the R190 guided filter, `grade.fx:1134`) and the zone
weights (`common.fxh:244`) use luminance only. So a brightness step between two
differently coloured materials is treated like a shadow edge, and a large dark
material becomes its own "dark light". This reopens the brightness-recovery work
closed on 2026-11-08, at the user's request.

## Prior result

The [Retinex screen](2026-11-08_retinex_light_screen.md) tested the classic
chromaticity rule (Funt, Drew & Brockington 1992): an edge with a colour change
is a material edge. It was the only rule better than production on the balanced
metric (.252/.299 vs .316/.313 stops), but blue skylit shade changes colour too,
so the rule discarded real shadow edges and lifted lit areas.

## Research

- **Illuminant-invariant chromaticity** ([Finlayson, Hordley, Lu & Drew, PAMI
  2006](https://www2.cs.sfu.ca/research/groups/VML/pubs/drew-shadow_removal-PAMI06.pdf);
  [entropy version, Finlayson, Drew & Lu, IJCV 2009](https://www2.cs.sfu.ca/~mark/ftp/Ijcv09/ijcv09.pdf)).
  In log chromaticity (log R/G, log B/G), a change of light along the
  Planckian/daylight locus moves a pixel along one fixed direction e. Projecting
  orthogonal to e removes shadows, and edges that remain are material.
- **Sun/sky shadow physics** ([road shadow detection, Sensors
  2020](https://www.mdpi.com/1424-8220/20/4/1012); [what characterizes a shadow
  boundary under the sun and
  sky](https://www.researchgate.net/publication/221110234_What_characterizes_a_shadow_boundary_under_the_sun_and_sky)).
  Shade is lit only by the sky, so a shadow edge is darker and bluer together, and
  R and G drop more than B.
- **Derivative classification** ([Tappen, Freeman & Adelson
  2005](https://people.csail.mit.edu/billf/publications/Recovering_Intrinsic_Images.pdf)).
  Each log-image derivative is labelled as shading or reflectance, and the
  shading derivatives are reintegrated.
- **Real-time intrinsic decomposition** ([Meka et al., Live Intrinsic Video,
  SIGGRAPH 2016](https://vcai.mpi-inf.mpg.de/projects/LiveIntrinsicVideo/)).
  It is GPU-feasible with a coarse-to-fine solver, but uses full optimization,
  far beyond this pipeline's pass budget.

## Screen

`tools/invariant_screen.py` extends `tools/retinex_screen.py` and uses the same
cached oracle frames and Poisson reintegration. Outputs are in
`captures/invariant_screen_20261109/` (run3 is final). Rules tested:
- **inv:** an edge is light if the invariant (orthogonal-to-e) change is below t.
  e comes from approximate sRGB blackbody colours (Planck), from the renderer's
  sun and sky (scene), or per frame by minimum entropy.
- **sky:** inv, plus the darker side must not be warmer, and the shift along e
  must be at most k per stop (+.03). Physics gives about .24 per stop for this
  renderer's sun→sky edge, and the cross-axis shift is .03.
- **auto:** the slope k is estimated per frame, as a stand-in for a GPU reduction.

The Planck direction (123°) matches the scene's true sun→sky direction (127°)
with no scene knowledge.

| Variant | Daylight balanced | Interior balanced | Notes |
| --- | ---: | ---: | --- |
| production | .316 | .313 | |
| chroma .15 (2026-11-08) | .252 | .299 | lifts lit bright (.37/.55) |
| inv Planck .05 | .275 | **.214** | |
| inv Planck .15 | .256 | .282 | |
| sky Planck .10, k .40 | **.182** | .345 | interior fill is warm: sign assumption fails |
| auto .10, slack .20 | .228 | .267 | slope estimate wrong (.013 vs .24 in daylight) |

Region errors, daylight, in stops:

| Region | Production | Sky rule |
| --- | ---: | ---: |
| shaded dark material | .95 | **.14** |
| lit bright | .04 | .06 |
| lit dark material | .52 | .52 |

**No colour rule fixes lit dark materials** (.5 stop, every variant). A black
object in sun next to a grey wall has no colour cue.

## Real frames

Panels are `edges_133058.png`, `edges_101035.png` and `edges_menu.png` (script
`edge_map.py`). Luminance edges are coloured red for material and cyan for light.
- **101035 (daylight cast shadows on paving).** The old rule marks the shadow
  edges as material; the invariant rule marks them as light. The sky rule marks
  most as light but some long shadow edges red.
- **133058 (shaded orange wall next to blue wall)**, the user's case. The
  invariant rule misses it, because orange↔blue lies along the daylight axis.
  The sky rule marks it as material: the darker side is warmer, which skylight
  cannot do. It also marks the wall vents, roof line and power lines (dark wire
  on bright sky) as material, which is correct.
- **Noise.** Paving and foliage texture produce speckle under the sky rule.

## Conclusions

1. The user's intuition is supported, with one physics correction: compare colour
   *across* the daylight axis, and require shadow edges to be darker-and-bluer.
2. The best daylight rule cuts the region-balanced error by 42%. Indoors under
   warm light it needs the plain invariant rule instead, so it needs a
   daylight/outdoor gate. The pipeline has illuminant estimates (`IllumWarm`,
   `NeutralIllum`), but such a gate is untested.
3. **Shader cost is the obstacle.** Every rule here needs gradient reintegration
   (Poisson). The GPU options are:
   - (a) a low-resolution multigrid of about 6–10 passes at 1/16–1/64 resolution;
   - (b) one or two Jacobi passes per frame with a history texture that converges
     over frames. This one is cheap, but it adds temporal lag and needs a
     scene-cut reset.
   A cheaper non-integrating use is to feed the edge class into the existing
   guided filter's ε, so smoothing crosses material edges and stops at light
   edges. That has not been screened.
4. Limits: two synthetic scenes and three real frames (visual only). The
   thresholds are untuned beyond this grid, and nothing was measured in the
   production chain.

## Follow-up: colour-aware tonal base (no reintegration) — negative

`tools/guided_screen.py` gives production's `TonalIlluminationLog` range weight
a soft per-pair colour classification. A material-looking step keeps full weight,
and a light-looking step keeps the .5–1 stop cutoff. 20 variants were tested:
chroma/inv/sky rules, stride 8/16, quadrant selection on or off. Output:
`captures/guided_screen_20261109/report.json`.

**Every variant is worse than production:** mean balanced error .322–.389 vs
.314. Daylight shaded dark material stays at .95 in all of them, and lit dark
material gets worse (interior .25 → .29–.60). The reasons:
- a ±16–32 px neighbourhood cannot carry shadow information far enough;
- averaging across a material edge mixes two materials' brightness instead of
  removing the material step.

The gain needs global propagation.

## Follow-up: reintegration at low resolution — positive

`captures/guided_screen_20261109/lowres.py` classifies and integrates on a
box-downsampled frame, then upsamples the light bilinearly. Balanced error:

| Rule, scene | Full | 1/4 | 1/8 | 1/16 |
| --- | ---: | ---: | ---: | ---: |
| sky .10, daylight (production .316) | .182 | .156 | .176 | .163 |
| inv .05, interior (production .313) | .214 | .212 | .205 | .214 |
| sky .10, interior | .345 | .355 | .353 | .351 |

At 1/16, daylight shaded dark material is .03 (production .95) and lit dark
material is .31 (production .52). The costs are deep occlusion .02 → .32 and lit
bright .04 → .13 in daylight, and lit dark material .25 → .60 in the interior.

**Shader route.** A Poisson solve at 1/16 resolution (160×90 at 1440p) is small.
Possible methods are a convolution pyramid ([Farbman, Fattal & Lischinski
2011](https://www.cs.huji.ac.il/labs/cglab/projects/convpyr/)), a short
multigrid V-cycle, or temporally accumulated Jacobi. Unresolved:
- choosing the rule (daylight sky rule vs indoor invariant rule; the
  automatic slope failed);
- the lit-dark-material and deep-occlusion regressions;
- the pass count against the GPU budget;
- the fact that production applies the light estimate through its own bounded
  lift, not this oracle curve.

## Follow-up: third light colour (bounce)

The user suggested a third colour between blue and yellow. Physically, shade is
lit by sky and by bounce light from nearby surfaces, which is often warm. That
explains the interior failure. Two free shade directions would explain any
chromaticity change, so the bounce direction is estimated per frame instead.
The shade direction b is the log-chroma of pixels at or below the median minus
that of the brightest 10%. `captures/guided_screen_20261109/three_colour.py`
reports to `three_colour.json`, with Poisson at 1/8 resolution.
- **shade:** the sky rule with e replaced by b.
- **three:** light if the edge passes the sky rule or the shade rule.

The estimated shade direction is 108° in daylight (true sky direction 123°) and
−49° in the interior (warm fill, opposite to sky).

| Rule | Daylight | Interior | Mean |
| --- | ---: | ---: | ---: |
| production | .316 | .313 | .315 |
| sky | .176 | .353 | .265 |
| shade | .233 | .181 | .207 |
| three | .238 | .180 | .209 |

The per-frame shade direction is the first single rule that improves both scenes
(−34% mean). Interior .18 is the best indoor result so far: shaded dark material
.13 and lit bright .04. In daylight it costs deep occlusion (.57; sky rule .25,
production .02). The 15° direction error probably makes some sky-shadow edges
read as material. It is GPU-friendly: b is two means from an existing statistics
pass.

## Follow-up: more light colours (4–12) and local colours

The user asked whether a 4th or 5th colour would help. Extra directions are
k-means clusters of shade-pixel chromaticity, each taken relative to the
brightest 10%, added to sky and frame shade.
- **Local:** one shade direction per G×G region.
- Scripts: `multi_colour.py`, `multi_seeds.py` and `multi_real.py`, with
  `multi_real.png`, in `captures/guided_screen_20261109/`.

| Colours | Daylight balanced (3 seeds) | Interior | Mean |
| ---: | --- | --- | ---: |
| 3 | .235 | .179 | .207 |
| 4 | .210–.235 | .173 | .196 |
| 5 | .192–.224 | .163–.172 | .188 |
| 8 | .181–.199 | .162 | .176 |
| 12 | .186–.189 | .162 | .175 |

Local regions (2×2 to 4×4) score .345–.374 in daylight, worse than production:
a region's shade colour is often a material colour.

**Synthetic gains do not transfer cleanly.** The synthetic scenes have few
material colours. On real frames, each added colour accepts more material edges
as light:

| Colours | 133058 material edges | Orange/blue wall boundary marked material | 101035 material edges |
| ---: | ---: | ---: | ---: |
| 1 | 48% | 81% | 74% |
| 3 | 25% | 65% | 45% |
| 5 | 22% | 61% | 26% |
| 8 | 19% | 55% | 23% |

In 101035, more colours correctly turn the cast shadows and paving texture into
light edges. By 8 colours, though, the power lines (dark wire on sky) and some
foliage edges also read as light. A plausible compromise is 3–5 colours, but it
is not established: there is no truth on real frames, and the synthetic set is
two scenes.

## Step 2: extended scene set and production's own lift

The user asked for this before any shader work. Code: `tools/oracle_scenes.py`
adds five scenes with coloured one-bounce fill (blockers radiate their own
albedo):
- colourful noon, with an orange box touching a blue box, both in shade and in
  sun;
- golden hour (low warm sun);
- overcast;
- green canopy shade;
- a warm-lamp interior with an orange sofa touching a blue locker.

`tools/colour_edge_eval.py` writes `captures/colour_edge_eval_20261109/report.json`.
Every method runs at 1/8 resolution with Poisson, on all 7 scenes, scored under
two curves:
- the idealised oracle curve;
- **production's shadow lift**, log2(1 + P·.1875·smoothstep(.35, 0, base))
  (`grade.fx:727–731`), with P = 1 because the GPU scene statistics are not
  replicated.

The error is |curve(estimate) − curve(true light)|, region-balanced. The new
scenes have few dark materials, so the dark-material regions are thin there.

| Mean of 7 scenes | production | inv | sky | shade1 | col3 | col4 | col5 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Oracle curve | .293 | .217 | .242 | .214 | .178 | .171 | **.162** |
| Wins vs production (oracle) | – | 7 | 5 | 6 | 7 | 7 | 7 |
| Production lift | **.039** | .061 | .072 | .063 | .047 | .046 | .045 |
| Wins vs production (lift) | – | 1 | 1 | 0 | 2 | 2 | 1 |

**Anchor check** (`anchor.py`): offsetting the estimates to match pixel log
luminance at p50, p75 or p90 leaves col4 at .046 under the production lift.
Production stays best.

**Interpretation.** The colour-edge estimates are much closer to the true light
(oracle curve −45%, winning all 7 scenes, including warm and coloured bounce).
Production's lift is gentle and broad (at most about +.25 stop at P = 1,
smoothstep over base 0–.35), though. Through it, every estimate is within
.03–.08 stop of the true-light lift, below visibility, and production's own base
is marginally closest. **A better light estimate would not visibly change
today's lift.** It pays off only with a stronger, more light-selective tonal
treatment (such as lifting shaded areas and leaving lit dark materials alone).
That would be a look change and needs the user's decision.

Recommendation: do not build the shader for the current lift. Keep col4 (sky +
frame shade + 2 k-means directions, Poisson at 1/8–1/16) as the light estimator
for any future light-selective treatment.

## Mock-ups: stronger light-selective lift

The user decided the estimator should not be parked if it gives a significant
improvement. A stronger treatment was therefore mocked up: the lift-only part of
the oracle curve, up to +.6 stop in the partial-shadow band, with no deepen.
It is driven by production's estimate, by col4, and on synthetic scenes by the
true light. Review: `captures/colour_edge_eval_20261109/review/review.html`
(script `make_review.py`, 7 synthetic scenes and 3 game frames).

Error against the true-light version, in stops, region-balanced:

| Scene | Production estimate | col4 |
| --- | ---: | ---: |
| daylight | .238 | .153 |
| interior | .209 | .172 |
| colourful noon | .104 | .042 |
| golden hour | .236 | .281 |
| overcast | .284 | .193 |
| canopy shade | .216 | .124 |
| lamp interior | .181 | .163 |
| **mean** | **.210** | **.161** (−23%) |

col4 wins in 6 of 7 scenes and loses in golden hour, where most of the frame is
low-sun shade. Visually, in synthetic daylight, the shaded boxes are lifted
closer to the true-light result. On game frames the difference is visible but
subtle, and there is no truth.

## Edge-aware upsampling

The user found the colour-edge light map blurry and asked whether 16-bit would
help. Bit depth is not the cause: the pipeline's intermediates are already 16F
and 32F, and quantization bands rather than blurs. The blur comes from the 1/8
solve being upsampled bilinearly. `colour_edge_eval.up_jbu` replaces that with
joint bilateral upsampling ([Kopf et al.
2007](https://johanneskopf.de/publications/jbu/)):
- a 4×4 grid of low-res samples per full-res pixel;
- weights from spatial distance (σ 1 low-res texel), log2 luminance (σ .35)
  and log chromaticity (σ .08), comparing the full-res pixel with the downsampled
  source.

Stronger-lift error against true light (mean of 7): col4 bilinear .161,
edge-aware .157, production .209. It wins in 5 of 7 scenes against bilinear.
Golden hour is unchanged at .282.

Visually, the light map follows object and shadow edges at full resolution
(review regenerated). Shader cost: one full-resolution pass with 16 taps of the
1/8 light plus the 1/8 guide. The existing highway spatial lane already holds the
low-res colour.

## Continued: shader candidate

The shader candidate, its failures on game frames and the v3 material-veto
estimate the user accepted are in the
[light lift candidate report](2026-11-09_light_lift_candidate.md).
