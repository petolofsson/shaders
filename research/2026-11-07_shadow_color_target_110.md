# Shadow color targeting and 10% strength increase

The user observed that the chosen color variant seemed more active in midtones
than actual shadows and requested roughly 10% more strength. The experiments
below use the isolated GZW lift .25 / BLACKS 0 profile with the experimental
.0025 color offset, and exclude the rejected compact brightness curve.
Production remains unchanged.

## Diagnosis

The original color gate fades in from linear grade-input luminance .0005 to
.005. In the selected 64×64 dark GZW shelf patch, an explicit same-update
readback sampled 256 points at four-pixel spacing. Input luminance ranged from
.000886 to .004513, median .002550; the original gate ranged .021–.967, median
.434. Thus it attenuates the correction substantially in this particular shadow,
consistent with the user's observation; it does not prove this distribution
across all scenes or actual physical shadows. All samples were within the
readback range, and two captures repeated exactly at encoded precision.

## Two isolated candidates

1. **110%:** multiply the color delta by 1.10 *before* calculating its shared
   upper-headroom budget, preserving that budget's role. This is 10% relative
   to the user's previously selected color amount, not a new production knob.
2. **Shadow-focused 110%:** keep the same 110% amount and move only the
   near-black fade-in to .00025–.0025. It remains zero at exact black and reaches
   full gate earlier. The upper fade is unchanged. This deliberately makes the
   response stronger in dark inputs; it can also restore more chromatic noise.

Both copied profiles match SHA-256
`b68135e895dc79abd510f95a5640263eb223dea0975a66d8de57331802918780`.
Grade hashes after capture are `b0f586cbc58107d8fc9e258e1eb11acb396507bcac9fe090e633dd914d3c88dd`
and `c5385603f82d5eb3eb4703be2ecb1f01a6e181f3cebadad6eb0a361e393864a8`.
Configs, shaders, image and log artifacts are isolated in
`captures/shadow_color_110_20261107/` and
`captures/shadow_color_110_shadow_20261107/`. The targeted directory also
contains clearly prefixed copies of the earlier 110% images.

## Observations and limits

For GZW shelf and held warm material, each new candidate has a separate still
repeat: all repeats vary by at most one 8-bit code with the marker masked.
The 100%→110% screenshots also differ by at most one code, so individual pixel
differences overlap repeat uncertainty. In the same-update shelf readback, the
mean Oklab ×100 color difference from 100% to 110% is .0410, with mean ΔL
+.0015; this is a change measurement, not a visible-quality score.

The shadow-focused candidate versus ordinary 110% differs by at most seven
codes in the shelf and warm stills. On the same 256-point shelf grid, its
same-update mean difference from ordinary 110% is .4806 ΔE, mean ΔL +.0229 and
mean Δb +.4713 on the Oklab ×100 scale. Its two readbacks are exact at encoded
precision and contain no excluded ceiling values. The 100/110/target clones in
these probes share a single ordinary-grade scene/history state; these are not
three separately evolved pipelines. The readbacks establish a stronger response
in this selected dark patch, not universal appearance or absence of noise.

On the synthetic zero-BLACKS six-color ramp, the shadow-focused version retains
positive *mean* luma steps in all rows. Relative to the earlier color-off still,
231 pixels become all-channel black versus 224 for the original 100% candidate;
the comparison includes independent capture variation, and these tiny near-black
pixel counts do not establish a visible defect or general endpoint behavior.
The targeted ramp repeats within one code. Direct GPU helper numeric contracts,
real game noise, dense motion, cuts and further materials have not been validated
for either new candidate. The still runner does not capture per-process full
dependency snapshots or drop telemetry; all private captures completed with
activity-marker checks. Explicit readback processes reported no drops/delays.

The local `captures/shadow_color_110_shadow_20261107/review.html` compares all
three still variants. No visual preference, production adoption, effectiveness
rescore or general game acceptance is inferred from these experiments.
