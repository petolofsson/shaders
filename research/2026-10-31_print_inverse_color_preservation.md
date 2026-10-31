# Print and inverse color preservation — 2026-10-31

**Adopted and validated. Focused print/look and inverse-chroma estimates are now
75/100 each, borderline. This finite follow-up is closed.**
The user explicitly requested improving both effects toward 75/100 and reiterated
that work should continue. The earlier finite decisions remain historical evidence;
this new request authorizes the targeted follow-up below.

## Scope and decisions

The starting point includes the previous print shoulder, guarded inverse-luma,
three-way CC and inverse-chroma budget changes. GZW's externally selected
`SHADOW_TINT=-0.015` and all other current profile settings are preserved.
Source, profile, shader and config hashes define baseline reuse. The muted GZW
baseline is freshly captured at the current tint; it is not the older -0.025 case.

Print's per-channel power/shoulder curve changes color ratios in addition to
density. The selected candidate keeps that curve's output luminance and blends
toward an RGB-ratio-preserving result over input linear Y=0.01–0.10. Below that
range the original print remains. The ratio path does not receive a second
desaturation. Existing masking/dye couplers, print adaptation, manual strength
and the preceding FilmCurve remain. This does not weaken the existing shadow
toe or add a new tuning control.

The first print ratio candidate retained the old desaturation and weakened
material colors; it is rejected. A second unprotected ratio candidate restored
midtone color but weakened subtle dark colors. The selected shadow-protected
blend retains the useful midtone/palette benefit while protecting deep shadows.

Inverse chroma's existing 0.85 hue budget does not describe the available gamut
at a pixel's lightness. The selected candidate searches outward from the valid
source color to that budget and limits added chroma to available SDR headroom.
When the original ceiling is valid, it remains exactly the original ceiling.
Incoming chroma is never deliberately reduced. The rational expansion, existing
gates, manual strength and final SDR projection remain.

A first candidate's blanket 2% budget margin reduced safe colors unnecessarily;
it is rejected. A 10-step headroom search showed a tiny ordering reversal in an
extreme-strength dense scalar test (minimum C step -0.000002486 at L=0.35,
budget 0.204, strength 2). The final search uses 14 steps. Earlier seven-scene
`joint` captures retain the 10-step version; `selected` captures use 14 steps.
Those epochs must not be silently combined as identical code.

## Independent contracts completed

- Print: a 35,937-color CPU grid at strengths 0, 0.3, 0.7 and 1 retains the
  original luminance to numerical precision, the deep-shadow response and the
  gray curve. Results remain bounded. The 7,680-record GPU probe covers gray
  ramps and mixed colors at strengths 0, 0.7 and 1; its repeated readbacks are
  identical and maximum CPU error is 0.000000418. Both zero-strength GPU variants
  are identical. The original CPU-generated HSV identity threshold of 1e-7 was
  too strict for GPU input generation/readback; the measured discrepancy is
  recorded separately, and the existing readbacks were analyzed without a
  production change or an unnecessary rerun.
- Inverse: the independent 14-step sweep covers 720 hue rays, 1,025 chroma values,
  eight lightnesses, three budget bounds and strengths 0.5, 0.6 and 2. It checks
  20,347,479 valid-input cases with no gamut excess or negative chroma step at
  the sampled spacing. This is a bounded numerical test, not a proof over every
  floating-point input or pixel-varying scene context.

The final inverse GPU readback contains 9,216 records: baseline, selected,
selected duplicate and no-expansion control, with 768 frozen input/context cases
and three record fields. The duplicated selected copy is not an independent
appearance test. Repeated readbacks are identical; maximum independent scalar
reference error is 0.000007288. For colored inputs (C>2 on the Oklab ×100 scale),
maximum hue change falls 1.48529°→0.000573°. A dark blue at encoded RGB
(0,0.0625,0.25) now abstains instead of expanding into the blue-cusp projection.
Expansion remains engaged for 193 inputs versus 203 previously. Maximum measured
chroma loss falls 0.013692→0.0000318 on the same ×100 scale, leaving floating
conversion/readback residuals rather than a bit-exact RGB identity claim.
The 155 already-rich cases remain within 0.000001669 encoded RGB of the explicit
no-expansion control. Source compression or artistic intent is still not known.

## Held appearance and retained costs

Seven final `selected`/repeat pairs are pixel-identical, as are the seven current
baseline pairs. No added black or code-255 channel pixels appear. The final
14-step images differ from the earlier 10-step images by at most one code;
the final-version repeats are tested directly rather than inferred from that.

The following are final joint-output measurements on the fixed source-selected
regions. L/C and color separations use Oklab ×100. Hue is source-relative and
not a universal fidelity objective; judgments also use the retained lighting,
material context and paired visual review.

| Selection | Baseline | Selected | Interpretation |
|---|---:|---:|---|
| GZW-profile vivid blue sky hue shift | 3.3168° | 0.1116° | Less incidental hue rotation; this is an Arc screenshot under the GZW profile |
| Arc daylight sky hue shift | 3.2743° | 0.7371° | Better sky palette preservation |
| GZW daylight cloud hue shift | 2.3567° | 0.8589° | Less cloud color shift |
| Arc warm-floor color separation | 5.0569 | 5.2429 | About 3.7% more variation |
| Arc red-lamp color separation | 2.8438 | 3.2257 | About 13.4% more variation |
| GZW shelf visible L / color gaps | 4.3885 / 0.5243 | 4.3885 / 0.5243 | All 92,000 source-selected shelf pixels are unchanged |
| Arc white-core visible L gap | 5.3337 | 5.3339 | Prior small-light improvement retained |
| GZW blue-wall color separation | 1.3622 | 1.2554 | About 7.8% loss retained |
| Arc cool-window color separation | 2.5942 | 2.4305 | About 6.3% loss retained |

Warm-floor hue shift grows 2.9226°→3.6171°; red-lamp shift grows
-0.0475°→0.9564°, with greater red-lamp chroma. Arc cloud L separation falls
5.5667→5.5481; the white-core median L falls about 0.10 while its visible gap
remains. Smaller paving, foliage, wall, road and vehicle color-separation costs
are recorded in `metrics.json`. These are retained tradeoffs after the passing
temporal and active-config checks; no all-material improvement is claimed.

For 30,787 existing source-smooth blue horizontal pairs, p99 pair ΔE changes
0.743223→0.742318. Mean local pair growth is +0.004156 ΔE, with maximum growth
0.444905 and maximum reduction -0.438791. This retains a small quantization cost;
it is not a new debanding task or evidence of dense-motion continuity.

Focused final ablations retain a useful contribution rather than simply
disabling the effects. With inverse bypassed, the vivid sky's median C is
9.5056; the selected chain gives 9.9760 against source C=10.2326, with hue shift
only 0.0801°→0.1116°. Red-lamp median C is 19.1922 with inverse bypassed and
19.6264 selected. White-core pixels are unchanged by that inverse bypass.
These are evidence of restrained engagement in selected contexts, not proof of
the source's original tonemapper or a universal demand for reconstruction.

The `selected_print_off` diagnostic sets `LOOK_STRENGTH=0`, bypassing the whole
look including couplers, not just the print helper. It raises sky median L
62.6732→66.2717 and C 9.9760→10.9009, while reducing its visible L gap
9.8596→9.3872. It raises white-core median L 94.9669→96.7239 and gap
5.3339→5.8610. Print still deliberately spends some highlight brightness and
separation for density; the selected change preserves more of the palette
without pretending that density is free. Same-update motion attribution isolates
the changed print helper separately from that whole-look bypass.

## Measured motion

Four new complete-pipeline history replays cover both profiles and unchanged
repeats. Four earlier baseline replays are reused only after checking their
isolated inverse/grade/profile code and immutable source identities against the
current starting point. The new diagnostics include an inverse-only final view
using the old print helper on the new inverse-fed history, the selected view,
and an independent extraction of the actual pipeline output.

All 384 full/actual controls (192 new, 192 reused) are exact on the common
12,984-sample support. Source pose/token and measured source-update/cut-update
ages match across comparisons. Each replay covers 24 night, 20 return and four
daylight observations. There are no new black or code-255 channel samples.

| Profile/window | Baseline maximum duplicate-step ΔE | Selected | Repeat baseline / selected |
|---|---:|---:|---:|
| GZW night | 0.112700 | 0.113753 | 0.112726 / 0.113747 |
| GZW return | 0.742670 | 0.737333 | 0.742187 / 0.738999 |
| GZW daylight | 0.146963 | 0.135262 | 0.146755 / 0.136996 |
| Arc night | 0.122413 | 0.118027 | 0.122840 / 0.118148 |
| Arc return | 0.758458 | 0.763436 | 0.758862 / 0.762789 |
| Arc daylight | 0.151094 | 0.142511 | 0.149459 / 0.142362 |

Small night/return costs remain; this does not establish a general temporal
improvement. Selected phase-matched repeats reach two codes and maximum mean
ΔE 0.002805 (GZW) / 0.007512 (Arc). They are not pixel-identical temporal repeats.
The seven held pairs are exact. Source/update alignment does not make elapsed
GPU timing identical between independent processes.

The synthetic daylight tiles change more than the held gameplay images:
maximum mean selected/baseline ΔE is 1.6863, predominantly from print retaining
more yellow/green/cyan color instead of the old desaturation. The same-update
print intervention reaches mean ΔE 1.6857 there; inverse-only differences stay
below mean ΔE 0.01098 across all windows. These are appearance differences, not
new timing jumps or fidelity scores. Paired tile review retains the stronger
synthetic colors as a visible tradeoff of the ratio-preserving print path.

## Adoption, validation and effectiveness judgment

Only the bodies of `ApplyPrintStock()` and `InverseGradePS()` change in this
follow-up. Both actual active-config full/repeat pairs match the selected isolated
candidate pixel-for-pixel: all four comparisons have maximum code difference 0
and mean ΔE 0. Profiles, both active configs, shader headers, existing prior
working changes, histories/rates/resources and eight grade passes remain.
There is no new tuning surface, exposure behavior, output format or effect.

Both selected zero-strength pairs (`LOOK_STRENGTH=0` and `INVERSE_STRENGTH=0`
together) match their unmodified-code controls exactly. The print numeric probe
also checks strength-zero identity directly against its GPU control. All 22
diagnostic tooling tests and whitespace checks pass.

The follow-up completes 46 fresh ordinary captures, six numeric readbacks,
four new measured history replays and four actual-config outputs: 60 completed
private GPU processes, all with zero dropped/delayed frames. Six existing static
baseline pairs and four earlier history replays are verified and reused rather
than rerun. The initial print numeric oracle failure and rejected 10-step scalar
ordering result remain explicit. The motion wrapper assertion was corrected
before its first GPU launch. No failed screen is silently counted as a successful
contract, and no unrelated precision/history repair is added.

The final artifact audit verifies 352 unique isolated files and 1,074 images,
including retained early numeric evidence and all four actual outputs. One
post-adoption audit attempt reported a clip-digest assertion without recording
the path/value. Independent rehashing of every recorded clip and two complete
subsequent audits pass against the original hashes. No source or expected hash
was changed; the transient assertion's cause remains unestablished and is saved
in `post_adoption_audit_retry.json`. It does not trigger another shader repair.

**Print/look: 70→75, borderline.** Paired visual review and source-selected
measurements now support useful density with less incidental palette movement,
retained deep-shadow behavior and preserved light shape. The earlier print
shoulder alone did not resolve that palette cooperation problem. The retained
cool-material, warm-hue, synthetic-primary and quantization costs limit the score;
this is not a claim that every material improves.

**Inverse chroma: 70→75, borderline.** The prior hue-only budget left a concrete
source-preservation weakness: attempted expansion could enter gamut projection
and change hue or reduce incoming chroma. The pixel-specific budget addresses
that failure while retaining useful modest engagement in the final bypasses.
Together with existing neutral/rich-color/illumination guards and the measured
transition behavior, this supports a restrained contribution on the assessed set.
It does not identify the source tonemapper, establish missing chroma or infer
artistic intent. Those uncertainties remain; the score is not a reconstruction
accuracy percentage or a reward for passing numerical tests.

Both estimates have roughly 5–10 point uncertainty. They supersede the earlier
70 entries only for these focused blocks. Chain/grade are not freshly re-scored;
their prior borderline 75 estimates remain carried forward. No new mandatory
repair or parameter search is queued. Broader games, dense motion, timing and
resolution coverage would support stronger claims, rather than automatically
adding another improvement task. GPU performance remains unprofiled; the inverse
adds a fixed 14-step arithmetic search. No commit or push is made.

- [Interactive final comparison](../captures/color_preservation_20261031/review.html).
- [Vivid sky comparison](../captures/color_preservation_20261031/gzw_vivid_blue_sky_final.png).
- [Arc sky comparison](../captures/color_preservation_20261031/arc_day_sky_final.png).
- [Shadow shelf comparison](../captures/color_preservation_20261031/gzw_dark_shelf_final.png).
- [Current 75-target report](2026-10-31_75_goal_report.md).

Local artifacts: `captures/color_preservation_20261031/`. All runtime captures
are fresh private/headless processes. Static captures use five seconds of compile
wait and twenty seconds of continuous settling; elapsed warmup is not proof of
universal convergence. Ordinary screenshots contain no offscreen telemetry.
The explicit motion readback uses measured source/cut update ages and the common
atlas mask. The cached source remains 15 unique poses/sec doubled to 30 fps;
it cannot establish dense native motion, high refresh, other games or resolutions.
