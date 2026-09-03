# Handoff - 2026-09-03

Read at session start. Keep under 60 lines. One fact per line.

## Active Chain

`analysis_frame : inverse_grade : corrective : grade`
`grade`: LFDownscale1 -> LFDownscale2 -> NeutralIllum -> GuidedCoeff -> GuidedBase -> ColorTransform -> DiffusionDownsample -> DiffusionBlurH -> DiffusionBlurV -> Diffusion -> TexHwyWrite

## Current State

- `CLAUDE.md` was renamed to `AGENTS.md`.
- Runtime compile/capture passed via `compare_frame --all-effects --only FILM_CURVE` on 1 Arc Raiders frame.
- `/tmp/vkbasalt.log` was not created during that successful runtime pass.
- FilmCurve is a luminance-preserving, shoulder-only transform with no toe knobs.
- FilmCurve is applied once after spatial tonal processing; inverse-grade no longer compensates
  for it.
- The shoulder is monotonic, preserves channel ratios, and keeps overrange values bounded for SDR.
- `BLACKS/WHITES` remap happens at the top of `ColorTransformPS`.
- `INVERSE_LUMA` runs before exposure as source reconstruction.
- `EXPOSURE` feeds DIR, FilmCurve, and 3-way CC.
- Halation, the negative matrix, Bezold-Bruecke, Abney, and chromatic induction
  have been removed from the active chain.
- Stable minimal checkpoint: Arc Raiders keeps inverse reconstruction, exposure,
  FilmCurve, adaptive contrast, shadow lift, and no game color-design knobs.
- Adaptive contrast is signed around the local zone median with a reduced shadow arm and
  highlight protection; shadow lift remains separately adaptive.
- Retinex and zone shaping attenuate smoothly in bright highlights to protect cloud detail.
- Retinex now uses a bounded log-domain gain and attenuates where 1/16 and 1/32 low-frequency
  scales disagree, reducing broad-edge haloing.
- Diffusion now uses a soft-thresholded bright pass and uniform additive bloom; the radial eye
  mask, full-image blur subtraction, and midtone blur overlay were removed.
- `DIFFUSION=0` is a true bypass.
- The 2x2 red top-left activity marker is intentional and should be masked in strict image tests.
- Exact-white frame/zone histogram samples are clamped into the final bin.
- Scene cut combines p50 delta with raw entropy delta.
- Guided-filter epsilon is local-variance adaptive.
- `compare_frame --all-effects` no longer references removed DIR/toe knobs.
- `tools/noise_floor.py` measures EXR high-frequency energy.
- Arc Raiders and GZW now share the new stable profile baseline: inverse controls `0.70`,
  FilmCurve `0.15`, Contrast/Shadows `1.00`, PrintStock `0.35`, Diffusion `0.5`, Grain `0.60`.
- Chroma and LOOK gates are enabled; creative hue-band controls remain absent from both profiles.
- `bless_all --check --game arc_raiders --delay 5` fails 4/4 vs old `dcc712f` goldens; review before reblessing.

## Next

- Run cross-game visual validation when convenient; avoid changing the stable shader/profile state
  without recording a new experiment.
- Review/rebless goldens only after visual acceptance.
