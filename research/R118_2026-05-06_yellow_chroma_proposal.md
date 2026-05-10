# R118 — Yellow/Orange Chroma Over-Saturation
**Date:** 2026-05-06

---

## Problem Statement

In Arc Raiders, yellow and orange hues exceed perceptually natural saturation levels after the full
pipeline runs. The issue is visible as yellow/orange "popping" beyond what feels physically correct.
The same problem likely exists in GZW but is masked by darker, higher-contrast scenes.

## Pipeline Amplification Stack

The pipeline applies chroma expansion at multiple sequential stages, each of which compounds:

1. **Inverse grade (R90)** — IQR chroma expansion. Restores tonemapper-compressed chroma
   uniformly across all hues. If the tonemapper's S-curve shoulder hits yellow/orange harder
   (plausible — yellow is high-luminosity, closer to the shoulder), inverse grade over-restores.

2. **CHROMA_STR 0.45 per-hue lift** — chroma lift near each hue band's scene mean.
   Yellow/orange pixels in the scene pull this lift up.

3. **R118D memory color attraction** — foliage boost fires across lab.x 0.35–0.75.
   Green-yellow hues in foliage range get an additional 0.006 × C nudge.

4. **R73 ceiling** — yellow ceiling is 0.24 Oklab C, the second loosest in the system.
   Justified by MacAdam discrimination ellipses being large in the yellow region.
   Red: 0.28 / Yellow: 0.24 / Magenta: 0.22 / Blue: 0.19 / Green: 0.16 / Cyan: 0.15.

5. **R118A Hunt effect** — `chroma_str *= lerp(0.80, 1.20, zone_log_key)`.
   In bright scenes, all chroma is boosted a further 20%.

The ceiling is reached, then held. But the question is whether 0.24 is the right ceiling for yellow
in Oklab — and whether MacAdam discrimination metrics are the correct justification for it.

## Research Questions

1. **Natural scene statistics for yellow chroma**: What Oklab C values does yellow reach in real
   natural images? Is 0.24 plausible or does it exceed the natural gamut?

2. **MacAdam ellipses in Oklab space**: MacAdam (1942) measured discrimination ellipses in x-y
   CIE 1931. Yellow ellipses are large there. But Oklab was designed to be perceptually uniform —
   in Oklab, are yellow discrimination ellipses still larger than blue/cyan? If not, the ceiling
   calibration is wrong.

3. **Tonemapper chromatic behaviour on yellow**: Do Reinhard, ACES, or Unreal's filmic tonemapper
   compress yellow/orange chroma more than other hues? If so, inverse grade would amplify this
   specific hue band.

4. **Industry ceiling practice**: How does DaVinci Resolve, ACES, or film-print workflows bound
   yellow saturation? Is there a known "yellow danger zone" in colorimetry?

5. **Perceptual loudness of yellow**: Is the HK/Helmholtz-Kohlrausch effect stronger for yellow
   than other hues? Does yellow at moderate C appear more saturated than blue at the same C?

## Hypotheses (pre-research)

- H1: Natural scene yellow rarely exceeds Oklab C ≈ 0.15. Our ceiling of 0.24 allows >60%
  overshoot above the natural range.
- H2: MacAdam ellipses in CIE 1931 are large for yellow, but Oklab already corrects for this.
  Using MacAdam to justify a loose ceiling in Oklab double-counts the correction.
- H3: The HK effect amplifies yellow's perceptual loudness, making even moderate saturation
  appear aggressive — the ceiling should account for appearance, not just discrimination.

## Proposed Fix Options (pre-research)

A. **Tighten R73 yellow ceiling** — reduce from 0.24 toward 0.16–0.18, removing the MacAdam
   relaxation that may be inapplicable in Oklab.

B. **Per-hue inverse grade de-weighting** — if the tonemapper over-compressed yellow, apply a
   per-hue correction weight in R90 rather than a uniform IQR expansion.

C. **ROT_YELLOW toward green** — push yellow pixels toward green before chroma ceiling fires,
   reducing the perceptual pop without touching saturation numbers.

D. **HK correction for yellow** — apply a stronger Helmholtz-Kohlrausch correction specifically
   on yellow hues to pre-compensate for its perceptual loudness.

The research will determine which of these is physically justified.
