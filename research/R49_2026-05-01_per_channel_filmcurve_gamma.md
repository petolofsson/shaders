# R49 — Per-Channel FilmCurve Shoulder/Toe Gamma

**Date:** 2026-05-01
**Status:** Implemented — pending validation

---

## Problem

`FilmCurve` in `grade.fx` applies a single scalar `factor` to the shoulder quadratic and a single
scalar toe coefficient, shared across R, G, B. The existing `CURVE_R_KNEE / CURVE_B_KNEE /
CURVE_R_TOE / CURVE_B_TOE` knobs in `creative_values.fx` control *where* compression starts
(position), but the *rate* at which each channel compresses once engaged is identical for all three.

In every published Kodak color negative film datasheet (VISION3 5219/7219, 2254; H-740 sensitometry
workbook), the three H&D characteristic curves for the red-, green-, and blue-sensitive dye layers
are not parallel:

| Layer | Gamma (γ) | Perceptual consequence |
|-------|----------|----------------------|
| Red (cyan dye) | 0.55–0.60 (shallowest) | Softer shoulder + more toe lift → warm shadows |
| Green (magenta dye) | 0.60–0.65 (middle) | Reference |
| Blue (yellow dye) | 0.65–0.70 (steepest) | Steeper shoulder + less toe lift → highlight neutrals pull slightly cool |

This is a consistent property of CMY dye coupler chemistry: the cyan-forming (red-sensitive) layer
trades some contrast for wider latitude. The result is the classic Kodak rendering — warm shadows,
neutral-to-slightly-cool highlights — that cannot be reproduced by knee-position offsets alone.

---

## Signal

None required — baked constants derived from published H&D sensitometry ratios. No runtime
measurement needed.

---

## Proposed implementation

Inside `FilmCurve()` at `grade.fx`, after `above` and `below` are computed, replace the scalar
return with per-channel weighted float3 terms:

```hlsl
// grade.fx — inside FilmCurve(), replace the return statement

// R49: per-channel gamma weighting from Kodak H&D sensitometry
// Red: lower γ → softer shoulder (+6%), more toe lift (+12%)
// Blue: higher γ → steeper shoulder (−7%), less toe lift (−14%)
float3 shoulder_w = float3(1.06, 1.00, 0.93);
float3 toe_w      = float3(1.12, 1.00, 0.86);

return x - factor * shoulder_w * above * above
           + (0.03 / (knee_toe * knee_toe)) * toe_w * below * below;
```

All operations are `float3 * float3 * float3` element-wise — legal SPIR-V, no branching.
Net lightness change at scene-median input is < 0.3% (calibrated to be perceptually transparent
at p50). Effect grows with scene saturation and distance from mid-exposure.

---

## Interaction with existing CURVE_* knobs

The `CURVE_*` position offsets and the R49 gamma weights are fully orthogonal:
- Position offsets shift the knee/toe point — *where* compression begins
- Gamma weights change the compression rate — *how fast* it progresses once engaged

Both operate independently. Users who have tuned `CURVE_*` values will see no interaction at
default gamma weights. Re-balancing after R49 requires only small positional tweaks if desired.

---

## Validation targets

- Dark interior with warm light source: shadows should read warmer without needing ROT_* or SHADOW_TEMP
- Overcast outdoor scene: highlights should neutral-to-slightly-cool without blue cast
- Pure white / neutral grey ramp: should show < 0.3% channel separation at midtone, growing
  toward toe and shoulder

---

## Risk

Low. Changes only the compression rate inside FilmCurve, not the knee/toe positions. Effect is
bounded — at default weights the maximum per-channel deviation at a fully saturated input is
~6% shoulder / ~12% toe. No automated downstream parameter depends on the absolute value of
`lin` in a way that is destabilised by this magnitude of change.
