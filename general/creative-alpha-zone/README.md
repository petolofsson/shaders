# Alpha Zone Contrast

Histogram-driven adaptive luma contrast for the alpha pipeline.

## What it does

Builds a luminance CDF from the scene histogram (64 bins, sourced from `frame_analysis.fx`) and uses it as the tone curve:

    output_luma = lerp(input_luma, CDF(input_luma), CURVE_STRENGTH)

Dense tonal regions expand (more contrast where content lives). Sparse regions compress (no wasted contrast in empty ranges). The full 0–1 range is graded — no fixed pivots, no parameterized S-shape.

## Passes

1. **BuildCDF** — prefix sum of `LumHistTex` (64 bins) → `LumCDFTex`. Temporally lerped for stability. Cold-start detection: if last CDF bin < 0.5, fills instantly (speed=1.0) rather than waiting for LERP_SPEED ramp-up.
2. **ApplyContrast** — samples CDF at pixel luma, blends toward equalized value, scales RGB by `new_luma / luma` (hue + saturation preserved). Near-black guard at `luma < 0.005`. Scale capped at 3× to prevent near-black blow-up.

## Key parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `CURVE_STRENGTH` | 0.30 | Blend toward full equalization — 0=bypass, 1=clinical |
| `LERP_SPEED` | 0.08 | Temporal smoothing rate for CDF stability |
| `HIST_BINS` | 64 | Must match `frame_analysis.fx` exactly |

## Chain dependency

    frame_analysis → alpha_zone_contrast → alpha_chroma_contrast

## Debug indicator

Teal pixel block at x:2519–2531, y:15–27 (luma 0.55 in the brightness gradient).
