# Local chromatic-residual screen

The [shared-component color proxy](2026-11-06_shared_chroma_proxy.md) protects saturated faces but amplifies existing neutral-shadow casts. This screen tests a different mechanism: enhance local color variation around a luminance-weighted neighborhood color, which leaves a spatially uniform tint unchanged in ideal arithmetic. **Decision: reject this version.** Selected shelf and metal color gains are small, and the model creates chromatic edge rims and amplifies synthetic channel noise. It does not resolve the separate brightness curve's cool-material costs. No production code changed.

## Method

For linear output RGB `v` with luminance `y`, form a local reference color ratio `blur(v)/blur(y)` using a separable Gaussian with sigma 4 native pixels and radius 16. The chromatic residual is `v-y*blur(v)/blur(y)`, which has zero linear luminance in ideal arithmetic. A 0.5 exploratory gain, the existing source-input and output-shadow gates, a common-RGB fraction and a lower/upper channel-headroom factor bound the correction. The source-input and output images are independent 8-bit captures, and the calculation is on padded crops. The combined proxy then applies the prior ordered brightness model. This is an offline spatial filter, not a shader, and would require its own real-time architecture and performance assessment if it were worthwhile.

A constant spatial RGB ratio, including a colored tint, produces no residual in exact arithmetic. This is narrower than preserving arbitrary lighting or neutrality: the neighborhood can straddle different materials, and the residual can include texture, dither or noise. Its filter support and per-pixel gates may create boundaries. All 17 current shader/profile/config identities match the prior grade-input diagnostic record; image hashes and code are in `captures/shadow_color_local_residual_20261106/`.

## Selected stills

| Region | Source-selected color-group distance current / color-only / combined | Four-pixel signed log-Y gap current / combined | Source-relative reversal current / combined |
| --- | ---: | ---: | ---: |
| GZW shelf | 0.327 / 0.332 / 0.376 | 0.11596 / 0.13719 | 6.49% / 6.67% |
| Arc dark metal | 1.575 / 1.629 / 1.666 | 0.13701 / 0.14375 | 5.75% / 6.42% |
| GZW blue wall | 0.092 / 0.079 / 0.087 | 0.07589 / 0.07003 | 2.63% / 3.29% |
| Arc cool window | 1.970 / 2.455 / 2.486 | 0.14997 / 0.14666 | 1.98% / 2.18% |

The color groups are based on separate source-screenshot b quartiles in source L 12–35 and can differ in brightness; larger distance is not automatically better. The cool-window result may include edge response and does not establish better material identity. Pairs overlap, and dither and 8-bit quantization affect the counts. Native comparison crops do not establish a clear overall improvement. The ordered brightness part still raises selected metal median L and reduces wall/window neighboring response.

## Synthetic controls

A flat tinted RGB field is unchanged to double-precision roundoff. For a two-color step at constant linear Y=0.01, the model creates opposing red-channel corrections peaking at ±0.0004051 linear at the boundary, decaying on each side; up to 0.718 of an 8-bit sRGB code in continuous encoded values and 1,024 pixels change on rounding. This is a deliberately simple synthetic edge, not proof that an equivalent halo is visible in the game captures.

For a synthetic code-16 field with independent ±1-code red-channel variation, continuous encoded red standard deviation rises from 0.818 to 1.125 codes (about 37.5%). This fixture quantizes back to the original 8-bit pixels, and it is not measured game noise or a flicker test. The continuous amplification and edge behavior show why the uniform-tint identity alone is insufficient. Exact code, inputs, synthetic profile and results are retained alongside the stills.

No compiled GPU, black-handoff, real warm/red-black, scene-held, noise-floor, motion/cut, or active-config test was performed. No threshold/strength sweep follows this early rejection. Profiles, configurations, histories, passes and ratings remain unchanged.
