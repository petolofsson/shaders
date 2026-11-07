# Black-anchored slope experiment — 2026-11-05

**Decision: reject this candidate.** The user asked to continue working on shadow gradients and whether further research was needed. Following the [late-offset rejection](2026-11-05_late_black_offset.md), the test preserves the configured early black offset and increases source response immediately above it. Despite a monotonic fixed-context scalar curve, selected shelf and metal gaps and neighboring-shade responses worsen in the full chain. No production shader, profile, config or rating changed.

## Rationale and candidate

A fixed-endpoint tone mapping has a finite output range: a steeper slope in one range requires a lower average slope elsewhere if endpoints remain fixed. This is a general consequence of a bounded tone curve, also discussed in [Zhang's perceptual imaging dissertation](https://www.cl.cam.ac.uk/~fz261/thesis/Dissertation__Path_from_Photorealism_to_Perceptual_Realism_compressed.pdf). [Shan, Jia and Brown's overlapping-window optimization](https://grail.cs.washington.edu/projects/sq_tonemapping/) is a possible research reference for local linear ordering, not a directly validated fixed-pass implementation here. Neither external work establishes that this candidate should work on already-tonemapped SDR game output.

In an isolated grade copy only, replace the early mapping with:

```text
B = BLACKS; Y = Luma(post-inverse RGB)
extra_gain = 2 * exp(-Y / max(B, 1e-6)) * step(1e-6, B)
lin = RGB * (WHITES - B + extra_gain) + B
```

The configured B and remaining stages are unchanged. Exact black produces the same pre-corrective input algebraically; positive extra gain vanishes toward brighter pixels, and B=0 disables it algebraically. For a fixed neutral scalar context with B>0 and WHITES−B near 1, the additional function `2Y exp(-Y/B)` has minimum full derivative approximately 0.729 at Y=2B and maximum excursion approximately 0.736B. The dense CPU calculation is a fixed scalar property, not a full-pipeline monotonicity, GPU endpoint or zero-bypass contract. It also lightens eligible source values, which can work against dark-shadow intent.

## Results

| Source-selected region | Measure | Current | Candidate | BLACKS=0 diagnostic |
|---|---|---:|---:|---:|
| GZW shelf | median L | 15.735 | 17.688 | 12.364 |
| GZW shelf | visible L gap | 2.661 | 2.378 | 4.387 |
| Arc dark metal | median L | 17.589 | 18.899 | 14.958 |
| Arc dark metal | visible L gap | 8.981 | 7.203 | 11.130 |

Fixed source-quartile gaps are not quality scores; source masks and regions match earlier shadow attribution. Mean signed log-Y gaps for fixed source-selected neighboring pairs at 1/4/16-pixel offsets fall 0.100760/0.115991/0.126915 → 0.069995/0.080563/0.088098 stops on shelf and 0.113594/0.136975/0.156600 → 0.086509/0.101020/0.114048 on metal. The candidate lifts selected medians but compresses these local gradients, despite its scalar monotonicity. The BLACKS=0 images are counterfactuals, not proposed profile values.

Four current-profile isolated candidate/repeat pairs cover GZW dark, Arc interior, Arc emitters, and Arc vivid content with GZW settings. All candidate pairs are pixel-identical with the 2×2 marker masked. All eight private headless GPU processes report zero dropped/delayed frames. Whole-image maximum per-channel differences are 10/11/10/13 codes respectively; no newly all-channel-black pixels or channel-255 samples were counted. White-core, halo and red-lamp L gaps are unchanged at displayed precision, but this is not a general highlight contract. Current/isolated source, profile, config and shader hashes were preserved or verified; the 20-second still protocol is not motion or full convergence evidence.

The [shelf](../captures/black_slope_20261105/gzw_dark_review.png) and [interior](../captures/black_slope_20261105/arc_interior_review.png) show current/candidate/black-off native crops. These are ignored local artifacts alongside scripts, configs, logs and metadata in `captures/black_slope_20261105/`.

No independent GPU numeric or exact-black/BLACKS-zero contracts, ramps, motion/cut controls, performance or actual-config adoption validation were performed. The negative held-scene result does not justify adoption or an amplitude/width sweep. It reinforces that fixed-context monotonicity and a steeper deepest-black slope do not by themselves produce richer full-chain gradients.
