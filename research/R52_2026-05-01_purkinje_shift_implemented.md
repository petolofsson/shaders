# R52 — Purkinje Shift in Deep Shadows

**Date:** 2026-05-01
**Status:** Implemented

---

## Problem

The human visual system operates in two modes depending on luminance level:

| Mode | Receptor | Peak sensitivity | Activation |
|------|----------|-----------------|------------|
| Photopic (day) | Cones | 555 nm (yellow-green) | > ~1 cd/m² |
| Scotopic (night) | Rods | 507 nm (blue-green) | < ~0.01 cd/m² |

The transition between them — the mesopic range — spans roughly 0.001–1 cd/m². Within it,
rod contribution increases as luminance falls, shifting perceived colour sensitivity toward
shorter wavelengths. This is the Purkinje shift.

In practice: deep shadows in a scene do not look the same colour as bright areas of the same
chromatic content. A dark red object reads as nearly black-grey; a dark blue-green object
retains more perceived hue. This is physically correct vision, but it is absent from every
game rendering pipeline because it is a *perceptual* property of the observer, not a scene
property.

The result of omitting it: deep shadows feel flat and neutral-dark rather than subtly alive.
The characteristic "richness" of shadow areas in reference cinema — the slight blue-green bias
that reads as depth — is missing.

---

## Signal

Per-pixel `new_luma` (post zone contrast, post Retinex) — the current adapted luminance
estimate. No additional texture reads required.

---

## Proposed implementation

Applied in the CHROMA stage, after Oklab conversion, before chroma lift:

```hlsl
// grade.fx — inside Oklab block, after RGBtoOklab, before chroma lift
// R52: Purkinje shift — rod-vision hue bias in deep shadows
// Peak rod sensitivity at 507 nm ≈ Oklab hue ~210° (blue-green, h = -0.37 rad)
// Shift is additive on Oklab b axis (negative b = blue-green direction)
{
    float scotopic_w = 1.0 - smoothstep(0.0, 0.12, new_luma); // active below luma 0.12
    float purkinje   = 0.018 * scotopic_w * C;                  // proportional to chroma
    lab.b -= purkinje;                                           // push toward blue-green
    C = sqrt(lab.a * lab.a + lab.b * lab.b);                    // recompute C after shift
}
```

Walkthrough:
- `scotopic_w = 1` at `new_luma = 0` (pure black), fades to 0 at `new_luma = 0.12`
- Effect is proportional to chroma `C` — neutrals are unaffected (C = 0 → no shift)
- `lab.b -= 0.018 * scotopic_w * C` shifts the b axis (yellow-blue) toward blue-green
- Maximum shift on a fully saturated shadow pixel: ~0.018 in Oklab b units ≈ ~4° hue rotation

**Why `lab.b` not `h`:** operating on the cartesian `b` axis avoids a atan2/cos/sin
round-trip. The shift direction (negative b = blue-green) is constant — the Purkinje peak
at 507 nm maps cleanly to the negative Oklab b direction. SPIR-V clean, no branches.

---

## Interaction with existing pipeline

- **Chroma lift (R36)**: Purkinje runs before the Hunt-based chroma lift. Chroma lift
  operates on `C` which is recomputed after the shift — the hue-shifted pixel then gets
  the scene-adaptive lift applied correctly.
- **Abney (R12)**: also operates in LCh and runs after chroma lift. Not affected.
- **Shadow lift**: operates on luma only, no interaction.
- **Neutrals**: `C = 0` → zero Purkinje shift by construction. Neutral shadow ramp
  is completely unaffected.

---

## Tuning lever

`PURKINJE_STRENGTH` (0–1, default 1.0) multiplied into the 0.018 constant.
At 0: passthrough. At 1: full 4° shift at luma = 0. Could be exposed in `creative_values.fx`
or baked (physiologically fixed constant — the argument for baking is that it is not
an artistic choice, it is a description of human vision).

---

## Validation targets

- Dark red object in shadow: should lose red hue, read as near-neutral dark with slight
  blue-grey bias
- Dark blue-green object in shadow: should retain hue better than dark red at same luma
- Pure neutral dark ramp: zero colour shift — C = 0 guarantees this
- Scene with mixed shadow/highlight: shift active only below luma 0.12, invisible in mids

---

## Risk

Low. Effect is bounded — maximum Oklab b shift is 0.018 (≈ 1.8% of the full b range).
Gated to `new_luma < 0.12` which in most scenes is the bottom 5–8% of pixels. No branches,
one multiply-subtract per pixel in the Oklab block. C recompute adds one `sqrt`.
