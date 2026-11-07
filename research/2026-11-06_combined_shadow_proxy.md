# Combined shadow brightness and color proxy

**Decision: no production candidate yet.** Combining the provisional half-strength color result with the source-gated brightness curve gives higher selected shelf/metal color-group and brightness gaps than the current result. It retains worse source-relative ordering, reduces the cool-window brightness gap and blue-wall color-group separation, and depends on a scene-fitted curve. The native crops show subtle differences; the evidence does not establish a clear overall improvement or resolve the black-anchor, neutral, noise and motion concerns. This is an offline image proxy, not a compiled combined shader.

## Method and identity

Start with the isolated half-strength bounded-color stills from the [subtle color screen](2026-11-06_subtle_shadow_color.md), which had exact static repeats. Decode those already quantized 8-bit PNGs and apply the [source-gated brightness curve](2026-11-06_shadow_curve_black_guard.md) using the separately captured diagnostic grade-input screenshot as gate. Scale RGB by the computed luminance ratio and re-encode to 8-bit. This order introduces another quantization and operates after the full chain; it is not equivalent to inserting the brightness curve into a compiled shader, nor a same-update input/output measurement. The curve pivot was chosen from the GZW shelf and the color candidate remains provisional. All recorded 17 shader/profile/config hashes match the workspace, and the color stills match their recorded capture hashes. Complete input hashes, scripts, metrics and native three-way crops are in `captures/shadow_combined_proxy_20261106/`.

Fixed source-selected groups and overlapping four-pixel pairs inherit the previous 8-bit, dither, sampling and independent-capture limitations. Color-group distance is Oklab a/b ×100 between source b-quartile groups at source L 12–35; groups can also differ in brightness. Bigger distances, gaps and changes do not by themselves mean better material appearance.

| Region | Color-group distance current / color / combined | Four-pixel log-Y gap current / color / combined | Source-relative reversals current / color / combined |
| --- | ---: | ---: | ---: |
| GZW shelf | 0.327 / 0.420 / 0.429 | 0.11596 / 0.11620 / 0.14240 | 6.49% / 9.07% / 9.07% |
| Arc dark metal | 1.575 / 1.779 / 1.799 | 0.13701 / 0.13685 / 0.14552 | 5.75% / 6.81% / 7.02% |
| GZW blue wall | 0.092 / 0.068 / 0.066 | 0.07589 / 0.07588 / 0.07529 | 2.63% / 2.77% / 2.80% |
| Arc cool window | 1.970 / 2.107 / 2.104 | 0.14997 / 0.15005 / 0.14625 | 1.98% / 2.12% / 2.39% |

The source-selected L 12–35 shelf median remains 16.073; the corresponding metal median rises 17.559 → 18.065. These medians use a different mask from whole-region quartile-gap statistics. The color-only candidate's source-neutral shifts remain unresolved; this screen does not establish neutral preservation for the combination. The underlying brightness curve's zero grade-input algebra, two-input ordering caveat and unverified actual source-black behavior remain as documented in its prior screens.

No new GPU process, numeric GPU contract, exact-black fixture, real warm/red-black sample, vivid or highlight control, temporal test, full-frame visual judgment, performance test or activation check was performed. A reliable combined approach would need a different or independently validated way to retain the target material gains without the recorded cool-material and ordering costs, before its own isolated shader and measured-motion validation could be justified. No shader, profile, config or rating changed.
