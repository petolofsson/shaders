# Shadow, color, print and highlight review — 2026-10-25

Continues the [visual baseline](2026-10-25_visual_baseline.md),
[Retinex correction](2026-10-25_flat_face_attribution.md), and
[zone-confidence correction](2026-10-25_zone_confidence.md).
This review covers the next assessment priorities without retuning profiles.
It also identifies the [inverse-luma units mismatch](2026-10-25_inverse_luma_units.md)
subsequently corrected and validated on six scenes plus matched motion.

## Protocol and scope

Eighteen fresh private headless processes capture five independent bypasses
on GZW dark/sunset plus full/repeat and selected bypasses on overcast GZW and
Arc lamps. All use five-second compile wait and 20-second continuous settling;
all report zero dropped/delayed frames. Dark/sunset full and unchanged repeats
reuse the verified equivalent zone candidate from the preceding fresh-process
batch. Source, profile and shared shader hashes are recorded and preserved.

[`captures/stage_review_20261025/`](../captures/stage_review_20261025/)
contains the [runtime report](../captures/stage_review_20261025/report.json),
[material metrics](../captures/stage_review_20261025/metrics.json), source
inventory, capture/analysis scripts and crops. This is the baseline **after
the zone correction, before the inverse-luma units correction**. Later candidate
comparisons are under `captures/inverse_luma_units_20261025/`.

Material rectangles and masks are selected from source pixels. Most comparisons
use every crop pixel; whole-frame summaries sample every fourth pixel after an
eight-pixel border crop. Marker/identity regions are excluded. UI remains in
the actual inputs and therefore in scene analysis; material selections avoid it.
Oklab L/C/ΔE are on the ×100 scale. Numbers describe changes, not fidelity scores.
Original source PNGs have the earlier measured one-code transfer uncertainty;
internal full/bypass comparisons use the same capture backend and repeat bounds.

## 1. Deep shadow color: separate tuning from visibility

[Shelf comparison](../captures/stage_review_20261025/gzw_dark-shelf_backboard.png).
The selected backboard has source median L=13.57, C=0.99; full L=12.26, C=0.45.

| Bypass | Median L | Median C | Meaning in this material |
|---|---:|---:|---|
| None, full | 12.26 | 0.45 | Current cooler shadow treatment |
| Three-way color correction | 12.09 | 1.26 | Main cause of subtle warmth/color reduction |
| Inverse luma | 12.26 | 0.45 | No measurable contribution here |
| Tonal stage | 11.29 | 0.31 | Tonal work helps visibility/color in this shadow |
| Chroma stage | 12.15 | 0.39 | Existing chroma work adds a small useful contribution |
| Print/look | 14.51 | 0.48 | Print chiefly changes depth/brightness here |

Source-defined low/high groups retain 4.16→4.24 L separation in the full
backboard. Print-off increases it to 4.73 L. This crop does not support disabling
tonal processing or speeding slow-key adaptation as a color remedy.
The existing profile deliberately has SHADOW_TEMP=−0.15 and SHADOW_TINT=−0.05;
keep those values intact during assessment. A warmer shadow direction is a
visual preference question, presented to the user asynchronously, rather than
an inferred reason to overwrite their profile.

## 2. Sunset: attribute brightness and color independently

[Ground comparison](../captures/stage_review_20261025/gzw_sunset-ground.png),
[facade comparison](../captures/stage_review_20261025/gzw_sunset-facade.png).

| Ground output | Median L | Median C | Fixed source-group L gap |
|---|---:|---:|---:|
| Source | 47.38 | 6.94 | 34.61 |
| Full baseline | 38.82 | 8.28 | 27.46 |
| Inverse luma off | 42.93 | 8.95 | 32.36 |
| Tonal off | 39.94 | 8.26 | 29.83 |
| Chroma off | 38.71 | 6.42 | 27.40 |
| Print/look off | 41.83 | 8.29 | 27.06 |

Inverse luma and print both lower ground brightness; the chroma stage chiefly
raises colorfulness. Contributions are not additive because later stages
respond to earlier changes. Print-off leaves ground chroma almost unchanged
but changes its median hue drift from −1.86° to +0.10°. The print stage therefore
deserves palette review, not a blanket saturation adjustment. The inverse-luma
bypass also restores facade group separation 34.91→40.83 L, near source 41.77.

Inspection of the responsible code finds that its computed **linear** luma
ratio scales Oklab coordinates directly, yielding a cubed RGB gain. A temporary
GPU probe confirms that mismatch. Correcting the units is a separate testable
issue from selecting a preferred print look; see the inverse-luma artifacts.

## 3. Restrained overcast material

[Foliage](../captures/stage_review_20261025/gzw_muted-foliage.png),
[neutral sky](../captures/stage_review_20261025/gzw_muted-neutral_sky.png).
Source-selected green foliage changes L 27.57→26.06 and C 3.68→4.03, retaining
group separation 16.57→17.57 L. Chroma-off C is 3.18; print-off C is 4.23.
The source palette remains visibly restrained, but its median green hue moves
+10.21°. That palette shift remains for review; higher chroma is not proof of
improvement. Neutral sky changes L 72.73→67.39 and C 1.17→1.30, with only
0.045% of selected source pixels already at a channel ceiling.

GZW's SATURATION=0.25 and CONTRAST=1.5 differ from Arc's default saturation and
CONTRAST=1.0; Arc also has MID_TEMP=0.05 and HIGHLIGHT_TEMP=0.05 versus GZW's
0 and 0.10. Shared candidate logic is the same, but these existing profile
differences prevent treating the tests as a unified untuned product preset.

## 4. Small emitters: real engagement, limited source information

[White lamps](../captures/stage_review_20261025/arc_emitters-white_lamps.png),
[red lamp](../captures/stage_review_20261025/arc_emitters-red_lamp.png).
The selected white cores change L 98.20→93.84. FilmCurve-off raises them to
94.74; print-off to 96.47. Their halo changes 73.47→69.48, unchanged by the film
bypass and rising to 71.89 with print off. FilmCurve meaningfully engages on
these compact lights even though its whole-frame mean contribution is small.

37.77% of the selected source white-core pixels already have a channel at 255.
Nothing here establishes recovery of their missing detail. The red source
selection has no channel clipping: L 51.77/C 19.22→46.20/17.83. FilmCurve-off is
negligible there; print-off gives L 47.77/C 19.00. The inverse-luma units follow-up
is relevant to the red source and halo, while leaving bright white cores largely
unaffected. No additional highlight or optical effect is justified by this review.

## 5. Coordination and review gate

Preserve useful shadow lift and the adopted spatial corrections. Correct the
verified inverse-luma units mismatch only after varied-input and motion checks.
Keep the manual temperature, saturation, print and exposure choices intact.
The remaining print/palette questions need matched visual preference, not
automation inferred from entropy, hue coverage or a saturation target.

The subsequent [linear-light correction](2026-10-25_inverse_luma_units.md)
restores sunset ground median L 38.82→41.46 and source-group separation
27.46→30.70 L without changing the cool shelf treatment or manual print settings.
Its final comparison artifacts include the new overcast and emitter scenes.

This traverses the current list through shadows, color relationships,
highlights and stage cooperation, and prepares concrete crops for live review.
It does not establish 75+ effectiveness, dense stability or broad cross-game
acceptance. More game inputs and user visual review remain necessary; no new
recording is required to continue the demonstrated technical work.
