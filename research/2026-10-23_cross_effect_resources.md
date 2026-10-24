# GZW strength investigation — 2026-10-23

The user reported that the GZW grade still looked close to the game output. A
matched daylight capture under the current four-effect config changed the image
by mean Oklab ΔE 2.74, mostly by darkening midtones. The initial GZW-only trial
raised `CONTRAST` and added a 25% global chroma gain. The original chain's
`CONTRAST` ablation remained exactly 0.00 ΔE; saturation contributed 0.91 and
print stock 3.03 on `autof_20260515_133932.png`.

Temporary diagnostic output from `ColorTransformPS` showed zero values for both
`ZoneHistoryTex` and `ReadTexHwyPerc()` in `grade.fx`. That is consistent with
vkBasalt allocating render textures within each effect instance: equal names in
separate `.fx` files do not make a shared GPU resource. This is visible in
vkBasalt's `ReshadeEffect::createReshadeModule`/texture allocation code. The
temporary diagnostic output was removed.

`general/pipeline/pipeline.fx` includes the existing source files and executes
their passes in one technique. The original effects remain independently
compilable. `gzw_stronger_trial.conf` activates that combined technique without
changing `gzw.conf`. The combined shader compiled and rendered through vkBasalt.
With the same trial profile (`CONTRAST=1.5`, `SATURATION=0.25`), the daylight
frame changed from source by mean ΔE 5.74 and the dark gameplay frame by 1.84.
The combined-versus-four-effect changes were 3.34 and 0.74 respectively.

Contrast attribution in the combined technique was 1.56 ΔE and Retinex 0.60
on the daylight frame; an unchanged-pipeline repeat rounded to 0.000. These
measure image change, not visual quality. The daylight change is mostly darker
shadows. Five-second warmup does not establish temporal convergence. The trial
still needs live gameplay assessment, motion/scene-cut checks, and GPU timing.
The active `gzw.conf` was not edited.

## Follow-up audit

An all-controls ablation on the trial at five seconds found an unchanged-run
variation of 0.373 ΔE. Clear daylight contributions were inverse luma 2.12,
zone contrast 1.54, saturation 0.95, and print stock 2.97. Exposure, midtone
temperature, hue rotation, vibrance, hue-selective luma contrast, and printer
lights were deliberately neutral in this profile and were skipped. The five-
second results below roughly 0.5 were inconclusive.

GPU diagnostic output showed that the raw 64-bin luma histogram summed to
0.999 while its temporally smoothed copy summed to only 0.436 after five seconds.
The percentile CDF walkers had assumed unit mass and returned about
0.100/0.418/0.624 for p25/p50/p75. Normalizing the smoothed histogram at the
percentile, high-percentile, and entropy consumers corrected the GPU values to
0.025/0.060/0.138; downsampled source estimates were 0.017/0.050/0.140.
The temporary debug output was removed.

At 20 seconds, the repeated daylight render differed by mean ΔE 0.00009.
Inverse chroma expansion contributed 0.00087 and FilmCurve 0.00627 mean ΔE in
that frame. Only 3.6% of its source pixels exceed Oklab C=0.10, the current
inverse chroma gate; nearly all pixels lie below FilmCurve's linear-light knee.
Those controls are connected but barely engaged here. A dark gameplay frame at
20 seconds gave identical 2.35 ΔE contributions for `SHADOWS` and
`SHADOW_LIFT_STRENGTH`, with a near-zero unchanged repeat. This confirms that
shadow lift engages on a relevant scene.

These checks do not establish correct behavior on bright cloud/sky scenes,
high-chroma objects, motion, scene transitions, different frame rates, or Arc
Raiders. They also do not measure GPU cost. The regular GZW config still uses
the four-effect chain with zeroed cross-effect data in grade.
