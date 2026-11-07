# Four-pixel floating-point shadow observations

The [same-update float-pair diagnostic](2026-11-06_shadow_float_pairs.md) is repeated with 16×16 native-pixel-center grids covering four 64×64 patches, so adjacent samples are exactly four pixels apart. This provides a closer spatial-scale check than the earlier coarse grid, while remaining sparse and covering only selected patches. The data reinforce that output quantization affects some ordering observations and that the CPU research model's effects differ by material. They do not establish an adopted visual improvement.

The four patches are shelf `(280,500)–(344,564)`, metal `(180,1100)–(244,1164)`, blue wall `(1600,350)–(1664,414)`, and cool window `(1640,740)–(1704,804)` in the same GZW/Arc stills. Patches were visually selected from the previous regions, not independently held scenes. The same clone, same-update input/output sampling, 24-bit encoded [0,0.25] range and pre-dither limitations apply as in the prior report. All four final repeat pairs are exact at encoded precision. Six shelf/metal/wall processes and the two successful window retry processes together comprise eight successful final captures; each reports zero dropped/delayed frames. One initial window process reported one dropped frame and is excluded: its screenshot and log `/tmp/shader-runtime-oxbbjtq8` are retained. The partial report for the first three pairs and the separate window retry report, configs, hashes and data remain in `captures/shadow_float_pairs_20261106/`. The window retry has 19 samples with at least one channel at the encoding ceiling; those samples are excluded, leaving 237 valid. The other patches have 256 valid each.

With the prior grade-input selection (both Y >0.0005 and an input difference >0.00001), and comparing pairs along both axes, the float, simulated 8-bit and simulated 16-bit sRGB reversal results are:

| Patch | Eligible 4-pixel pairs | Float reversals | 8-bit reversals | 16-bit reversals | Changed classification 8-bit / 16-bit |
| --- | ---: | ---: | ---: | ---: | ---: |
| Shelf | 430 | 0 | 3 | 0 | 3 / 0 |
| Metal | 361 | 0 | 2 | 0 | 2 / 0 |
| Blue wall | 437 | 0 | 0 | 0 | 0 / 0 |
| Cool window | 425 | 6 | 12 | 7 | 14 / 1 |

Rounding changes can add and remove reversals; counts overlap spatially. The 16-bit simulation changes one window classification, so even 16-bit is not a universal ordering guarantee. Quantization was performed on the already-read-back pre-dither float RGB and does not model the game's actual 16-bit swapchain, dither or same-update screenshot. The source used for ordering is post-inverse grade input, not original game pixels; some genuine stage changes are intentional.

Applying the earlier **CPU-only** bounded brightness/color model to the float pairs changes mean input-signed output linear-Y gaps as follows: shelf 0.0003633→0.0004195, metal 0.0003712→0.0004124, wall 0.0023282→0.0023163 and window 0.0097743→0.0097182. Reversal counts stay 0/0/0/6 for these selected pairs. Neither cap activates in the valid samples; constructed saturated-face failures remain. The model also raises mean Y by 0.0000976, 0.0000383, 0.0009547 and 0.0009283 respectively. These values are descriptive, not visibility or taste scores, and the different materials, edges, source masks and color profiles matter. The model remains scene-fitted and the cool-material, neutral-color, exact-black and temporal concerns remain unresolved.

The source-only screenshot supplies separate, quantized selection metadata for optional color-group results; it is not same-update float source. Scripts, all analysis and both diagnostic reports are in the capture directory. No GPU candidate, 16-bit output activation, profile/config change or rating is implied.
