# Fidelity audit implementation — 2026-10-23

Historical scope: the initial implementation and captures below used GZW
BLACKS=0.05 and EXPOSURE=0.2. The user corrected BLACKS to 0.005, then later
changed several profile values again. Current GZW settings are documented in
`research/2026-10-23_session_restart.md`; do not treat the profile snapshot in
the older effect JSONs as current.

Implemented shader and diagnostic corrections while preserving the GZW profile as
it existed at that point: BLACKS=0.05, EXPOSURE=0.2, shadow lift=0.75. The game
config was not edited. Shader header comments were preserved; some older
headers describe automatic sRGB decoding, which is now explicitly handled in code.

## Corrections

- Retinex luminance reconstruction uses the luminance before normalization as its
  denominator. Chroma reconstruction uses the original chroma magnitude, so the
  saturation-by-luminance adjustment is no longer canceled.
- Corrective and tonal stages retain signed RGB and overrange until the SDR
  boundary. Three-way CC and guided detail no longer clamp highlights early.
- FilmCurve's rational shoulder actually approaches one; it preserves identity
  below the knee without dividing tiny luminance by an artificial black floor.
- Gamut mapping tests negative and over-one channels through ten fixed bisection
  steps along Oklab chroma at constant lightness and hue. A final saturate remains.
- Soft hue-ceiling rolloff and gamut pre-knee preserve chroma after intentional
  luminance/saturation adjustments; final SDR projection handles display-gamut limits.
- Inverse-grade independently protects high local channel values, including small
  colored emitters that do not affect the global luminance near-clip fraction.
- DIR no longer adds its logarithm epsilon back into RGB; print toe, primary
  shadow tint, ambient tint, and spatial dither preserve exact zero input.
- Dither uses sRGB code units and symmetric endpoint attenuation. Selective
  hysteresis, zone EMA and slow-key smoothing use elapsed time. Scene cuts no
  longer force the film/print targets to maximum strength.
- Spatial filtering cannot sample highway metadata below the spatial lane.

## Color-space evidence

vkBasalt selects UNORM versus sRGB sampler views using the sampler's sRGB flag and
render-target views using the pass write flag. Neither was explicitly enabled in
this chain. See the [vkBasalt implementation](https://raw.githubusercontent.com/DadSchoorse/vkBasalt/master/src/effect_reshade.cpp).

Runtime logs showed format 64, a 10-bit UNORM swapchain. The implementation now
keeps UNORM views and performs explicit sRGB decode/encode, so it does not depend
on a corresponding sRGB hardware format. Float analysis textures remain linear.

The constant-lightness/chroma-direction projection follows the general approach
described in [Ottosson's gamut-clipping article](https://bottosson.github.io/posts/gamutclipping/),
using a fixed search rather than its optimized analytic intersection. This has
not yet been profiled for GPU cost in-game.

## Validation

- Nine diagnostic unit tests pass; Python syntax and whitespace checks pass.
- CPU reference equations passed 10,000 signed/high-range roundtrips (maximum RGB
  error 2.04e-6), 10,000 extreme gamut samples, monotonic-shoulder checks, dither
  endpoint/mean checks, and equal one-second hysteresis response at 30/60/144 Hz.
  These reference calculations do not execute the GPU implementation.
- The final GZW chain compiled and rendered successfully through vkBasalt, with
  no shader errors in the retained runtime logs.
- The test image was `autof_20260515_133058.png`, 2560x1440. A cropped 2552x1439
  image was rejected. No image resizing was used to manufacture a match.
- Each final comparison used a fresh mpv process, five-second compile wait,
  five-second history warmup, equal stage gates, explicit sRGB/BT.709 playback,
  marker verification and marker exclusion from metrics.
- The final JSON includes exact source/reference SHA-256 hashes, the original
  profile, and the unchanged FULL repeat. The restored source files matched those
  hashes after the run.

| Comparison | Mean Oklab distance, x100 |
|------------|-------------------------|
| FULL versus unchanged FULL repeat | 0.000043 |
| FULL versus BLACKS_WHITES bypass | 12.987228 |
| FULL versus FILM_CURVE bypass | 0.000436 |
| FULL versus RETINEX bypass | 0.000349 |

These measure changes, not fidelity. This dark frame demonstrates a large
contribution from the current elevated black floor. It does not demonstrate the
effectiveness of FilmCurve or Retinex across scenes. The diagnostic black-floor
bypass was restored; it is not a profile calibration change.

Final run: `gamespecific/gzw/full_analysis/effects_2026-10-23_155339.json`.
Earlier runs in the same folder used evolving capture protocols; compare their
metadata before interpreting their numbers together.

## Remaining work

Visual recalibration, broader dark/daylight/sky/emitter captures, fresh Arc Raiders
runtime validation, motion and transition testing, and GPU timing remain pending.
Other analysis Kalman filters were not converted to continuous-time models.
The five-second warmup is not a claim of convergence of the 20-second slow key.
Offscreen highway telemetry still needs a real GPU readback path; screenshots now
reject that operation instead of fabricating statistics from image pixels.
