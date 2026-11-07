# Grade-input proxy for the guarded shadow curve

The prior [source-gated curve](2026-11-06_shadow_curve_black_guard.md) used a source-only screenshot as a proxy for the post-inverse grade input. This follow-up replaces that proxy with the separately captured diagnostic grade-input screenshots from the [safeguard screen](2026-11-06_shadow_color_guards.md). **Decision: no candidate adoption.** The four output crops are pixel-identical to the preceding source-proxy result after 8-bit quantization. A separate continuous calculation on the captured pairs finds some newly reversed neighboring relationships, but the available images cannot establish whether these occur in the actual shader or are visible.

The diagnostic intercepted grade input and encoded it as a screenshot. It is closer to the intended gate input, but is still 8-bit, is a separate capture from the full output, and does not supply same-update float input/output pairs. Both input screenshot repeats were exact at their capture checkpoint. All 17 recorded shader, include, profile and config hashes match the current workspace; the grade-input images match their recorded hashes. Source, input and current-output image hashes, selected crops, code and measurements are recorded under `captures/shadow_curve_grade_input_20261106/`. The earlier capture's identity and timing limitations still apply.

The output screenshot is decoded, adjusted with the same shelf-fitted curve and gate as before using diagnostic-input luminance, then encoded to 8-bit. All four guarded output crop images match the source-screenshot-gated proxy byte for byte; this does not mean the gate inputs or continuous corrections are identical. The existing shelf/metal gains and cool-material costs reported previously therefore remain unchanged at this screenshot precision. The scene-fitted pivot and same two scenes limit generalization.

To investigate the two-input concern, take horizontal and vertical neighboring pairs in each complete material rectangle, at one- and four-pixel separation. Include a pair when diagnostic-input Y differs by more than 0.00001, current-output Y has the same signed ordering, and at least one input Y is below 0.003. Apply the proxy correction in continuous linear luminance and count cases where that output order becomes opposite to the diagnostic-input order. Pairs overlap; the rectangle population is not the earlier source-selected material mask, so the counts cannot be compared directly with its reversal percentages.

| Rectangle | One-pixel pairs eligible / newly reversed | Four-pixel pairs eligible / newly reversed | Maximum newly reversed linear-Y gap |
| --- | ---: | ---: | ---: |
| GZW shelf | 92,230 / 342 | 111,289 / 142 | 0.0000284 |
| GZW blue wall | 2,084 / 18 | 2,779 / 7 | 0.0000556 |
| Arc dark metal | 34,882 / 139 | 51,305 / 138 | 0.0000268 |
| Arc cool window | 181 / 0 | 197 / 0 | 0 |

These are continuous calculations **after decoding independently quantized screenshots**, before re-encoding the proxy. Small gaps, dither and the separate captures may influence pair ordering; counts are not independent observations, a visibility score, a numerical GPU contract or a temporal result. The input difference cutoff is an exploratory selection, not a measured noise floor. The exercise identifies contexts worth a same-update float investigation only if a candidate first demonstrates a worthwhile visual benefit and addresses cool-material loss. It cannot establish that the synthetic fixed-output scenario from the prior screen occurs in real processing, or that the guarded mapping reverses shader pixels.

No shader, profile, configuration, pass or rating changed. A more reliable next step needs a genuinely better material/black-anchor design, or same-update input/output diagnostics for a visually justified candidate; repeating the same screenshot proxy or tuning its thresholds is not justified by this result.
