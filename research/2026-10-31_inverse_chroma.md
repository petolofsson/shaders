# Inverse chroma restraint — 2026-10-31

**Adopted and closed:** the rich-color reconstruction budget is 85% of the
existing hue ceiling, with incoming chroma preserved. Final held/numeric/history,
zero-strength and actual active-config checks pass within the stated scopes.

The final bounded improvement task selects a lower reconstruction budget for
already-rich color. It compares blanket half-strength expansion with a limit at
85% of the existing hue ceiling. The limit improves selected red-light color
variation and moderates some blue relationships, while retaining more useful
expansion than the blanket reduction. Blue chroma and some warm-material/color
separation costs remain. This is restraint under model uncertainty, not proof
that an arbitrary SDR source needs inverse reconstruction.

## Starting point and cause

The baseline includes the adopted print shoulder and the [new CC settings](2026-10-31_three_way_cc.md).
Seven full/repeat pairs are reused from the verified CC half/half-repeat images
only after current source, profile, shader/helper and active-config hash checks.
No pre-CC full images are treated as current. Inverse strengths 0.60 GZW / 0.50
Arc and all unrelated profile values are preserved by this work; the external
GZW tint edit is labelled and refreshed below.

The current model's scene slope modifies magnitude rather than establishing
necessity: slope is clamped to 1.15–2.2, and its strength modifier has a 0.7
floor. Colored pixels passing the existing chroma, illumination and local/global
clip guards can therefore expand even in a vivid scene. A histogram or source
chroma measurement cannot establish that those colors were compressed upstream.
This is a role/selectivity limitation, not a new measurement or arithmetic defect.

The original rational curve uses `max(HueCeil(hue), C+0.001)` as its reconstruction
ceiling. It can spend color headroom even for an already-rich input and can crowd
colored shades toward that ceiling. The preceding assessment also showed that
some expansion compensates for downstream losses. Matching final median chroma
to source is not sufficient evidence that reconstruction is appropriate.

## Finite alternatives

1. **Half expansion:** multiply the existing `c1` by 0.5, leaving profiles and
   the original ceiling unchanged.
2. **Rich-color limit:** replace the reconstruction ceiling with
   `max(0.85 * HueCeil(hue), C)`, leaving `c1` and all its existing guards unchanged.

The selected limit does not reduce incoming C. Below the budget the original
rational family still expands toward that budget; at or above it, the formula
returns input C. The budget is a conservative use of the existing hue calibration,
not a detector of lost color or a universal definition of artistic richness.
No new knob, histogram, history, rate or pass is introduced.

A simple multiplicative fade was discarded before GPU appearance testing:
with a fade over C/HueCeil=0.45–0.85, the scalar curve can reverse chroma ordering
at strong settings. The lower-ceiling alternative avoids that failure in the
independent fixed-context sweep. This is not a repair to a shipped fade.
Across 25 ceilings from 0.12–0.24, chroma gates 0.06/0.08/0.10 and strengths
0–2, the selected scalar curve's minimum measured slope is 0.131320. Above-budget
scalar change is below 1.2e-16 in double precision. This freezes the other guards;
it does not prove every pixel-varying RGB/gamut path is monotone.

Both candidates and inverse-off are captured for the vivid blue view, Arc
emitters/interior and GZW daylight. The selected rich-color limit is then tested
with fresh bypasses and unchanged repeats over all seven current held cases.
Half is rejected as the default: it gives less red-light shade preservation and
spends more warm-floor/blue separation without offering a demonstrated compensating
material benefit in this screen. This decision does not imply every image favors
the selected candidate or that its decimal is globally optimal.

## Material/light observations

L/C use Oklab's 0–100 reporting scale. Fixed source rectangles/masks and source-L
quartiles are retained. Color separation compares mean output a/b in lower and
upper source-b quartiles; it is a selected relationship, not known reflectance.
Source PNG is a reference, not assumed identical to rendered shader input.
Final-output interventions include downstream analysis/history responses and
are not additive stage budgets. UI remains in the ordinary images.

The table below is the original screen at GZW shadow tint -0.025; the later
on-disk change and current-profile refresh are recorded separately below.

| Selection / measurement | Starting full | Half | Rich-color limit | Inverse off |
|---|---:|---:|---:|---:|
| Arc red-lamp color separation | 2.457 | 2.670 | **2.844** | 2.486 |
| Arc red-lamp median C | 19.008 | 18.959 | **18.830** | 18.476 |
| Arc red-lamp visible L gap | 18.376 | 18.377 | **18.381** | 18.608 |
| Arc warm-floor color separation | 5.093 | 4.965 | **5.057** | 4.873 |
| Vivid blue-sky median C | 10.096 | 9.707 | **9.888** | 9.422 |
| Vivid blue-sky color separation | 3.844 | 3.448 | **3.570** | 3.048 |
| Vivid blue-field color separation | 6.343 | 5.694 | **6.067** | 5.151 |

The red lamp gains about **15.7% color-shade separation** with less than 1%
median-C loss and essentially unchanged luminance structure. Source color
separation is 2.928, so this retains more of the selected source relationship.
White-core/halo treatment remains. This is not a reward for added saturation:
the selected variant expands less and improves variation within the red light.

The blue-sky/field source color separations are 2.821/5.414. The selected output
moderates the starting chain's larger separations toward those relationships,
but also loses some blue richness. Blue-sky median C is 10.233 source, 10.096 full
and 9.888 selected; the selected output is about 3.4% below source. Arc daylight
sky C falls 9.617→9.450. These are retained palette costs, not automatically
benefits because activity is lower. Warm-floor color separation falls about 0.7%.

Selected dark shelf/blue wall and low-chroma foliage statistics remain effectively
unchanged. Arc dark-metal visible gap remains about 7.752. The preceding CC
settings, shadow-stage work and deliberate black/film controls are retained.
This is not a new solution to the broader shadow-richness goal.

At the current GZW tint -0.015, among 30,787 source-smooth blue horizontal pairs,
p99 pair ΔE changes 0.754140→0.743223, with mean pair growth -0.004972. Maximum
local growth is still +0.372247 and maximum reduction -0.447912. Less processing does not improve
every gradient. These are existing-gameplay spatial observations, not dense
motion, all-gradient or physical-display acceptance.

## Independent numeric evidence

An explicit GPU readback evaluates 768 gray/primary/intermediate-color inputs
under frozen slope/chroma/illuminant/clip/direction states and strengths
0.5/0.6/2. The original, half and selected production-function copies plus an
explicit no-expansion conversion control produce **9,216 records**. Independent
CPU scalar/reference calculations agree within 0.000002517. The readback repeat
is identical. Incoming C is not reduced, output is SDR-bounded, and 155
above-budget cases abstain from expansion within binary-readback/float precision.
Achromatic hue is undefined, so the hue-derived ceiling comparison is omitted
below C=0.0001; C/new-C/strength checks remain.

The first numeric run used an overly tight 0.000005 encoded-RGB identity check.
It failed at 0.000013590 encoded RGB, about **0.0035 of an 8-bit code**. A separate
no-expansion conversion control attributes most of that residual to the existing
RGB/Oklab round trip; selected/control difference is at most 0.000001669 encoded
RGB. The original failed check, images and configs are retained separately.
The follow-up does not claim bit-exact floating RGB identity or change the shared
gamut helpers to chase a sub-code residual. Above-budget chroma abstention and
bounded output pass. The scalar fade counterexample and this identity-threshold
follow-up are diagnostic decisions, not new production defects or repair queues.

## Profile change and held-repeat evidence

In the initial screen, the seven verified starting pairs are exact. Six selected
pairs are exact; GZW daylight differs by one code in 5,281 pixels, about 0.14%
of the frame, with sampled mean ΔE 0.000304 and p99 zero. The final artifact audit
caught an earlier overstatement that all selected repeats were exact; the claim
is corrected here. Small GZW-day differences near that variation are inconclusive.
The red-light and vivid-blue benefit/cost comparisons have exact selected repeats.

Static captures use fresh private/headless processes, five-second
compilation waits and twenty seconds of continuous settling. The held screen
uses 25 new ordinary captures: seven bypasses, seven selected outputs, seven
selected repeats and four half-strength candidates.

Two additional original/selected zero-strength captures match their corresponding
original bypass images exactly. The guard and source bypass remain unchanged.

After those checks, the protected-input audit detected an external GZW profile
change: **`SHADOW_TINT=-0.025` became `-0.015` on disk**. The inverse task did
not make or overwrite that edit. All original snapshots remain labelled with
their original hashes; they are not silently presented as the current profile.

A separate refresh preserves -0.015 and adds **16 current-GZW held captures**:
full/repeat/bypass/selected/selected-repeat for vivid, day and dark, plus one
selected-zero check in daylight. All three refreshed baseline and selected
repeat pairs are exact, the current daylight zero pair is exact, and no black
or code-255 channel pixels are added. The Arc profile is unchanged, so its held
evidence remains current. The muted GZW case retains its earlier -0.025 scope
and is labelled accordingly in the review; it is not claimed as a fresh -0.015
case. This is an input-epoch correction, not a second shader candidate search.

With the current tint, vivid-sky C changes 10.092→9.878 and color separation
3.841→3.567; the blue-field separation changes 6.347→6.071. The same modest blue
cost remains. Current GZW shelf/wall material statistics remain unchanged; daylight
foliage/paving differences are very small. The report's original half-candidate
table remains a comparison within its original profile, not a cross-profile delta.

## Independent temporal validation

The inverse runs before corrective analysis. Each original/selected replay
advances its **own complete actual pipeline and inverse-fed histories**; no
grade-only substitution against baseline histories is used as a surrogate.
The original eight replays cover two variants × two profiles × two repeats.
Four GZW replays refresh the changed tint without rerunning unchanged Arc data.

Each replay freezes 24 night, 20 return and four daylight source phases. Across
all twelve runs, **576 full/actual extraction controls are pixel-identical** on
the common 12,984-sample mask, excluding borders and both atlas-tag footprints.
The current-profile comparison uses refreshed GZW and unchanged Arc, with strict
source/token/source-update/cut-update matching. There are no added black or
clipped-channel samples in those measured windows.

| Current profile/window | Original maximum duplicate-step ΔE | Selected | Repeat original / selected |
|---|---:|---:|---:|
| GZW night | 0.112570 | 0.112700 | 0.112733 / 0.112726 |
| GZW return | 0.743192 | 0.742670 | 0.740518 / 0.742187 |
| GZW daylight | 0.152318 | 0.146963 | 0.152318 / 0.146755 |
| Arc night | 0.122332 | 0.122413 | 0.122449 / 0.122840 |
| Arc return | 0.759758 | 0.758458 | 0.760440 / 0.758862 |
| Arc daylight | 0.139123 | 0.151094 | 0.139166 / 0.149459 |

The Arc daylight peak grows about **0.012 ΔE**, a retained cost; its first
duplicate step grows 0.078422→0.081462. Other small changes do not establish a
general temporal improvement. Current selected temporal repeats reach one code,
with maximum mean ΔE 0.001680 GZW / 0.002850 Arc. The largest selected/original
mean difference over the measured current windows is about 0.03454 ΔE. History
targets may respond differently to the reconstructed source; producer formulas,
rates, initialization and storage are not changed to hide that response.

After adoption, **four actual active-config full/repeat captures**, two per
profile, match their current-profile isolated candidates pixel-for-pixel. GZW
uses the preserved -0.015 tint; Arc retains its existing settings. The earlier
repeat-noise qualification is retained even though these actual checks are exact.
All completed passing runtime runs have zero dropped/delayed frames.

The final audit checks 348 unique isolated files and 1,283 held/frozen/
atlas images, the exact controls, zero bypasses, repeat variation, source/media
identity, preserved profiles at each labelled epoch and inverse-only code scope,
plus the four actual-config outputs. The passing GPU validation comprises 43
new ordinary images, two numeric readbacks, twelve independent history replays
and four actual-config images. The two initial numeric identity-threshold
readbacks are retained separately, not counted as passing numeric contracts.
All 22 diagnostic tooling tests and whitespace checks pass.

Only the reconstruction-ceiling line and its explanatory body comment change in
production. Shader header comments, profiles, configs, grade code, all histories/
rates, resources and eight grade passes remain. In particular, the external GZW
tint edit is preserved and none of the earlier working changes are reset.

Static settling is a fixed protocol, not proof of universal convergence. The
cached clip is 15 unique poses/sec duplicated at 30 fps. Measured sparse phases
do not prove dense native gameplay, physical high refresh, new-game generality,
other resolutions/aspects or calibrated-display acceptance. Runtime work remains
private/headless; no performance profiling, HDR output or auto-exposure is added.

## Effectiveness and closure

My focused inverse-chroma estimate remains **70/100**, with roughly 5–10 point
uncertainty. The selected restraint has a useful bounded contribution: less
presumptive expansion, preserved selected red-light variation and restrained
blue relationships without changing current profiles. It still spends some
blue richness and warm-material separation and retains a small measured Arc
daylight-step cost. Source statistics cannot prove compression or establish
that every remaining engaged pixel needs reconstruction. These limitations do
not support rounding the block up to 75 merely because its contracts pass.

Chain/grade are not re-scored. The last focused CC judgment is borderline 75;
print/look and inverse chroma remain 70, so the all-retained-effects target is
still not demonstrated. The later external GZW tint choice is not a new CC
effectiveness reassessment. These are appearance judgments, not fidelity or
technical-working percentages or universal acceptance.

This closes the finite half/limited-budget decision and the three planned
improvement tasks. No further inverse parameter screen, mandatory repair or
automatic score-driven queue is added. Broader games, dense motion, timing and
resolution/aspect coverage remain optional confidence work. A new change should
have a concrete reported shortcoming and a finite benefit/cost decision.

Subsequent baseline reuse must use the current-profile inverse verification and
selected images with their input hashes. The older muted GZW case and original
pre-edit matrix remain historical, and earlier CC/print full outputs also precede
the new reconstruction budget. Do not reuse them on grade-code identity alone.

All profiles and unrelated working changes remain protected. No commit/push is
made. Scripts/media/configs stay ignored under `captures/inverse_chroma_20261031/`;
this report is versioned. Do not force-add capture artifacts or restore goldens.

- [Interactive current/candidate/bypass review](../captures/inverse_chroma_20261031/review.html).
- [Red-light variation](../captures/inverse_chroma_20261031/arc_emitters_red_lamp_decision.png).
- [Vivid sky](../captures/inverse_chroma_20261031/gzw_vivid_blue_sky_decision.png).
- [Dark-material control](../captures/inverse_chroma_20261031/arc_interior_dark_metal_decision.png).
- [Scalar curves](../captures/inverse_chroma_20261031/scalar_curves.png).
