# Full-strength shadow color: evidence correction and noise screen

The user's selected 100% color variant has more prior evidence than the previous
handoff implied. The saved [bounded 100% screen](2026-11-06_shadow_color_bounded_screen.md)
and its [numeric/ramp checks](2026-11-06_shadow_color_numeric_ramps.md) use the
same color formula as the later 100% candidate: direct comparison of the saved
grade bodies finds only include paths and an explicit `1.00` multiplication.
The historical screen records matching profile, source, clip and production
identities for its own captures. Its finite compiled arithmetic and synthetic
ramps therefore inform the **BLACKS=.0025** full-strength candidate, within the
original stated scope and repeat uncertainty. They do not validate the separate
experimental offset with BLACKS=0 and lift .25.

## New same-update noise test

An isolated diagnostic cloned the production and 100% grade transforms in one
GPU invocation, using the existing explicit RGBA32F readback design. A fixed
synthetic source contains exact black and independent RGB code ±1 fields around
8, 16 and 32, with 64 sampled pixels per band. Input and both cloned outputs
share the same update; ordinary candidate history is not evolved in this probe.
Two private headless captures per GZW and Arc profile completed, with zero
reported frame drops/delays. Source/clip, clone, capture and production hashes
are recorded in `captures/shadow_color_full_noise_20261107/report.json`; sampled
arrays and scripts are adjacent. The 17 production identities matched before
and after. The fixture and the bounded insertion were derived from the historical
screens without importing the capture-on-import bounded generator.

Combined Oklab a/b standard deviations, before output dither/encoding, are:

| RGB code | Input | GZW current → 100% | Arc current → 100% |
| --- | ---: | ---: | ---: |
| 8 | .3532 | .1901 → .2689 | .1934 → .2738 |
| 16 | .2845 | .1971 → .2934 | .1991 → .2965 |
| 32 | .2861 | .2564 → .3000 | .2598 → .3037 |

At code 16 the full candidate increases measured chromatic variation by about
49% relative to current in both profiles, and is slightly above input variation.
This is a synthetic small-sample noise tradeoff, not a visual noise threshold or
proof of objectionable in-game noise. Simulated undithered 8-bit rounding changes
the relation (GZW code 16 current .2332, candidate .3610, input .2852); it is not
actual dithered game output. Exact source-black samples have identical baseline
and candidate outputs in the measured probe. No encoded readback ceiling values
were found.

Inputs repeat exactly, but float outputs do not. Maximum output repeat change is
0.0001231 GZW and 0.00000447 Arc; GZW is materially less settled than the older
half-strength fixture. At code 16 GZW current/candidate a/b std in the second
run is .1973/.2937, and Arc .1992/.2965, preserving the observed direction.
Do not call these exact repeats or attribute their state variation to the color
change. The fixture and its 64 samples are not representative game noise.

## Next decision

The 100% color treatment supports the goal's material-dependent color direction
in selected stills, while amplifying synthetic chromatic variation. The 50%
review's quantitative noise and motion results cannot be assigned to 100%.
No new shader guard is justified from synthetic noise alone: a guard could erase
the weak material colors the user wants. Inspect native dark surfaces and actual
motion/noise before choosing a model change. The user's isolated lift .25 /
BLACKS 0 configuration uses a different, decoupled offset and must be assessed
separately, including signed near-black behavior and the rejected brightness
curve it currently contains. Production remains unchanged.

## Requested zero-BLACKS visual isolation

The requested GZW lift .25 / BLACKS 0 profile was copied to two isolated builds
under `captures/shadow_color_zero_black_20261107/`. Both remove the previously
rejected compact curve; the color build alone retains the experimental .0025
offset. The copied profiles are byte-identical (SHA-256
`b68135e895dc79abd510f95a5640263eb223dea0975a66d8de57331802918780`), and a
grade-body diff shows only the color insertion. The color-off and color grade
hashes are `5f50a63b38e251a575ccf4b0b3908332f2ca3a566db5ae4a33ff0b09baba8c0b`
and `f6072f05f6a9ececb643b6fbe5dc338ab14e803ed4b3ca85b359ba6318707339`.
Configuration and pipeline paths point to their respective copies. These
post-capture checks are not a complete per-process dependency snapshot.

Four private headless runs used the held warm-material source, five-second
compile wait and 20-second settling. Color-off repeats differ in 27,299 pixels,
color-on in 64,194, each by at most one code with the marker masked. Off versus
on differs in 3,289,523 pixels by at most eight codes; change magnitude is not a
quality score. The color-on image gives the timber and pack a subtle warmer
appearance at native overview while preserving a dark room; it does not resolve
tonal gradation. These are one-scene stills and observer judgments. The source,
captures and private logs are retained in that directory; PipeWire setup
warnings occurred but screenshots and marker checks succeeded. No explicit
dropped-frame telemetry was collected for these single-frame runs.

With BLACKS zero, the decoupled correction is not a redistribution of an
existing positive pedestal. For some highly chromatic near-black inputs its
negative channel correction can yield signed internal RGB, which the pipeline
allows; this observation alone is not proof of output clipping or an artifact.
Numeric/neutral/ramp and realistic-noise behavior for this particular offset
remain unverified. Do not transfer the earlier BLACKS=.0025 guarantees to it.
All 17 production identities match after the test.

## Zero-BLACKS compiled arithmetic and full-chain ramps

The exact isolated zero-BLACKS insertion was extracted as text into a direct
RGBA32F GPU probe with an independent double-precision reference. For 256
constructed gray, primary, mixed and near-black inputs, maximum RGB error was
2.94e-7 and maximum luma difference from the uncorrected affine base was
3.33e-7; gray outputs were identical at the roughly 4.77e-7 readback step. One
sample engaged upper headroom. The minimum intermediate component was −.002500,
and 58 inputs had at least one component below −1e-6. The encoding range is
signed; preserving signed internal RGB is allowed. These finite helper checks
do not establish downstream behavior or imply that intermediate negatives are
output errors. The private process reported zero drops/delays and production
hashes matched. Probe, decoded array and report are in
`captures/shadow_color_zero_numeric_20261107/`.

Four separate private headless GZW captures then compared color-on/off with the
same zero-BLACKS/lift-.25 profile, each repeated, on a synthetic RGB8 chart with
64 steps from code 0 through 63 in neutral, red, green, blue, warm and cool rows.
All six rows have positive **mean** linear-luma steps for both variants. This
does not prove pixelwise or color monotonicity. With the marker masked, color-off
repeats differ in 4,352 pixels, color-on in 7,214, at most one code. The neutral
row color-on/off differs in 6,543 pixels by at most one code; helper gray identity
does not guarantee exact whole-chain identity after upstream processing and
independent histories.

Color-on has 224 newly all-channel-black pixels and 12 no-longer-black pixels
relative to color-off, with the marker masked. All 224 new black pixels came
from source levels 1–2 and were at most one code in the baseline; 69 overlap a
repeat change in at least one variant, while 155 are new black in both repeated
pairs. This is a real scoped quantization tradeoff, not proof of a visible game
artifact or a general endpoint failure. The chart images, source and logs are
retained in the diagnostic directory; image hashes were recorded during the
run, and the capture tool did not snapshot every dependency at each capture.
PipeWire setup warnings appeared, but captures and activity-marker checks
succeeded. No explicit drop telemetry was collected for the still captures.

The result supports continued color evaluation but not a claim of artifact-free
near-black handling. Compare real dark colored surfaces, cuts and motion before
choosing whether this tradeoff warrants a model change. The zero-BLACKS formula
is still an isolated user-requested experiment, not an adopted control.
