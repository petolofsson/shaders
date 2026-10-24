# Resolve near-black zone statistics — 2026-10-24

After the contrast-toe correction, the next shadow improvement targets the
measurements feeding local contrast, Retinex, slow key and shadow lift.
The 32-bin linear-light zone histogram put every luminance below 1/32 into
one bin. For a uniform zone, intra-bin interpolation therefore returned the
same median and quartiles for black and many visibly different dark grays.
This was demonstrated on the GPU, not inferred solely from code.

## Code change

`general/corrective/corrective.fx` now uses 64 zone bins with squared edges:
`edge(b) = (b/64)^2`. The distribution has finer spacing near black; its
widest bin is 127/4096, slightly narrower than the previous 1/32 bin.
CDF interpolation happens in the square-root coordinate and is squared back
to linear luminance. Moment centers are decoded before computing variance.
Consumers continue to receive linear-light medians, quartiles and standard
deviation, so their existing tuning units are preserved. The global histogram,
entropy definitions and creative values are untouched. Histogram gather work
increases with the wider histogram; GPU cost was not profiled, per user priority.
Shader header comments are preserved as instructed.

## Direct GPU diagnostic

An isolated copy of the combined technique appends an explicit debug pass.
It renders each zone's median, p25 and p75 as sRGB-encoded R/G/B, respectively,
plus the normal activity marker. The 4×4 source contains known uniform neutral
patches. Reading these deliberately rendered values is distinct from the
unsupported screenshot `capture --dump` mode, which cannot inspect offscreen
textures. The temporary technique/config live under ignored
`captures/zone_precision_20261024/`; neither active config is edited.

Every capture uses a fresh process, lossless continuous RGB playback,
5-second compile delay, 20-second settle and an unchanged repeat. Center
samples cover 20×20 pixels per zone. The following are diagnostic median
values expressed as equivalent 8-bit neutral codes, not graded output pixels.

| Source code | Previous median estimate | Corrected median estimate |
|---|---:|---:|
| 0 | 33 | 0 |
| 2 | 33 | 2 |
| 4 | 33 | 5 |
| 6 | 33 | 5 |
| 8 | 33 | 10 |
| 10 | 33 | 10 |
| 12 | 33 | 10 |
| 16 | 33 | 15 |
| 20 | 33 | 21 |
| 24 | 33 | 26 |
| 32 | 33 | 31 |
| 40 | 33 | 41 |
| 48 | 33 | 50 |
| 64 | 61 | 64 |
| 96 | 93 | 94 |
| 128 | 124 | 127 |

On the 13 dark patches through source code 48, mean absolute median error
falls from 19.31 to 1.08 codes; maximum error falls from 33 to 2. The old
black zone also had false p25/p75 estimates equivalent to codes 22/42.
The corrected estimates encode to zero there. Histogram binning still has
finite precision and does not recover the exact distribution within a bin.

The diagnostic reports are [before](../gamespecific/gzw/full_analysis/alternate/effects_2026-10-24_144919.json)
and [after](../gamespecific/gzw/full_analysis/alternate/effects_2026-10-24_145055.json).
Their whole-image source-to-output ΔE is **not** a visual-quality measurement:
they show deliberately encoded statistics. The actual rendered-look checks
below use the ordinary combined pipeline without the debug pass.

## Normal-output validation

Before captures use the already-corrected contrast toe with the old zone
histogram; after captures differ only in `corrective.fx`. Shader/profile hashes
and unchanged repeats constrain the comparison. The dark GZW source
`autof_20260515_133058.png` changes by 0.0927 ΔE. Whole-frame near-black
coverage (max RGB < 5) falls from 2.82664% to 2.62923%. Exact-black coverage
changes slightly from 0.006158% to 0.006592%. No source-selected shadows
with 4 < max RGB <= 64 become exact black in either output. Among those
2,475,429 pixels, near-black occupancy falls from 2.97027% to 2.67647%.
The eligible-pair separation proxy changes from 0.04368% to 0.04305%; this
small difference does not by itself prove a perceptual texture improvement.
The corrected unchanged repeat is 0.0000204 ΔE. This is a modest normal-output
change alongside a clear improvement in the measured zone estimates.

The 12 diagnostic tests pass. Runtime regressions and cut checks are recorded
below. Existing user edits, both tuning profiles, GZW configs,
and the earlier contrast correction are preserved. Moving Babylon validation
remains separate from these held-source comparisons.

## Normal-output regressions

| Input/profile | Exact black %, before → after | Whole-image change ΔE | After unchanged repeat ΔE |
|---|---:|---:|---:|
| gzw_sunset | 0.496203 → 0.498617 | 0.08998 | 0.000002 |
| gzw_dark | 0.006158 → 0.006592 | 0.09265 | 0.000020 |
| gzw_vivid | 0.359538 → 0.356039 | 0.03841 | 0.000019 |
| arc_cloud | 0.006917 → 0.006972 | 0.03435 | 0.002715 |

`gzw_vivid` is an Arc source under the GZW profile; `arc_cloud` is an Arc
source under its own combined-trial profile. These stress inputs do not
calibrate the GZW look. All tested source-black pixels remain RGB (0,0,0),
and no test adds white-channel clipping. Selected vivid regions have zero
median hue change; their mean changes are under 0.08 ΔE in the GZW captures.
Bright regions change by under 0.04 ΔE on average. Small increases in black
occupancy on some inputs mean this is not a universal clipping reduction;
the demonstrated improvement is accurate zone estimates, with modest visual
benefit on the dark GZW reference and controlled ramp.

The contextual ramp retains 60/59/51/47 distinct median levels across its
four surrounding-brightness contexts, versus 60/58/50/46 before this change.
The zero-step counts are 0/2/5/7 versus 1/2/5/7. This is a small improvement
beyond the preceding contrast-toe correction. It does not establish moving
texture stability. The active Arc four-effect chain also compiles/renders,
with a near-zero unchanged repeat; its cross-effect contrast reads remain
inactive, as before. All 12 normal full/repeat captures show the intended
unobscured scenes in `regression_contact_sheet.png`.

Complete normal-run report paths, before/after region measurements and scripts
are retained in ignored `captures/zone_precision_20261024/` (`normal_reports.json`,
`comparisons.json`, `compare_candidate.py`, `ramp_metrics.json`). That directory
also retains the original shader and profile/config hashes, the isolated GPU
diagnostic technique and test input, GPU measurement JSON, and
`zone_median_accuracy.png`. These artifacts are diagnostic evidence, not a
restored golden-image suite.

## Cut recovery and remaining limitation

The [corrected dark→sunset→dark probe](../gamespecific/gzw/full_analysis/alternate/transition_2026-10-24_145942/report.json) completed all six fresh runs, with zero dropped/delayed frames.

| Comparison | Mean ΔE |
|---|---:|
| second_early_to_late | 0.126350 |
| first_early_to_late | 0.219070 |
| first_before_to_after | 0.339600 |
| first_before_to_recovered | 0.015103 |

The returned dark frame at 6.5 seconds is about 0.340 ΔE from the initial
settled dark frame, compared with 0.320 before the histogram change. At
18 seconds the residual is about 0.015 ΔE, versus 0.0000346 before. The
remaining difference is small but measurable above unchanged-repeat variation;
this change does not solve temporal settling. It improves the zone measurement
reference, and is retained with this limitation recorded. Longer-run convergence
and actual moving-shadow stability remain unverified. History behavior is the
next targeted investigation; no specific history filter is blamed without
isolated evidence. The global histogram, zone/slow-key histories and selective
adaptive history can have different response times.

Both tuning profiles and both GZW configs match their starting hashes. The
prior contrast-toe shader also matches its starting hash. Header comments are
unchanged. The normal GZW four-effect chain still lacks shared zone/highway
resources, so the demonstrated adaptive benefit is in the combined trial.
