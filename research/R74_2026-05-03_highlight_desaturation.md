# R74 — Highlight Desaturation

**Date:** 2026-05-03
**Status:** Proposed

## Problem

R22 applies Munsell-calibrated chroma rolloffs in shadows only:
```hlsl
C *= saturate(1.0 - 0.20 * saturate(1.0 - lab.x / 0.25)   // shadow arm
                  - 0.25 * saturate((lab.x - 0.75) / 0.25)); // highlight arm
```
Wait — there IS a highlight arm at lab.x > 0.75. Review whether the current 0.25
coefficient and 0.75–1.0 range are calibrated to Munsell data or are empirical.

R51 print stock applies `desat_w` in mid-range (luma 0–0.3 and 0.6–1.0) but this
is symmetric and film-curve-motivated, not specifically a highlight chroma rolloff.

Film print stock (Kodak 2383) desaturates near paper white: chroma approaches zero
as luminance approaches 1.0, independently of the shadow toe behaviour.

## Research task

1. Find Munsell chroma vs. Lightness data for high L* values (L* > 80). Determine
   the empirical rolloff shape — linear, quadratic, or faster.
2. Compare against the current R22 highlight coefficient (0.25 over L 0.75–1.0 in
   Oklab units). Confirm if 0.25 is calibrated or empirical.
3. Check whether R51's desat_w adequately models the highlight-specific behaviour
   or whether a separate term is needed.

## Likely implementation

```hlsl
C *= 1.0 - 0.30 * saturate((lab.x - 0.80) / 0.20);
```
Verify coefficient and threshold against Munsell data.

## GPU cost

2 ALU. No new taps, no new knobs.
