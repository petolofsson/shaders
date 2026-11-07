# Shadow gradient research: monotone output-curve feasibility

## Finding

A spatially uniform, monotone luminance curve is a plausible alternative to enhancing a local residual. An exploratory output-image proxy improves selected shelf and metal brightness separation while preserving the shelf median, and cannot generate the opposing spatial rims of the preceding bilateral residual model in its continuous scalar mapping. It also compresses other brightness ranges, changes the selected cool-window and blue-wall relationships, and does **not** preserve the actual chain's source-black response by construction. The example is fitted to one shelf region, works on quantized screenshots, and is not a recommended shader change or evidence of a general visual improvement. It establishes a lead worth a properly anchored full-chain investigation, not an adoption decision.

## Research and design rationale

[Eilertsen, Mantiuk and Unger's noise-aware tone mapping](https://computergraphics.on.liu.se/rntm/) combines locally adaptive contrast-distortion control with explicit noise-aware detail handling and temporal filtering. Their paper concerns HDR video and display adaptation, with different inputs and costs; it does not validate this SDR pipeline or this curve. [Disney Research's temporally coherent local tone mapping](https://la.disneyresearch.com/publication/hdr-video/) uses spatiotemporal edge-aware filtering to address moving video. It requires motion-aware temporal machinery that is not present in this model. The practical lesson here is that a more complex local method needs independent noise and motion evidence rather than assuming an edge-aware filter is sufficient.

As a smaller feasibility question, a pointwise increasing function preserves scalar luminance ordering before color conversion, gamut clipping, and quantization. The same function at every spatial position does not generate the alternating edge overshoot characteristic of a spatial residual. It does not distinguish signal from noise: steeper portions amplify both. Because a bounded curve must rejoin its original endpoints, added slope somewhere entails reduced slope elsewhere. It also does not preserve input colors or the source-black appearance automatically when inserted in the full nonlinear color chain.

## Offline proxy

Use the existing separately captured current-output and source-only 8-bit images identified in `captures/shadow_curve_research_20261106/report.json`. Decode current output to linear RGB, calculate luminance `y`, map it with

`y' = y + 0.3*(y-0.003864)*smoothstep(0.0015,0.003,y)*(1-smoothstep(0.006,0.015,y))`,

scale RGB by `y'/y`, clamp and encode to 8-bit. This pivot is the measured GZW shelf output median; it is deliberately chosen on the test scene and is not an adaptive method or game-independent calibration. A million-step scalar CPU grid on [0,1] gives derivative range approximately 0.5805–1.3000 and maps exact output Y=0 to zero. This is a sampled scalar property, not proof of the complete chain, pre-quantization monotonicity for RGB after clipping, exact black-source preservation, or implementation feasibility. The output images have already undergone dither and quantization; this proxy can magnify those artifacts and cannot recover lost information. The input captures are not same-update float readbacks.

| Source-selected region | Median L current → proxy | Quartile L gap current → proxy | Four-pixel signed log-Y gap current → proxy | Source-relative reversal current → proxy |
| --- | ---: | ---: | ---: | ---: |
| GZW shelf | 15.735 → 15.735 | 2.661 → 3.489 | 0.115959 → 0.142145 | 6.49% → 6.49% |
| Arc dark metal | 17.589 → 18.047 | 8.973 → 9.449 | 0.137007 → 0.152131 | 5.75% → 5.98% |
| GZW blue wall | 39.619 → 39.619 | 9.468 → 9.384 | 0.075890 → 0.075458 | 2.63% → 2.64% |
| Arc cool window | 37.092 → 37.092 | 31.972 → 31.545 | 0.149966 → 0.146070 | 1.98% → 2.24% |

Selected source masks and overlapping pairs inherit the prior 8-bit, independent-capture and one-code sensitivity limitations. Metrics are descriptive, not preference or visibility scores. Maximum changes in these crops are two, three, two and two codes respectively in table order. Native crops show subtle shelf and metal differences, not a demonstrated clear gameplay improvement; no blind or user review was made. The cool-window cost and reversal changes remain even though the continuous scalar map is increasing, because measured source ordering and quantized RGB output are different contracts.

Most importantly, preserving **output Y=0** is not the same as preserving the current output of **source black**. The earlier GZW black-field screenshot median `[5,6,6]` corresponds to approximately linear Y=0.001757; the proxy changes that luminance by approximately -0.000049, about -2.8% before re-encoding, if applied to that color. This is an illustrative calculation on an earlier screenshot, not a same-update black-field test or a statement that every black pixel changes by the same amount. It explicitly prevents claiming the requested black anchor is preserved.

## Next decision

A credible implementation would need a stable reference to the *actual processed source-black response*, preserve it without introducing an unrequested user control, and preserve intended colors and bounded output. An adaptive pivot or anchor would require its own source/state and temporal contracts; there is currently no demonstrated safe producer for such an anchor. Before building one, compare this idea against a real source-black field, gradients, one-code/noise inputs, vivid and muted material, and both current profiles, with independent pre-quantization GPU evidence if any isolated shader candidate becomes worthwhile. The earlier black-anchored slope and shadow-curve screens failed in the full chain; this output-referred 8-bit proxy does not reverse those decisions. No shader, profile, configuration or rating changed.
