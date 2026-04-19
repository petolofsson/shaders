# Frame Analysis

Per-frame histogram analysis. Shared data source for the adaptive contrast and chroma shaders.

## What it does

Downsamples the frame to 32×18, then builds two smoothed histogram textures that persist until the next frame:

- **LumHistTex** — 64-bin luminance histogram (R32F, 64×1)
- **SatHistTex** — 64-bin saturation histogram per hue band (R32F, 64×6)

Samples are linearized before binning so percentile values are in linear light, consistent with the shaders that consume them.

## Passes

1. **Downsample** — bilinear reduce to 32×18 → `DownsampleTex`
2. **LumHistRaw** — scatter luma samples into 64 buckets → `LumHistRawTex`
3. **SatHistRaw** — scatter saturation samples into 64 × 6 hue-band buckets → `SatHistRawTex`
4. **SmoothLum** — temporal lerp `LumHistRaw` → `LumHistTex`
5. **SmoothSat** — temporal lerp `SatHistRaw` → `SatHistTex`

## Key parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `LERP_SPEED` | 8 | Histogram temporal smoothing rate — higher = faster response |
| `SAT_THRESHOLD` | 4 | Minimum saturation to include in saturation histogram |
| `HIST_BINS` | 64 | Bin count — must match `alpha_zone_contrast` and `alpha_chroma_lift` |

## Chain dependency

Must run before any shader that reads `LumHistTex` or `SatHistTex`:

    frame_analysis → youvan_orthonorm → alpha_zone_contrast → alpha_chroma_lift

## Debug indicator

Yellow pixel block at x:2489–2501, y:15–27.
