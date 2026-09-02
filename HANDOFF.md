# Handoff - 2026-09-02

Read at session start. Keep under 60 lines. One fact per line.

## Active Chain

`analysis_frame : inverse_grade : corrective : grade`
`grade`: LFDownscale1 -> LFDownscale2 -> NeutralIllum -> GuidedCoeff -> GuidedBase -> ColorTransform -> DiffusionDownsample -> DiffusionBlurH -> DiffusionBlurV -> Diffusion -> TexHwyWrite

## Current State

- `CLAUDE.md` was renamed to `AGENTS.md`.
- Runtime compile/capture passed via `compare_frame --all-effects --only FILM_CURVE` on 1 Arc Raiders frame.
- `/tmp/vkbasalt.log` was not created during that successful runtime pass.
- R205 FilmCurve is active: shoulder-only inverse, no toe knobs, WHITES taper.
- `BLACKS/WHITES` remap happens at the top of `ColorTransformPS`.
- `INVERSE_LUMA` runs before exposure as source reconstruction.
- `EXPOSURE` feeds DIR, FilmCurve, and 3-way CC.
- Halation, the negative matrix, Bezold-Bruecke, Abney, and chromatic induction
  have been removed from the active chain.
- Stable minimal checkpoint: Arc Raiders keeps inverse tone mapping, exposure,
  FilmCurve, adaptive contrast, shadow lift, grain, and no game color-design knobs.
- `DIFFUSION=0` is a true bypass.
- The 2x2 red top-left activity marker is intentional and should be masked in strict image tests.
- Exact-white frame/zone histogram samples are clamped into the final bin.
- Scene cut combines p50 delta with raw entropy delta.
- Guided-filter epsilon is local-variance adaptive.
- `compare_frame --all-effects` no longer references removed DIR/toe knobs.
- `tools/noise_floor.py` measures EXR high-frequency energy.
- Arc Raiders values: `FILM_CURVE=0.65`, `PRINT_STOCK=0.75`, `GRAIN=0.40`,
  `CHROMA_STRENGTH=000`, `LOOK_STRENGTH=000`.
- `bless_all --check --game arc_raiders --delay 5` fails 4/4 vs old `dcc712f` goldens; review before reblessing.

## Next

- Decide whether Arc Raiders `LOOK_STRENGTH=000` is intentional.
- Run full `compare_frame --all-effects --game arc_raiders` after the LOOK decision.
- Review/rebless goldens only after visual acceptance.
