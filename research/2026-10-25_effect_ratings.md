# Provisional effect ratings — 2026-10-25

Updated after the retained-capture baseline, native Retinex reconstruction,
conservative zone-confidence correction and inverse-luma gain-units fix.
Supersedes the assessment section of [the earlier stage audit](2026-10-24_stage_verification.md#provisional-effect-assessment).

These are approximate engineering judgments on a 0–100 scale, not measured
fidelity percentages. Differences of five points are directional estimates;
they do not establish statistically significant quality changes.

- **Technical working:** confidence that the implementation performs its stated
  role correctly, based on code, GPU diagnostics and runtime checks.
- **Effectiveness:** estimated contribution to [the visual goal](../GOAL.md),
  including restraint and tradeoffs. This is the relevant column for the 75+
  target, but the estimates are not accepted cross-game quality results.
- **Importance:** expected relevance to that goal, not implementation quality.

## Current assessment

| Effect or block | Technical working | Effectiveness | Importance | Basis or remaining gap |
|---|---:|---:|---:|---|
| Complete combined chain | 90 | **75** | 100 | Fewer false rims and less unintended density; palette/print tradeoffs, legacy profiles and broader acceptance remain open |
| Analysis frame | 90 | 80 | 95 | Histogram normalization, endpoints/cuts and explicit readback evidence; broader scene coverage still needed |
| Inverse grade | 80 | 65 | 60 | Bounded chroma reconstruction/protection; source tone-mapping assumptions and usefulness across games remain uncertain |
| Corrective analysis | 90 | 80 | 85 | Near-black zone precision and direct zone/slow-key history attribution; additional transitions remain open |
| Grade overall | 90 | 75 | 100 | Corrected reconstruction and spatial behavior; artistic calibration and full-chain preference still provisional |
| Explicit sRGB output | 95 | 90 | 95 | Explicit UNORM decode/encode and runtime endpoint checks; wider display validation remains |
| Gamut projection | 85 | 80 | 90 | Two-sided bounds and internal range retention; detailed hue/gamut continuity still needs broader review |
| Zone contrast | 85 | 75 | 85 | Conservative uniform budget removes false rims and avoids the stronger candidate's shadow cost; coarse-field gradients remain |
| Shadow lift | 85 | 75 | 80 | Useful dark-material visibility with black-floor guard; preference and other slow-key transitions remain open |
| Print stock/look | 85 | 65 | 80 | Clearly active and bounded; palette shifts, density and sky-contrast interactions need calibration/review |
| Inverse luma | 95 | 80 | 75 | GPU-confirmed gain-units fix, six-scene and active-chain checks; partial ACES model and blue-sky tradeoff remain |
| FilmCurve | 85 | 75 | 75 | Real compact-lamp and cloud engagement with bounded shoulder; broad highlight calibration remains |
| Saturation/chroma | 85 | 70 | 75 | Corrected reconstruction and bounds; color distinctions, restrained palettes and profile-dependent shifts remain |
| Adaptive history/cuts | 85 | 70 | 75 | Direct slow-key attribution and exact sparse motion matches; dense continuity and additional cut recovery remain unverified |
| Three-way CC | 90 | 65 | 70 | Executes predictably; current cool settings remove subtle shelf warmth and contribute palette changes requiring preference review |
| Retinex | 90 | 80 | 85 | Native guide reconstruction and removal of coarse-edge strength fading reduce demonstrated held/moving rims; broader illumination edges remain |
| Black/white mapping | 90 | 80 | 45 | Predictable deliberate endpoint controls; neutral values may correctly contribute nothing |
| Dither | 80 | 70 | 40 | Code-domain, endpoint-safe spatial output; noise floor and display-gradient benefit remain unmeasured |

The complete-chain effectiveness estimate is assessed separately, not averaged
from the individual scores. A provisional 75 is a borderline current judgment
with material uncertainty, not a declaration that the acceptance target is met.
Runtime activity or a larger delta-E does not earn an effectiveness score alone.

The older table rated technical/visual confidence together under “Working” and
had no separate effectiveness column. Do not present its Working values as
earlier effectiveness scores. The largest justified confidence gains concern
Retinex/zone spatial behavior, inverse-luma units, and diagnostic attribution.
Print, CC and general reconstruction assumptions remain the main quality gaps.

## Scope and novelty

These scores apply to the **combined trial** and retained GZW/Arc/Babylon inputs.
The active four-effect configs still lack shared analysis resources; dependent
stages cannot inherit the combined-trial ratings. The pointwise inverse-luma
correction is separately validated on both active configs.

Novelty has not been re-scored: these changes are correctness and calibration
work using established methods, without a new prior-art assessment. Remaining
improvement potential is substantial in automatic palette/print restraint,
cross-game calibration and dense temporal validation; it is not an achievement
score and has no required minimum.

Neutral or untested optional controls do not receive a new standalone quality
rating: deliberate exposure, hue rotation, optional vibrance/hue-selective
contrast and printer lights need evidence in their intended role.

Evidence and review starting point: [review pack](2026-10-25_review_pack.md),
[stage attribution](2026-10-25_stage_review.md),
[zone confidence](2026-10-25_zone_confidence.md),
[inverse-luma units](2026-10-25_inverse_luma_units.md), and
[Retinex correction](2026-10-25_flat_face_attribution.md).
