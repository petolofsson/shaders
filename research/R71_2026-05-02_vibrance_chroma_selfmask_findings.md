# R71 Findings — Vibrance / Chroma Self-Masking

**Date:** 2026-05-02
**Status:** Implemented

---

## Implementation

Inserted between the `lifted_C` computation and `final_C` (grade.fx ~line 431):

```hlsl
float vib_mask = saturate(1.0 - C / 0.22);
float vib_C    = C + max(lifted_C - C, 0.0) * vib_mask;
```

`final_C` now uses `vib_C` as its base instead of `max(lifted_C, C)` directly.

---

## Ceiling value 0.22

The self-mask ceiling of 0.22 (Oklab C) was chosen to correspond to roughly 85% of
the sRGB primary gamut extent in Oklab (~0.26–0.30). Below 0.22 the scaling is
linear; at 0.22 the lift completely vanishes. This means:

- Fully desaturated pixel (C=0): 100% lift applied
- Moderately saturated (C=0.11): 50% lift applied
- Vivid primary (C=0.22+): zero lift applied

The slope is continuous — no hard boundary visible at any chroma level.

---

## Interaction with R73 (memory color ceiling)

R71 runs before R73. `vib_C` feeds into `min(vib_C, max(C_ceil, C))`. This is correct:
vibrance determines how much lift is applied; memory color caps the result. In cases
where a pixel is below 0.22 but the band ceiling is below `vib_C`, R73 takes over.
The two gates are complementary and non-conflicting.

---

## Verdict

Implemented. Coefficient 0.22 tunable by adjusting the hardcoded value if scenes
show lift insufficient for midrange saturations — 0.18 for more aggressive self-masking,
0.26 for less.
