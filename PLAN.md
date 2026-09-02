# Pipeline Plan

Tracks completion/novelty at stage level. Novelty is judged against game
post-processing, not color-science literature.

| Stage | Finished | Novel | Notes |
|-------|----------|-------|-------|
| Input / `inverse_grade` | 99% | 90% | Tonemapper shoulder pre-inverse plus Oklab chroma expansion bounded by hue ceilings. Remaining risk: ACES-biased slope calibration. |
| Film stock / corrective | 99% | 94% | Negative matrix, DIR couplers, FilmCurve, 2383 print stock, masking/dye couplers. Remaining risk: empirical amplitude calibration. |
| Tonal | 98% | 90% | Zone statistics, Retinex, Oklab L substitution, shadow lift, guided-filter detail. Local adaptive epsilon is implemented. |
| Color + halation | 98% | 89% | HELMLAB, Munsell ceilings, Abney, HK, Purkinje/shadow cast, framebuffer-only halation. Remaining risk: stacked hue interactions. |
| Output | 98% | 93% | HBM diffusion, temporal dither, Selwyn-style grain, intentional red activity marker. Remaining risk: noise floor and PSF calibration. |

## Current Priorities

1. Decide whether Arc Raiders should keep `LOOK_STRENGTH 000`.
2. Review current Arc Raiders output against stale `dcc712f` goldens before reblessing.
3. Run full `compare_frame --all-effects --game arc_raiders` after the LOOK gate decision.
4. Use `tools/noise_floor.py` on matched renders when evaluating dither/grain changes.
5. Either use or remove unused highway/context surfaces: `HWY_CHROMA_P75`,
   `HWY_HUE_CONC`, `HWY_P10`, `HWY_IQR`, and `ctx.illum_warm`.

## Scoring Discipline

- Directional constants should be literature-backed where possible.
- Amplitudes and blend endpoints are allowed to be empirical, but must be tested.
- Do not inflate novelty for standard concepts such as exposure, saturation,
  bloom, LUT-like color shifts, or generic film grain.
- Prefer effect-attribution data over theoretical confidence when stages interact.
