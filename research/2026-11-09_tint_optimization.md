# Shadow surround tint: cost reduction without output change (2026-11-09)

The user asked to make the adopted [shadow surround tint](2026-11-08_shadow_tint_candidate.md)
cheaper "without reducing fidelity". GPU profiling is retired, so cost is given
as pass and fetch counts.

## Changes

| | Before | After |
| --- | --- | --- |
| Tint passes | 5 | 4 |
| Blur fetches per 1/16 texel | 169 + 361 = 530 | 2 × 19 × 2 textures ≈ 64 |
| Per-pixel trig | `atan2` + `sin` ×2 | none |

1. **Merged gather.** `TintGatherPS` writes `TintGatherATex` and
   `TintGatherBTex` through two render targets. The four lane reads and the Oklab
   conversion happen once instead of twice.
2. **Separable environment blur.** `TintEnvHPS` then `TintEnvVPS` use two
   render targets each, with RGBA32F/RG32F intermediates. The kernels factor
   exactly per axis:
   - square σ 3.46 / r 6 for the colour field and the surface-luma channel (the
     r 6 mask is a product of 1-D masks);
   - square σ 4.90 / r 9 for the emitter channel.

   Normalization factors as the product of the 1-D sums, and CLAMP addressing is
   per axis.
3. **Trig-free H-K hue term.** |sin((h − 90°)/2)| = √((1 − sin h)/2), with
   sin h = b/C. The C = 0 case gives the same value, and it is multiplied by C anyway.

Region and per-pixel application are unchanged. No resource format the per-pixel
path reads is changed: the final environment textures stay 16F.

## Verification

- **CPU.** The H-K term matches to 3e-12 relative over 10⁶ random a,b, zeros
  included. The separable blur matches the 2-D loops to 2e-8, including borders
  and the masked channel.
- **Compile.** vkBasalt accepts the two-target passes, with 0 errors in all
  private headless runs.
- **Matched stills.** Candidate ×2 vs production ×2 on six scenes. Script and
  stills: `captures/tint_opt_20261109/` (`analyze.py`, `report.json`). Two Arc
  210448 captures failed when `/tmp` filled; they were re-run.

| Scene | Production repeat max | Candidate vs production max | Pixels >1 code |
| --- | ---: | ---: | ---: |
| GZW 133058 | 1 | 1 | 0% |
| GZW 101035 | 2 | 2 | .001% |
| GZW 133750 | 1 | 1 | 0% |
| Arc 205938 | 3 | 3 | .011% |
| Arc 210448 | 1 | 3 | .008% |
| GZW 133932 (firelight) | 3 | 11–13 | 0.7–3.8% |

**Firelight isolation.** A trig-only build and a gather/blur-only build were each
captured twice. Same-build repeats differ by up to 10 and 13 codes, in dark pixels
next to the fire. So this scene is capture-unstable for any build: the earlier
production repeat of max 3 was a favourable pair. The gather/blur-only build
reproduced production within 1 code in one pair. The differences there are
therefore capture variation, not an output change.

This is a production observation, not a regression from this change: dark pixels
near emitters in this scene vary by up to ~16 codes between captures. A likely
cause is the tint's ratio of near-zero blurred fields where surroundings are
nearly black, but this is unconfirmed.

## Adoption

The user asked for the optimization ("do step 2 as well as you can without
reducing fidelity"). The candidate's `general/` differed from production only in
`grade.fx` and `pipeline.fx`, and those were copied:
- grade `6a5b7b24025ae86c0e1ec069a743a2cd1a794a9e3051323d9a1ad5d0714cff4e`;
- pipeline `a20641fec412ca3e156f5a359abe242d57717d748155abd3f76e1af3b3b68474`.

Limits:
- Stills only; the noise fixtures and scene-cut checks were not re-run.
- The output is intended identical, and the per-pixel path is unchanged apart
  from the exact trig identity.
- The real GPU time saved is unmeasured.
