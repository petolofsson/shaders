# Shadow-context color: isolated review candidate

The user requested a working review test with limited remaining time. This
candidate is an isolated exploratory change, not a validated shadow detector
or production adoption. It starts from the GZW darker-range 110% color variant,
with experimental lift .25 and BLACKS 0, and does not include the rejected
brightness curve. Captures and review are in
`captures/shadow_context_review_20261107/`.

## Candidate and limits

At the post-inverse grade input, eight fixed BackBuffer taps at 32 and 96 native
pixels seek neighbors that are brighter and similar in RGB direction. A smooth
combination extends the existing color gate toward brighter pixels where that
evidence exists. It retains the current pixel's color direction; it does not
recover underlying albedo, propagate neighbor color, use a material ID or know
whether a pixel is really in shadow. Different materials, highlights and texture
can trigger it, and matching can miss colored illumination or large shadows.
The additional texture reads and their cost have not been profiled. This is one
fixed heuristic, not a parameter sweep or a confidence-certified model.

The candidate's grade SHA-256 is
`b7bbc4cb625130f0296c327c16e9d2e09992f0a2a2e42c9788d06a319ef1f300`, copied
profile `b68135e895dc79abd510f95a5640263eb223dea0975a66d8de57331802918780`,
and isolated config `aed05ca74750a37991bfdf03ca84eacd3b02aee6dca602944c137d0cbb975fa3`.
The still runner did not record a complete capture-time dependency snapshot or
explicit drop telemetry. It used private headless playback, five-second compile
wait and 20-second settling, and activity-marker checks.

## Review captures and repeat variation

The GZW daylight source `Screenshot_20260516_101035.png` and dark shelf source
`autof_20260515_133058.png` were captured with candidate repeats. A fresh prior
darker-range repeat pair was also captured for daylight; the existing matching
prior shelf captures are reused. With the marker masked, the candidate daylight
repeat differs in 2,335,923 pixels by at most two codes; the prior daylight
repeat differs in 2,952,792 pixels by at most three. Candidate versus prior
daylight reaches seven codes, but small differences overlap repeat variation.
Candidate shelf repeats differ in 15,545 pixels by at most one code; candidate
versus the preserved prior shelf reaches six codes. Neither magnitude nor
percent changed establishes appearance quality. Fixed settling does not prove
convergence. No natural motion or color-noise validation has been completed.

## Explicit context-signal observation

A separate isolated diagnostic build explicitly writes the context signal as
grayscale, sRGB encoded, before the activity marker; it is not a graded image.
The diagnostic screenshot is
`captures/shadow_context_signal_20261107/context_signal.png`. On one daylight
capture, decoded signal exceeds .01 on about 34% of the manually selected
64×64 shadow-paving patch, 19% of the larger sun-paving crop, and 37% of the
nearby dark-crate crop. The sun crop includes a boundary and the crate itself
may be partly shadowed; these are not verified material/shadow masks or false
positive rates. They demonstrate that the cue responds in multiple areas and is
not selective enough to claim material or shadow identification. The output is
8-bit diagnostic encoding, not a floating-point accuracy or temporal contract.

The local `review.html` switches source, prior and context candidate for both
scenes. Source buttons show original inputs rather than separately validated
source-only playback. The review is for the user's appearance judgment; it does
not erase the uncertainty above. Production remains unchanged.
