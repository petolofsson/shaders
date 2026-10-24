# GZW orange hue correction — 2026-10-23

GZW midtone temperature was set from 0.10 to 0.00. The isolated MID_TEMP ablation
on the same 2560x1440 GZW frame changed orange-band hue by +4.2° toward yellow;
the unchanged-pipeline repeat differed by only 0.000 ΔE (rounded; measured 0.000043).

For a paired source-mask comparison, pixels were selected from the reference image
at Oklab hue 47.5–76°, chroma above 3 on the analyzer's Oklab×100 scale, and source
linear luminance 0.08–0.85. This leaves 61 clearly chromatic orange pixels. Their
hue drift and chroma change from source were:

| GZW MID_TEMP | Mean orange hue drift | Mean chroma change (Oklab×100) |
|--------------|-----------------------:|-------------------------------:|
| 0.10 | +3.52° | +0.627 |
| 0.00 | -0.76° | +0.099 |

The isolated comparison measures a +4.2° warm shift from MID_TEMP; the matched
high-chroma pixels show the correction bringing orange close to the source hue and
chroma. An earlier exploratory mask included near-neutral pixels whose hue angles
are unstable; its 12.72°/5.77° figures are superseded and should not be used.
This is one scene with only 61 high-chroma orange pixels, not evidence of overall
fidelity. Assess daylight, skin, foliage, neutral scenes, and emitters in-game.

The capture is `/tmp/compare_frame_t_c90mrp/autof_20260515_133058_after.png`.
The supporting midtone ablation is in
`gamespecific/gzw/full_analysis/effects_2026-10-23_161900.json`.

After the user changed several GZW controls, a separate same-frame capture used
the current profile (`INVERSE_LUMA=0.6`, `BLACKS=0`, `WHITES=0.995`, `EXPOSURE=0`,
`FILM_CURVE=0.75`, `MID_TEMP=0`). A shader change also preserved input chroma
through the soft hue-ceiling rolloff and pre-gamut knee; final SDR gamut projection
still limits unrepresentable colors. The change compiled. On this reference frame,
the before/after images differed by mean ΔE 0.00034 overall and the 61-pixel
high-chroma orange mask was unchanged, indicating those oranges were already in
gamut. Capture: `/tmp/compare_frame_qeurqorp/autof_20260515_133058_after.png`.
