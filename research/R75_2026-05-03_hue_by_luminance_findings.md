# R75 Findings — Hue-by-Luminance Rotation

**Date:** 2026-05-03
**Status:** Implement — small magnitude, primarily neutral-axis effect

Sources: Kodak 2383 data sheet, r/colorists practitioner analysis, X88 Cinematic
LUTs documentation (gamut.io), koraks.nl "Sickly colors – the crossover issue".

---

## Kodak 2383 tonal hue behavior

**Confirmed:** warm highlights, cool shadows. From Kodak's own product description:
"toe areas of the three sensitometric curves are matched more closely than 2386 Film,
producing more neutral highlights on projection."

From practitioner RGB curve analysis: red channel lower / blue channel higher in
shadows; red higher / blue lower in highlights. This produces:
- Shadows: slight blue-green (cool) cast
- Highlights: slight amber/warm cast

**Magnitude:** modest in actual calibrated prints. The teal-orange tonal split
widely attributed to 2383 is significantly exaggerated in LUT emulations for
aesthetic reasons. Kodak's engineering goal was *neutral* highlights — meaning the
stock minimises rather than maximises this crossover. The effect is a few degrees
of hue angle on the neutral axis, not tens of degrees.

**Hue selectivity:** primarily affects the neutral axis (achromatic and
desaturated colors). Saturated colors show mainly a chroma change rather than a
hue rotation — dye layers are designed to maximise midtone saturation, so the
crossover manifests more in neutrals.

---

## Implementation

`r21_delta` is hue-dependent but luminance-agnostic. Adding a luminance-dependent
delta maps the 2383 tonal characteristic:

```hlsl
// R75: hue-by-luminance — cool shadows, warm highlights (2383 tonal character).
// Primarily affects neutral axis; saturated colors already have dominant hue.
float hue_lum_rot = lerp(-0.003, +0.003, lab.x);
r21_delta += hue_lum_rot;
```

`lab.x` is Oklab L (0=black, 1=white):
- At L=0 (black): −0.003 rotation (cool — shadow crossover)
- At L=0.5 (midtone): 0 (neutral)
- At L=1.0 (white): +0.003 rotation (warm — highlight crossover)

±0.003 in normalised hue (0–1 range) = ±1.1° of hue angle. This is consistent
with 2383's characterisation as a modest neutral-axis shift rather than a bold
tonal split.

**Why `lab.x` (the pre-tonal L, not `new_luma`):** `lab = RGBtoOklab(lin)` is
computed from the post-Stage-1, post-Stage-2 value. Using `lab.x` here is
consistent — it applies the rotation relative to the actual displayed luminance
value.

**Coverage of the neutral-axis specificity:** the rotation applies to all hues
via `r21_delta`. For saturated pixels, the added ±0.003 is small relative to the
`ROT_*` knob contributions — effectively below user-perceptible threshold for
vivid colors. For neutral/desaturated pixels (h undefined but averaged to ~0.5
in h_perc), the ±1.1° correctly steers them along the warm/cool axis. This
naturally concentrates the effect on neutrals as expected from 2383.

---

## Interaction with R19 (3-way CC)

R19 already provides SHADOW_TEMP/HIGHLIGHT_TEMP as manual warm/cool corrections.
R75 adds a fixed automatic tonal hue rotation grounded in 2383 physics, at a
magnitude small enough to be overridden by the R19 knobs if desired. No conflict.

---

## GPU cost

1 `lerp` + 1 `+=`. Zero new taps, zero new knobs.
