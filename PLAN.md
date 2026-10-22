# Pipeline Plan

Tracks completion/novelty at stage level. Novelty is judged against game
post-processing, not color-science literature.

| Stage | Finished | Novel | Notes |
|-------|----------|-------|-------|
| Input / `inverse_grade` | 99% | 90% | Source reconstruction plus Oklab chroma expansion bounded by hue ceilings; FilmCurve is no longer pre-inverted. Remaining risk: ACES-biased slope calibration. |
| Film stock / corrective | 99% | 94% | DIR couplers, luminance-preserving FilmCurve, 2383 print stock, masking/dye couplers. Remaining risk: empirical amplitude calibration. |
| Tonal | 98% | 90% | Zone statistics, Retinex, signed adaptive contrast, Oklab L substitution, shadow lift, guided-filter detail. Local adaptive epsilon is implemented. |
| Color | 98% | 89% | Munsell ceilings and gamut projection. Removed low-value perceptual and surround transforms. Remaining risk: stacked hue interactions. |
| Output | 98% | 93% | Spatial dither and intentional red activity marker. Diffusion and grain are removed. |

## Current Priorities

1. Review current Arc Raiders output against stale `dcc712f` goldens before reblessing.
2. Run cross-game visual validation for the shared Arc Raiders/GZW baseline.
3. Use `tools/noise_floor.py` on matched renders when evaluating dither and quantization changes.
5. Validate the new scene-adaptive automation across Arc Raiders and GZW before
   reblessing goldens.

## Scoring Discipline

- Directional constants should be literature-backed where possible.
- Amplitudes and blend endpoints are allowed to be empirical, but must be tested.
- Do not inflate novelty for standard concepts such as exposure, saturation,
  bloom, LUT-like color shifts, or removed optical finishing effects.
- Prefer effect-attribution data over theoretical confidence when stages interact.
