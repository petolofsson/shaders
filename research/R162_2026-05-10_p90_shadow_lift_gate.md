# R162 — P90 Specular Contrast Gate for Shadow Lift

**Date:** 2026-05-10
**Scope:** grade.fx `ApplyTonal` — shadow lift, `BuildSceneCtx` — specular_contrast

---

## Problem

Shadow lift was modulated by texture, fine-texture, detail-protect, and temporal context
gates — but not by scene dynamic range. In scenes with isolated bright sources (sun, lamps),
lifting shadows compresses the apparent depth relationship between foreground shadows and
background highlights. The viewer's eye adapts to the bright source, making unlifted shadows
feel natural; lifting them reads as flat.

`HWY_P90` (slot 200) was already computed by `analysis_frame` and used by halation to
scale scatter strength. Shadow lift was not reading it — identified as a gap in a full
highway slot audit (2026-05-10).

## Signal

`specular_contrast = saturate((p90 − p50) / 0.40)`

The p90−p50 gap measures how far the bright tail extends above the scene median — a direct
proxy for isolated bright sources against a darker surround. Small gap = flat/uniform scene.
Large gap = sun, lamp, or window dominating the bright end.

Previously computed inline in `ApplyCorrective` for halation only. Moved to `BuildSceneCtx`
as `ctx.specular_contrast` so both stages share the same value without re-reading the highway.

## Implementation

In `BuildSceneCtx`:
```hlsl
ctx.specular_contrast = saturate((ReadHWY(HWY_P90) - ctx.perc.g) / 0.40);
```

In `ApplyTonal` shadow lift:
```hlsl
float specular_att = 1.0 - smoothstep(0.50, 0.90, ctx.specular_contrast) * 0.35;
shadow_lift *= specular_att;
```

At specular_contrast < 0.50: no attenuation — uniform or low-DR scenes get full lift.
At specular_contrast > 0.90: 35% reduction — strong isolated sources moderate the lift.
Maximum 35% — shadow lift is not zeroed, just pulled back to preserve depth.

## Halation cleanup

`ApplyCorrective` previously re-read `HWY_P90` inline to compute `specular_contrast`
for halation. Now uses `ctx.specular_contrast` — one highway read instead of two.

## No new knobs

`SHADOW_LIFT_STRENGTH` already scales the entire lift chain including this gate.
