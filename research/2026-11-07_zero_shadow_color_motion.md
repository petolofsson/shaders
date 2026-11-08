# Zero-BLACKS shadow color: sparse motion and shelf follow-up

The isolated GZW color-on/off build uses the requested shadow lift .25 and
BLACKS 0 with the experimental .0025 color offset, and excludes the rejected
compact brightness curve. The [preceding report](2026-11-07_full_shadow_color_noise.md)
contains its numeric and ramp costs. Production is unchanged.

## Sparse motion and cuts

Two independent private headless replays use the existing cached Babylon
15-source-poses/sec clip duplicated to 30 fps and its measured source/cut
update identities. The actual grade is the isolated color candidate; the
color-off and color-on clones are evaluated in the same update and share the
candidate's evolving state. This comparison is not two independent ordinary
pipelines with their own histories. The copied GZW profile hash is
`b68135e895dc79abd510f95a5640263eb223dea0975a66d8de57331802918780`.
The captured grade and diagnostic files, clips, source hashes, update records,
screenshots and playback counters are recorded in
`captures/shadow_color_zero_motion_20261107/`. Both replays report zero dropped
and delayed frames; production hashes match before and after.

All 96 candidate-clone versus ordinary-candidate extraction controls match
exactly on the shared valid mask. Both variants' independent replay repeats
reach at most one 8-bit code. The largest mean color step for matched same-source
updates, on the Oklab ×100 reporting scale, is:

| Window | Color off | Color on |
| --- | ---: | ---: |
| Early night | .13414 | .13915 |
| Return | .71651 | .72116 |
| Daylight | .14565 | .14573 |

The repeat has the same direction. These small increases are retained costs,
not a visibility score or proof of flicker. The sampling mask excludes borders,
marker and atlas tags. The fixture is sparse, its views are small diagnostic
tiles, and static holds/cut windows cannot establish dense gameplay continuity,
real game noise or 80–110 fps performance.

## Dark GZW shelf

Four fresh private headless still captures compare the two isolated builds on
`autof_20260515_133058.png` (SHA-256
`2d4f69c97438f40d50c1b82601392440339682efb293590e053e6bee174d9225`), with
five-second compile wait and twenty-second settling. Color-off repeats differ
in 5,697 pixels and color-on repeats in 10,185, each by at most one code after
masking the marker. The on/off images differ in 2,812,246 pixels by at most eight
codes. These are change and repeat counts, not quality measurements.

In the whole-scene review, the shelf remains dark and the color difference is
subtle; the candidate does not obviously resolve the suspected tonal readability
loss. Native stills and logs are under `captures/shadow_color_zero_black_20261107/`
as `shelf_current_*` and `shelf_color_*`. The still runner did not record a
complete capture-time dependency snapshot or explicit drop telemetry. PipeWire
setup warnings appear in logs; screenshots and activity-marker checks succeeded.
The source is a still screenshot, not live footage.

## Decision boundary

The color-only experiment remains a plausible modest contribution, not a
confirmed overall shadow solution or a production-adoption decision. The
synthetic noise and near-black quantization costs and sparse-motion limits remain.
The selected zero-BLACKS profile is an experimental copy, not a request to alter
the active profile. Further work should examine actual dark-color motion/noise
and the broader tonal relationship; no new guard or rewrite is supported merely
by the small numeric changes above.
