# GZW combined trial audit continuation — 2026-10-24

This continues [stage verification](2026-10-24_stage_verification.md). The
runtime was `gamespecific/gzw/gzw_stronger_trial.conf`; `gzw.conf` still uses the
four-effect chain with zeroed cross-effect resources in grade. The GZW tuning
file had SHA-256 `ed371ec361c6590442dd6f0aaaf35aeab93f829395576fffe60fe5d5f4811aa1`
before and after the probes. No shader source, header comment, or tuning value
was changed. An existing staged deletion of `startprompt-2026-10-23.md` was left
alone.

## Matched effect captures

All small-effect comparisons used a fresh mpv/vkBasalt process for each render,
continuous lossless RGB playback at 30 fps, `--settle 20`, then a paused desktop
capture. The full render was repeated unchanged before each ablation. See the
[cloud report](../gamespecific/gzw/full_analysis/alternate/effects_2026-10-24_074204.json)
and retained `captures_2026-10-24_073935/` images. The source is the Arc Raiders
cloud gameplay frame `autof_20260515_210213.png`, rendered under the **GZW**
profile as a highlight stress input. It is not a GZW calibration reference.

| Bypass | Mean Oklab ΔE | Relevant region | Unchanged repeat |
|---|---:|---|---:|
| `FILM_CURVE` | 0.152 | Highlights: 0.831 ΔE, −0.820 ΔL in full output | 0.000005 |
| `INVERSE_STRENGTH` | 0.030 | Cloud highlights effectively unchanged | 0.000005 |

FilmCurve thus engages on broad bright material, while inverse chroma requires
chroma rather than luminance alone. The earlier GZW-profile Arc stress frame
`autof_20260515_210958.png` at 20 seconds already found inverse chroma 0.146,
saturation 0.908, chroma gate 1.038 and look gate 3.533 ΔE against an unchanged
repeat; see [stress attribution](../gamespecific/gzw/full_analysis/alternate/effects_2026-10-24_030422.json).
The genuine GZW sunset/menu frame at 20 seconds had inverse chroma below 0.01,
FilmCurve about 0.01, and a near-zero repeat; see
[individual attribution](../gamespecific/gzw/full_analysis/alternate/effects_2026-10-24_025209.json).

Source-selected region checks used 4× spatial subsampling, sRGB decoding and
Oklab on retained paired PNGs. In the GZW sunset, 6.34% of sampled pixels met
`max(source RGB)>0.65`, channel spread `>0.35`, Oklab C `>8`, hue 35–100°.
The full output changed that warm region by mean −5.69 ΔL, +0.11 ΔC and median
−3.06° hue; none of those output pixels had a clipped white channel. A broad
bright mask (`max RGB>0.85`, 4.34% of pixels) changed by mean −3.27 ΔL. These
numbers describe the current look, not fidelity. In the cross-game Arc stress
frame, the bright vivid mask (12.86% of pixels) changed by mean −9.02 ΔL,
+2.48 ΔC and median +4.61° hue, mainly on blue sky. No GZW source here contains
a broad bright sky and vivid gameplay object together. The current GZW sunset
render's increase in exact black, recorded in stage verification, remains a
live visual-review concern; these stills do not justify changing the profile.

## Scene cuts and playback

The [extended transition report](../gamespecific/gzw/full_analysis/alternate/transition_2026-10-24_074306/report.json)
uses a lossless 30 fps dark GZW image for 20 seconds, sunset for 8 seconds, then
dark for 20 seconds. Each target came from a fresh playback and was paused at
its target time. Sunset at 0.5 versus 6 seconds after the cut differed by 0.183
ΔE. Returned dark at 0.5 versus 6.5 seconds differed by 0.211. At 6.5 seconds
the returned dark differed from the original dark by 0.320, but at 18 seconds
the difference was 0.00028. All six runs reported zero dropped and delayed
mpv frames. This establishes recovery for this pair of static images; it does
not decode offscreen scene-cut confidence or test real camera motion.

## Capture reliability, motion, and cost

One cloud ablation initially captured a decorated mpv window instead of
fullscreen. The activity marker rejected it, and `creative_values.fx` was
restored. `compare_frame.py` now checks mpv fullscreen state before capture,
re-enters fullscreen when needed, and warms continuous playback again after
that swapchain change. The repeated cloud run completed with all marker checks.

There is no raw motion clip in the workspace. The user plans to provide raw
GZW and Arc footage later; real motion, emitters, motion-related halos, and
temporal behavior during camera movement remain unverified. Code inspection
finds only reduced-size zone/chroma histories and a 1×1 adaptive history in
the grade path, with current-frame spatial filtering. That limits one source
of image ghosting, but scene statistics can still lag through movement and
spatial filtering can still reveal halos. The existing two
120 fps mpv/MangoHud baseline/trial pairs showed median frame times of
8.37→8.96 ms and 8.77→8.55 ms over seconds 5–15. GPU load logged as zero in
all four runs, and the untimed FFV1 playback was CPU/compositor limited, so
these data do not isolate shader GPU cost. The combined technique contains 27
passes; full-resolution inverse/grade and the ten-step SDR gamut projection
are plausible cost centers, but no per-pass GPU measurement is available.
The user's approximate 10 FPS in-game loss is the only game cost observation.

Twelve diagnostic tests pass. No shader defect was established by these
additional captures, so no shader/profile change was made. The next useful
input is a 60–90 second **raw, shader-disabled** recording per game with in-game
HDR off, covering movement, dark and bright areas, vivid objects, emitters and
scene transitions. Replay each unchanged raw clip through the matching trial
for frame-matched output and history observations before reconsidering tuning
or switching `gzw.conf`.
