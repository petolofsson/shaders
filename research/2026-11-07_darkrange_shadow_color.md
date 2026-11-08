# Narrower shadow-color range

The user clarified that the desired change is color in dark, gray/black-looking
shadows rather than a visible midtone shift. This isolated test starts from the
previous shadow-focused 110% build with GZW lift .25 and BLACKS 0. The color
calculation still follows the pixel's available input color; it does not infer
material color when the input is neutral or distinguish dark materials from
shadows. Production remains unchanged.

## Candidate

The sole shader-body change moves the upper linear-luminance fade from .08–.15
to .01–.04. The lower fade .00025–.0025, 110% amount, shared headroom budget and
all copied profile values are unchanged. This is a single targeted experiment,
not a parameter sweep. Candidate grade SHA-256 after captures:
`a7e2b1754029bc087eae0ef7e847aa35632f29806e97d1abac17cea07d077553`;
copied profile SHA-256:
`b68135e895dc79abd510f95a5640263eb223dea0975a66d8de57331802918780`.
It is isolated in `captures/shadow_color_darkrange_20261107/`.

## Same-update evidence

Two private headless captures each sampled a 16×16 grid at four-pixel spacing
in a 64×64 dark shelf patch `(280,500)-(344,564)` and a brighter yellow wall
patch `(700,400)-(764,464)` from the GZW shelf source. The previous 110% and
new transforms were cloned and evaluated in the same invocation, sharing the
ordinary baseline's scene/history state. They are not independently evolving
ordinary pipelines. All 256 samples per patch were within the [0,.25] readback
range and each patch repeated exactly at encoded precision. Four processes
reported zero dropped/delayed frames. Inputs, output arrays, configs, cloned
shader and report hashes are in `captures/shadow_color_darkrange_probe_20261107/`.

For the dark shelf, input linear luminance is .000886–.004513, median .002550;
all 256 sampled previous/new outputs match at readback precision because both
upper gates are fully open there. For the wall, input linear luminance is
.028923–.040494, median .034070. Its previous upper gate is fully open; the new
upper gate's sampled median is .102. Mean new-minus-previous output is
`(ΔL, Δa, Δb) = (−.00535, +.02285, −.27954)` in Oklab ×100, with mean ΔE .28061.
This confirms a smaller contribution on this wall while retaining this dark
patch; it does not establish a general perceptual preference, semantic shadow
segmentation, natural-noise behavior or universal endpoint safety.

## Still comparisons

Two private headless captures per GZW shelf and warm interior used five-second
compile wait and 20-second settling. New shelf and warm repeats differ in 7,298
and 33,933 pixels respectively, each by at most one 8-bit code, marker masked.
Compared with the previous 110% still, the new shelf reaches seven codes and
warm reaches six; these are changes, not quality scores. Still captures and
logs are under `captures/shadow_color_darkrange_20261107/`. They do not include
per-process full dependency snapshots or explicit frame-drop telemetry.

`captures/shadow_color_darkrange_20261107/review.html` switches source, prior
110% and new range. Source images are original screenshots, not independently
validated playback transfers. The candidate has not had dense motion, actual
game noise, synthetic near-black ramp or broad material validation. The earlier
near-black quantization risks still apply; changing the upper fade does not
establish their resolution. Further selection is a visual decision, not
automatic production adoption.

## Requested 200% visual comparison

The user requested a 200% version in the same review. The isolated
`captures/shadow_color_darkrange_200_20261107/` copy changes only the color-delta
multiplier from 1.10 to 2.00; its luminance gates and profile are identical to
the 110% darker-range candidate. Four private headless captures used the same
shelf and warm source images, 5-second compile wait and 20-second settling.
With the marker masked, the 200% shelf repeat differs in 4,550 pixels and the
warm repeat in 2,007, both by at most one code. Captures and isolated config
remain in that directory, with runtime logs under `/tmp/shader-runtime-toy92kpf`,
`/tmp/shader-runtime-wxn2aeci`, `/tmp/shader-runtime-0whg8p4k` and
`/tmp/shader-runtime-qt7zttk7`. The still runner did not collect explicit
drop telemetry or complete per-process dependency snapshots. The current
production identity set remained unchanged. The existing review now includes
the 200% images; these are for visual comparison, not a noise/motion validation
or production adoption.
