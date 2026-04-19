# Youvan Orthonorm

Dynamic color space orthonormalization. Removes per-zone color cast introduced by the game engine's tone mapper and grading before the adaptive shaders process the signal.

## What it does

Samples 64 Halton-distributed points per frame, classifies them into dark / mid / bright luma zones, and computes per-zone mean RGB. A 3×3 correction matrix maps those means toward luma-equivalent neutral grays. Applied per-pixel with a blend strength control.

Saturation and brightness are preserved: the correction is hue-only — the matrix output is rescaled to match the input channel maximum and saturation ratio, so only the color cast is removed.

## Passes

1. **ZoneStats** — 64 Halton samples → per-zone mean RGB → `ZoneTex` (temporal lerp)
2. **ComputeMatrix** — build 3×3 correction matrix B from zone means → `MatrixTex`
3. **ApplyOrtho** — apply B per-pixel blended by `ORTHO_STRENGTH`

## Key parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `ORTHO_STRENGTH` | 15 | Correction blend — 0=bypass, positive=toward neutral, negative=exaggerate |
| `LERP_SPEED` | 2 | Matrix adaptation speed — lower keeps matrix stable across cuts |
| `ZONE_DARK_MAX` | 33 | Luma threshold: dark zone upper bound |
| `ZONE_BRIGHT_MIN` | 66 | Luma threshold: bright zone lower bound |

## Chain dependency

    primary_correction → frame_analysis → youvan_orthonorm → alpha_zone_contrast

## Debug indicator

Green pixel block at x:2459–2471, y:15–27.
