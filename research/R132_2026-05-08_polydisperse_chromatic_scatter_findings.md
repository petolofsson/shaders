# R132 — Polydisperse Chromatic Scatter: Findings
**Date:** 2026-05-08
**Status:** Implemented

## Problem
HBM diffusion blur was achromatic — single radius for all channels. Real micro-lenslet scatter is wavelength-dependent (longer wavelengths scatter more). A uniform blur radius produces spectrally neutral bloom with no wavelength character.

## Solution
Per-channel blur radius scaling: red ×1.15 (widest), green ×1.00 (reference), blue ×0.85 (narrowest). Matches Mie scatter wavelength dependence where longer wavelengths diffract more.

## Implementation
DiffusionBlur passes scale sample offsets by per-channel scalar (R:G:B = 1.15:1.00:0.85).

## Result
Highlight bloom has subtle warm fringe — spectrally correct, not a post-hoc tint.
