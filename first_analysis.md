# First Pipeline Analysis

Date: 2026-09-02

Scope: root docs, active Arc Raiders/GZW configs and profiles, and shared shader
code under `general/`.

## Verdict

The pipeline architecture is valid: `analysis_frame -> inverse_grade -> corrective
-> grade` matches data dependencies, preserves BackBuffer where needed, avoids
known vkBasalt mip pitfalls, and keeps SDR output bounded. Remaining risk is
validation/calibration of a dense perceptual stack, not broad architecture.

## Findings

| Item | Status | Note |
|------|--------|------|
| Diffusion zero bypass | fixed | Removed fixed `0.10` midtone overlay baseline; `DIFFUSION=0` now bypasses. |
| Red activity marker | intentional | Restored 2x2 top-left red pixels by user request; mask in strict image tests. |
| Exact-white histogram samples | fixed | Frame and zone histograms clamp `luma` to `< 1.0` before binning. |
| Exposure order | fixed | `INVERSE_LUMA` remains source reconstruction; `EXPOSURE` now feeds DIR, FilmCurve, and 3-way CC. |
| Arc Raiders LOOK gate | open | `LOOK_STRENGTH 000`; configured print stock and printer lights do nothing there. |

## Pipeline Notes

- `analysis_frame.fx`: spatial highway lane, histograms, percentiles, scene cut,
  chroma stats, entropy/mode, scalar highway slots.
- `inverse_grade.fx`: pre-corrective FilmCurve shoulder inverse and Oklab chroma
  expansion with hue ceilings.
- `corrective.fx`: zone/chroma history and slow key; passthrough is required.
- `grade.fx`: corrective, tonal, chroma, LOOK, diffusion, dither, grain, and final
  highway publication.
- `HighwayTex` is `R16F`; slot values are normalized by convention.

## Quality Work Applied

- Scene cut combines p50 delta with raw histogram entropy delta.
- Guided-filter epsilon is local-variance adaptive.
- `compare_frame --all-effects` no longer references removed DIR/toe knobs and
  now fails if a requested knob is missing.
- Added `tools/noise_floor.py` for EXR high-frequency measurements.
- LFDownscale1 was reviewed but not changed; offsets are consistent with packed
  `TexHwyTex` coordinates.

## Current Risks

- Arc Raiders LOOK is disabled while LOOK knobs are configured.
- Current Arc Raiders output fails old `dcc712f` goldens; review before reblessing.
- Chroma stage has many individually plausible hue/chroma transforms; validate
  combined output with hue-band attribution.
- Some produced data is lightly used or unused: `HWY_CHROMA_P75`, `HWY_HUE_CONC`,
  `HWY_P10`, `HWY_IQR`, `ctx.illum_warm`.
- `INVERSE_STRENGTH <= 0` also disables FilmCurve pre-inverse; document or split
  if that coupling becomes undesirable.

## Tests Recorded

- Python compile for analysis tools: pass.
- Active stale-token search for removed DIR/toe knobs and old diffusion term: pass.
- One-frame runtime `compare_frame --all-effects --only FILM_CURVE`: pass,
  FilmCurve contribution `DeltaE 1.12`.
- `bless_all --check --game arc_raiders --delay 5`: fails 4/4 against old goldens.
  MAE: gradient `0.22923`, colorchecker `0.27139`, highlights `0.21470`,
  skintones `0.34145`.
- `/tmp/vkbasalt.log` was not created during the runtime pass.

## Next

1. Decide Arc Raiders `LOOK_STRENGTH`.
2. Visually review current output and decide whether to rebless goldens.
3. Run full `compare_frame --all-effects --game arc_raiders`.
4. Use `noise_floor.py` on matched renders for dither/grain decisions.
