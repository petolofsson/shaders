# Whole-scene review against the revised shadow goal

**Evidence correction:** the earlier bounded 100% candidate also has direct
compiled arithmetic and ramp checks, as verified in the later
[full-color noise report](2026-11-07_full_shadow_color_noise.md). References below
to more extensive 50% controls do not negate those full-strength checks; they
refer to the distinct half-strength motion and noise validation.

The revised goal concerns the relationship of lit areas, midtones and deep
shadow, alongside restrained material color. This is a visual reassessment of
existing evidence, not a new capture or a new shader candidate. The root grade
hash still matches the checkpoint (`efea23e8c8e061a77619c8c42f89f1d73c35523623ea90a1f3ee4028e8f40c56`);
the historical reports document their own full source/profile/config/include
and repeat identity checks. A grade hash alone does not establish capture identity.

## Observations

- The [November 4 review](2026-11-04_native_visual_review.md) supplies matched
  source/full overviews and native crops in `captures/visible_review_20261104/`.
  In the GZW shelf, the full output keeps a dark recess and visible shelf edges,
  but the dark back panel appears more uniform and less visibly wood-like than
  source. The brighter shelf and courtyard remain distinct. This is a plausible
  local readability cost, not proof that the deeper appearance is undesirable.
- In the Arc trader interior, the graded image preserves a deep foreground and
  the warm market/cool skylight relationship. Some dark structural surfaces look
  denser, but available views do not establish a recurring objectionable loss
  across independent scenes. The vivid daylight overview also retains the broad
  light/landscape relationship; it uses an Arc source under GZW settings, not a
  third game. These static views do not establish moving-game appearance.
- In the independent [held timber comparison](2026-11-06_compact_tone_held_material.md),
  the compact curve makes timber somewhat lighter and flatter while helping a
  selected pack. This conflicts with a consistent depth improvement. The curve
  remains rejected; it is present in some isolated combined stills only as a
  historical comparison.
- The [color investigation](2026-11-06_shadow_color_half_validation.md) supports
  a subtle preservation mechanism, not inference of actual material or lighting.
  Its full numerical, noise and sparse-motion checks apply to 50%. The user chose
  100% for isolated visual testing; the [later captures](2026-11-07_motion_brightness_prototype.md)
  cover limited stills and do not transfer those controls to 100%. The requested
  lift .25 / BLACKS 0 configuration also changes several factors at once, so it
  cannot isolate the color correction's contribution.

## Decision and next evidence

The shelf is a concrete lead, but the existing review explicitly did not establish
an unambiguously objectionable recurring shared loss. The Arc interior alone does
not establish a second instance. Do not invent a new algorithm or reopen rejected
curve sweeps from these observations. Existing bypasses show print, tonal and
black/white stages each affect the scene; their coupled outputs do not uniquely
attribute the appearance to a single stage.

Next, assemble identity-verified native source/full/repeat comparisons from
additional already available representative scenes, emphasizing partial shadows,
deep occlusion and warm/cool/neutral materials. Compare the 100% color candidate
against its matched current output where identities permit, separately from the
combined curve and profile changes. Record both gains and losses and the user's
visual judgment where available. If a recurring consequential loss emerges, use
matched bypasses for attribution before selecting a model. No new score,
production change, temporal benefit or GPU performance claim follows here.

## Follow-up: color and additional whole scenes

Rechecked all 17 production shader, producer, include, profile and configuration
hashes against the held-color report: all match. Its retained captures and the
November 6 color review document their original source, clip, isolated body and
repeat checks. This does not retroactively supply missing capture-time hashes for
the separate November 7 100% screenshot.

The held GZW timber/pack scene preserves the distinction between the dim room,
the warmer lit worktop and the dark figure in both source and current; timber
texture remains visible. The original input PNG is not a separately verified
source-only transfer. The muted GZW daylight control preserves readable paving,
lit masonry and darker foliage; its input PNG has the same transfer limitation.
Neither adds an independent example of the shelf's suspected lost back-panel
detail. In the matched half-color crops, shelf warmth, cool metal and timber
remain restrained, with a small difference at native size; the pack retains its
blue identifier. This is an observer judgment, not user acceptance or proof of
lighting-aware material recovery.

The saved 100% GZW profile is byte-identical to the current profile; its saved
pipeline differs in the grade include path, and its saved grade differs by the
documented color insertion. All 17 current production identities match the
held report. The screenshot report names the same source and records a repeat
within one code, but does not record a complete capture-time snapshot or image
hash chain. Thus the saved comparison is useful for provisional appearance,
not a fully established matched-identity test. In the overview the candidate's
appearance is very close to current, consistent with a subtle contribution;
no additional tonal improvement is apparent. A fresh matched, repeated 100%
comparison with frozen identities is needed before stronger claims, particularly
on held warm material and Arc. The .25-lift/zero-BLACKS combined configuration
must be evaluated separately because it is not an isolated color comparison.

## Fresh 100% warm-material stills

Four fresh private headless `compare_frame.py` runs used the held GZW
`autof_20260515_133444.png`, five-second compile delay and 20-second settling:
two 100% color-only captures followed by two current captures. Images and runtime
logs are retained in `captures/revised_goal_color_100_20261107/`. The source hash
is `ee2f38defaf0823fbe0c5bbf379d4a05b3bc8c8264ee97e0c569b412981203a5`.
The saved candidate profile matches production byte-for-byte; configuration and
pipeline differ by the isolated profile/pipeline/grade paths, and the grade body
diff is the 100% color insertion. The 17 production identities matched the held
report before the run. Candidate grade SHA-256 after the runs is
`bee54194b7670d5e7f963d4b13754c743c58d0e45b325c57278224a311b84597`;
candidate pipeline is `bf3e5e850359906411740a6fb95200b4d9097c1608c57de0f0a2ad7222fe951d`
and config is `c98331ed1ad83d8981660c3d505a1b92f50577b1f782dab8a1f8cd57de616f4f`.
The tool did not snapshot the full dependency tree at each capture, so this is
not equivalent to the earlier comprehensive provenance audit.

With the top-left activity marker masked, baseline repeats differ in 56,111
pixels by at most one 8-bit code; candidate repeats differ in 14,120 pixels by
at most one code. Baseline versus candidate differs in 3,328,067 pixels, at
most seven codes. These changes and repeat variation do not measure quality.
The 100% candidate appears subtly warmer in the timber and pack while preserving
the darker room and lit worktop relationship; it does not visibly solve tonal
gradation. This is one static image and an observer judgment. It does not settle
noise, cuts, real motion, Arc, neutral behavior or user preference. The earlier
50% checks cannot simply be assigned to 100%. PipeWire setup warnings appear
in the private display logs; all four captures completed and the tool verified
the activity marker. No explicit dropped-frame telemetry was recorded by these
single-frame runs. Production adoption remains undecided.

## Fresh 100% Arc interior stills

Four further private headless runs used Arc source
`autof_20260515_205938.png` (SHA-256
`90fa798ca9fb816ab1882691183a412409df0b20da4ea5c28056f7a8563425a1`), the same
delay/settle protocol and two captures each of the candidate and current. Images
and logs are retained alongside the warm-material captures. The isolated Arc
profile matches production byte-for-byte and the isolated grade matches the GZW
100% grade byte-for-byte. Its pipeline hash after capture is
`bddb3795a73d1865d7b43e18bd43012cbc60280e373ec3e9883e62f5519ae809`, config
`de47483ec39f58f12a7052cf397eaa763ddf077f5be918392e17054a9223cbd9`.
The same per-capture snapshot limitation applies.

With the activity marker masked, baseline repeats differ in 28,983 pixels by
at most two codes; candidate repeats differ in 117,115 pixels by at most two
codes. Candidate versus baseline differs in 2,314,455 pixels by at most eight
codes. The repeat variation is real and small differences cannot be confidently
attributed to the candidate. The overview retains the warm market/cool skylight
relationship with no obvious broad cast; the candidate's visual effect is subtle
at this scale. This is a single still, not motion, neutral/noise acceptance or a
claim of improvement. The ordinary private display logs contain PipeWire setup
warnings; capture and activity marker checks succeeded. No explicit dropped-frame
telemetry was collected.
