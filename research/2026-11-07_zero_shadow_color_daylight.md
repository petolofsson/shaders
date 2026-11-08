# Zero-BLACKS color: daylight controls and same-update readback

The isolated color-on/off builds use GZW lift .25 and BLACKS 0 with the
experimental .0025 color offset in the on build; neither includes the rejected
compact curve. The daylight source `Screenshot_20260516_101035.png` is
2552×1439, SHA-256
`22c2d89b3df7caa5eb81af0c8cc97e83809beb27e4166e6ae92a1b9d8691db6e`.

## Ordinary stills

Four private headless runs used five-second compile wait and 20-second settling.
Color-off repeats differ in 2,727,135 pixels (mean absolute channel change .416
code), color-on repeats in 2,826,230 (.449 code), both reaching two codes with
the activity marker masked. The two same-index off/on comparisons differ by at
most six codes. The large repeat changes limit visual attribution and do not
establish why the histories differ; elapsed settling alone is not convergence.
All four screenshots and logs are retained in
`captures/shadow_color_zero_black_20261107/day_*`; the logs are in the same
directory. Private display logs contain PipeWire setup warnings; captures and
marker checks succeeded. No explicit drop telemetry or full per-process source
snapshot was recorded for these still runs.

## Same-update patch controls

To separate the color calculation from those still-repeat differences, a
diagnostic evaluates baseline and candidate clones in the same invocation,
sharing the current scene and history. The ordinary grade remains the baseline;
this is not a candidate with its own evolving history. Three 16×16 sampled
grids cover 64×64 native-pixel patches at four-pixel spacing. The first intended
foliage patch `(2000,500)-(2064,564)` fell on bright sky: every one of its 256
samples reached the .25 readback ceiling. It is retained and **excluded**.
The corrected dark-foliage patch `(2260,650)-(2324,714)` and masonry patch
`(800,850)-(864,914)` each have 256 valid samples and no ceiling exclusions.
Nearest-neighbor enlarged location previews are in
`captures/shadow_color_zero_foliage_20261107/`; they are not native-scale
appearance evidence.

Two private headless captures per patch repeat exactly at the encoded readback
precision. Four ordinary patch runs plus two excluded-sky runs report zero
dropped/delayed frames, and all 17 production identities match before and after.
Image and snapshot hashes were rechecked against each report. Results, cloned
shader/config identities, source/clip hashes, encoded screenshots and arrays are
under `captures/shadow_color_zero_daylight_20261107/` and
`captures/shadow_color_zero_foliage_20261107/`.

On the Oklab ×100 scale, same-update color-on minus color-off has mean
`(ΔL, Δa, Δb) = (−.0038, −.0861, +.2365)` in foliage and
`(−.0033, −.0281, +.0358)` in masonry. Mean ΔE is .2524 and .0464 respectively.
These establish a sampled change, not material fidelity, visible quality or
lighting inference. The readback is pre-dither and has limited [0,.25] range;
excluded samples cannot establish their values or safety. The corrected patches
cover only one image and 256 points each; they do not establish natural game
noise, moving-game behavior or universal neutral protection.

The foliage responds more than the masonry in these selected samples, consistent
with the intended source-color selectivity. No new model or production adoption
follows from the measurements alone. Existing zero-BLACKS dark-ramp quantization
costs and sparse-motion limitations remain.

## Colored-light stress scene and review gallery

Four private headless still captures used the Arc emitter source
`autof_20260515_210448.png` (SHA-256
`d38c4fecbdd18859cbc2d3aeffd96614ddaee94f85d1d95afd29064c507fa4c2`)
with the isolated **GZW** lift .25 / BLACKS 0 profile, 5-second compile wait and
20-second settling. This is a GZW-profile palette stress test on another game's
source, not validation of Arc's own profile. The color-off repeats differ in
225,579 pixels by at most one code; color-on repeats differ in 626,284 pixels
by at most two codes. Color-on versus off differs in 2,695,987 pixels by at most
six codes, with marker masked. Neither new all-channel-black pixels nor new
code-255 channels occur in this selected still pair; this is not an exhaustive
endpoint test. On overview the red and white lights and their broad relationship
remain, without an obvious broad new cast. These are observer judgments, and the
repeat variation limits attribution of subtle changes.

Images and private runtime logs are retained as `emit_*` under
`captures/shadow_color_zero_black_20261107/`; `review.html` there presents the
four GZW-profile scene comparisons with color on/off switching. The runner did
not capture explicit drop telemetry or a complete per-process dependency
snapshot. Production identities were rechecked unchanged after capture.
