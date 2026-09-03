# Pipeline Plan

Tracks completion/novelty at stage level. Novelty is judged against game
post-processing, not color-science literature.

| Stage | Finished | Novel | Notes |
|-------|----------|-------|-------|
| Input / `inverse_grade` | 99% | 90% | Source reconstruction plus Oklab chroma expansion bounded by hue ceilings; FilmCurve is no longer pre-inverted. Remaining risk: ACES-biased slope calibration. |
| Film stock / corrective | 99% | 94% | DIR couplers, luminance-preserving FilmCurve, 2383 print stock, masking/dye couplers. Remaining risk: empirical amplitude calibration. |
| Tonal | 98% | 90% | Zone statistics, Retinex, signed adaptive contrast, Oklab L substitution, shadow lift, guided-filter detail. Local adaptive epsilon is implemented. |
| Color | 98% | 89% | Munsell ceilings and gamut projection. Removed low-value perceptual and surround transforms. Remaining risk: stacked hue interactions. |
| Output | 98% | 93% | HBM diffusion, temporal dither, Selwyn-style grain, intentional red activity marker. Remaining risk: noise floor and PSF calibration. |

## Current Priorities

1. Review current Arc Raiders output against stale `dcc712f` goldens before reblessing.
2. Run cross-game visual validation for the shared Arc Raiders/GZW baseline.
3. Use `tools/noise_floor.py` on matched renders when evaluating dither/grain changes.
5. Either use or remove unused highway/context surfaces: `HWY_CHROMA_P75`,
   `HWY_HUE_CONC`, `HWY_P10`, `HWY_IQR`, and `ctx.illum_warm`.

## Scoring Discipline

- Directional constants should be literature-backed where possible.
- Amplitudes and blend endpoints are allowed to be empirical, but must be tested.
- Do not inflate novelty for standard concepts such as exposure, saturation,
  bloom, LUT-like color shifts, or generic film grain.
- Prefer effect-attribution data over theoretical confidence when stages interact.
