# Full-chain shadow-detail model: CPU screen — 2026-11-05

**Decision: do not build or adopt a shader from this screen.** The user asked to examine a model that carries original source shading through the combined grade. This approximate CPU screen gives small, mixed selected changes and no clear visible improvement. Production shader, profiles/configs and ratings are unchanged. The screen does not prove the model could not work in a different implementation or input.

## Model and important limits

The adopted tonal base preserves some source-relative variation through the combined Retinex/zone/lift portion, but black mapping, corrective and print remain outside that shared calculation. A literal full-chain preservation model needs a local estimate of the processed output as well as the original source. The current single ColorTransform pass has no precomputed surface containing that output. A real implementation would require further processing/resources or duplicate full-chain evaluation, with real performance, precision and timing costs; neither was built or profiled.

As a feasibility approximation, an offline script takes source PNG and current full-output PNG, decodes both to linear RGB, calculates a source log-luminance base with the existing 25-tap, 8-pixel-stride proximity/window scheme, and computes a processed log-luminance base using those same source-defined weights. It forms `source_detail - output_detail`, clamps it to ±0.5 stops, and blends the correction with a smooth input-Y shadow window from 0.002–0.012 and 0.05–0.15. It scales output linear RGB by the bounded gain and encodes/clamps to an 8-bit image. This changes final-output luminance and is an exploratory whole-chain approximation, not an HLSL implementation, validated image formation model, or separate GPU observation. No assumptions of exact scene reflectance or new information are justified.

The source PNG is not proven identical to the rendered signal sampled on GPU; previous work observed source transfer differences. The input/output PNGs have 8-bit quantization, dither, the intentional marker and game UI, so the model can interpret quantization, marker or UI as detail. In particular, its 25-tap output-window reads include the activity marker near the upper-left corner; the initial 10-code GZW maximum at (2,0) is contaminated and is excluded. Excluding a 24×24 marker neighborhood, maxima are 5/4/5 codes in GZW dark, Arc interior, and Arc vivid under GZW profile. This does not prove other samples are free of UI or sampling contamination. Boundaries, exact-zero identity and noisy or moving sources are unvalidated.

## Selected findings

| Source-selected selection | Current visible L gap | CPU model L gap | 4-pixel neighbor log gap, current → model |
|---|---:|---:|---:|
| GZW shelf | 2.661 | 2.661 | 0.115991 → 0.116003 |
| GZW blue wall | 9.480 | 9.524 | 0.075500 → 0.079903 |
| Arc dark metal | 8.981 | 9.011 | 0.136975 → 0.138188 |
| Arc cool upper | 20.385 | 20.368 | 0.101640 → 0.101277 |
| Arc cool window | 31.973 | 31.969 | 0.149985 → 0.151382 |
| GZW-profile Arc vivid blue field | 27.390 | 27.379 | 0.160929 → 0.160002 |

These fixed-source region and neighbor statistics are descriptive, not visual quality scores; the native crops show no clear target improvement. The vivid scene is Arc source with GZW settings, not a third game. Current full baselines are the earlier current-profile captures; their source and image SHA-256 values are in `captures/full_chain_shadow_20261105/metrics.json`. No new GPU capture or repeat, explicit pre-quantization readback, actual-config verification, boundary chart, motion/cut test, noise test or performance measurement was performed for this offline model. 20-second static prior captures and source/profile identities retain their original limitations.

The CPU calculation does not establish that the input-side and output-side bases are faithful to actual GPU operations; in particular source and processed neighborhoods differ and the output estimate is weighted from source windows. Its magnitude and palette changes are not predictive of a GPU implementation. This modest, mixed preliminary result does not justify an additional full-resolution surface/pass or more parameter search under the user's clear-visible-improvement criterion. Local script, model PNGs, crops and metrics remain ignored under `captures/full_chain_shadow_20261105/`.
