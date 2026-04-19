# Veil

Veiling glare simulation — atmospheric contrast reduction. The opposite of bloom: compresses local contrast by blending a blurred copy of the scene onto itself.

## What it does

Downsamples the frame with a Kawase filter, upsamples it back to full resolution, then lerps it onto the original scene. Effect:

- Darks lift slightly (bright neighbours bleed in via the blur)
- Brights pull down slightly (dark neighbours lower the blur average)
- Result: reduced local contrast, a sense of air and physical depth

Two gates prevent unwanted artefacts:
- **White gate** — prevents glow on very bright surfaces (concrete, overlit areas)
- **Sky gate** — blue-dominant pixels skip the veil to prevent teal sky tint

## Passes

1. **Down** — Kawase downsample BackBuffer → `VeilDownTex` (half res)
2. **Up** — Kawase upsample `VeilDownTex` → `VeilUpTex` (half res)
3. **Apply** — optional warm tint (luma-preserving) + gated lerp onto scene

## Key parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `VEIL_STRENGTH` | 0.10 | Lerp toward blurred scene (0=off, 0.20=heavy haze) |
| `VEIL_WARMTH` | 0.5 | Warm tint on veil layer (0=neutral, 1=full warm) |

## Chain position

    … → pro_mist → veil → output_transform

## Debug indicator

Periwinkle pixel block at x:2414–2426, y:15–27.
