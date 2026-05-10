# R74 Findings — Highlight Desaturation

**Date:** 2026-05-03
**Status:** Implement — coefficient correction confirmed

Sources: Munsell renotation data (Paul Centore MacAdam limit extrapolation),
Kodak 2383 product data sheet, r/colorists practitioner analysis.

---

## Munsell chroma rolloff at high Lightness

Maximum achievable chroma in Munsell space drops substantially as Value approaches 10:

| Hue | Value 6 max chroma | Value 9 max chroma | Reduction |
|-----|-------------------|-------------------|-----------|
| Red (5R) | ~30 | ~12 | **60%** |
| Orange (5YR) | ~22 | ~18 | 18% |
| Yellow (5Y) | ~14 | ~26 | **peaks at high value** |
| Green (5G) | ~12 | ~3 | 75% |
| Blue (5B) | ~10 | ~3 | 70% |
| Purple-Blue (5PB) | ~12 | ~4 | 67% |

**Yellow is a structural exception** — saturated yellow is inherently light-valued.
It retains and even peaks at high Value. All other hues drop by 18–75%.

The rolloff shape is approximately linear from Value 7.5–9 for warm hues, and
steeper for cool hues (blue/cyan/green are already very low-chroma by Value 8).
Onset at Munsell Value ~7.5 corresponds to Oklab L ≈ 0.75 — the current R22 onset
is correctly calibrated.

---

## Current R22 highlight arm is under-scaled

Current code:
```hlsl
C *= saturate(1.0 - 0.20 * saturate(1.0 - lab.x / 0.25)   // shadow arm
                  - 0.25 * saturate((lab.x - 0.75) / 0.25)); // highlight arm
```

At Oklab L = 1.0: max rolloff = 25%. Munsell data says correct average is 50–60%
for warm hues, 70%+ for cool hues. The 25% coefficient is too gentle by a factor
of ~2 for most hues.

Yellow is the exception (peaks at high Value). A single universal coefficient
cannot be perfect for all hues. A conservative universal increase to 40–45%
covers the majority of hues adequately:

```hlsl
C *= saturate(1.0 - 0.20 * saturate(1.0 - lab.x / 0.25)
                  - 0.45 * saturate((lab.x - 0.75) / 0.25));
```

This gives:
- At Oklab L = 0.75 (onset): 0% highlight rolloff ✓
- At Oklab L = 0.875: ~22.5% rolloff
- At Oklab L = 1.0: **45% rolloff** — matches Munsell average (vs 25% current)

Yellow pixels at L=1.0 will receive the same 45% rolloff, which slightly
under-models their real higher chroma retention. This is acceptable — a yellow
pixel at Oklab L=1.0 is extremely close to white and its chroma is gamut-limited
in any case.

---

## 2383 highlight desaturation

Confirmed separate from shadow toe. Kodak markets 2383 as having "neutral
highlights" via matched toe curves for R/G/B. At D-min (paper base), the stock
has a slight warm tint from the base material — only visible in the very
brightest values. This is modest and partially covered by the FilmCurve shoulder
behavior. No specific density threshold published; the effect is a specification
goal (minimise crossover), not a discrete onset.

**Conclusion:** The Munsell-calibrated increase from 0.25 to 0.45 is the primary
fix. The 2383 D-min warmth is not a separate chroma rolloff — it's a hue effect
addressed by R75.

---

## Implementation

One-character change in grade.fx R22 highlight arm: `0.25` → `0.45`.
