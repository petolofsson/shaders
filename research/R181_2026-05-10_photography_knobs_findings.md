# R181 — Photography Knob Additions: Findings
**Date:** 2026-05-10
**Status:** Implemented

## Problem
Comparing to Lightroom Basic+HSL panels, three functional gaps identified: no dedicated highlight recovery (WHITES is a hard ceiling, not soft recovery), no global saturation multiplier (VIBRANCE is lift-only), no per-hue saturation control (HSL Saturation row).

## Solution
HIGHLIGHTS: soft luma push/pull via `smoothstep(0.55, 0.85, new_luma)` mask, ±0.20 L range, in ApplyTonal after shadow lift. SATURATION: global `C *= max(0, 1 + SATURATION)`, −1=greyscale, +1=2× chroma, in ApplyChroma after vibrance. SAT_RED/YELLOW/GREEN/CYAN/BLUE/MAG: 6-band weighted chroma scale `C *= max(0, 1 + sat_delta × 0.80)`, same HueBandWeight loop as ROT_*, applied after SATURATION.

## Implementation
grade.fx ApplyTonal (HIGHLIGHTS) and ApplyChroma (SAT_* + SATURATION). arc_raiders creative_values.fx only — GZW synced on final profile copy.

## Result
Full Lightroom Basic+HSL parity for practical game grading. All defaults 0.0 = passthrough.
