# Alpha Chroma Contrast

Per-hue-band saturation equalization via CDF LUT for the alpha pipeline.

## What it does

Each of 6 hue bands (Red / Yellow / Green / Cyan / Blue / Magenta) gets its own CDF built from the corresponding row of `SatHistTex` (sourced from `frame_analysis.fx`):

    output_sat = lerp(input_sat, CDF_band(input_sat), CURVE_STRENGTH)

Bands overlap with smooth Gaussian-style weights so transitions are seamless. A 4° cool hue shift on greens is preserved from the stable build.

## Passes

1. **BuildSatCDF** — per-band prefix sum of `SatHistTex` rows → `SatCDFTex` (64×6 R32F). Temporal lerp per band with cold-start detection.
2. **ApplyChroma** — per-pixel HSV conversion, 6-band CDF lookup + hue-weighted blend, green cool-shift, HSV→RGB. Pixels below `SAT_THRESHOLD` are passed through unchanged.

## Key parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `CURVE_STRENGTH` | 0.45 | Blend toward full per-band equalization |
| `LERP_SPEED` | 0.08 | Temporal smoothing rate |
| `BAND_WIDTH` | 0.15 | Hue band overlap width (0–1 hue space) |
| `SAT_THRESHOLD` | 0.05 | Skip equalization below this saturation |
| `GREEN_HUE_COOL` | 4°  | Cool hue shift applied to green pixels |

## Chain dependency

    frame_analysis → alpha_zone_contrast → alpha_chroma_contrast → color_grade

## Debug indicator

Orange-red pixel block at x:2504–2516, y:15–27 (luma 0.41 in the brightness gradient).
