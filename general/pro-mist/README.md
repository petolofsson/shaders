# Pro-Mist

Black Pro-Mist optical diffusion filter simulation. Removes the clinical sharpness of digital rendering without adding bloom or glow.

## What it does

Applies a separable Gaussian blur to the scene and blends it back onto the original, gated by a luminance mask. The gate is strongest in the highlight range (DIFFUSE_LUMA_LO–DIFFUSE_LUMA_HI) and fades out toward near-white (DIFFUSE_LUMA_CAP) to keep bright surfaces crisp. A green-channel extension lowers the gate for green-dominant pixels so dark foliage is included.

The result: edges lose their pixel-perfect hardness, highlights soften slightly. No light is added — purely a softening operation.

## Passes

1. **DiffuseH** — horizontal 9-tap Gaussian → `DiffuseTex`
2. **DiffuseV** — vertical 9-tap Gaussian on `DiffuseTex` + luminance-gated blend onto scene

## Key parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `DIFFUSE_STRENGTH` | 0.22 | Softness intensity (0–1) |
| `DIFFUSE_RADIUS` | 0.020 | Physical blur width |

## Chain position

    … → color_grade → pro_mist → veil → output_transform

## Debug indicator

Magenta pixel block at x:2399–2411, y:15–27.
