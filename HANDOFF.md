# Handoff — 2026-10-24

Read this first. New stage results: [research/2026-10-24_stage_verification.md](research/2026-10-24_stage_verification.md).
Earlier implementation: [research/2026-10-23_session_restart.md](research/2026-10-23_session_restart.md).
Pipeline rules: [AGENTS.md](AGENTS.md). Keep this file under 60 lines.

## Chain

Active `gzw.conf`: `analysis_frame : inverse_grade : corrective : grade`.
Trial `gzw_stronger_trial.conf`: one `pipeline` effect containing those passes.
`grade`: LFDownscale1 -> LFDownscale2 -> NeutralIllum -> GuidedCoeff -> GuidedBase -> ColorTransform -> AdaptiveHistory -> TexHwyWrite

## Current GZW profile

- Source of truth: `gamespecific/gzw/shaders/creative_values.fx`; user has changed these values during the session, use the file.
- INVERSE_STRENGTH .75, INVERSE_LUMA .6, BLACKS 0, WHITES .995, EXPOSURE 0, FILM_CURVE .75.
- SHADOW_TEMP -.15, SHADOW_TINT -.05, MID_TEMP 0, MID_TINT 0, HIGHLIGHT_TEMP .10, HIGHLIGHT_TINT 0.
- CONTRAST 1.5, SATURATION .25, SHADOWS/RETINEX/ZONE_CONTRAST 1, SHADOW_LIFT .75.
- PRINT_STOCK 1, printer lights 0, all stage gates 100.
- GZW config and shader header comments were not edited.

## Code changes

- Explicit sRGB decode/encode over UNORM BackBuffer; runtime swapchain was 10-bit UNORM.
- Signed, high-range internal Oklab; 10-step two-sided gamut projection at SDR boundaries.
- Preserve input chroma through soft HueCeil/gamut pre-knee; physical SDR projection still bounds output.
- Fix Retinex and chroma reconstruction denominators, early clipping, FilmCurve asymptote and exact-black energy addition.
- Local channel near-clip protection, spatial-lane UV clamp, sRGB code-domain endpoint-safe dither.
- Time-based selective hysteresis and zone/slow-key rates; scene cuts do not force max film/print targets.
- Combined trial keeps cross-effect resources inside one technique; smoothed histogram consumers now normalize startup mass.
- `compare_frame --all-effects` now loops lossless RGB video so `--settle` advances history, then pauses for capture; it checks playback and can retain PNGs. Scene-cut and throughput probes were added.
- Screenshots cannot decode offscreen HighwayTex; `capture --dump/--no-frame` now fails explicitly.
- Golden-image system and synthetic fixtures were removed at the user's earlier request; do not restore them.
- Full implementation details and scope: [fidelity implementation record](research/2026-10-23_fidelity_implementation.md).

## Orange investigation and evidence

- `MID_TEMP=.10` shifted orange about +4.2° toward yellow in an isolated GZW frame comparison; GZW is now at 0.
- On 61 source pixels selected as high-chroma orange, drift changed +3.52° to -.76°; chroma change moved +.627 to +.099 (Oklab×100).
- Current profile compiled/rendered. After chroma-floor change, same-frame output moved only mean ΔE .000344; orange mask was unchanged because it was already in gamut.
- These are single-frame change measurements, not visual-quality scores. Full capture history and caveats: [orange investigation](research/2026-10-23_gzw_orange_hue.md).
- `gamespecific/gzw/full_analysis/latest.json` is a live-chain run; `full_analysis/alternate/latest.json` is the combined trial. Read each JSON's profile/config before comparing.

## Restart priorities

- GZW's configured four-effect chain gives grade zeroed cross-effect highway and
  zone history. A combined effect compiles and restores contrast/Retinex in
  `gzw_stronger_trial.conf`; see [resource finding](research/2026-10-23_cross_effect_resources.md).
- `gzw.conf` remains on the four-effect chain pending live trial review.
- Earlier still-image `--settle` runs were paused; their temporal convergence claims are superseded. New all-effects runs use continuous 30 fps playback, fresh processes, 20-second settle, and unchanged repeats.
- GZW sunset: fixed-endpoint corrective/tonal/chroma/look gate bypasses change output by 2.38/1.51/0.97/2.94 ΔE; inverse luma 1.79, Retinex .57, zone contrast 1.39, saturation .82. FilmCurve and inverse chroma barely engage there.
- GZW dark gameplay: shadow lift changes output by 2.35 ΔE. Bright Arc inputs activate inverse chroma (.15) and FilmCurve under Arc's own profile (.15); `arc_raiders_pipeline_trial.conf` preserves the tested combined config. Full results and exact JSON paths are in the new stage report.
- Dark→sunset→dark cut probe: early-to-late output changes .192/.210 ΔE; return dark still differs .334 ΔE after 6.5 seconds. Five runs dropped zero 30 fps mpv frames. No direct highway telemetry.
- User reports roughly a 10 FPS in-game cost and considers it acceptable. Untimed mpv/MangoHud pairs could not isolate shader GPU time. Twelve diagnostic tests pass.
- Raw histogram mass was .999 but smoothed mass .436 at five seconds. After
  normalization, GPU p25/p50/p75 match the source estimate. Details in the resource finding.
- Resume with live judgment of trial strength, GZW orange, and the provisional effect rankings in [stage verification](research/2026-10-24_stage_verification.md); GZW references still lack bright saturated objects and broad highlights.
- Validate real motion, emitters, output noise, and longer cut recovery from GZW gameplay footage.
- Recalibrate profiles only from matched current captures; repeat effect baselines and preserve concurrent user edits.
