# Shadow tint shader candidate

This is the shader version of the accepted [shadow tint mockup](2026-11-08_shadow_tint_mockups.md)
look (v9, strength 1.0). It is an isolated copy of current `general/`, including
the uncommitted [review fixes](2026-11-08_ultrareview_fixes.md). Artifacts are in
`captures/shadow_tint_candidate_20261108/`:
- `review.html`, `stills_report.json`;
- `noise/noise_report.json`, `transition/`;
- CPU references `reference.py` (per-pixel, superseded) and `reference_smooth.py`
  (shipped design).

Candidate grade SHA-256 `bab1bac786988326af97c58b17688ee51f9dc79526f4f339b37e3b7bd2db1cb9`.
Production grade (`36f44c14…f7180`), profiles and configs were hashed before and
after every run: unchanged.

## Implementation

Five low-resolution passes run before `ColorTransform`. All read the existing
1/8 spatial lane (linear source); there is no new full-resolution read.

| Pass | Size | Output |
| --- | --- | --- |
| TintGatherA | 1/16 | 2×2 lane mean of Oklab (a·ws, b·ws, L·ws, ws); ws excludes near-black and emitters/sky |
| TintGatherB | 1/16 | (luma·ws, luma·emitter) |
| TintEnvA | 1/16 | normalized Gaussian σ 3.46 texels (13×13) |
| TintEnvB | 1/16 | σ 3.46 surface luma; σ 4.90 emitter field (19×19) |
| TintRegion | 1/8 | lane (luma, Oklab a, b, L), Gaussian σ 1 (5×5) |

`ApplyShadowTint` runs on `lin` right after BLACKS/WHITES, before corrective.

**Shadow weight.** Weight = relative darkness (surface-only wide luma ÷ regional
luma) × not-bright region × not-near-black × a lit-spot guard. The guard fades
pixels 1–2 stops above their region.

**Colour step.** The Oklch+ step toward the surroundings' hue is evaluated on
the regional colour and added per pixel as an Oklab a,b offset. The saturation
cap is then .45·L or the original.

**Darkening.** The Fairchild–Pirrotta lightness is kept through an RGB gain from
the regional colour, clamped to .5–1. It fades out near emitters.

**Control.** `SHADOW_TINT_STRENGTH` defaults to 1.0 through `#ifndef`; it is not
in the profiles.

## Defects found and fixed during validation

1. **Lit spots.** Run 1 used per-pixel math without a lit-spot guard. Small bright
   features in dark regions (fire embers, Y .53 in a region at .07) received
   weight up to .83. The candidate repeats then differed by up to 28 codes in the
   fire scene (production: 2). The guard keeps 98.7–99.8% of the shadow weight in
   the mockup scenes. Outputs are in `stills_run1/`; run 2 was stopped and is in
   `stills_run2_stopped/`, partial and superseded.
2. **Noise amplification.** On the CPU reference, the per-pixel Oklch+ step and
   H-K darkening amplified ±1-code chroma noise 1.4–1.7× inside shaded patches,
   worse than the rejected darker-range candidate. Evaluating both on the
   regional colour (smooth offset and gain) brings it below the input level. In
   the mockup scenes it matches v9 by eye; the mean per-pixel |Δab| is 0–30% lower,
   partly because v9's figure included stretched noise.

## Matched stills (final design)

28 private headless `compare_frame.py` runs (5 s compile, 20 s settle):
candidate ×2 and production ×2 on GZW 133058, 133444, 101035, 133750, 133932 and
Arc 205938, 210448. Zero vkBasalt errors; the intended pipeline loaded.

Repeats, in pixels / max code:

| Scene | Candidate | Production |
| --- | ---: | ---: |
| 133058 | 8,708 / 1 | 8,364 / 1 |
| 133444 | 48,822 / 1 | 19,300 / 1 |
| 101035 | 475,395 / 1 | 1.46 M / 1 |
| 133750 | 13,609 / 1 | 11,939 / 1 |
| 133932 | 2.05 M / 4 | 1.86 M / 3 |
| 205938 | 639,106 / 2 | 565,364 / 2 |
| 210448 | 506,310 / 1 | 49,039 / 1 |

Candidate vs production in shadow, where shadow means reference weight > .5 on
the source:

| Scene | Shadow fraction | Δab ×100 | ΔL ×100 | Non-shadow ΔE ×100 |
| --- | ---: | ---: | ---: | ---: |
| 133058 | .17 | .81 | −.75 | .009 |
| 133444 | .10 | .90 | −.78 | .017 |
| 101035 | .09 | .92 | −.43 | .069 |
| 133750 | .18 | .87 | −.98 | .016 |
| 133932 | .28 | 1.14 | −.47 | .103 |
| 205938 | .27 | .70 | −.51 | .122 |
| 210448 | .23 | .73 | −.56 | .015 |

The largest code differences (16–41) are all in the blue channel of shaded warm
pixels (median weight .86–1.0, production minimum channel around codes 22–35).
That is the warm tint lowering already-low blue, amplified by sRGB coding at low
values.

Native crops show the following:
- Forest shadows are a deeper green.
- Red-light shadows are warmer, with the lamp glow intact.
- Warm gravel shadows are warmer.
- Dark UI panels can be tinted, as with every pixel-only method.

## Output noise (final design)

The final 8-bit dithered screenshots were measured, ×2 per game.

**2026-11-07 band fixture** (`a1b76bc5…f09bac`). Candidate equals production in
every statistic; uniform bands receive no shadow weight.

**New tint fixture** (`noise/tint_noise_source.png`, `42e30146…421de`, seeded).
It has 120 px ±1-code patches at codes 8/16/32 on a green mid-tone surround, so
the tint is fully active. Results for GZW (Arc within .01):

| Code | Input ab σ ×100 | Production | Candidate | Production L σ | Candidate L σ | Mean L prod / cand |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 8 | .258 | .168 | .169 | .256 | .286 | 15.26 / 13.96 |
| 16 | .213 | .167 | .161 | .265 | .265 | 17.90 / 16.74 |
| 32 | .195 | .186 | .183 | .257 | .282 | 23.82 / 22.82 |

Chroma noise matches production. Lightness noise is up to about 11% higher at
codes 8/32; production repeats vary by up to .01 at code 32. Mean L is 1.0–1.3
lower, which is the intended darkening on a strongly coloured surround. This is
synthetic noise, not a visual threshold.

## Scene cut

`--transition` was run once per variant: GZW shelf → courtyard → shelf. Zero
dropped or delayed frames. Settling ΔE, candidate / production:
- second early→late .053 / .070;
- first early→late .119 / .118;
- late→recovered .165 / .167;
- before→recovered .294 / .298.

No pumping difference.

## Status and costs

**Costs.**
- Five small passes: 1/16 at 160×90 with 169–361 taps per texel, and a 1/8 pass
  with 25 taps. The per-pixel work adds Oklch+ and CIELAB conversions of the
  regional colour.
- GPU cost was not profiled (profiling is retired).
- UI tinting.
- Pixel-only cues: dark materials in light can also receive weight, and lit dark
  areas next to bright surfaces count as relatively dark.
- Lightness noise is slightly higher.

## Character halo and adoption

The user reported artifacts around the character in Arc 210448. A halo metric
compared dark background within 50 px of bright objects against background more
than 150 px away:
- tint .53 vs .03 (×100);
- hue 55–58° (the scene's average surface colour) vs the scene red at about 40°.

Colour-only fixes all failed on the CPU reference, sometimes raising coverage:
- directional context;
- brightness-limited surroundings with joint bilateral upsampling (halo .61);
- wide-scale hue;
- colour-family-similar context.

The halo band is not separable by relative darkness either (median 2.0 vs 1.7
stops). A smaller context radius reduced the halo only 14% but cut the tint
everywhere by about 30%. Depth was rejected: depth-buffer access is an
anti-cheat flag.

The user accepted the limitation. The tint was adopted into production on
2026-11-08 (uncommitted), renamed `SHADOW_SURROUND_TINT` to avoid confusion with
the 3-way CC `SHADOW_TINT`, at .7 in both profiles. At .7 the halo and all tint
are about 30% weaker. Production captures on 210448 and 133750 match the .7
candidate (`strength07/`) within ≤2 codes; vkBasalt logged no errors and ran
all five passes. Resulting identities: grade `bc30c83a…2bad`, pipeline
`bec87bec…15b2`. After reviewing 0.7 vs 1.0 (`strength_review.html`), the user set
1.0 in both profiles; the production grade default is also 1.0 (grade `111afeee…17ea`).
It is identical to the validated candidate except for the control name and comments. Queued after
the review: oracle scoring of the cue maps and an H-K chroma mockup (see PLAN).
