# Black-offset detail-transfer screen

## Decision

The black-offset bypass contains local variation that can be transferred back into the current result without the full bypass's large reduction in median brightness in the selected dark regions. This provides evidence of a possible direction, not a shader ready for adoption. The selected improvements are modest and the transfer increases source-relative ordering reversals in several regions. The reference uses a second full-chain image rendered with BLACKS disabled, making a literal real-time implementation impractical without duplicated processing. No production shader or profile changed.

The prior recommendation to investigate a black-anchored slope overlooked that the [black-anchored slope experiment](2026-11-05_black_anchored_slope.md) had already tested and rejected one direct version. That candidate made the shelf and metal gradients worse in the full chain. Moving the offset late was also [rejected](2026-11-05_late_black_offset.md). The present test asks a different question: whether detail from the black-off result is useful after removing its local average brightness difference.

## Offline test

Use the existing current-profile full-chain and isolated BLACKS=0 captures, plus source-only playback captures, for the same GZW and Arc stills as the [multiscale analysis](2026-11-05_shadow_multiscale_measurement.md). Both profiles remain at BLACKS=0.0025. Each screenshot is 8-bit; the captures are independent processes rather than paired pre-quantization GPU observations. Source, black-off and current image hashes are recorded in `captures/shadow_black_detail_20261106/report.json` and their original capture provenance and still-repeat limitations remain in the earlier report.

For each 96-pixel-padded crop, calculate the difference between black-off and current log luminance, subtract a Gaussian sigma-8-pixel blur of that difference, clamp the residual to ±0.5 stops and apply a source-luminance shadow window. Multiply current linear RGB by that gain and quantize to an 8-bit output. This subtracts a local average difference before the window and clamp; it does not guarantee preservation of local mean brightness, the exact black anchor, colors, edges, ordering or temporal stability. It also includes any independent capture differences and 8-bit quantization in its residual. The code and comparison crops are ignored local artifacts in `captures/shadow_black_detail_20261106/`.

## Selected results

| Region | Median L current → transfer | Source-selected quartile L gap current → transfer | Four-pixel mean signed log-Y gap, stops current → transfer |
| --- | ---: | ---: | ---: |
| GZW shelf | 15.735 → 15.735 | 2.661 → 2.761 | 0.115959 → 0.126394 |
| GZW blue wall | 39.619 → 39.619 | 9.468 → 9.418 | 0.075890 → 0.080680 |
| Arc dark metal | 17.589 → 17.608 | 8.973 → 9.329 | 0.137007 → 0.157554 |
| Arc cool window | 37.092 → 37.368 | 31.972 → 32.225 | 0.149966 → 0.161144 |

By comparison, the actual black-off median is 12.364 on the shelf and 14.958 on the metal. These measurements describe fixed selected regions and overlapping pairs, not a perceptual quality score. The native metal comparison shows a small difference; it does not establish a clearly visible improvement in gameplay. Maximum per-channel changes in the four whole crops are 5, 17, 14 and 14 codes respectively, so the restrained median changes do not imply every pixel is protected.

Four-pixel source-relative reversal rates are 6.488% → 6.469% for shelf, 2.626% → 3.566% for blue wall, 5.754% → 7.064% for dark metal, and 1.984% → 3.538% for cool window. The source comparison is quantization-sensitive and source ordering is not a complete visual-quality criterion, but the increase warns against assuming that the transferred detail is faithful. No edge, synthetic noise, pre-quantization black-anchor, motion, convergence or GPU performance test was run. This first screen does not justify a production implementation or a parameter sweep.
