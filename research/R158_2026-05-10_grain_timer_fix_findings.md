# R158 — Grain Timer Source Fix: Findings
**Date:** 2026-05-10
**Status:** Implemented

## Problem
`source = "framecount"` returns 0 in vkBasalt — grain slot was always slot 0, producing a static noise pattern. At 60fps this looked like a fixed texture overlay, not film grain.

## Solution
Replaced with `source = "timer"` (ms since app start). Grain slot: `uint(FRAME_TIMER / 41.667)` — turns over at ~24fps regardless of display framerate.

## Implementation
Uniform renamed from FRAME_COUNT to FRAME_TIMER. Same fix applied to Halton base_idx in UpdateChromaKalman in corrective.fx.

## Result
Grain animates correctly at ~24fps. GRAIN_STRENGTH reset 2.0→1.0 (was inflated to compensate for invisible static grain).
