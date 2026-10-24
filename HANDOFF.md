# Handoff — 2026-10-24

Read this first. Resumed from [the saved pause](research/2026-10-24_session_pause.md). Latest: [matched headless motion](research/2026-10-24_background_motion_resume.md), [history attribution](research/2026-10-24_shadow_history_readback.md), [Retinex halo fix](research/2026-10-24_retinex_edge_halo.md). Priorities: [PLAN.md](PLAN.md). Next session: [startup-prompt-latest](startup-prompt-latest); the [earlier work plan](research/2026-10-24_next_shader_work.md) is historical. Earlier chain change: [near-black zone precision](research/2026-10-24_shadow_zone_precision.md); previous [contrast toe](research/2026-10-24_contrast_shadow_toe.md). Earlier results: [automated Babylon course](research/2026-10-24_babylon_shader_course.md), [Babylon Firefox smoke test](research/2026-10-24_babylon_firefox_smoke.md), [Electric Dreams trailer probe](research/2026-10-24_electric_dreams_trailer_probe.md), [GZW audit continuation](research/2026-10-24_gzw_audit_continuation.md), and [stage verification](research/2026-10-24_stage_verification.md).
Earlier implementation: [research/2026-10-23_session_restart.md](research/2026-10-23_session_restart.md).
Agreed product direction: [GOAL.md](GOAL.md) — game-agnostic SDR color fullness, dimensionality and deep nuanced shadows, with unobtrusive automatic restraint. Pipeline rules: [AGENTS.md](AGENTS.md). Keep this file under 60 lines.

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
- Combined trial keeps resources inside one technique; smoothed histograms normalize startup mass. Zone analysis now uses 64 squared-edge bins with linear decoding; controlled dark-patch GPU median error fell from at most 33 to at most 2 equivalent 8-bit codes.
- `compare_frame` CLI now defaults to a private headless Gamescope display with post-vkBasalt captures; no desktop focus or monitor changes. `--capture-backend desktop` is explicit. Continuous lossless playback, fresh processes, repeats and settling are retained. [Validation](research/2026-10-24_background_capture.md).
- Screenshots cannot decode offscreen HighwayTex; `capture --dump/--no-frame` now fails explicitly.
- Golden-image system and synthetic fixtures were removed at the user's earlier request; do not restore them.
- Full implementation details and scope: [fidelity implementation record](research/2026-10-23_fidelity_implementation.md).

## Orange investigation and evidence

- `MID_TEMP=.10` shifted orange about +4.2° toward yellow in an isolated GZW frame comparison; GZW is now at 0.
- On 61 source pixels selected as high-chroma orange, drift changed +3.52° to -.76°; chroma change moved +.627 to +.099 (Oklab×100).
- Current profile compiled/rendered. After chroma-floor change, same-frame output moved only mean ΔE .000344; orange mask was unchanged because it was already in gamut.
- These are single-frame change measurements, not visual-quality scores. Full capture history and caveats: [orange investigation](research/2026-10-23_gzw_orange_hue.md).
- `gamespecific/gzw/full_analysis/latest.json` is a live-chain run; `full_analysis/alternate/latest.json` is the combined trial. Read each JSON's profile/config before comparing.

## Audit state and next work

- GZW's active four-effect chain still gives grade zeroed cross-effect highway and zone history. The combined trial restores those reads; see [resource finding](research/2026-10-23_cross_effect_resources.md). Do not switch `gzw.conf` without the user's request.
- Earlier paused-PNG `--settle` claims are superseded. Current effect captures loop lossless 30 fps RGB, use fresh processes, 20-second settle for small effects, and an unchanged repeat.
- GZW sunset gate bypasses: corrective/tonal/chroma/look 2.38/1.51/0.97/2.94 ΔE; inverse luma 1.79, Retinex .57, zone contrast 1.39, saturation .82. FilmCurve and inverse chroma barely engage there. Dark gameplay shadow lift: 2.35 ΔE.
- New GZW-profile Arc cloud stress: FilmCurve 0.152 ΔE, highlight −0.820 ΔL, inverse chroma 0.030, unchanged repeat 0.000005. Earlier vivid Arc stress: inverse chroma 0.146. Cross-game inputs test engagement, not GZW look quality.
- Source-selected GZW sunset bright orange covers 6.34% of sampled pixels; full output changed it by −5.69 ΔL, +0.11 ΔC, median −3.06° hue, with no new white-channel clipping. GZW sunset exact-black increase remains a live visual concern, not a justified profile edit.
- Direct packed GPU readback and two static/two cut repeats show local zones have settled by return +0.5 seconds; slow key carries the tail. Holding only grade’s slow-key consumer at the initial dark value reduces +6.5-second residual 0.341→0.000024 ΔE and +18-second residual 0.013→0.000018. Eight fresh readback/output runs dropped/delayed zero frames. Its deliberate slow rate is unchanged. [Evidence](research/2026-10-24_shadow_history_readback.md).
- Headless Babylon source export/replay is validated: 17 exact identities across all seven windows after one retry set; all six replay processes have zero mpv dropped/delayed frames. Mean trial/repeat 0.010 ΔE, foliage maximum 0.085. Twenty diagnostics pass. Sparse 15-pose/sec motion does not prove dense continuity or fidelity. [Evidence](research/2026-10-24_background_motion_resume.md). Shadow-history attribution is complete on the fixed dark/sunset pair; other transitions remain open.
- Two prior mpv/MangoHud pairs cannot isolate shader GPU cost. User reports about a 10 FPS in-game cost, considers it acceptable, and has explicitly deprioritized GPU cost.
- Earlier foreground Babylon forest/clearing/night course ran in isolated Firefox → Gamescope SDL → vkBasalt at 2560×1440, with held-frame baseline/trial/repeat captures (`--settle 20`) and a moving route with two verified cuts. Forest trial ΔE 7.773, revised night 1.881; both baseline repeats 0.000. See [runner](tools/babylon_scene/README.md) and [course report](research/2026-10-24_babylon_shader_course.md).
- Electric Dreams 28.6-second 1080p SDR promo was replayed through the GZW trial at 12 target times; baseline and trial each had zero mpv dropped/delayed frames at 30 fps, but this does not measure shader GPU cost. Clean scenes lack vivid emitters.
- A matched forest frame exposed black clipping under the GZW trial: settled source→full near-black 0.003%→1.803%; bypassing either contrast gate reduced full output to 0.069%. Continuous video baseline→trial was 0.017%→5.939%, with different transfer paths/history. Cross-game evidence does not justify changing GZW tuning.
- Black title cards at 10.9 and 15.6 seconds showed no residual forest image; the 19.9-second moving-text pair differed by one source frame and was excluded. Display was restored to 2560×1440 at 144 Hz; GZW tuning/config hashes are unchanged.
- Raw GZW/Arc footage may supplement later, but do not block on user recording. Next: establish the cross-game color/shadow-depth baseline in [PLAN.md](PLAN.md), then assess existing stages against [GOAL.md](GOAL.md). Matched motion is already available; the earlier [work plan](research/2026-10-24_next_shader_work.md) is historical.
- Retinex coarse-edge strength fading painted borders into uniform fields. The shared fix retains bounded gain/global confidence and reduces four matched clearing-pose halo gaps 3.50–3.61→0.37–0.88 L; 15 held GZW/Arc regression captures and two motion replays passed, with no new white clipping. Both profiles/configs and shader headers stay unchanged. [Evidence](research/2026-10-24_retinex_edge_halo.md). Remaining goal-led work: color/shadow baseline, nuanced shadows, color distinctions across brightness, convincing highlights, automatic stage coordination and cross-game/live review. New effects are deferred until a relevant gap is demonstrated. Earlier: fixed the local contrast shadow arm with a luminance-relative smooth bound: GZW sunset selected shadows becoming exact black 4.31%→0.11%; hardest ramp now retains 47 levels vs 20 before both fixes. Dark/bright/vivid and Arc combined/active-chain captures pass; true black stays black and bright regions barely change. See [evidence](research/2026-10-24_contrast_shadow_toe.md). Tuning/configs remain unchanged; matched Babylon motion is now validated above; dense continuity remains open.
