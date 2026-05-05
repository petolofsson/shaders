# R69 — Abney Coefficient Validation (Pridmore 2007)

**Date:** 2026-05-02
**Status:** Proposed

## Problem

The Abney correction in `grade.fx` applies a chroma-proportional hue rotation per
band to simulate the Abney effect — the perceived hue shift when white is added to a
spectral colour (i.e. as chroma decreases toward white):

```hlsl
float abney = (+hw_o0 * 0.06    // RED     +rotate
              - hw_o1 * 0.05    // YELLOW  -rotate
              - hw_o3 * 0.08    // CYAN    -rotate
              + hw_o4 * 0.04    // BLUE    +rotate
              + hw_o5 * 0.03)   // MAGENTA +rotate
              * final_C;
```

These five coefficients have no research document and no reference to a published
psychophysical source. The sign pattern is directionally plausible but the magnitudes
are unverified.

## Reference

Pridmore, R.W. (2007). "Effect of purity on hue (Abney effect) in various conditions."
*Color Research & Application*, 32(1), 25–39.

This is the most comprehensive published dataset for the Abney effect: hue rotation
vs. purity for all principal hues, averaged across 31 subjects. It provides the
direction and magnitude of hue rotation for red, yellow, green, cyan, blue, and
magenta as saturation changes from spectral pure to white (C → 0).

## Research task

1. Obtain Pridmore 2007 Table 2 (or equivalent) — hue rotation in degrees per unit
   change in purity, per principal hue.
2. Convert Pridmore's purity-based rotations to Oklab chroma-based rotations:
   - Oklab C range [0, ~0.4] vs CIE purity [0, 1]
   - Rotation in Oklab hue normalised units [0, 1] vs degrees [0, 360]
3. Compare derived per-band coefficients to the current values (0.06, 0.05, 0.08,
   0.04, 0.03).
4. If any coefficient diverges by more than 30%, update it.

## Notes

- GREEN is absent from the current Abney formula (hw_o2 not used). Pridmore data
  may show a non-zero Abney effect for green — if so, add it.
- The current formula applies the correction proportional to `final_C` (post-lift
  chroma). Whether the Abney effect should scale with C or with the *change* in C
  (delta from input) is a modelling question to resolve during research.
- The Abney effect is strongest for yellow (~15° shift from saturated to white,
  per Pridmore), which corresponds to the largest coefficient in the current formula
  (YELLOW is -0.05 — but CYAN at -0.08 is larger, which may be incorrect).

## GPU cost

Zero. Coefficient constants only.

## Success criterion

Current coefficients are either confirmed against Pridmore data (within 30%) or
updated to match. Research doc records the derivation so future changes have a
quantitative basis rather than empirical tuning.
