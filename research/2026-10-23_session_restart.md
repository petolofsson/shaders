# Session restart record — 2026-10-23

This is the detailed handoff for a fresh coding session. Read repository guidance
in `AGENTS.md` first and the short current-state index in `HANDOFF.md` next.

## Scope and working-tree care

The workspace was already dirty from the user's earlier shader work. The user
explicitly requested deleting the golden-image system; its source, four image
fixtures and golden EXRs/JSONs remain deleted. Do not restore them. Preserve all
other existing edits and do not run a reset/checkout/clean operation. Some tracked
Python bytecode also appears in `git status`; avoid regenerating it in place.

The GZW config `gamespecific/gzw/gzw.conf` was not edited. Shader header comments
were left alone. Game tuning lives in each game's `creative_values.fx`.

## Current GZW profile

Read `gamespecific/gzw/shaders/creative_values.fx` because the user changed tuning
values while this work was active. The latest observed values are:

| Control | Value |
|---|---:|
| INVERSE_STRENGTH / INVERSE_LUMA | 0.75 / 0.60 |
| BLACKS / WHITES / EXPOSURE / FILM_CURVE | 0 / 0.995 / 0 / 0.75 |
| SHADOW_TEMP / SHADOW_TINT | -0.15 / -0.05 |
| MID_TEMP / MID_TINT | 0 / 0 |
| HIGHLIGHT_TEMP / HIGHLIGHT_TINT | 0.10 / 0 |
| CONTRAST / SHADOWS | 1 / 1 |
| RETINEX_STRENGTH / ZONE_CONTRAST_STRENGTH / SHADOW_LIFT_STRENGTH | 1 / 1 / 0.75 |
| PRINT_STOCK / printer lights | 1 / 0, 0, 0 |
| CORRECTIVE / TONAL / CHROMA / LOOK gates | 100 / 100 / 100 / 100 |

The profile's comment still calls it “Arc Raiders”; that stale profile comment was
not changed. Do not infer GZW settings from old JSON or this session's early runs.

## Shader implementation changes

The active chain remains `analysis_frame : inverse_grade : corrective : grade`.
`grade` has eight passes: LFDownscale1, LFDownscale2, NeutralIllum, GuidedCoeff,
GuidedBase, ColorTransform, AdaptiveHistory and TexHwyWrite. Analysis/corrective
explicit render-target techniques finish with a BackBuffer passthrough.

Color-space handling is explicit. Runtime logs showed a 10-bit UNORM swapchain;
shader BackBuffer views therefore remain UNORM, and shader code decodes/encodes
sRGB at the pipeline boundaries. Processing is linear-light. Output stays SDR.

`common.fxh` now has signed high-range internal Oklab conversion, fixed-iteration
two-sided gamut projection and spatial-lane UV clamping. Grade retains signed and
overrange intermediates until gamut projection. `OklabToSDR` searches ten times
along chroma at constant lightness and hue, checks both negative and over-one RGB
channels, and saturates only after the projection.

`grade.fx` fixes the Retinex reconstruction denominator to the pre-Retinex luma
and the chroma reconstruction denominator to input chroma. Chroma reconstruction
preserves hue-band/luminance-adjusted baseline chroma through the soft HueCeil cusp
and pre-gamut knee; final SDR projection remains responsible for real gamut limits.
FilmCurve now has a sub-one rational shoulder asymptote and identity below its
knee. DIR, shadow/ambient tint, print toe and output dither preserve true black.
Dither runs in sRGB code units with endpoint attenuation. Selective film/shadow/
print/gamut hysteresis and corrective zone/slow-key smoothing use elapsed time;
scene cuts no longer force maximum film/print targets. Other analysis Kalman
filters were not changed to continuous-time models.

`inverse_grade.fx` supplements scene-wide near-clip history with local max-channel
protection for small colored emitters. `analysis_frame.fx` clamps near-clip
history by frame time and leaves its BackBuffer passthrough last.

## Orange investigation

The initial report “orange is kinda lost its color” was investigated on
`gamespecific/gzw/analysis/reference/autof_20260515_133058.png` (2560×1440). A
cropped 2552×1439 reference was rejected. The midtone-temperature control was
isolated with equal stage gates and a repeated full-pipeline capture. `MID_TEMP`
0.10 shifted the tool's orange band by +4.2° toward yellow; GZW was set to 0.00.
This profile change is still present.

For a second paired measurement, pixels were selected from the source at Oklab
hue 47.5–76°, chroma >3 on the analyzer's Oklab×100 scale, and source linear luma
0.08–0.85. Only 61 pixels met this mask. With MID_TEMP 0.10 their mean hue drift
was +3.52° and mean chroma change +0.627; with MID_TEMP 0 their mean hue drift
was -0.76° and chroma change +0.099. An earlier exploratory mask included near
neutrals and gave unstable hue angles; discard its superseded 12.72°/5.77° values.

The user subsequently changed inverse luma, blacks, whites, exposure and FilmCurve.
A same-frame capture of that current profile reported an orange-band mean chroma
change +0.4 and hue change +0.7° versus source. A source mask of 61 high-chroma
pixels was close to the source hue/chroma. This single frame does not prove the
user's in-game orange looks right; it contains few saturated orange samples.

The HueCeil cusp rolloff had also been compressing existing chroma before actual
display gamut mapping. Grade now preserves the post-luminance-adjustment chroma
baseline through that soft rolloff and the pre-gamut knee; Oklab SDR projection
still contracts genuinely out-of-gamut colors. It compiled on the current profile.
Comparing captures before/after this code change on the current reference gave
mean ΔE 0.000344 overall, p99 0, and no change in the 61-pixel orange mask: the
orange in that scene was already in gamut. This fix targets more saturated scenes.

MID_TEMP and cusp changes have distinct causes: MID_TEMP addresses hue direction;
the cusp floor avoids loss of already-present chroma. Do not undo them based on
old full-analysis JSON.

See `2026-10-23_gzw_orange_hue.md` for orange metrics and capture paths.

## Other shader and tool changes

- `analysis_frame.fx`: explicit sRGB sampling, elapsed-time near-clip smoothing,
  final passthrough placement.
- `corrective.fx`: explicit sRGB read, time-based zone EMA/slow key and final
  passthrough placement.
- `inverse_grade.fx`: local highlight protection and two-sided SDR projection.
- `grade.fx`: signed/high-range reconstruction, corrected shoulders and chroma,
  black-safe stages, adaptive history, sRGB output and endpoint-safe dither.
- `hue_bands.fxh` remains the twelve-center ceiling/slope map; creative controls
  are still omitted from the game profiles except their standard values.
- `compare_frame.py`: private PID IPC socket, retained per-run mpv/vkBasalt logs,
  validated IPC replies and activity marker, exclusive desktop/profile lock,
  optional-control fallback handling, equal gates, fresh mpv process per image,
  settling option, fixed sRGB/BT.709 playback and source/reference hashes.
  All-effects captures an unchanged FULL repeat before ablations.
- `analyze_delta.py`: rejects mismatched/nonfinite input, excludes the intentional
  2×2 marker, reports endpoints, and separates orange/amber hue bands.
- `capture.py`: RGB EXR remains; highway scalar/histogram decoding from screenshots
  is removed because HighwayTex is offscreen. `--dump` and `--no-frame` error.
- `stage_isolate.py`: shares the diagnostic lock. `TOOLS.md` and `tools/README.md`
  document current capture behavior.
- `tests/test_diagnostics.py` has nine checks for metrics, marker, telemetry,
  optional knobs and IPC. Those nine passed before the final chroma-floor shader
  edit; do not claim they were rerun afterward.
- Earlier CPU reference calculations validated Oklab roundtrip, gamut bounds,
  shoulder, dither and frame-rate equations. They are not GPU image-quality tests.

The user previously requested removal of the entire golden system. Do not bring it
back. Current useful artifact list is under `gamespecific/gzw/full_analysis/`;
`latest.json` is an older MID_TEMP=0.10 run, not the current profile. The two
research reports are historical records and include their own scope notes.

## Runtime and remaining work

GZW shader compilation and matched capture succeeded through mpv/vkBasalt. Logs
are stored in `/tmp/shader-runtime-*/` and can expire. The last current-profile
capture was `/tmp/compare_frame_qeurqorp/autof_20260515_133058_after.png`.
The runtime format logged was 10-bit UNORM (format 64); explicit sRGB conversion
is why the pipeline does not rely on SRGB image views. A five-second warmup is not
proof that the 20-second slow key converged. The pipeline's 2×2 red marker is
intentional; compare_frame verifies it and masks it in metrics.

The unchanged-pipeline repeat was 0.000043 on an earlier single-frame run. That
run used BLACKS=0.05 and EXPOSURE=0.2, both later user-edited; its BLACKS_WHITES
ΔE 12.987 and FilmCurve/Retinex deltas must not be applied to the current profile.
The 3WAY_CC/PRINT_STOCK/MID_TEMPERATURE effect runs also predate the user's latest
profile edits. Exact old profiles and hashes remain in the dated JSON files.

Still pending: user evaluation in a live GZW scene; matched orange-heavy daylight,
foliage, skin, neutral and emitter samples; broader Arc Raiders runtime validation;
motion/fade/scene-cut and frame-rate testing; GPU cost of the 10-step gamut mapper;
and profile recalibration only after those captures. No overall fidelity score has
been established. DeltaE here measures change, not improvement.

Preserve concurrent user edits. Never edit `gzw.conf` unless explicitly requested.
