# Print/look tone preservation — 2026-10-30

**Adopted:** reduce the secondary print shoulder coefficient from 1.5 to 0.75.
The shadow-toe candidate is rejected. This finite decision is closed.

The finite print/look follow-up separates print tone from color, rejects a
shadow-toe change, and adopts a gentler secondary highlight shoulder after
validation. Its benefit is better small-light structure while retaining the
current dark-material treatment and ordinary print density. It does not solve
the broader shadow-richness goal or establish a 75+ print/look result.

## Attribution before candidates

The starting point is the current working-tree grade, including the adopted
guarded shadow reconstruction, rather than stable 1.0. Current profiles and
both active combined configs are preserved. Seven verified current-code
full/repeat/look-off sets from the [effect reassessment](2026-10-29_effect_ratings.md)
are reused after source, profile, helper and normalized grade checks.

Fourteen fresh ordinary captures separately bypass:

- **Print tone:** the per-channel power toe and secondary Reinhard shoulder;
  the desaturation and both color couplers remain.
- **Print color:** desaturation, masking and dye couplers; the original power
  toe and shoulder remain.

These are final-output interventions, including downstream interactions, rather
than additive stage budgets. Source-selected rectangles and masks are retained
from the reassessment. L and C below use Oklab's 0–100 reporting scale; visible
gaps compare fixed source-L quartiles.

| Selection | Current full | Tone off | Color off | Look off |
|---|---:|---:|---:|---:|
| GZW shelf visible L gap | 4.388 | 4.822 | 4.388 | 4.822 |
| Arc dark-metal visible L gap | 7.752 | 8.164 | 7.713 | 8.091 |
| Arc white-core visible L gap | 4.621 | 5.857 | 4.616 | 5.861 |
| Arc white-core median L | 94.065 | 96.724 | 94.065 | 96.724 |
| Arc red-lamp median C | 19.008 | 19.188 | 20.120 | 20.507 |

Tone accounts for the selected shelf/core costs, while color treatment usefully
restrains the lamp. Tone bypass also weakens density elsewhere: GZW lit-paving
gap falls 17.102→16.437 and Arc warm-floor gap falls 32.363→31.078. Removing the
whole print treatment would trade away useful behavior. The shelf's brighter
bypass also lowers relative contrast, 1.643→1.506 stops; brightness alone does
not establish an improvement.

## Closed two-candidate decision

The first candidate softens only the low-end power response using
`x^1.10 * (x + 0.05*exp(-x/0.05))^0.05`, asymptotically returning to the original
`x^1.15`, and reduces the secondary shoulder coefficient from 1.5 to 0.75.
It retains the original color treatment. This is a candidate in isolated code,
not an additional control.

The shadow part is **rejected**. Shelf median L rises 12.212→12.382, but its
visible gap barely changes, 4.388→4.395, while relative gap falls 1.643→1.604
stops. Blue-wall gap falls 10.418→10.320 and Arc dark-metal gap falls
7.752→7.673. Five completed ordinary captures include exact unchanged pairs
for the shelf and emitters and one interior observation. The interior repeat
was interrupted after rejection; it is excluded from completed evidence. The
remaining planned runs of that rejected candidate were stopped. No extension
of its toe-parameter screen is queued.

The second candidate retains the original toe and changes only the secondary
shoulder coefficient, **1.5→0.75**. For post-toe excess `d=max(ps-0.60,0)`, it
uses `0.60 + d/(1+0.75*d)` instead of `0.60 + d/(1+1.5*d)` above the knee.
The derivative stays positive and joins continuously at the knee. The transfer
is identical through pre-print linear channel value `0.60^(1/1.15) ≈ 0.6413`.
The luminance-preserving FilmCurve shoulder remains in its original earlier
position; this change only reduces the later print shoulder's repeated
compression. It does not reconstruct clipped source information.

| Selection | Current full | Highlight-only candidate | Interpretation |
|---|---:|---:|---|
| White-core visible gap | 4.621 | 5.334 | About 15.4% more visible separation |
| White-core median L | 94.065 | 95.068 | Brighter, still below look-off 96.724 |
| White-core relative gap | 0.214 stops | 0.246 stops | Improvement includes relative separation |
| White-halo visible gap | 20.386 | 20.386 | Selected halo is unchanged |
| Red-lamp visible gap | 18.153 | 18.376 | Small light-structure benefit |
| GZW shelf visible gap | 4.388 | 4.388 | Source-selected shelf pixels unchanged |
| Arc dark-metal visible gap | 7.752 | 7.752 | Source-selected dark metal unchanged |
| GZW lit-paving visible gap | 17.102 | 17.102 | Selected ordinary material unchanged |
| Arc cloud visible gap | 5.369 | 5.567 | Some high-end separation is retained |

All seven final candidate/repeat pairs are pixel-identical, as are the seven
verified starting pairs. No new black or code-255 channel pixels appear.
The shelf, blue wall and source-selected dark-metal pixels match current full
exactly. Bright details inside those source rectangles can change; the claim
uses the existing dark-material mask, not every pixel in the rectangle.

The change acts on individual channels, so a bright blue channel can engage
even when luminance is moderate. Vivid-sky median C rises 10.231→10.258 and
source-relative hue shift grows 3.351°→3.376°. Its median L rises 62.743→62.791.
Among 30,787 existing source-smooth blue horizontal pairs, p99 pair delta-E stays
0.754148. The maximum local pair-growth cost is 0.212637 delta-E; mean growth is
0.000091. These retained quantization/color costs are not a new repair queue.
Candidate/full differences reach six codes in bright parts of the held set;
that is a treatment delta, not an error relative to known ground truth.

## Validation and limits

All runtime work is private/headless, using fresh processes, five-second
compilation wait, twenty-second continuous static settling, protected source/
profile/config identities and the intentional activity marker. Ordinary image
metrics mask the marker. Source PNGs remain references; prior file/rendered-input
differences are not assumed away.

An independent explicit GPU readback probes the production print helper and
the isolated selected helper at 1,280 gray/primary/secondary inputs, each at
strengths 0, 0.7 and 1: **7,680 records**. A separately calculated CPU reference
matches within **0.000000174**. The repeated readback is identical. Gray ramps
are monotone, black remains exact, and zero strength preserves all inputs.
The probe uses bounded input because gamut projection precedes print; no new
signed/overrange handling or history storage is introduced.

Four measured cut replays cover both profiles and their repeats, with 48 explicit
source/token/source-update/cut-update keys per run: 24 night, 20 return and four
daylight observations. All **192 extracted full/actual controls are pixel-identical**
on the common 12,984-sample mask, excluding borders and both atlas-tag footprints.
No added black or code-255 channel samples appear. History producers, states and
rates are unchanged; candidate and full images use the same update's context.

| Profile/window | Full maximum duplicate-step ΔE | Candidate | Repeat full / candidate |
|---|---:|---:|---:|
| GZW night | 0.114909 | 0.114693 | 0.116029 / 0.115811 |
| GZW return | 0.744506 | 0.746947 | 0.747088 / 0.749510 |
| GZW daylight | 0.127509 | 0.146237 | 0.130920 / 0.150150 |
| Arc night | 0.127482 | 0.127407 | 0.127729 / 0.127714 |
| Arc return | 0.758453 | 0.759902 | 0.762980 / 0.764311 |
| Arc daylight | 0.134183 | 0.143348 | 0.136717 / 0.145845 |

The small daylight-step growth is a retained cost of the brighter high-end
response. Return-step growth is close to or below between-run variation and
does not establish a new timing defect. Phase-matched repeat differences reach
one code, with maximum mean ΔE 0.007881 for GZW and 0.006895 for Arc candidate
images. These temporal repeats are not pixel-identical; the held-image repeats
are. The maximum candidate/full mean change in these windows is about 0.358 ΔE.

After adoption, four fresh **actual active-config full/repeat captures**, two per
profile, match the isolated candidate pixel-for-pixel. All completed ordinary,
numeric, cut and actual-config processes have zero dropped/delayed frames. The
screen adds 33 ordinary captures, two numeric readbacks, four cut replays and
four actual-config captures; the intentionally interrupted rejected run is
excluded. The artifact audit verifies 240 unique isolated files, all frozen
images/media identities, exact controls, no added endpoints and protected
profiles/configs/other shaders. All 22 diagnostic tooling tests and whitespace
checks pass.

Only one numeric literal in `ApplyPrintStock()` changes in this follow-up.
Profiles/configs, shader header comments, previous working changes, manual
ceilings, histories/rates, resources and eight grade passes remain. No commit
or push is made.

Static warmup is a fixed protocol, not proof of universal history convergence.
The existing Babylon clip has 15 unique poses/sec duplicated at 30 fps; sparse
frozen samples cannot establish dense gameplay continuity, physical high refresh,
other games/resolutions or calibrated-display acceptance.

## Effectiveness judgment and scope

The focused print/look estimate remains **70/100** with roughly 5–10 point
uncertainty. The core improvement is useful, but the rejected toe candidate
does not improve dark-material appearance convincingly, and current palette/
density costs remain. No score is raised merely because a targeted candidate
passes its technical checks. Chain/grade are not re-scored.

This closes the two-candidate print decision on the measured scope. The next
requested work is three-way CC in isolated
profile copies, followed by inverse chroma selectivity. Production profiles
remain intact; these tasks do not authorize overwriting the user's settings.

Local evidence: `captures/print_look_20261030/` contains the attribution, rejected
candidate, selected held comparisons, independent numeric readback, source and
isolated-file hashes, metrics and review assets. Scripts/media remain ignored.

- [Interactive full/candidate/tone/color review](../captures/print_look_20261030/review.html).
- [Small-light core comparison](../captures/print_look_20261030/arc_emitters_white_core_decision.png).
- [Dark-material comparison](../captures/print_look_20261030/arc_interior_dark_metal_decision.png).
- [Bright-blue comparison](../captures/print_look_20261030/gzw_vivid_blue_sky_decision.png).
- [Print transfer and highlight slope](../captures/print_look_20261030/print_transfer.png).
