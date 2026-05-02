# R76 — Perceptual Input Normalization

**Date:** 2026-05-03
**Status:** Proposed

## Problem

Stage 0 is a power function (EXPOSURE) and range remap — no perceptual model,
no scene-illuminant correction. No game pipeline has a perceptual input stage.

Two components:

## R76A — CAT16 Scene-Illuminant Chromatic Adaptation

The scene illuminant chromaticity is available from `CreativeLowFreqTex mip 2`
(used by R66 for ambient shadow tint). CAT16 (from CIECAM16, CIE 248:2022) normalises
toward D65 in LMS cone space — more physiologically correct than R19's linear RGB
shifts. Unlike the dismissed Gray World auto-WB, this uses the spatially-measured
illuminant from the analysis infrastructure.

After R76A, R19 becomes an artistic deviation from neutral rather than a scene
correction. The two do not conflict — one is automatic calibration, the other is
creative intent.

### Research task

1. Obtain CAT16 transform: RGB→LMS matrix (Hunt-Pointer-Estevez or CAT16 specific),
   von Kries adaptation in LMS, inverse LMS→RGB.
2. Derive illuminant XYZ from CreativeLowFreqTex mip 2 RGB (sRGB → XY chromaticity).
3. Validate illuminant estimate reliability across diverse game scenes — confirm mip 2
   is stable enough to drive a chromatic adaptation.
4. Derive strength limit: full CAT16 adaptation may over-correct intentionally-warm
   scenes. Determine appropriate blend factor or adaptation degree.

## R76B — CIECAM02 Viewing Condition Surround Compensation

CIECAM02 (CIE 159:2004) models how perceived contrast varies with display surround
luminance. A dark-room surround produces higher apparent contrast than an average
surround for the same display output. The surround factor `Fs` in CIECAM02 adjusts
the effective tone response.

New knob: `VIEWING_SURROUND` (dark / dim / average) applied at input stage before
FilmCurve shapes the response.

### Research task

1. Extract the surround compensation formula from CIECAM02 Appendix A. Identify the
   Fs values for dark (0.8), dim (0.9), average (1.0) surrounds.
2. Derive a per-pixel tone adjustment in linear light that approximates the CIECAM02
   J (lightness) correction for each surround condition.
3. Confirm independence from FilmCurve: surround compensation should be applied before
   the FilmCurve, not after.

## GPU cost

CAT16: matrix multiply (~9 MAD). Surround: 2–3 ALU. No new taps.

## Dependency

R76A must be validated before R76B. R76B uses the CAT16 neutral as its reference point.
