# R67 — Pipeline Opportunity Analysis

**Date:** 2026-05-02
**Status:** Proposed — research task, no implementation

## Goal

Systematically audit every pipeline stage for improvement headroom. Output: a ranked
shortlist of specific investigations with estimated visual impact, implementation
complexity, and GPU cost. Not a feature proposal — a map of where effort is worth
spending next.

## Methodology

For each stage: characterise what it currently does, identify what it cannot do or does
imperfectly, and ask whether a better model exists in the literature. Score each gap on
three axes (H/M/L):

- **Visual impact** — how noticeable is the current limitation in-game?
- **Implementation cost** — new passes, new textures, shader complexity?
- **GPU cost** — extra taps, ALU, register pressure?

## Stages to audit

---

### Stage 0 — FILM RANGE (R54)
`col × (CEILING − FLOOR) + FLOOR`

Current limitation: linear remap only. No awareness of where signal energy actually sits
relative to the floor/ceiling. Could floor/ceiling be auto-derived from PercTex p25/p75
rather than manual knobs?

Research question: is there a perceptual benefit to an auto-adapting film range, or does
manual control here serve a purpose (preserving artistic intent)?

---

### Stage 1 — CORRECTIVE (FilmCurve)
H&D-inspired per-channel knee/toe. Weights from R49.

Current limitation: curve shape is fixed — knee and toe positions are manual. The curve
does not react to scene content; a low-key scene gets the same curve shape as a high-key
scene. R48 addressed zone contrast automation but the FilmCurve itself remains static.

Research question: what is the literature on scene-adaptive S-curve shaping (beyond
simple gamma)? Is there a perceptually-motivated curve that outperforms the current H&D
model for SDR output?

---

### Stage 1.5 — PRINT STOCK (Kodak 2383)
Fixed approximation at `PRINT_STOCK = 0.20`.

Current limitation: the emulsion model is a static blend. Real Kodak 2383 response
varies with exposure level (the paper emulsion has a non-linear cross-over between
layers). The current model may be accurate at mid-exposure but diverge at extremes.

Research question: is there a published spectral/photochemical model for 2383 that would
give better highlight rolloff and shadow toe than the current linear blend?

---

### Stage 1.7 — 3-WAY CORRECTOR
Manual temp/tint per shadow/mid/highlight.

Current limitation: fully manual — the only completely un-automated stage in the
pipeline. A scene with shifting white balance (e.g. moving between indoor and outdoor
areas) gets no automatic correction. Also: the shadow/mid/highlight boundaries are fixed
smoothstep ranges, not content-adaptive.

Research question: can scene white balance be estimated from the existing ChromaHistoryTex
(chroma mean and hue direction per zone) and used to auto-centre the temp/tint, leaving
the knobs as offsets from neutral rather than absolute values?

---

### Stage 2 — TONAL (Shadow lift, Retinex, Zone S-curve)
R57–R66 now cover this heavily. R65/R66 just implemented.

Current limitation: the zone S-curve strength is automated by zone_std but the *shape*
is fixed (smoothstep). The Retinex weights (0.20/0.30/0.50) are from satellite imagery
literature — are they optimal for game rendering? Clarity (wavelet) uses fixed band
weights from the same source.

Research question: is there evidence for different Retinex mip weights for photographic
vs rendered content? Does the current 3-band wavelet clarity produce halo artefacts at
high TONAL_STRENGTH?

---

### Stage 3 — CHROMA (Oklab, HK, Abney, Purkinje, density)

This is the most complex stage and the least recently audited.

**3a. Gamut compression**
Current implementation: not visible in grade.fx output — need to audit what gamut
compression exists and whether it handles near-gamut-boundary colours gracefully.

Research question: is there a soft-knee gamut compression curve in the current pipeline?
If not, saturate() as the SDR ceiling may be clipping chromatic highlights abruptly.

**3b. Abney effect correction**
The Abney effect (perceived hue shift when white is added to a spectral colour) is noted
as implemented but no research doc exists for it. Its accuracy is unknown.

Research question: what correction formula is being used and how does it compare to
published Abney models (Pridmore 1999, Xiao 2011)?

**3c. Opponent-channel interaction**
Current chroma model processes C (magnitude) and h (angle) independently per pixel.
Real visual cortex processing involves opponent channel interactions (red/green,
blue/yellow) that affect perceived saturation differently by hue angle. The HK effect
partially addresses this but only for luminance.

Research question: is there a spatial opponent-channel model in the post-processing
literature that would improve perceived colour separation?

**3d. Spatial chroma variation**
All chroma adjustments are per-pixel with no spatial context — every pixel in the same
luma/chroma band gets the same treatment. CreativeLowFreqTex carries the low-frequency
colour field, currently used only for luma (Retinex). Could chroma lift or density be
modulated by local spatial frequency content — boosting chroma in flat areas, restraining
it in already-detailed areas?

Research question: is there evidence that spatial chroma modulation improves perceived
image quality versus global per-pixel treatment?

---

### Stage 3.5 — HALATION (R56)
`R(mip1) > G(mip0), B=0. Gate: smoothstep(0.80, 0.95, luma). HAL_STRENGTH 0.35.`

Current limitation: B channel is zero — physical film halation has a weak B component.
The gate is luma-only; real halation also depends on chroma (a warm highlight halos
differently than a cool one). The scatter source is mip0/mip1 of CreativeLowFreqTex —
the spatial spread is fixed by mip resolution.

Research question: what does physical film halation spectral data say about the
R/G/B ratio and spatial falloff? Is there a published spectral model (Kodak data,
sensitometry papers) that gives better RGB weights?

---

### pro_mist — MIST (R55)
Bidirectional scatter from CreativeLowFreqTex mip 0+1 blend, IQR-driven radius.

Current limitation: the scatter source is the full low-frequency image. A physical Black
Pro-Mist filter scatters primarily from specular highlights — the current implementation
gates on luma but doesn't weight by highlight chroma. Also: the mip blend radius is
IQR-driven but the transition between mip 0 and mip 1 is a fixed lerp; a physical filter
would have a continuous radial falloff.

Research question: is there a published optical model for diffusion filters (Pro-Mist,
Black Satin) that gives a more accurate scatter kernel shape? Does the current additive
RGB scatter reproduce the chromatic character of the physical filter?

---

## Scoring template (to fill in after research)

| Stage | Gap | Visual impact | Impl cost | GPU cost | Priority |
|-------|-----|---------------|-----------|----------|----------|
| Stage 1 | Scene-adaptive FilmCurve | ? | ? | ? | ? |
| Stage 1.5 | 2383 exposure-varying emulsion | ? | ? | ? | ? |
| Stage 1.7 | Auto white balance centre | ? | ? | ? | ? |
| Stage 2 | Retinex weights for rendered content | ? | ? | ? | ? |
| Stage 3a | Gamut compression audit | ? | ? | ? | ? |
| Stage 3b | Abney correction accuracy | ? | ? | ? | ? |
| Stage 3c | Opponent-channel interaction | ? | ? | ? | ? |
| Stage 3d | Spatial chroma modulation | ? | ? | ? | ? |
| Stage 3.5 | Halation spectral model | ? | ? | ? | ? |
| pro_mist | Scatter kernel accuracy | ? | ? | ? | ? |

## Expected output

A findings document that fills in the scoring table, names 2–3 high-priority
investigations with specific literature references, and formally closes the rest as
low-priority or not-worth-pursuing. The findings doc becomes the roadmap for R68+.

## Note on scope

This is a research-only task — no code changes. The findings document should be
actionable: each entry either becomes a numbered proposal or is explicitly dismissed with
a reason.
