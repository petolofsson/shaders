# Scene-adaptive zone contrast — 2026-10-26

Continues the [spatial attribution](2026-10-26_spatial_color_attribution.md).
Interpolating a 4×4 contrast pivot paints low-frequency gradients into uniform
materials. This experiment tests scene-adaptive pivots before changing shared
code. Profiles, headers, histories and prior Retinex/rim repairs remain intact.

## Candidate and tradeoff

`scene_pivot` replaces the pixel's interpolated median with the existing scene
key, the live mean of sixteen temporally smoothed zone medians. It retains the
local IQR. `scene_fields` also replaces the interpolated IQR with the existing
global percentile span. The latter makes the zone curve spatially uniform for
a fixed scene context and input luminance, so the zone stage cannot create a
gradient inside a uniform material. These are live statistics, not a fixed UV,
hardcoded pivot, exposure feedback or paused adaptation.

This changes the stage's model: local median/IQR contrast becomes a
scene-adaptive signed contrast curve. It gives up region-specific tonal
placement to avoid interpreting mixed neighboring materials as illumination.
The existing strength, uniform 0.65 confidence, slope cap, highlight protection,
smooth negative-arm toe, diagnostic gate and history rates remain unchanged.
No new control, pass or effect is added. Actual history production remains live
for aggregate statistics and other consumers.

This is an experiment, not an assumption that global processing is always
better. Dark materials, scene-dependent strength and colored highlights can
change when the local pivot changes. Native game crops, clipping/quantization
costs and matched motion must constrain adoption. No strength is retuned to
make an individual test frame pass.

## Held-pose evidence

Four fresh private headless captures compare each candidate and its unchanged
repeat on source pose 1044/token 262. Current/current-repeat reuse the preceding
attribution's byte-identical captures after checking source and all shared
shader/profile/config hashes. Each fresh process uses a five-second compile
wait and twenty-second continuous settling, verifies source identity/marker
and reports zero dropped/delayed frames. Both candidate repeat pairs are
byte-identical.

Exact source RGB masks are eroded eight pixels on the full raster, restricted
to ROI (800,700)–(1840,870). Aligned 8×8 blocks wholly inside each selection are
averaged in Oklab L, then their 95th−5th percentile spread is measured (L ×100).
This reduces dither sensitivity; it is not an independent transfer calibration.

| Material | Current broad spread | Scene pivot | Scene fields |
|---|---:|---:|---:|
| Purple | 0.259 | 0.018 | 0.018 |
| Cyan | 0.301 | 0.018 | 0.018 |
| Green | 0.238 | 0.018 | 0.018 |
| Orange | 0.157 | 0.017 | 0.017 |
| Blue background | 0.564 | 0.023 | 0.023 |
| Magenta | 0.469 | 0.183 | 0.183 |

Orange and purple edge-minus-center median L remain zero. Magenta's edge gap
falls 0.118→0.082 L; its non-zone interior variation remains. The uniform blue
background's edge gap falls −0.368→0.000 L. Native crops show reduced interior
shading while retaining the earlier rim corrections. These selected interiors
cannot distinguish the two candidates: their values match here but whole-frame
images differ, since local IQR still affects other regions.

## Rejected unbounded candidates

`scene_fields` is rejected after current/candidate/repeat on dark GZW, GZW
sunset and vivid Arc input under GZW tuning. The next Arc-cloud capture is
interrupted and excluded; the batch is not a completed six-scene regression.
All nine completed captures have zero dropped/delayed frames and unchanged
shared sources. Sunset adds 19,869 black pixels from source max-channel codes
2–7; vivid adds 31,512 from codes 3–18. No new white-channel clipping is added.
The flatter held faces do not justify these shadow costs.

A narrower `scene_pivot` follow-up retains local IQR and reuses the verified
fresh current sunset capture. Candidate/repeat are identical, but still add
3,205 black pixels, all output max-channel code 1→0 from source codes 2–7.
It too is not adopted as a general repair. These reports/images remain intact
at the artifact root and under `median_only/` respectively.

## Bounded shadow-tail candidate

The existing subtractive toe is `Y / (1 + A/Y)`, where A is positive shadow
debt. If the scene pivot is positive while Y approaches zero, A can approach
a positive constant and the result approaches `Y²/A`. Smooth zero alone
therefore does not prevent excessive relative darkening near black.

The revised candidate keeps the scene fields but normalizes that debt by
`Y + M`, where M is the same live scene pivot: `Y / (1 + A/(Y+M))`. This is
a shadow-arm change, not exposure feedback or an additive black floor. The
positive arm, curve strength, slope cap, confidence, highlight protection and
zero-strength bypass remain. The earlier smooth nonnegative toe is retained
and strengthened with a finite gain bound; no user setting is added.

For nonnegative source luminance and M, the negative-arm debt obeys `A ≤ S*M`,
where S is the existing effective zone-strength budget (including IQR and
confidence). Consequently the revised output/input ratio is at least
`1/(1+S)`, rather than tending to zero. Exact black stays black; as input tends
to black, its output has a linear tail with finite nonzero gain. This uses the
existing scene scale and strength budget, without adding a fitted clamp.

The first bounded sunset candidate/repeat are identical and add no new black
or white-channel clipping. Exact-black count is 16,070→9,316 (source 9,298).
That count alone is not a quality score. Ground source-group separation changes
30.699→30.358 L (source 34.607); facade 38.785→37.639 L (source 41.771).
These are retained tonal tradeoffs, requiring the remaining game/motion checks.

## Bounded GPU and six-scene checks

The explicit GPU curve probe extracts the actual zone body into old/new
diagnostic functions. It replaces texture context with controlled scalar
arguments and renders the results into RGBA32F before binary 24-bit readback
over [0,2]. Ordinary screenshots are not treated as hidden shader telemetry.
Four median/IQR contexts exercise 64 log-spaced luminances including zero and
one, then repeat with the zone gate disabled: 512 records per capture.

Two fresh private processes match the independent reference to at most
0.000000462, with identical repeated readback. Tested curves are monotonic,
black is exact, zero strength returns input, and positive-input gain respects
the derived floor. Minimum measured candidate gain in these contexts is
0.914411; the old response approaches zero. This is controlled curve evidence,
not proof that all arbitrary user profiles or complete images are monotonic.
See `probe/report.json` and its archived extracted shader.

Fifteen fresh bounded candidate/current/repeat captures complete six held
scenes. The three original current captures from the rejected batch are reused
only after verifying source/shared-code/profile identity and image hashes;
the other current captures and all candidate/repeats are fresh. Each process
uses the same five-second compile wait and twenty-second continuous settling.
Full-raster summaries exclude only the 2×2 activity marker.

| Input/profile | Current→candidate mean ΔE | Candidate/repeat mean ΔE | Black pixels, current→candidate |
|---|---:|---:|---:|
| GZW dark / GZW | 0.060069 | 0 | 219→0 |
| GZW sunset / GZW | 0.675504 | 0 | 16,070→9,316 |
| Vivid Arc input / GZW | 1.007034 | 0 | 9,431→124 |
| Arc cloud / Arc | 0.444968 | 0 | 193→93 |
| GZW overcast / GZW | 0.544145 | 0 | 6,958→28 |
| Arc emitters / Arc | 0.135692 | 0 | 9→0 |

Every candidate/repeat pair is byte-identical. No case adds newly black pixels
or white-channel clipping; exact source black stays zero. Source black counts
are respectively 0, 9,298, 124, 91, 28 and 0. These counts bound endpoint costs
without establishing aesthetic quality.

Inspected full-scene and native material crops retain expected geometry,
clouds, light shapes and the manually selected palettes. Material lightness
gaps compare fixed source bottom/top quintiles:

- Shelf gap 4.238→4.068 L (source 4.156); median L/C stay 12.257/0.451.
- Sunset ground/facade gaps retain the losses recorded above.
- Vivid sky gap 6.939→7.377 L (source 9.709), median C unchanged at 12.653.
  Retinex's remaining broad-sky compression is not repaired by this change.
- Arc cloud gap 19.778→19.066 L (source 18.610); median L remains 91.015.
- Overcast foliage gap 17.570→17.239 L (source 16.570); median C 4.034→4.046.
  Existing three-way profile choices remain; no green-hue retuning is introduced.
- Red-lamp median L stays 49.913 and C 18.728→18.744. White-core median L
  stays 93.837, but white-halo median falls 70.424→69.082 L (source 73.472).
  That halo brightness cost is retained rather than hidden by whole-frame means.

The candidate gives up some local separation and halo brightness while removing
the zone field's false structure and excessive near-black debt. It is not a
claim that every material improves, or that fewer black pixels prove fidelity.

## Bounded held pose and matched motion

Two further fresh bounded held-pose captures are byte-identical. Purple's broad
spread is 0.259→0.014 L, cyan 0.301→0.018, green 0.238→0.018, orange
0.157→0.017, background 0.564→0.020 and magenta 0.469→0.190. Orange and purple
edge gaps remain zero; magenta changes 0.118→0.024 L. The bounded candidate
retains the earlier rim removals; magenta's non-zone variation remains.

Nine fresh private continuous replays provide 28 exact source identities,
25 inside all seven requested windows. The original incomplete coverage from
the first and second attempts is retained. All nine processes report zero
dropped/delayed frames. The unchanged cache manifest, all source-frame hashes,
clip hash, 20-second pre-roll and 15-pose/sec duplicated-30-fps protocol are
verified. No route, speed or pause change is introduced to manufacture matches.

Motion summaries use an eight-pixel outer border mask and every fourth pixel;
endpoint counts use the complete masked interior. Frame labels and marker are
excluded. Only exact decoded identities enter the comparison.

| Window | Exact matches | Current→candidate mean ΔE | Candidate/repeat mean ΔE |
|---|---:|---:|---:|
| Foliage | 5 | 0.636095 | 0.026100 |
| Clearing | 1 | 0.812638 | 0.000023 |
| Before night cut | 3 | 0.758952 | 0.000174 |
| After night cut | 3 | 0.381744 | 0.001744 |
| Corridor | 8 | 0.005076 | 0.001445 |
| Before return cut | 3 | 0.003228 | 0.000747 |
| After return cut | 2 | 0.816081 | 0.794314 |

No matched interior adds black or white-channel clipping; exact source black
remains zero. At clearing identity 1020:256, purple's broad spread falls
0.210→0.015 L and its edge gap 0.092→0.000 L. Orange, green and cyan broad
spreads fall 0.142/0.221/0.293→0.019/0.018/0.020 L; orange's edge gap remains
zero. Magenta spread falls 0.351→0.189 L but its edge gap increases slightly,
0.071→0.077 L, identically in candidate/repeat. This small retained boundary
cost is not presented as every metric improving. The inspected exact-match
contact sheet retains source geometry and the earlier obvious rim correction.

The first return identity 2160:541 is inconclusive for temporal stability:
current→candidate is 0.916 mean ΔE, while candidate/repeat is 1.588. One of
three repeat-run samples differs markedly from the others; the other pair
differs by 0.000188. Two available original-current samples differ by 0.001253,
and two candidate samples by 0.000834. This larger isolated repeat difference
must remain explicit. A shared source pose does not identify which duplicated
presentation or analysis-history state was captured at the cut. Later identity
2188:548 repeats at 0.000300. No dense-continuity, all-cut stability or physical
high-refresh acceptance follows. See `bounded/return_repeat_audit.json`.

## Adoption and verification

The bounded candidate is applied to `general/grade/grade.fx`. Executable code
matches its tested isolated copy after include/comment normalization; shader
header comments are unchanged. Per-game profiles, active configs, producer
statistics, authoritative histories, rates, pass count, manual exposure and
the earlier Retinex/gamut repairs remain. The per-zone histories are still
produced for live aggregate median/spread consumers; unused quartiles are not
repaired or removed by association.

Twenty diagnostic tooling tests and the whitespace check pass. The pre-adoption
artifact audit verifies all recorded image/config/profile/shader hashes, exact
lossless source-clip pixels, completed runtime logs, held repeats and motion
coverage. This is scoped technical validation, not an effectiveness score or
overall aesthetic/temporal acceptance.

Five final fresh private captures complete applied-path verification. Shared
GZW sunset, Arc cloud and the held target match their tested candidates
pixel-for-pixel. Active GZW sunset and Arc cloud match their unchanged before
controls pixel-for-pixel. All five have zero dropped/delayed frames. The active
chains' unavailable cross-effect analysis resources remain; these controls do
not validate adaptive behavior there or switch either active config.

The final artifact audit passes after the applied change, with only
`general/grade/grade.fx` changed among shared shaders/profiles/trial configs.
See `audit_after.json`, `bounded/applied_report.json` and
`bounded/applied_pixels.json`. Rejected candidates and incomplete coverage are
retained alongside successful runs. The isolated first-return repeat outlier
needed presentation/history-state alignment before temporal acceptance;
Retinex sky compression was the next repair at that point. The follow-ups below
resolve alignment and sky compression; wider hue/gamut/game coverage remains open.

Subsequent [return-cut GPU alignment](2026-10-26_return_cut_alignment.md) resolves
the apparent repeat outlier above: it compared GPU update 2 with update 1 of
the duplicated pose. Frozen native outputs reproduce 1.588 ΔE across phases;
same-phase repeats differ by at most 0.000426. The historical measurements stay
intact, but they are not phase-aligned temporal-repeat evidence. The real
Retinex cut-confidence handoff is deterministic and remains a separate visual
behavior to assess, rather than an unexplained history instability.

## Artifacts and status

Ignored [captures/zone_scene_pivot_20261026/](../captures/zone_scene_pivot_20261026/)
contains isolated sources/configs, capture and analysis scripts, runtime-log
paths, hashes, held images, native crops and metrics. `held_report.json` and
`held_metrics.json` record the initial comparison. `bounded/` holds the revised
candidate and six-scene checks; `probe/` holds explicit GPU curve readback.
`bounded/motion_report.json` retains every attempt and exact-match coverage;
`bounded/motion_metrics.json` records material/endpoint costs. Active-chain
controls and final applied captures are indexed separately. No golden suite,
profiling, new effect, profile retuning or active-config switch is introduced.

The subsequent [Retinex follow-up](2026-10-26_retinex_sky.md) uses this post-zone
baseline and repairs measured sky compression without restoring held-face rims.
