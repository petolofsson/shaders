# Current review pack — 2026-10-25

Two further corrections are applied in `general/grade/grade.fx`: conservative
uniform zone confidence removes false rims without the stronger candidate's
shadow cost; inverse luma now applies its computed gain once in linear RGB,
correcting the previous cubed gain. Both preserve the prior Retinex guide fix.
Profiles, shader headers, manual exposure and active configs remain intact.
The [updated provisional ratings](2026-10-25_effect_ratings.md) estimate complete
combined-chain effectiveness at 75/100; accepted cross-game quality remains open.

## Progress through the requested list

| Priority | Result | Remaining judgment/work |
|---|---|---|
| Zone-driven flat-face shading | Corrected: held purple spread 1.07→0.34 L; edge gap 0.73→0.00 L. Six matched moving poses retain 0.00–0.09 L gaps. | Smaller coarse-zone interior gradients remain. |
| Deep shadow color/detail | Attributed the selected shelf's warmth reduction chiefly to existing cool three-way correction. Tonal work helps visibility; print chiefly sets depth. | Cooler versus warmer shadow preference; values remain unchanged. |
| Sunset interactions | Corrected a verified inverse-luma gain-units error. Ground median L 38.82→41.46, source 47.38; group separation 27.46→30.70 L. | Print/saturation palette choices and reconstruction assumptions across more games. |
| Color/highlight preservation | Added overcast GZW and Arc small lamps to dark, sunset, vivid and cloud checks. Red lamp approaches source L/C; white cores stay largely unchanged. | Overcast green hue shift and blue-sky contrast cost need visual review. Clipped source light detail is unavailable. |
| Automatic stage cooperation | Removed geometry-dependent zone strength artifacts and unintended extra inverse-luma density before tonal/print work. Existing bounds/adaptation remain. | Broader bounded print/palette calibration after preference and varied-input evidence. No new effect justified. |
| Cross-game/live review | Source/previous/current/repeat crops are ready, with static repeats, matched motion and active/combined checks. | User visual review, additional games, dense continuity/cuts, and a unified untuned preset remain open. No 75+ acceptance score is claimed. |

## Start with these comparisons

[Six-scene overview](../captures/inverse_luma_units_20261025/review_overview.png).
Columns are **source / previous zone-corrected output / current output /
current repeat / inverse-luma bypass where shown**. The previous output retains
the incorrect cubed gain; it is a measured change reference, not a preferred
target or golden image. Vivid Arc input uses GZW tuning; clouds/lamps use Arc
tuning. Existing profile differences are disclosed in the stage review.

- [Sunset ground](../captures/inverse_luma_units_20261025/gzw_sunset-ground.png)
  and [facade](../captures/inverse_luma_units_20261025/gzw_sunset-facade.png):
  assess restored light and shade relationships against the retained warm look.
- [Blue sky](../captures/inverse_luma_units_20261025/gzw_vivid-sky.png): median
  L rises 58.61→61.92 toward source 67.45, while fixed-group separation decreases
  9.61→6.94 L against source 9.71. Judge this explicit contrast tradeoff.
- [Overcast foliage](../captures/inverse_luma_units_20261025/gzw_muted-foliage.png)
  and [neutral sky](../captures/inverse_luma_units_20261025/gzw_muted-neutral_sky.png):
  check restrained atmosphere and credible color; source-selected green hue
  still shifts about +10° under the existing profile.
- [White lamps](../captures/inverse_luma_units_20261025/arc_emitters-white_lamps.png),
  [halo](../captures/inverse_luma_units_20261025/arc_emitters-white_halo.png) and
  [red lamp](../captures/inverse_luma_units_20261025/arc_emitters-red_lamp.png):
  red L/C changes 46.20/17.83→49.91/18.74, source 51.77/19.22. About 38% of the
  selected source white cores already touch a channel ceiling.
- [Shadow preference comparison](../captures/stage_review_20261025/gzw_dark-shelf_backboard.png):
  source / full / repeat / color-correction bypass / print bypass. This earlier
  stage comparison remains applicable to the selected backboard: its current
  L=12.26/C=0.45 is unchanged by the inverse-luma fix. The warmer bypass reaches
  C=1.26 versus source 0.99. The asynchronous preference question remains open;
  current tuning is preserved in the meantime.

## Verification and scope

Twenty diagnostic tests pass. Zone validation includes ten fresh conservative
candidate/repeats, five motion processes and three applied-path captures.
The next stage review adds eighteen fresh bypass/input captures. Inverse-luma
validation adds two successful GPU function probes, twelve candidate/repeats
across six scenes, two motion processes, six active-chain captures and four
final shared-path checks. Successful runs report zero dropped/delayed frames.
Rejected candidates, initial matching failures and the temporary probe compile
failure remain documented separately; they are not counted as passing checks.

The inverse-luma correction engages on the unchanged active four-effect chains.
Their unavailable cross-effect analysis resources remain unresolved, so these
checks do not establish full adaptive-chain behavior there. GZW's combined trial
remains the assessment path; `gzw.conf` was neither edited nor switched.

Full evidence: [zone confidence](2026-10-25_zone_confidence.md),
[stage attribution](2026-10-25_stage_review.md),
[inverse-luma units](2026-10-25_inverse_luma_units.md).
Matched source identities and repeats support the stated samples, not dense
temporal stability, subjective fidelity percentages or completed cross-game
acceptance. No new effects, golden suite or GPU profiling was introduced.
