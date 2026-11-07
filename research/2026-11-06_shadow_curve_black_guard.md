# Source-gated shadow curve: black-anchor screen

**Decision: do not implement this version.** A source-dependent gate provides a simple algebraic way to leave the grade output unchanged when its gate input is zero, without estimating a processed black level. The isolated screenshot proxy retains some shelf/metal separation gains, but also retains the cool-material cost. More fundamentally, its result is a function of two independently varying signals; a monotone curve in output luminance no longer guarantees monotonicity as the gate changes. A deliberately adverse scalar probe demonstrates a reversal. No production shader, profile, config or rating changed.

## Mechanism and available input

The existing `ColorTransformPS` decodes the post-inverse BackBuffer to `col.rgb` before the grade black offset, then has the pre-dither processed `result` in the same invocation. One could multiply the [previous output-curve](2026-11-06_shadow_monotone_research.md) correction by `smoothstep(0.0005,0.003,Luma(col.rgb))`. For exact zero grade input this multiplier is zero, so in arithmetic the candidate leaves the existing pre-dither result unchanged at that pixel in the same context; the unchanged dither then receives the same input. This does **not** establish that every exact source-black pixel reaches grade as zero after inverse and UNORM handoff, nor provide a GPU endpoint or same-update contract. `NativeGuideLogTex` is captured earlier, but its log input is floored at 0.001 and is not an exact-zero discriminator. No additional resource is needed for this proposed gate, and no new surface or user control was introduced.

The guard itself varies with pixel input. Its derivative contributes to the composite response; it is therefore not the same spatially uniform one-variable monotone mapping as the original proxy. The source-only screenshots below are not the actual post-inverse grade input and cannot validate this gate's real engagement or endpoint.

## Offline image proxy

Using the same output and source-only screenshots, pivot and curve as the preceding report, multiply the proposed output-luma correction by the gate calculated from decoded source-only screenshot Y. Fixed source-selected results:

| Region | Quartile L gap current → guarded proxy | 4-pixel signed log-Y gap current → guarded proxy | Source-relative reversal current → guarded proxy |
| --- | ---: | ---: | ---: |
| GZW shelf | 2.661 → 3.024 | 0.115959 → 0.141048 | 6.49% → 6.49% |
| Arc dark metal | 8.973 → 9.344 | 0.137007 → 0.145613 | 5.75% → 5.99% |
| GZW blue wall | 9.468 → 9.368 | 0.075890 → 0.075305 | 2.63% → 2.65% |
| Arc cool window | 31.972 → 31.544 | 0.149966 → 0.146070 | 1.98% → 2.24% |

The selected shelf median L stays 15.735 and metal rises 17.589 → 18.047. Maxima in these crops are two, three, two and two 8-bit codes in table order. These are descriptive selected measurements, with the independent-capture, quantization, dither, fitted-pivot and original-mask limitations of the previous report. They do not demonstrate gameplay preference, actual source-black preservation, or full-chain behavior. Native crops, hashes, script and full measurements are in `captures/shadow_curve_source_guard_20261106/`.

## Independent scalar stress test

At fixed hypothetical processed Y=0.0025, sweep the independent gate input from 0 to 0.004. The guarded output decreases from 0.0025 to approximately 0.0021969 as input increases: 2,500 of 4,000 sampled steps are negative. The zero-input endpoint remains 0.0025. A separate 5–9 sRGB-code gate-input sweep at the same fixed processed Y changes the output by up to 0.0000547 linear Y between adjacent input codes. This constant-output scenario is deliberately adverse, not proof that the real chain holds output Y constant while its grade input changes, nor a measured game-noise model. It demonstrates the missing two-input ordering and sensitivity guarantee, not a visible artifact in existing gameplay. CPU script and exact results are `probe.py` and `probe.json` in the capture directory.

These findings do not invalidate all input-gated curves. A useful continuation needs either measured evidence that the real input/output relationship excludes harmful cases across materials and transitions, or a construction whose combined response remains ordered under a stated, independently verified bound. It must also address the selected cool-material loss and retain the subtle-color objective; no strength or threshold sweep is justified by the current two stills.
