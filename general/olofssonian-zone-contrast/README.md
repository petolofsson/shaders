# OlofssonianZoneContrast

A real-time adaptive contrast shader for ReShade and vkBasalt.

Instead of applying a fixed contrast curve, it samples the scene each frame, extracts the tonal distribution, and pivots two S-curves at the scene's own 25th and 75th percentiles. Each pixel then self-selects its correction based on where it sits in that distribution.

## How it works

Each frame, 128 quasi-random [Halton(2,3)](https://en.wikipedia.org/wiki/Halton_sequence) points are sampled across the screen. An in-shader bitonic sort extracts the 25th, 50th, and 75th percentile luminance values. Two S-curves are constructed — one pivoted at the dark percentile, one at the bright — and blended per-pixel using the scene's own interquartile range as the blend axis. Scenes with compressed tonal range receive more correction; wide-range scenes receive less.

All operations are luma-only. Hue is preserved.

**Key properties:**
- No histogram buffer, no compute shader, no multi-pass accumulation
- Single pixel shader pass with a small history texture for temporal smoothing
- Resolution-independent (Halton points are UV coordinates)
- Temporal lerp on percentile values prevents flicker on scene cuts

## Prior art

The closest published work is the **Quartile Sigmoid Function (QSF)** — "Adaptive Quartile Sigmoid Function Operator for Color", IS&T Color Imaging Conference (CIC), 9th edition. QSF also uses Q1/Q3 quartile pivots, but operates offline, hard-switches at the median, and processes per-channel RGB (causing hue shifts). OlofssonianZoneContrast differs in every dimension: continuous per-pixel blend, luma-only, real-time single-pass, temporally stable.

The conceptual seed was Todd Dominey's video [*The Wrong Way to Add Contrast (and What to Do Instead)*](https://www.youtube.com/watch?v=BTe0JLe5g2Y) — the insight that contrast curve pivots should be derived from the scene's own tonal distribution, not a fixed constant.

## Usage

### vkBasalt (Linux)

Add to your vkBasalt config:
```ini
olofssonian_zone_contrast = /path/to/olofssonian_zone_contrast.fx
effects = olofssonian_zone_contrast
```

### ReShade (Windows)

Copy `olofssonian_zone_contrast.fx` into your `reshade-shaders/Shaders/` folder and enable `OlofssonianZoneContrast` in the ReShade overlay.

Place it **first** in the effect chain for correct results.

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `CURVE_STRENGTH` | 0.25 | S-curve bend intensity |
| `LERP_SPEED` | 0.08 | Temporal smoothing speed (lower = slower adaptation) |
| `TOE_STRENGTH` | 0.37 | Shadow darkening (cubic rolloff) |
| `TOE_RANGE` | 0.35 | Range of shadow gradient |
| `TOE_TINT_R/G/B` | -0.028 / -0.014 / +0.040 | Indigo shadow tint |
| `BLACK_LIFT_R/G/B` | 0.008 / 0.025 / 0.035 | Shadow floor lift |
| `SHOULDER_STRENGTH` | 0.10 | Highlight rolloff |

## Author

Peter Olofsson  
AI was used in the making of this code.
