# R67 Findings — Pipeline Opportunity Analysis

**Date:** 2026-05-02
**Status:** Complete — spawns R68, R69, R70

---

## Summary

Three stages have meaningful improvement headroom. Seven are either already well-handled
or the gap is too small/costly to pursue. Findings below justify each verdict.

---

## Scored table

| Stage | Gap | Visual impact | Impl cost | GPU cost | Verdict |
|-------|-----|---|---|---|---|
| Stage 0 | Film range adaptation | L | M | L | Dismiss |
| Stage 1 | Scene-adaptive FilmCurve | L | M | L | Dismiss |
| Stage 1.5 | 2383 exposure emulsion | M | H | L | Dismiss |
| Stage 1.7 | Auto white balance | M | M | L | Pursue (R70) |
| Stage 2 | Retinex mip weights | L | L | L | Dismiss |
| Stage 3a | Gamut compression pre-knee | M | M | L | Pursue (R68) |
| Stage 3b | Abney coefficient accuracy | M | L | L | Pursue (R69) |
| Stage 3c | Opponent-channel interaction | L | H | M | Dismiss |
| Stage 3d | Spatial chroma modulation | H | L | L | **Top priority (R68 scope)** |
| Stage 3.5 | Halation B channel | L | L | L | Dismiss |
| pro_mist | Scatter kernel shape | L | H | M | Dismiss |

---

## Stage-by-stage findings

### Stage 0 — Film range (DISMISS)
Linear remap with manual FLOOR/CEILING knobs. No perceptual model suggests
non-linear floor/ceiling gives better results for SDR post-process. Low impact.

### Stage 1 — FilmCurve (DISMISS)
Research (PMC1773023) confirms content-aware tone mapping outperforms fixed curves —
but the pipeline already adapts. `fc_knee` and `fc_knee_toe` are driven by `eff_p75`
and `eff_p25` from PercTex (grade.fx:245–253). The FilmCurve is already scene-adaptive
via percentile anchors. Gap is smaller than the proposal assumed. No further action.

### Stage 1.5 — Kodak 2383 (DISMISS)
The real 2383 emulsion has exposure-varying inter-layer cross-over. The current
implementation is a deliberate linear approximation at `PRINT_STOCK = 0.20`, not a
claim to physical accuracy. More accurate models exist (10,000-point LUT, Reddit
r/cinematography) but at prohibitive GPU cost and with no perceptual benefit at this
blend level. Intentionally stylistic — dismiss.

### Stage 1.7 — Auto white balance centre (PURSUE → R70)
The 3-way corrector is the only fully manual stage. Gray World auto-WB
(estimate illuminant from mean RGB, compare to gray) is well-established. The pipeline
already tracks `mean_chroma` per band but only as a scalar magnitude — hue direction
(mean a, mean b) is not tracked. Implementing auto-WB would require:
1. Adding mean a/b per zone band to UpdateHistoryPS in corrective.fx
2. Deriving illuminant hue from zone-band mean a/b
3. Feeding the estimate to auto-centre SHADOW_TEMP/SHADOW_TINT and MID_TEMP/MID_TINT

Gray World fails on scenes with deliberate colour casts (intentional teal-orange grade),
but "auto-centering as a neutral offset" rather than "forced correction" would let the
user knobs act as offsets from neutral rather than absolute values — a more ergonomic
control surface. Medium visual impact, medium implementation cost.

### Stage 2 — Retinex mip weights (DISMISS)
Current weights 0.20/0.30/0.50 (coarse-biased, from satellite imagery) are appropriate
for game content. UE5/Lumen creates large-scale illumination gradients that benefit from
coarse-scale dominance. No literature found suggesting different weights for rendered
content vs. natural imagery. Zone_std-based blend already gates the Retinex to scenes
where it's needed. Dismiss.

### Stage 3a — Gamut compression pre-knee (PURSUE → R68)
**Actual code (grade.fx:455–466):**
```hlsl
float gclip = saturate((1.0 - L_grey) / max(rmax - L_grey, 0.001));
chroma_rgb  = L_grey + gclip * (chroma_rgb - L_grey);
lin = saturate(chroma_rgb);
```
`gclip` projects chroma toward L_grey only when `rmax > 1`. This is a post-hoc
correction — it activates after pixels have already hit the gamut boundary and
produces a hard geometric projection with no soft rolloff. Pixels near but below the
gamut boundary receive no compression; pixels just over it receive a sharp correction.
The final `saturate()` clips anything that escapes.

The issue: hue shifts occur at the gamut boundary because projection toward L_grey
does not follow constant-hue lines in Oklab. A soft-knee pre-compression (starting
at e.g. 85% of gamut distance) would smoothly roll chromatic highlights into gamut
rather than clipping or projecting.

ACES gamut compression (Daniele, 2020) and the Blue Light Gamut Mapper both use a
"distance from achromatic axis" approach with configurable soft-knee. This fits
the pipeline's Oklab structure naturally — C is already computed; a smoothstep rolloff
applied to C before gclip would give a proper soft boundary.

Visual impact: medium — most visible on highly saturated highlights (game UI elements,
energy effects, specular highlights on coloured surfaces).

### Stage 3b — Abney coefficient accuracy (PURSUE → R69)
**Actual code (grade.fx:437–441):**
```hlsl
float abney = (+hw_o0 * 0.06   // RED     +rotate
              - hw_o1 * 0.05   // YELLOW  -rotate
              - hw_o3 * 0.08   // CYAN    -rotate
              + hw_o4 * 0.04   // BLUE    +rotate
              + hw_o5 * 0.03)  // MAGENTA +rotate
              * final_C;
```
This applies a chroma-proportional hue rotation per band to simulate the Abney effect
(hue shift when white is added to a spectral colour). The coefficients are not
referenced to any published psychophysical data.

Pridmore (2007, Color Res Appl) provides the most comprehensive Abney effect dataset:
hue rotation vs. purity for all principal hues, measured across 31 subjects. The
sign pattern in the code (RED+, YELLOW-, GREEN absent, CYAN-, BLUE+, MAGENTA+)
broadly matches Pridmore's direction data, but the magnitudes (0.03–0.08) are
unverified. Pridmore's data shows the Abney effect is largest for yellow (~15°
shift from saturated to white) and smallest for unique red.

Research task: compare current coefficients against Pridmore 2007 Table 2 data.
Recalibrate if divergence > 30%. Low implementation cost (just coefficient values),
medium visual impact (mainly affects yellow-green transitions to white).

### Stage 3c — Opponent-channel interaction (DISMISS)
High implementation cost, unclear perceptual ROI for SDR game post-process. The
pipeline already has HK (Hellwig 2022, accurate to C^0.587), Abney (hue rotation by
chroma), and Purkinje (R52). Opponent-channel spatial interactions would require
significant new math with no published simplified shader model. Dismiss.

### Stage 3d — Spatial chroma modulation (TOP PRIORITY → R68)
**The highest-value gap in the pipeline.**

Current state: all chroma adjustments (lift, density, HK scale) are per-pixel with
no spatial context. A bright saturated pixel in a detailed texture region gets the
same chroma treatment as the same pixel in a large flat area.

Research support: Perceptual image quality research (PMC12470951, SPSIM algorithm)
explicitly uses texture complexity as a weighting function for colour quality
assessment — flat regions and textured regions are treated as perceptually different.
"Gradient region consistency" and "texture complexity weighting" are the state of the
art in colour IQA.

Why this matters: in flat shadow or sky regions, boosting chroma makes the colour
appear richer. In detailed texture regions, the spatial contrast already implies colour
variation — additional chroma boost can look artificial or over-processed.

**Available signal at zero cost:** The wavelet clarity block (R30, grade.fx) already
computes `D1 = luma - illum_s0` (fine detail) and `D2 = illum_s0 - illum_s1` (mid
detail). These bands are already in registers at the point chroma is processed.

Proposed signal: `detail_level = smoothstep(0.0, 0.08, abs(D1) + 0.5 * abs(D2))`
- `detail_level ≈ 0` in flat regions → apply full chroma_str
- `detail_level ≈ 1` in detailed regions → attenuate chroma_str by ~30–40%

This modulates the existing `chroma_str` scalar — no new passes, no new textures,
one smoothstep + one lerp.

### Stage 3.5 — Halation B channel (DISMISS)
Film layer structure confirmed (Britannica): blue layer is topmost, red layer is
deepest (closest to base). Halation from base reflection reaches red layer most,
green less, blue least. Modern stocks include anti-halation dye layers (Kodak 2383
data sheet: "efficient antihalation layer under the emulsion layers using patented
solid particle dyes") that largely suppress blue channel halation. B=0 is physically
justified for a stock with anti-halation. Dismiss.

### pro_mist — Scatter kernel (DISMISS)
No published optical PSF model for diffusion filters was found. Physical Black Pro-Mist
scatter is empirically characterised by manufacturers but no open spectral/spatial data
exists. The current IQR-adaptive mip blend is already a reasonable approximation.
Kernel shape refinement would require optical bench measurements. Dismiss.

---

## Spawned proposals

| ID | Title | Basis |
|----|-------|-------|
| R68 | Spatial chroma modulation + gamut compression pre-knee | Stage 3d (priority) + Stage 3a (same code region) |
| R69 | Abney coefficient validation against Pridmore 2007 | Stage 3b |
| R70 | Auto white balance centre from zone chroma history | Stage 1.7 |
