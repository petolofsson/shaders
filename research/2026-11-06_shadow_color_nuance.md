# Shadow color and brightness nuance

## Question and finding

The requested goal is rich, nuanced dark gradients: neighboring shadows can retain distinct warm and cool colors as well as brightness, rather than receiving one uniform shadow tint. Earlier work largely measured brightness and did not answer that question. This screen examines existing full-chain and isolated black-offset-bypass stills for changes in their dark color relationships.

The selected dark shelf and metal show less color separation in the current output than in their source-only captures, even when groups are compared within narrow source-brightness bands. The BLACKS=0 counterfactual retains more of that separation, while also darkening these materials. This supports a concrete shadow-color preservation lead, but does not establish the perceptually correct color, assign the entire loss to a single stage, or show that larger color distances are necessarily better. No shader, profile or configuration was changed.

## Inputs and method

Reuse the two separately captured source-only stills, current full-chain stills and isolated BLACKS=0 full-chain stills documented in the [multiscale screen](2026-11-05_shadow_multiscale_measurement.md). Image SHA-256 values and results are recorded in `captures/shadow_color_nuance_20261106/report.json`. These are separate 8-bit screenshots of a 10-bit playback path, not direct same-update shader-input readbacks. Existing source-capture production/profile/config hashes match the current workspace. Static repeats and settling are not motion validation.

Within the existing selected regions, select source Oklab L 12–35 on the ×100 scale. Split pixels into source-b quartiles and measure the distance between mean output a/b vectors of the lower and upper groups. Then repeat the grouping separately within two-L-unit source-brightness bands to reduce brightness/color confounding. These are source-selected comparisons with overlapping, spatially correlated pixels; b quartiles are not material labels and the vectors can contain both a and b differences. Gamut, grade look, dither, quantization and remaining within-band L variation can affect the result. Source appearance is a reference, not an assertion of the desired final palette. One-code sensitivity is especially important in shadows.

| Selection, source L band | Samples | Source color-group distance | Current | BLACKS=0 |
| --- | ---: | ---: | ---: | ---: |
| GZW shelf, 12–14 | 34,011 | 0.456 | 0.250 | 0.404 |
| GZW shelf, 14–16 | 31,382 | 0.487 | 0.310 | 0.436 |
| Arc dark metal, 12–14 | 17,336 | 0.554 | 0.327 | 0.557 |
| Arc dark metal, 16–18 | 13,933 | 1.359 | 1.009 | 1.336 |
| Arc cool window, 18–20 | 884 | 0.739 | 0.566 | 0.662 |

These distances use Oklab ×100 and are descriptive, not visibility or preference scores. They do not prove that all dark colors are lost, that warm red-black material is covered, or that bypassing BLACKS is a safe improvement. At a wider 12–35 source-L selection the shelf median output L is 16.073 current versus 12.589 black-off; metal is 17.559 versus 14.926. The cost in darkness is therefore material.

## Mechanism and exploratory visual reference

The early grade mapping is `RGB * (WHITES - BLACKS) + BLACKS`: the same positive linear-RGB offset is added to each channel. For fixed input, the offset leaves absolute channel differences proportional to the multiplier but increases luminance, reducing channel difference relative to luminance, particularly near black. It plausibly contributes to weaker dark color relationships as well as weaker relative brightness gradients. The BLACKS=0 comparison includes all downstream, adaptive and quantization interactions and does not isolate this algebra from their contribution. Input to the mapping has already passed inverse processing, so source-screenshot values are not direct inputs to this equation.

An intentionally non-runtime reference copies the black-off image's linear RGB ratios into the current image at the current pixel's linear luminance, blended through a source-shadow gate and an off-image near-black guard. In exact arithmetic, before RGB clipping and 8-bit quantization, both blended endpoints have the same current luminance. No pre-encoding channel clipping occurred in the four tested crops, but quantization changes measured L and no endpoint or gamut guarantee follows. This requires two full-chain renders and can copy noise, tint changes and quantization; it is not a candidate implementation. It addresses only color in this test, not the separate brightness-gradient requirement.

For the source-selected L 12–35 groups, shelf a/b distance changes 0.327 current → 0.437 color reference (black-off 0.445); dark metal 1.575 → 1.851 (black-off 1.909). Median L changes 16.073 → 16.035 and 17.559 → 17.634 respectively after encoding. The color-reference group is measured over the whole 12–35 range; these numbers are not the narrower-band measurements above. Native three-way crop comparisons and exact input hashes are in `captures/shadow_color_nuance_20261106/`. On the shelf the difference is subtle at native size; no subjective gameplay preference is established. No held scenes beyond these two sources, flat-neutral charts, true black, noise tests, GPU contracts or motion controls were performed.

The evidence suggests investigating a **luminance-preserving, dark-color-selective treatment** of the early offset, coupled with separate brightness-gradient evaluation. Any real candidate must use the actual grade input, preserve neutrals and existing black behavior, and be screened against quantization and colored boundaries. The two-render reference does not itself meet those conditions. A strength sweep or production adoption is not justified by this first screen.
