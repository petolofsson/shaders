# Unusual improvement lead: color correction through shared RGB — 2026-11-03

**Subsequently adopted with user authorization:** see the
[completed adoption decision](2026-11-03_neutral_component_cc_adoption.md). The
following records the initial discovery screen and its then-current limits.

**The strongest new lead is to make three-way color correction act in proportion
to the component shared by all three RGB channels.** An isolated three-line
prototype has a useful first result: the selected GZW foliage hue shift falls
from +2.962° to −0.131°, while the measured neutral-shadow treatment remains
essentially unchanged. Arc cool-upper color separation increases about 4.4%.
There are small paving, cloud and warm-floor costs. This is a promising lead,
not an adopted enhancement or a new effectiveness score.

Production remains `738a6f6`. Shared production shaders, profile values, active
configs, headers and histories remain unchanged. Chain/grade stay 78/100 and
other estimates are carried forward. The task was to find an unusual improvement;
source/design work and a small isolated screen establish this as the next
concrete candidate without turning it into a production change.

## Why look here

`Apply3WayCC` in `general/grade/grade.fx` adds scene-key-weighted Oklab a/b offsets
with a near-black fade. Its offset has no material-color selectivity: at the
same Oklab lightness, gray concrete, green foliage and a colored practical can
receive the same vector. The earlier [CC assessment](2026-10-31_three_way_cc.md)
documented foliage hue steering and canceled subtle shelf warmth. Halving the
shadow controls improved the balance, but also reduced the neutral-shadow
response. Those selected profile values remain intact.

The new approach changes **where correction applies**, rather than reducing all
settings again. Write a nonnegative linear RGB pixel as:

```text
rgb = minimum_channel * (1,1,1) + colored_remainder
shared_fraction = minimum_channel / linear_luminance
```

Multiply the existing CC offset by the bounded shared fraction. Keep its
original zone weights, offsets, black fade and user controls. In the isolated
copy this is just:

```hlsl
float common_rgb = max(min(lin.r, min(lin.g, lin.b)), 0.0);
float neutral_share = saturate(common_rgb / max(Luma(lin), 1e-10));
black_gate *= neutral_share;
```

The two existing offset expressions then use the modified `black_gate`.
Nothing is subtracted from the final image's gray component. This is a weight
on the existing correction, not RGB replacement or saturation enhancement.

A gray pixel retains the full existing correction. A saturated primary has no
shared component and receives zero offset. A dark green gets protection because
it is green, without depending on how many green pixels occupy the frame.
For positive RGB scaling, the ratio is exposure-invariant in this helper's input
domain. The complete chain still has its existing affine black/white mapping
and artistic exposure response; no whole-chain exposure invariance is claimed.

This is an algebraic color-selectivity rule, **not a measured separation of
reflectance and illumination**. A colored light can illuminate a gray material;
the formula cannot identify that situation, artist intent, or semantic objects.
It deliberately retains more incoming color in those pixels. Whether that is
preferable needs varied scene review. No white balance, material recognition,
new effect, new tuning surface, added pass/texture, automatic exposure or HDR is
introduced. This is unusual relative to the current pipeline, not a claim of
research novelty.

## Initial evidence

CPU algebra checks establish full gray-axis response, positive exposure
invariance, zero response on RGB primary faces and finite black behavior. A
muted green example `[0.03,0.08,0.025]` receives 38.2% of the original correction;
rich green `[0.004,0.1,0.006]` receives 5.5%; warm near-gray `[0.10,0.08,0.065]`
retains 78.2%. These are supplied linear-RGB examples, not measured game material
properties or compiled GPU contracts.

The private headless screen uses current GZW daylight and Arc interior. Six
fresh captures plus two independently verified reused current Arc captures
supply four exact current/prototype held pairs. Source/clip/profile/config and
normalized grade identities are checked before reuse. The isolated pipeline is
identical to production; only the three CC lines differ. All eight captures
have zero reported drops/delays. Each uses five seconds compile wait and twenty
seconds continuous settling; this fixed protocol does not prove convergence.

Fixed source-selected regions and masks match prior material reports. Hue is
reported only for sufficiently chromatic samples. Color separation is the gap
between mean a/b vectors in fixed lower/upper source-b quartiles, on the existing
Oklab ×100 scale. These measures explain changes; they are not quality targets.

| Selected measurement | Current | Shared-component CC | Interpretation |
|---|---:|---:|---|
| GZW foliage source-relative hue shift | +2.96165° | −0.13131° | Much less source hue steering |
| GZW foliage color separation | 1.84390 | 1.90091 | +3.1% |
| GZW lit-paving color separation | 2.64111 | 2.72027 | +3.0% |
| GZW wall color separation | 1.09377 | 1.13379 | +3.7% |
| GZW shadow-paving color separation | 1.97654 | 1.96868 | −0.4% cost |
| GZW cloud color separation | 6.54063 | 6.46782 | −1.1% cost |
| Arc dark-metal color separation | 1.62732 | 1.69436 | +4.1% |
| Arc cool-upper color separation | 3.08872 | 3.22567 | +4.4% |
| Arc cool-window color separation | 2.59514 | 2.61515 | +0.8% |
| Arc warm-floor color separation | 5.22446 | 5.14254 | −1.6% cost |
| Arc warm-floor source-relative hue shift | +3.67887° | +2.88596° | Smaller hue shift despite separation cost |

Selected L gaps are nearly unchanged: foliage 5.22996→5.22604, dark metal
8.98051→8.98143 and cool window 31.97347→31.97327. This is principally color
selectivity, not increased tonal contrast. Arc cool-upper median chroma increases
3.9391→4.0366, while warm-floor chroma decreases 4.5363→4.4877. More chroma is
not uniformly the outcome or the objective.

A source-neutral shadow diagnostic samples C<0.5, L=12–35 on the existing
stride-eight border-cropped grid. GZW has only 31 samples and its median output
b remains −0.129065. Arc has 5,032 samples: median output b changes
−0.399180→−0.396311, retaining the cool neutral treatment. These are final output
observations, not isolation of the CC contribution or proof that every
near-neutral source pixel is unchanged. Exact gray-axis preservation is currently
a CPU algebra property.

No new black or code-255 channel pixels occur in either held case. Changes are
larger than the rejected transport's one-code redistribution: maxima are 11
codes in GZW and 21 in Arc, with the Arc maximum in its top-left colored UI
logo. This is neither an improvement score nor evidence that a large delta is
wanted. The unchanged repeat pairs are exact, so these selected differences are
repeatable under the held protocol.

Visual review covers both overviews and native foliage, paving/wall/cloud,
dark-metal, warm-floor, cool-upper/window and maximum-change crops. The foliage
is less hue-steered; the neutral cool-shadow direction remains. Changes are
subtle at overview scale. Some muted-color/lighting treatment is reduced, and
selected separation costs are retained rather than called fidelity gains.

## Other ideas considered

- **Illuminant-relative chroma expansion:** subtract a lighting-color anchor,
  enhance only deviations, then restore it. This could preserve atmosphere
  while distinguishing materials, but the current low-frequency/neutral estimate
  cannot reliably distinguish a colored wall from colored lighting. That
  assumption risk makes it a weaker first choice than the local algebra above.
  This is not authorization to revive automatic white balance.
- **Preserve pairwise color relationships through the look:** protect differences
  between nearby material colors rather than each pixel's absolute saturation.
  This could address relationships a scalar chroma floor misses, but needs a
  clearly attributed surviving gap and stable spatial confidence. No shader or
  runtime experiment is claimed for it; no new local-detail effect is queued.

The selected lead has a clear reason to engage in both current profiles, no
inferred illuminant, no new temporal state and no full-resolution working
surface. It directly tackles a documented material/creative-treatment tradeoff.
It does not reopen print toe, tonal gain limits, gamut-budget or transport
screens.

## Limits and concrete continuation

This first screen establishes a worthwhile candidate, not adoption. It does not
include direct GPU arithmetic readback, zero-control/gray/primary/quantized-gradient
charts, additional dark/vivid/emitter cases, measured motion/cut controls,
actual-config activation or performance acceptance. CPU checks are not GPU
validation. A 21-code colored UI response and selective reduction of warm/cool
lighting treatment warrant emitter/palette checks before any production change.

A focused continuation would first challenge colored-light and muted-material
behavior, including the earlier weak shelf case; then validate the compiled
selectivity and gray/zero-control contracts. Broader adoption work is justified
only if those comparisons retain a useful visual balance. No score increase or
parameter sweep follows from this initial result.

## Artifacts and publication

Local ignored evidence: `captures/neutral_cc_20261103/` contains `design.json`,
`report.json`, `metrics.json`, `audit.json`, isolated copies, source/capture
identities and runtime paths. `verification.json` hashes the archived files.
[Local comparison sheet](../captures/neutral_cc_20261103/review.html).
The production tree remains unchanged and published at `738a6f6`; this report
and updated startup/handoff notes are uncommitted and not pushed.
