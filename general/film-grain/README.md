# Film Grain

Luminance-weighted animated film grain. Hides 8-bit banding introduced by the grade chain and adds physical texture to the output.

## What it does

Generates per-pixel pseudo-random noise using a high-quality hash seeded by screen position and frame count. The grain amplitude is weighted by a bell curve peaking at luma 0.5 — matching the grain distribution of real photochemical film: strongest in midtones, fading to zero at pure black and pure white.

Frame count seeds the hash so grain animates every frame rather than being static digital noise.

## Key parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `GRAIN_STRENGTH` | 3.5 | Peak noise amplitude (subtle: 2–4) |
| `GRAIN_SIZE` | 1.0 | Pixel clump size — 1=per-pixel, 2=2×2 clumps |

## Chain position

Place at the end of the chain, after `output_transform`.

    … → output_transform → film_grain

## Debug indicator

Dark purple pixel block at x:2429–2441, y:15–27.
