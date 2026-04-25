# Olofssonian Color Grade

A creative film-stock color grade for ReShade and vkBasalt. Shared between the stable and alpha shader chains.

Replaces the clinical look of digital rendering with the optical character of photochemical negative film — inter-channel dye bleed, non-linear tone in shadows and highlights, and stock-dependent gamut behavior.

## Film presets

Set `#define PRESET` at the top of the shader:

| Preset | Stock | Character |
|--------|-------|-----------|
| 1 *(default)* | ARRI ALEXA | Clean, neutral, wide latitude |
| 2 | Kodak Vision3 500T | Warm shadows, golden highlights, slightly desaturated mids |
| 3 | Sony Venice | Warm neutral, slight character, protected mids |
| 4 | Fuji Eterna 500 | Cool, flat, green-leaning mids |
| 5 | Kodak 5219 | Punchy, pushed, deep warm blacks |

## Operations (in order)

1. **Indigo toe tint** — bell-curve additive tint in deep shadows, saturation-gated. Reproduces the cool shadow character of Vision3 internegative.
2. **Black lift** — additive floor in pure blacks. Replicates film base fog.
3. **Shadow tint** — luma-weighted additive tint in lower midtones, saturation-gated.
4. **Highlight lift** — warm additive tint in near-white highlights, falls off at true white.
5. **Luma-neutral midtone cast** — per-channel gain applied at constant luma (no net brightness change). Shifts hue of midtones without brightness drift.
6. **White point** — per-channel quadratic roll-off at the highlight ceiling. Stock-dependent.
7. **Film print matrix** — inter-channel dye bleed. Each channel receives small contributions from the others. Gated by chroma and luma so it only fires on sufficiently saturated, non-black pixels.

`GRADE_STRENGTH` lerps from bypass (0.0) to full preset (1.0). Values above 1.0 overdrive the effect.

## Key parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `PRESET` | 1 | Film stock selection (1–5) |
| `GRADE_STRENGTH` | 1.0 | 0=bypass, 1=full, >1=overdrive |
| `TOE_RANGE` | 0.30 | Luma extent of toe tint bell curve |
| `SHADOW_RANGE` | 0.18 | Upper luma limit of shadow tint |
| `HIGHLIGHT_START` | 0.65 | Luma where highlight lift begins |

## Usage

### vkBasalt (Linux)

```ini
color_grade = /path/to/olofssonian_color_grade.fx
effects = color_grade
```

### ReShade (Windows)

Copy `olofssonian_color_grade.fx` into `reshade-shaders/Shaders/` and enable `OlofssonianColorGrade` in the overlay.

## Debug indicator

Cornflower blue pixel block at x:2534–2546, y:15–27 (luma 0.25 in the brightness gradient).

## Author

Peter Olofsson — photographer, photojournalist.
