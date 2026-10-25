# Signal, statistical and bypass contracts — 2026-10-25

Follows the [completed history audit](2026-10-25_remaining_histories.md), in the
user's requested order: priority 1, then priority 2. Current profiles and prior
corrections remain fixed. This pass checks numerical intent and data flow;
it does not establish artistic acceptance or repair active-chain integration.

## Units and pass cooperation

| Signal | Produced units / processing contract | Live consumer |
|---|---|---|
| BackBuffer | UNORM sRGB code values; explicit decode/encode, sRGB sampler/write flags false | Processing boundaries; source reconstruction ends in bounded SDR before the next BackBuffer effect |
| Histogram, p10/p25/p50/p75/p90/mode | Linear-light luma; global p25/p75 are deliberately trimmed 0.275/0.725 CDF anchors | Corrective/tonal/film/shadow context; no exposure feedback |
| Zone median/quartiles | Linear-light luma decoded from squared histogram-edge coordinates | Local tonal fields and aggregate scene key |
| Zone spread | Population standard deviation of linear-light bin centres, not variance | Zone/Retinex/shadow confidence thresholds |
| Slow key | Linear mean of zone medians with the existing temporal rule | Cube-root neutral-lightness pivot, deliberately clamped to 0.30–0.80 |
| Median C / a,b centroid | Oklab chroma; all-pixel median, colored-only centroid | Inverse slope/hue confidence and grade chroma/print/gamut context |
| Highway chroma slope | Encoded `(slope-1)/1.5`; decoded `value*1.5+1` | Inverse chroma modifier |
| Highway hue angle | Encoded `(atan2(b,a)+pi)/(2*pi)`; inverse reconstructs radians | Inverse hue alignment; sin/cos outputs are assigned in the correct order |
| Cut, achromatic and near-clip fractions | Normalized scalar confidence/fractions | Adaptive gates and highlight/chroma restraint |
| Guided base and coefficients | Log2 linear-light luma; coefficient model evaluated against native input luma | Bounded Retinex gain and local-structure consumers |
| Frame time / exposure | Milliseconds / deliberate `exp2(stops)` user gain | Time-based histories / corrective image signal respectively |

In the combined technique, raw source analysis precedes inverse reconstruction;
corrective zone/chroma publications precede grade. This keeps inverse chroma
from measuring its own expansion. Neutral illuminant is deliberately published
for next-frame inverse use. Grade computes adaptive-next values for its image,
then its later history pass stores that same next step from the same previous
state and current targets; it does not apply two temporal updates per frame.
The [inverse-luma units correction](2026-10-25_inverse_luma_units.md) remains
intact: gain acts in RGB, not as cubed Oklab-coordinate scaling. Its completed
probe is not repeated here.

Stage gates retain their established semantics: corrective/tonal/chroma/look
gates bypass their respective helpers. FilmCurve has its separate `FILM_CURVE`
control and remains outside `TONAL_STRENGTH`, as documented in the earlier
[stage verification](2026-10-24_stage_verification.md). Final SDR projection
and spatial dither remain at output. Complete bypass therefore also zeroes
`INVERSE_STRENGTH` and `FILM_CURVE`, and sets the separately applied affine
black/white mapping to `BLACKS=0`, `WHITES=1`. Existing gate semantics remain.

## Zone histogram population defect

The native producer gathers exactly 10x10 samples per zone and stores each
bin as `count/100` in R16F. `BuildZoneLevelsPS` treated these quantized fractions
as exact unit-mass probabilities, comparing their CDF with 0.25/0.50/0.75 and
using unnormalized first/second moments. Quantization can therefore create a
false percentile crossing and apparent variance in a uniform zone.

A controlled GPU technique uses the actual native R16F histogram and actual
`BuildZoneLevelsPS`, retaining its unrounded result in RGBA32F as well as its
ordinary RGBA16F observation. Sixteen distributions test empty-bin gaps, exact
CDF ties, narrow bright/dark populations, uniform zones and broad distributions.
All 101 possible individual counts 0–100 are also written through R16F and
decoded. A separate pass fills the native spatial lane and calls the actual
`ComputeZoneHistogramPS` on sixteen controlled 10x10 sample populations, then
calls the same statistics function. This checks the producer/consumer path,
not only manually seeded histogram fractions.

The actual producer's tested histograms have total mass approximately
0.9995118 rather than one. A 50/50 first-bin/last-bin population produces
median 0.969009 instead of 0.000244 under the existing interpolated CDF walk.
The 33/17/50 split across bins 40/41/60 produces 0.878921 instead of 0.430664.
The reference retains the existing squared-coordinate within-bin interpolation
and CDF tie convention; it does not introduce an average-of-middle-samples
median. All samples in the final bin produce spurious std 0.021746 rather
than zero. No particular GPU rounding mode is inferred.

The isolated correction recovers the fixed population with
`floor(encoded_count*100+0.5)`, walks CDF targets 25/50/75 in count units, and
computes population variance with weighted Welford updates. This avoids both
the incorrect unit-mass assumption and subtraction of nearly equal moments.
Every possible 0–100 count is recovered exactly at diagnostic precision;
all sixteen populations recover a total of 100. Histogram bins, squared-edge
decoding, observation/history formats, sampling, rates, pass count, scene
adaptation and profiles stay unchanged.

Three fresh private headless before/candidate/repeat processes use five-second
compile wait and 20-second continuous playback. Candidate known-population
maximum median/std errors are 0.000000112/0.000000073; maximum native-producer
error across all four statistics is 0.000000089. Candidate repeat is identical.
All processes have zero dropped/delayed frames. The initial manually seeded
experiment is retained separately; the final experiment additionally verifies
the actual producer and canonical division expression.

## Matched scene and motion checks

Twelve fresh candidate/repeat captures cover the six existing scenes. Before
images are the verified current shared code's complete candidate from the
preceding history batch: all shared shader sources match those snapshots
exactly after include normalization, all source/profile/config/image hashes
are checked, and its unchanged repeats are byte-identical. Every process uses
the same five-second compile wait and 20-second continuous-settle protocol.
No golden image or pre-history-repair baseline is used.

| Input | Before→candidate mean Delta E | Candidate→repeat mean Delta E |
|---|---:|---:|
| GZW dark | 0.000464 | 0 |
| GZW sunset | 0.002607 | 0 |
| Vivid Arc / GZW profile | 0.030606 | 0 |
| Arc clouds | 0.012964 | 0 |
| GZW muted | 0.000708 | 0 |
| Arc emitters | 0.040379 | 0 |

All twelve processes report zero dropped/delayed frames. Full-raster tests
mask only the 2x2 marker. No case adds white-channel clipping, and exact source
black remains zero. Vivid input adds 584 newly black pixels from source
max-channel codes 3–14; all before outputs have max-channel code 1, becoming
zero identically in candidate/repeat. Black coverage rises 0.239990%→0.255833%,
approximately 0.015842 percentage points. Other scenes add no black pixels;
sunset/emitter exact-black coverage decreases. This one-code shadow cost is
retained, not presented as a clipping-free correction or a fidelity score.

The zone-only motion check retains seventeen exact source-identity matches,
sixteen in the seven requested windows. One additional continuous candidate
replay filled missing return-window identities; the incomplete initial coverage
and retry schedule remain archived. All seven windows are covered, with no
seeking, paused playback or route edits. Explicit offscreen readback records
raw zone mass 0.999329–0.999863 and recovered count 100 (normalized encoding
error below 0.000000090). These are diagnostic outputs, not inferred telemetry
from ordinary screenshots.

Candidate/repeat remain close to the baseline in the matched interiors. The
late-return effect is comparable to repeat variation and is inconclusive there.
No match adds white-channel clipping or loses source black. At identities
1408:353 and 1428:358 the candidate adds 45 and 644 black pixels respectively
(repeat: 44 and 642), all changing max code 1→0 from source codes 6–9. This
quantization cost remains visible in the evidence.

## Numerical and complete-bypass checks

Actual GPU helper calls cover signed/positive-overrange RGB↔Oklab,
linear↔sRGB, FilmCurve knees 0/0.6/1, dither noise −0.5/0/+0.5, SDR RGB faces
and eleven explicit out-of-gamut Lab cases. RGBA32F raw results are explicitly
encoded for readback, including finite flags; ordinary screenshots are not used
as numerical telemetry. Bounds, fixed lightness/hue, chroma reduction, half-code
dither amplitude and exact endpoints are checked with quantization-aware
near-black error budgets. Signed roundtrip maximum error is 0.000002504;
relative error is below 0.000002147. Film reference error is below 0.000000465,
sRGB inverse error below 0.000000233, and repeated readback is identical.

An added in-gamut identity invariant exposes a real SDR projection defect:
matrix roundoff can reconstruct a tiny negative or over-one channel at a valid
SDR face, unnecessarily starting chroma contraction. Pure blue and other face
colors can move substantially; maximum tested identity error is 0.214420 in
linear RGB. `OklabToSDR` now permits only a ±0.000001 matrix-roundoff tolerance
in its initial validity test. Binary-search feasibility remains strictly [0,1],
and final `saturate()` still bounds every output. Tested valid-color identity
error falls to 0.000001018, all gamut invariants pass, and repeat is identical.
This is not a wider output gamut or a change to real out-of-gamut compression.

The initial complete-bypass experiment incorrectly left the profile's affine
black/white controls active; that setup and failure are archived. Corrected
local profile copies neutralize those controls, inverse, all four helper gates
and FilmCurve. Original profiles remain unchanged. For both profiles, 768
patches (256 grays plus a 512-color RGB cube) compare disabled baseline,
bypass and unchanged repeat in fresh processes. Maximum interior difference is
one code, mean absolute code difference 0.119091; repeat is byte-identical and
black/white endpoints are exact. All processes have zero dropped/delayed frames.

## Global raw histogram count contract

The global producer also has a fixed population: 32×18 = 576 samples. Its raw
R16F fractions were passed directly into smoothing and raw cut-entropy math.
Normalizing the smoothed histogram's mass cannot recover information lost when
individual fractions round differently. An actual-producer distribution with
190 samples in bin 2, 98 in bin 5 and 288 in bin 58 exposes the problem: the
existing CDF convention requires p50 = 6/64 = 0.09375, while the old direct
walk/cache return approximately 0.906252.

`DecodeLumHistFraction` recovers each raw count with
`floor(encoded*(DS_W*DS_H)+0.5)` and divides by the population before smoothing
or cut entropy. Smoothed histograms are never rounded to integer counts.
All 577 possible counts recover correctly. Actual producer, smoothing, CDF
and percentile-cache passes are exercised in three fresh private processes.
Candidate direct/cache quartiles are approximately 0.04427627, 0.09375004,
0.91328129; maximum oracle error is 0.000000046 and repeat is identical.
Rates, thresholds, initialization, sampling and histogram/publication formats
remain unchanged. No CDF epsilon or scene-dependent tuning is added.

## Combined numerical corrections

The exact-count global histogram and SDR-face guard are checked together on top
of the applied zone-statistics correction. Twelve fresh held candidate/repeat
processes use unchanged sources, profiles and trial configs, five seconds for
compilation and 20 seconds continuous settling. Before images are hash-verified
post-zone candidates with identical repeats. Four scenes are byte-identical to
before; sunset mean Delta E is 0.00000778 and clouds 0.00009676. All six repeats
are byte-identical. Full-raster comparisons mask only the intentional marker:
no added black/white-channel clipping, and exact source black remains zero.
Two fresh individual-reversion captures (global count decoding on vivid input,
gamut guard on emitters) are also byte-identical to the full candidate.
Contact-sheet inspection reveals no visible additional scene change. These
mostly unchanged examples do not establish the rare numerical cases are absent;
the controlled producer/gamut probes demonstrate those defects directly.

Three further fresh before/candidate/repeat continuous motion runs yield fifteen
exact identity matches, thirteen within all seven requested windows. Every
process reports zero dropped/delayed frames. These ordinary screenshots contain
only source identity labels and the activity marker; no history telemetry is
claimed. Interior tests mask an eight-pixel border. Window mean Delta E changes
range 0.000140–0.009268, with repeat variation 0.000257–0.009285. Foliage and
corridor effects are comparable to or below repeat variation. This does not
prove dense continuity or eliminate elapsed-time convergence uncertainty.

No matched interior adds white-channel clipping or loses exact source black.
One pixel at identity 1428:358 (740,833), source RGB (6,6,6), changes output
(0,1,0)→(0,0,0), while repeat returns to (0,1,0). It is retained as an
inconclusive one-code endpoint difference, not attributed as a stable benefit
or defect. Contact-sheet inspection shows no visible new discontinuity at the
sampled poses; source motion remains sparse 15 poses/sec duplicated at 30 fps.

## Adoption

Shared code adopts the exact tested zone count/Welford body, global raw-count
decoder and common gamut validity guard. Headers, profiles, configs, pass order,
manual controls, timing and the earlier corrections remain. The audit closes
PLAN priority 2 for this pass; inverse-model assumptions, sky separation,
coarse-zone gradients and green hue behavior still require the spatial/color
assessment in priority 3. Numerical correctness is not overall visual acceptance.

Two final fresh shared combined-trial captures (GZW vivid and Arc clouds) match
the tested candidates exactly. Both have zero dropped/delayed frames; source,
profile and config hashes remain unchanged. Twenty diagnostic tooling tests
pass and `git diff --check` is clean. These tooling tests do not certify shader
quality; GPU readback and matched captures supply the runtime evidence.

## Scope and artifacts

Ignored [captures/signal_contracts_20261025/](../captures/signal_contracts_20261025/)
retains native/seeded histogram probes, exact count references, isolated shaders,
config/profile copies, source hashes, binary readback and all matched captures.
Active GZW/Arc separate effects still cannot share required analysis resources;
their data-flow defect remains explicit priority 6. No active config switch,
profile retuning, new effect, auto-exposure, HDR output, golden-image suite,
GPU profiling or effectiveness-score increase is introduced by this audit.
