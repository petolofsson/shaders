# R35 — Automate SHADOW_LIFT
**Date:** 2026-04-30
**Type:** Proposal
**ROI:** Medium — removes one knob, correct behaviour in dark vs bright scenes without tuning

---

## Problem

`SHADOW_LIFT = 15` is hardcoded in `creative_values.fx`. It applies a fixed toe lift:

```hlsl
float lift_w  = new_luma * smoothstep(0.4, 0.0, new_luma);
new_luma      = saturate(new_luma + (SHADOW_LIFT / 100.0) * 0.75 * lift_w);
```

A fixed value is wrong at both extremes:
- **Dark scene** (night, indoor, tunnels) — p25 is low, scene has genuine shadow content.
  Lift should be aggressive (pull up shadow detail that the camera compressed).
- **Bright scene** (outdoors, noon, overexposed) — p25 is already high, shadows are not
  crushed. A strong lift here creates a washed, milky look.

The current 15 is a compromise that under-lifts dark scenes and over-lifts bright ones.

---

## Signal

`PercTex.r = p25` — the 25th percentile of scene luminance (Kalman-smoothed after R34).
This is exactly the right driver: it measures how much shadow content the scene has.

---

## Formula (from R24 research)

```hlsl
float shadow_lift = lerp(20.0, 5.0, smoothstep(0.04, 0.28, perc.r));
```

| Scene | p25 | shadow_lift |
|-------|-----|-------------|
| Dark interior / night | ~0.02–0.05 | 18–20 (aggressive lift) |
| Typical outdoor | ~0.10–0.18 | 10–14 (moderate) |
| Bright overcast / noon | ~0.25–0.35 | 5–6 (minimal) |

---

## Implementation

`grade.fx` — replace the `SHADOW_LIFT` knob read with the derived formula.
`perc` is already read at this point (`float4 perc = tex2D(PercSamp, ...)`).

```hlsl
float shadow_lift = lerp(20.0, 5.0, smoothstep(0.04, 0.28, perc.r));
float lift_w      = new_luma * smoothstep(0.4, 0.0, new_luma);
new_luma          = saturate(new_luma + (shadow_lift / 100.0) * 0.75 * lift_w);
```

Remove `#define SHADOW_LIFT` from `creative_values.fx` (arc_raiders + gzw).

---

## Risk

**Interaction with EXPOSURE:** HANDOFF notes that lowering EXPOSURE already lifts
shadows via gamma. If EXPOSURE is raised above 1.0, p25 rises, shadow_lift reduces —
complementary behaviour. If EXPOSURE is lowered, p25 drops, shadow_lift increases —
also complementary. The automation reinforces rather than fights EXPOSURE.

---

## Success criteria

- `SHADOW_LIFT` removed from `creative_values.fx`
- Formula drives lift from p25 (already Kalman-smoothed)
- Dark scenes: visibly more shadow detail than current fixed 15
- Bright scenes: cleaner toe, no milky wash
- Knob count: 23 → 22
