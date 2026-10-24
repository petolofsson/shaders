# Shader chain stage verification — 2026-10-24

The configured GZW `gzw.conf` still uses four separate effects. In that layout,
grade reads zero from cross-effect highway and zone resources. All measurements
below use `gzw_stronger_trial.conf`, which executes the passes in one technique.
No tuning values, shader source, shader header comments, or `gzw.conf` were
changed during this audit.

## Capture protocol correction

Earlier `--all-effects --settle 20` runs played a paused PNG in mpv. The elapsed
wait did not provide continuous rendered frames, so their temporal convergence
claim is superseded. The vkBasalt `before applying effect` log line counts command
buffer setup, not presented frames; an initial interpretation of its count was
wrong. `compare_frame --all-effects` now loops a lossless 30 fps FFV1 RGB clip,
checks mpv playback position and pause state, and retains paired PNGs with
`--keep`. A decoded clip frame matched its source PNG byte for byte. The early
continuous-playback ablations let video keep running during the slow desktop
screenshot, so their effective settle exceeded 20 seconds by a variable amount.
The gate run was repeated after pausing immediately at the 20-second capture
point; its four results matched the earlier gate run within 0.01 ΔE. Each run
used a matched unchanged FULL repeat. Twenty seconds is a reproducible test
point, not a proof of complete slow-key convergence.

## GZW sunset/menu frame

Source: `analysis/reference/autof_20260515_133932.png`. Full versus source was
5.64 mean Oklab ΔE (an image-change measure, not a fidelity score). The unchanged
repeat was 0.012 for the individual-control run and approximately zero for the
fixed-endpoint gate run. See [individual controls](../gamespecific/gzw/full_analysis/alternate/effects_2026-10-24_025209.json)
and [fixed-endpoint grade gates](../gamespecific/gzw/full_analysis/alternate/effects_2026-10-24_032937.json).

| Bypass | Mean ΔE | Interpretation on this scene |
|---|---:|---|
| INVERSE_STRENGTH | <0.01 | Chroma gate barely engaged; retained pixels changed in 0.35% of the frame |
| INVERSE_LUMA | 1.79 | Active source-luma reconstruction |
| BLACKS_WHITES | 0.10 | WHITES=0.995; BLACKS=0 |
| FILM_CURVE | 0.01 | Few pixels above its linear-light knee |
| 3WAY_CC | 0.61 | Active shadow/highlight color controls |
| CONTRAST / ZONE_CONTRAST | 1.39 each | Both affect the same zone-contrast path |
| RETINEX | 0.57 | Active local tonal correction |
| SHADOWS / SHADOW_LIFT | 0.24 each | Same shadow-lift path |
| SATURATION | 0.82 | Active chroma gain |
| PRINT_STOCK | 2.94 | Strongest individual look contribution |
| CORRECTIVE_GATE | 2.38 | `ApplyCorrective` only |
| TONAL_GATE | 1.51 | `ApplyTonal` only; FilmCurve remains active |
| CHROMA_GATE | 0.97 | `ApplyChroma`; final SDR projection remains active |
| LOOK_GATE | 2.94 | Print stock and printer-light block |

EXPOSURE, MID_TEMP, hue rotation, vibrance, hue-selective luma contrast, and
printer lights were neutral in the current profile and intentionally skipped.
Gate and individual-control deltas overlap and must not be summed. The full
output has 2.425% exact-black pixels versus 0.252% in the source; most source
pixels that became black were already below sRGB code 30. The tonal gate is
responsible for most of that increase. This is a visual-review concern, not
evidence for a profile change from one still.

## Dark GZW gameplay

On `autof_20260515_133058.png`, zeroing SHADOWS or SHADOW_LIFT_STRENGTH changed
output by 2.35 ΔE, mostly in shadows. Zone contrast changed it by 0.11 and
Retinex by approximately zero. The unchanged repeat was near zero. See the
[dark-frame attribution](../gamespecific/gzw/full_analysis/alternate/effects_2026-10-24_025954.json).

## Bright and chromatic real-game inputs

The GZW reference set lacks broad bright highlights and vivid colored objects.
As a code stress test, the current GZW profile processed the Arc Raiders
`autof_20260515_210958.png` image in the combined trial. Inverse chroma changed
output by 0.15 ΔE, saturation by 0.91, the chroma gate by 1.04, and the look
gate by 3.53; FilmCurve was near zero. See the [stress attribution](../gamespecific/gzw/full_analysis/alternate/effects_2026-10-24_030422.json).
Exact black rose from 0.003% to 4.085% on that cross-game input, chiefly from
dark source pixels. This cannot set GZW's in-game artistic calibration.

Arc Raiders' own profile and `arc_raiders_pipeline_trial.conf` (matching the
temporary config used during capture by SHA-256) rendered its broad
cloud scene `autof_20260515_210213.png`. FilmCurve contributed 0.15 ΔE against
a 0.003 repeat and reduced highlight luminance by about 0.8 ΔL. The sky/cloud
structure remained visible in the retained capture. See the [Arc attribution](../gamespecific/arc_raiders/full_analysis/alternate/effects_2026-10-24_030620.json).
Arc's configured four-effect chain was not switched.

## Abrupt cut and playback health

A lossless 30 fps clip held the dark GZW image for 20 seconds, showed the sunset
image for 8 seconds, then returned to dark for 8 seconds. Every timed snapshot
used a fresh playback, paused only at its target before the slow desktop capture.
The early-to-late differences were 0.192 ΔE on sunset and 0.210 on dark. The
return-to-dark frame at 34.5 seconds still differed by 0.334 from the original
18-second dark frame, consistent with ongoing adaptation. This does not directly
read the offscreen scene-cut scalar. mpv reported zero dropped and zero delayed
frames in all five 30 fps runs. Images and metrics: [transition report](../gamespecific/gzw/full_analysis/alternate/transition_2026-10-24_031106/report.json).

## Cost and remaining limits

Two untimed 120 fps FFV1/MangoHud pairs compared mpv with vkBasalt disabled and
with the combined GZW pipeline. Over seconds 5–15, baseline median frame times
were 8.37 and 8.77 ms; pipeline medians were 8.96 and 8.55 ms. Mean frame times
and effective rates likewise overlapped (about 75–76 fps); all runs reported
zero mpv drops. The test was CPU/compositor constrained, so it cannot isolate
shader GPU milliseconds or the cost of the 10-step gamut projection. Logs are
under `gamespecific/gzw/full_analysis/alternate/perf_2026-10-24_*`.
The user subsequently reported roughly a 10 FPS in-game cost and said it is
acceptable; this is a user observation, not a measurement from these logs.

Direct offscreen highway readback, output dither/noise-floor measurement, real
motion, emitters, vivid GZW objects, longer cut recovery, and live trial judgment
remain open. The activity marker and SDR endpoint counts
were checked in runtime captures. Twelve diagnostic tests pass. No profile or
active game config was changed.

## Provisional effect assessment

The following 1–100 ratings are engineering judgment from the current code and
the limited captures above, **not measured fidelity**. “Working” means evidence
that a stage executes and produces a plausible bounded result; “importance”
means expected contribution to the intended SDR correction. The scores apply to
the combined trial. In the active four-effect config, the broken cross-effect
history and highway reads invalidate these ratings for dependent stages.

| Effect or block | Working | Importance | Main evidence or gap |
|---|---:|---:|---|
| Analysis frame | 75 | 95 | Histogram normalization and cut response checked indirectly; no offscreen scalar readback |
| Inverse grade | 55 | 60 | Luma reconstruction active; chroma lightly engages only in a cross-game stress frame |
| Corrective analysis | 70 | 85 | Combined resources and corrective gate active; zone/key behavior lacks direct telemetry |
| Grade overall | 65 | 100 | Major gates active; visual quality and motion remain unverified |
| Explicit sRGB output | 85 | 95 | Runtime UNORM boundary and output endpoints checked |
| Gamut projection | 65 | 90 | Bounds checked; vivid GZW hue and chroma need footage |
| Zone contrast | 60 | 85 | Strong on GZW sunset, weak on dark scene; possible black crush |
| Shadow lift | 75 | 80 | Strong dark-frame response; shadow appearance needs live review |
| Print stock/look | 60 | 80 | Strongest sunset look contribution; artistic strength unjudged |
| Inverse luma | 75 | 75 | Clearly active in sunset frame |
| FilmCurve | 65 | 75 | Engages on Arc cloud scene; GZW highlights missing |
| Saturation/chroma | 70 | 75 | Chroma gate and saturation active; vivid GZW objects missing |
| Adaptive history/cuts | 70 | 75 | Cut probe shows ongoing adaptation; recovery and scene-cut scalar unverified |
| Three-way CC | 75 | 70 | Active under current shadow/highlight controls |
| Retinex | 65 | 65 | Active on sunset; halos and motion untested |
| Black/white mapping | 80 | 45 | WHITES=.995 affects output; BLACKS=0 is neutral |
| Dither | 55 | 40 | Endpoint behavior checked; noise floor and display quantization unmeasured |

Neutral controls (EXPOSURE, MID_TEMP, hue rotation, vibrance, hue-selective luma
contrast, printer lights) have no current-profile quality score. Bypass ΔE values
measure change, never whether an effect improves the image. The current GZW
profile needs matched raw/graded gameplay, ideally 60–90 seconds spanning dark
and bright areas, saturated objects, highlights/emitters, movement, and cuts.
Keep in-game HDR off. Review the combined trial live before any change to
`gzw.conf`; the user accepts an approximately 10 FPS in-game cost.

The report JSONs are small and versioned with this audit. Retained PNG captures
and mpv/MangoHud logs remain local in the workspace and `/tmp`; regenerate them
with the documented commands if the checkout lacks them.
