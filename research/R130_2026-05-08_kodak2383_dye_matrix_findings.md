# R130 — Kodak 2383 Dye Matrix: Findings
**Date:** 2026-05-08
**Status:** Implemented

## Problem
Print stock emulation needed physically accurate dye cross-talk. A naive RGB curve treats each channel independently, missing the spectral overlap where each dye layer (cyan, magenta, yellow) absorbs across all three measurement channels — not just its primary. Without this, shadow cast and highlight desaturation are wrong.

## Solution
Applied the 3×3 matrix from Kodak H-1-2383t publication encoding cyan/magenta/yellow dye layer spectral overlap. The matrix captures inter-channel density coupling before the per-channel print stock density curve is applied.

## Implementation
Matrix multiply on RGB before print stock density curve application.

## Result
Accurate warm shadow cast and highlight desaturation characteristic of 2383.
