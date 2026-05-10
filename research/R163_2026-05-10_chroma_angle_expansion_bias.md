# R163 — Dominant-Hue Aware Chroma Expansion (CHROMA_ANGLE)

**Date:** 2026-05-10
**Scope:** inverse_grade.fx — `InverseGradePS` chroma expansion factor

---

## Problem

`HWY_CHROMA_ANGLE` (slot 201) was written by `analysis_frame` every frame and never
read by any processing stage — identified as a dead signal in a full highway slot
audit (2026-05-10).

The slot encodes the mean chroma direction of the scene: the ab-plane centroid of all
sufficiently coloured pixels, expressed as `(atan2(b,a) + π) / 2π`.

## Signal

CHROMA_ANGLE is the only highway signal that encodes **colour direction** rather than
magnitude or scalar statistics. It is distinct from:
- `HWY_MEAN_CHROMA` — magnitude of mean chroma, not direction
- `HWY_ACHROM_FRAC` — fraction of achromatic pixels, not hue direction
- `HWY_SLOPE` — tonemapper compression ratio, not colour bias

## Motivation

The inverse grade expansion (`new_C = mean_C + (C − mean_C) × factor`) treats all hue
directions equally relative to `mean_C`. But in a scene with a dominant colour (warm
sunset, cool nighttime), pixels **aligned with the dominant hue** are already
well-represented by the scene's own content. Pixels **complementary to the dominant
hue** are under-represented — they carry the visual richness that makes the scene
feel less monochromatic — and benefit more from expansion.

This mirrors how colour film dye layers behave: the dominant hue layer is more heavily
exposed and retains more dye; complementary layers have lower exposure and benefit more
from any development-side gain.

## Implementation

```hlsl
float2 dir        = lab.yz / max(C, 1e-5);          // per-pixel normalised chroma dir
float  scene_ang  = ReadHWY(HWY_CHROMA_ANGLE) * 6.28318 - 3.14159;  // decode to radians
float2 scene_dir;
sincos(scene_ang, scene_dir.y, scene_dir.x);         // scene dominant (a,b) unit vector
float  alignment  = dot(dir, scene_dir);             // 1 = aligned, -1 = complementary
float  dir_scale  = 1.0 - alignment * 0.15;         // ±15% on expansion lerp weight
float  factor     = lerp(1.0, slope_eff, INVERSE_STRENGTH * mid_weight * c_weight * dir_scale);
```

`alignment` ranges −1→1: +1 = pixel hue matches scene dominant, −1 = pixel is complementary.
`dir_scale` at alignment=+1: 0.85 (15% less expansion for dominant hue).
`dir_scale` at alignment=−1: 1.15 (15% more expansion for complementary hue).
`dir_scale` at alignment=0: 1.0 (neutral, perpendicular hues unchanged).

Maximum effect bounded by ±15% on the lerp weight, which is itself scaled by
`INVERSE_STRENGTH × mid_weight × c_weight` — the actual chroma delta is small.

## No new knobs

Effect magnitude is hardcoded at ±15% of the lerp weight. This is deliberately subtle —
it shifts colour richness without being an independent saturation control.
`INVERSE_STRENGTH` already scales the entire expansion including this modulation.
