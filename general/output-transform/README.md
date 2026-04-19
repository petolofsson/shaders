# Output Transform

Display Rendering Transform — last shader in the chain. Applies an OpenDRT-inspired tone curve, gamut compression, and highlight chroma compression.

## What it does

### Gamut compression
Handles out-of-gamut negatives (clamps to luma) and excess saturation above a threshold. Runs in linear space before the tone curve.

### OpenDRT tone curve
Per-channel filmic S-curve with analytically solved constants:

    f(x) = A × x^c / (x^c + K)

Constants K and A are derived from two constraints: scene grey (0.18) maps to display grey (0.18), and scene white (1.0) maps to display white (1.0). Result: slight shadow toe for contrast, smooth highlight shoulder — no hard clip.

### Highlight chroma compression
Desaturates pixels as luminance approaches 1.0. Matches film behaviour where highlights shift toward white rather than clipping with preserved hue.

## Key parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `CONTRAST` | 1.35 | Tone curve steepness — affects toe and shoulder |
| `CHROMA_COMPRESS` | 0.40 | Max highlight desaturation (0=none, 1=full gray) |
| `BLACK_POINT` | 3.5 | Black floor lift (0–100) |
| `SAT_MAX` | 85 | Gamut compression saturation threshold |
| `SAT_BLEND` | 15 | Gamut compression blend strength |

## Chain position

Must be last in the chain.

    … → color_grade → pro_mist → veil → output_transform

## Debug indicator

Dark red pixel block at x:2549–2561, y:15–27.
