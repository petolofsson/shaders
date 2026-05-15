# R159 — Luma Inverse Tonemap Removal + R145 Decoupling: Findings
**Date:** 2026-05-10
**Status:** Implemented

## Problem
R144 pivot-based luma expansion (cbrt(p50_linear) Oklab L pivot in inverse_grade) caused texture smoothing on bright surfaces in dark scenes. The L pivot shifted all luma up, reducing local contrast on textured highlights.

## Solution
Removed R144 luma expansion from inverse_grade entirely — the effect now handles chroma only. Zone S-curve owns luma restoration. Removed R145 zone coupling workaround (ZONE_STRENGTH / slope) which existed only to compensate for R144.

## Implementation
inverse_grade.fx is now chroma-only. ZONE_STRENGTH (now CONTRAST) is uncoupled from inverse-grade slope.

## Result
Textured surfaces correct in dark scenes. INVERSE_STRENGTH tuned to 0.40 post-removal.
