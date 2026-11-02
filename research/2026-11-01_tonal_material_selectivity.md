# Tonal material selectivity — 2026-11-01

**Current attribution is complete; four lift-classification candidates are
rejected. Production shaders and profiles are unchanged.** The user selected
shadow/midtone material separation as the next improvement area.

The useful distinction is between the configured near-black pedestal and
automatic midtone compression. The Arc black setting accounts for much of the
selected dark-metal separation loss. Retinex and lift also reduce selected
midtone relationships, with lift contributing measurable neighboring-shade
compression in a fresh bedroom/menu case. The candidates below do not improve
that behavior sufficiently to adopt.

## Current inputs and measurements

The baseline is the adopted weak-color checkpoint, with current distinct
profiles and GZW inverse luma 0.60 / tint -0.015 preserved. Seven available
baseline/repeat pairs are reused after checking current verification hashes,
source, profile, normalized grade, isolated files and clip identity. They are
all exact. Arc `autof_20260515_210009.png` supplies a fresh bedroom/menu case;
its full/repeat is also exact. This adds a lighting/material view within the
existing two games, not another game or dense gameplay evidence.

The candidate cases are Arc interior, Arc bedroom and GZW daylight. Arc interior
adds inverse-luma, Retinex, zone, lift, endpoint and black-only bypasses. Bedroom
adds endpoint, Retinex and lift bypasses. Diagnostic settings exist only in
isolated creative-profile copies. No bypass is adopted.

Whole-region visible gaps use the existing fixed source-L quartile groups and
Oklab L ×100. Relative gaps use the same groups' mean log2 linear Y difference.
The new bedroom rectangles are fixed in native pixels in the local analysis
script. They include lighting changes and some object boundaries; the plaster
rectangle includes part of the rack. They are not pure-reflectance ground truth
or a flat-face halo fixture.

A supplementary native neighboring-shade measurement uses horizontal offsets
of 1, 4 and 16 pixels. Pairs are selected solely from source pixels: L between
12 and 65, absolute log-Y difference between 0.02 and 0.5 stops, and Oklab ab
distance below 2. Existing material masks also apply. The reported local ratio
is the median signed output log-Y difference divided by its source difference.
The tables below use offset four. This is sampled response within fixed
selections, not an analytic transfer derivative, fidelity score or requirement
to reproduce source contrast exactly. Quantized source/output codes limit small
differences; changed source grouping is never used to favor a candidate.

## Attribution: darkest material and automatic midtones

| Arc dark-metal variant | Visible L gap | Relative gap, stops |
|---|---:|---:|
| Source | 11.3974 | 2.6367 |
| Current full | 7.7517 | 1.5257 |
| Inverse luma off | 7.7748 | 1.5268 |
| Retinex off | 7.5873 | 1.5317 |
| Zone off | 7.7437 | 1.5192 |
| Lift off | 7.6089 | 1.5586 |
| Black offset alone set to zero | 11.1324 | 2.8374 |

The black-only diagnostic preserves `WHITES=0.995`, isolating the intervention
from the additional white change in the endpoint diagnostic. Arc's production
`BLACKS=0.005` remains. Bypassing it nearly restores the visible gap but expands
relative separation beyond source. This is a substantial configured tradeoff,
not a demonstrated automatic-state defect or authorization to retune the
profile. Bypass results include downstream responses and are not additive
per-stage budgets.

| Material/measurement | Current full | Retinex off | Lift off |
|---|---:|---:|---:|
| Interior warm-floor relative gap, stops | 2.4962 | 2.5539 | 2.6573 |
| Interior warm-floor neighboring ratio | 0.9375 | 0.9748 | 1.0033 |
| Interior cool-upper relative gap, stops | 2.1305 | 2.3383 | 2.2034 |
| Bedroom cloth neighboring ratio | 0.8497 | 0.8551 | 0.9124 |
| Bedroom plaster/rack neighboring ratio | 0.8673 | 0.8713 | 0.9177 |
| Bedroom floor neighboring ratio | 0.8711 | 0.8670 | 0.9994 |

The interior warm-floor local measurement contains 7,745 selected four-pixel
pairs. Source whole-region relative gaps are 2.5312 stops for that floor and
2.4958 for the cool upper region. Lift bypass can exceed source relative
contrast, while Retinex bypass can change overall brightness and illumination
balance. These counterfactuals identify a real opportunity for selective local
response preservation, without establishing that disabling either stage is a
better complete image. Zone bypass reduces interior selected separation.

The fresh bedroom confirms why visible and relative gaps must be assessed
together: lift bypass raises plaster/rack relative separation 1.8126→1.8802
stops while reducing its visible L gap 16.2184→15.7481. A smaller absolute gap
alone does not demonstrate lost texture.

## Two new candidate families

Both families change only the pixel luminance used by the existing lift fade
`smoothstep(0.35,0,Y)`. Native luminance still scales the added lift. Its manual
strength, detail protection, current-source complete product, histories,
time constants, resources, stage order and eight grade passes remain.

**Guided-base classification, full and half.** Evaluate the existing source-domain
guided fit `fit=a*native_log+b`, condition its residual by `(1-a)`, and map its
base/native ratio onto the current pre-lift luminance. Full uses that base for
the fade; half blends halfway from the existing pixel classification. This
changes the classification signal rather than fading strength at coarse edges.
It tests whether nearby shades can share a lift gain while retaining the
existing native-guide conditioning. No new filter or analysis surface is added.

These variants produce negligible useful material changes. The full interior
warm-floor visible gap changes 32.3939→32.3940, with its local ratio unchanged.
Bedroom floor changes 17.4681→17.4690 while its neighboring ratio slightly falls.
Whole-image sampled mean changes remain below 0.00022 ΔE, with at most one-code
changes. They are rejected without claiming those tiny differences are free of
render variation or compilation roundoff.

**Original-source classification, full and half.** The hypothesis is that
preceding darkening may cause original midtones to receive unnecessary lift.
The classifier uses the original native source Y, mapped through the existing
black/white and deliberate exposure settings. Full uses that signal; half
blends halfway with the existing pre-lift luminance. This is not the previously
rejected global scene-key eligibility taper or a combined log-gain limit.

| Measurement | Current | Source classifier | Half |
|---|---:|---:|---:|
| Interior warm-floor visible L gap | 32.3939 | 32.4448 | 32.4182 |
| Interior warm-floor neighboring ratio | 0.9375 | 0.9233 | 0.9304 |
| Interior cool-upper visible L gap | 19.7903 | 19.5624 | 19.6767 |
| Bedroom cloth visible L gap | 37.3847 | 37.0505 | 37.2129 |
| Bedroom plaster/rack neighboring ratio | 0.8673 | 0.8498 | 0.8583 |
| Bedroom floor neighboring ratio | 0.8711 | 0.8474 | 0.8578 |
| GZW lit-paving visible L gap | 17.2628 | 17.1631 | 17.2064 |

The full source classifier widens the interior floor's whole-region visible gap
about 0.16% but makes its local neighboring response worse. It also loses about
1.15% cool-upper visible separation and about 0.89% bedroom-cloth separation.
The half version reduces the changes without establishing a useful target gain.
GZW cloud separation expands further from its already expanded baseline. Native
review shows subtle changes rather than clearer materials. Both are rejected.

The maximum source-classifier changes are five codes in the interior, eleven
in the bedroom and two in GZW daylight. Half reaches three/six/one codes.
Neither family adds black or code-255 channel pixels in these three cases.
These endpoint checks are not universal gamut or numerical GPU contracts.

## Decision, validation and limits

All four candidates are rejected. The attribution narrows useful automatic
improvement work to local midtone response, with the configured Arc near-black
offset kept explicit. A future candidate would need to retain neighboring-shade
response and useful illumination balance jointly. This screen supplies no
justification for another sweep of these classifiers, a global strength change,
a new effect, profile retuning or an effectiveness score increase.

Twenty-three fresh private headless GPU processes cover twelve candidate
captures, nine bypasses and the new full/repeat pair. Every process has zero
dropped/delayed frames. All use five seconds compile wait and twenty seconds
continuous static settling, which does not prove universal convergence.
Marker pixels are checked and excluded from image metrics.

The final audit verifies 148 isolated files, 37 images, eight exact baseline pairs
and all sixty source-exact RGB frames of the new lossless bedroom clip. The
fourteen reused baseline/repeat images retain verified current identities.
Production shader/profile/trial-config hashes and both actual active-config
hashes are unchanged. All 22 diagnostic tooling tests and whitespace checks pass.

Ordinary screenshots contain no hidden history telemetry. No numeric GPU,
candidate-repeat, boundary-chart, motion/cut or actual-config adoption validation
is claimed for these rejected candidates. Existing production validation and
baseline hashes remain at `captures/weak_color_20261031/verification.json`.
No chain/per-effect re-score, commit or push is made.

Local ignored artifacts: `captures/tonal_materials_20261101/report.json`,
`metrics.json`, `audit.json`, isolated profiles/shaders/configs, media and logs.

- [Dark-metal stage attribution](../captures/tonal_materials_20261101/arc_interior_dark_metal.png).
- [Warm-floor candidates](../captures/tonal_materials_20261101/arc_interior_warm_floor_candidates.png).
- [Bedroom plaster/rack candidates](../captures/tonal_materials_20261101/arc_bedroom_plaster_candidates.png).
- [Bedroom floor candidates](../captures/tonal_materials_20261101/arc_bedroom_floor_candidates.png).
