# Research 04 — FilmCurve and zone contrast interaction — Findings

## Tonal space map

| Operation | Space | Source |
|-----------|-------|--------|
| FilmCurve anchors (p25/p50/p75) | Pre-FilmCurve | PercTex — computed by analysis_frame.fx from raw BackBuffer |
| Zone medians (ZoneHistoryTex) | Pre-FilmCurve | corrective.fx Pass 1–3 read raw BackBuffer before grade.fx runs |
| FilmCurve execution | Transforms raw → post-FC | grade.fx Stage 1 |
| Zone S-curve input (`luma`) | Post-FilmCurve | Computed from `lin` after FilmCurve applied |
| Zone S-curve pivot (`zone_median`) | Pre-FilmCurve | Read from ZoneHistoryTex |
| Clarity `detail = luma - low_luma` | Mixed | `luma` post-FC, `low_luma` from CreativeLowFreqTex (pre-FC) |

The mismatch is structural: `zone_median` is a pre-FilmCurve value used as a pivot for a post-FilmCurve operation.

## Where FilmCurve actually moves values

The FilmCurve function:
```hlsl
float3 above = max(x - knee,      0.0);  // knee = 0.80–0.90
float3 below = max(knee_toe - x,  0.0);  // knee_toe = 0.15–0.25
return x - factor * above * above
           + (0.03 / (knee_toe * knee_toe)) * below * below;
```

Both `above` and `below` are zero for the midtone band (~0.25–0.80). The FilmCurve is a **pass-through for midtones** — it only acts on:
- Highlights above knee (0.80–0.90): compressed downward by 0–5%
- Deep shadows below knee_toe (0.15–0.25): lifted upward by ~0.5–1%

## Interaction analysis by tonal region

**Midtones (zone median 0.25–0.80) — Neutral**

FilmCurve moves nothing here. Post-FilmCurve `luma` ≈ pre-FilmCurve `luma`. The zone median pivot is in the correct tonal space — mismatch is zero. Zone S-curve operates exactly as designed.

**Deep shadows (zone median < 0.20) — Mild additive, same direction**

FilmCurve lifts shadows: post-FC luma > pre-FC luma for these pixels. The zone median pivot is at the pre-FC value, which is now slightly below the actual zone center. `dt = luma - zone_median` is slightly positive even for pixels sitting at the true zone center. The S-curve interprets these as sitting above its pivot and applies marginal upward pressure on top of FC's lift. Both operations push in the same direction (up). Numerically small — FilmCurve shadow lift is ~0.005–0.010 in linear — and is unlikely to cause visible problems at typical ZONE_STRENGTH settings.

**Highlights (zone median > 0.80) — Mild additive, same direction**

FilmCurve compresses highlights: post-FC luma < pre-FC luma. The zone median pivot is above the actual post-FC zone center. `dt = luma - zone_median` is slightly negative for pixels sitting at the true zone center — the S-curve treats the whole zone as sitting below its pivot and applies the compressive side of contrast. This stacks with FilmCurve's downward compression; both push in the same direction. The offset scales with FilmCurve displacement (0–5%), which is largest for scenes with very high p75 (>0.80), where the knee is moved leftward to 0.80, making FC more aggressive. At high ZONE_STRENGTH with a very bright scene, this additive effect is the most likely to be perceptible.

**No region where the operations oppose each other.** FilmCurve and the zone S-curve never push in opposite directions. The geometry is consistent: wherever FC moves a value, the resulting pivot offset biases the S-curve in the same direction.

## Clarity interaction

`detail = luma - low_luma` uses a mixed-space subtraction: `luma` is post-FilmCurve, `low_luma` is from `CreativeLowFreqTex.a` which was computed from the raw BackBuffer in corrective.fx Pass 1. In midtones the bias is zero. In highlights, post-FC `luma` is slightly lower, so the detail signal (and thus Clarity boost) is slightly suppressed in bright areas. In shadows, it is slightly inflated. These are second-order effects relative to the zone median mismatch and are unlikely to produce visible artifacts.

## Verdict

**The interaction is benign for the typical scene.** The core reason: FilmCurve is a pass-through for the midtone range where virtually all zone medians fall in a well-exposed game scene. The mismatch only activates meaningfully in highlights and deep shadows, where the numerical offset is small (0–5%) and both operations happen to push in the same direction — so there is stacking but not conflict.

The interaction becomes a real concern only under two simultaneous conditions: (1) ZONE_STRENGTH is set high, and (2) the scene contains many bright zones (zone medians above 0.80). In that combination, the pivot offset from FilmCurve's highlight compression causes the zone S-curve to further darken highlight zones beyond its design intent — cumulative over-compression of highlights.

## Architectural fix (if the stacking ever becomes a problem)

The cleanest fix would be to write the post-FilmCurve frame luma into an intermediate texture after Stage 1 of grade.fx, then rebuild the zone histogram pass in corrective.fx (or a new small pass in grade.fx) to read from that texture instead of the raw BackBuffer. Zone medians would then live in post-FilmCurve tonal space, and the S-curve pivot would be correctly calibrated. This requires either splitting grade.fx's single MegaPass or adding a feedback texture that carries the post-FC luma across frames with one frame of latency — structurally invasive enough to justify doing only if the highlight stacking proves problematic in practice.
