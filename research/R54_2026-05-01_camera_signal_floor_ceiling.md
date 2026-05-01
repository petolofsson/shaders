# R54 — Camera Signal Floor / Ceiling

**Date:** 2026-05-01
**Status:** Research complete — see findings file before implementing.

---

## Motivation

Real camera sensors and log profiles do not produce true 0 (pure black) or true 1
(digital clip). ARRI LogC3 lifts the code-value black point to 64/1023 ≈ 6.25% of
full-scale (7.3% of the usable 64–940 range); RED Log3G10 encodes from −0.01 linear;
Sony S-Log3 parks its black at code value 64. `inverse_grade.fx` previously applied
a similar remap; it was pulled ("game tone curve is better"). `ColorTransformPS` can
currently receive and pass through true 0 and true 1.

---

## Proposed implementation

A two-line remap at the top of `ColorTransformPS` in `grade.fx`, before EXPOSURE runs:

```hlsl
// R54: camera signal floor/ceiling
col.rgb = col.rgb * (FILM_CEILING - FILM_FLOOR) + FILM_FLOOR;
```

Parameters in `creative_values.fx`:

```hlsl
uniform float FILM_FLOOR   < ... > = 0.003;   // see findings — 0.07 is a code-value %, not linear
uniform float FILM_CEILING < ... > = 0.95;
```

**Insertion point:** line 224 of `grade.fx`, immediately after the data-highway guard and
before the FilmCurve/EXPOSURE block (line 240).

---

## Research tasks

1. Find published black point / white ceiling values for ARRI LogC, RED, Sony S-Log —
   what are the actual signal floor percentages? ✓ See findings §1.
2. Determine whether the remap should be a fixed constant or a user knob. ✓ See findings §2.
3. Check interaction with EXPOSURE — before or after gamma? ✓ See findings §3.
4. Assess whether this conflicts with PRINT_STOCK black lift (R51, 0.025 linear). ✓ See findings §4.
