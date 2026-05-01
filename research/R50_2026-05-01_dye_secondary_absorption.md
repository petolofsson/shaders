# R50 — Dye Secondary Absorption Softening

**Date:** 2026-05-01
**Status:** Implemented

---

## Problem

After `FilmCurve`, `lin` goes directly into the R19 3-way colour corrector with no inter-layer
coupling. In real chromogenic film, every dye has secondary (unwanted) absorptions:

| Dye | Primary absorption | Secondary absorptions |
|-----|-------------------|----------------------|
| Cyan (red-sensitive layer) | Red | ~5–8% green, ~3% blue |
| Magenta (green-sensitive layer) | Green | ~4–6% red, ~2% blue |
| Yellow (blue-sensitive layer) | Blue | ~3% red, ~2% green |

These secondary absorptions reduce the *apparent* density of the dominant dye layer when
complementary dyes are also present — i.e., in coloured (non-neutral) pixels. The IS&T Color
Imaging Conference (vol. 4) states: "for accurate colour reproduction and compensation of
secondary absorption, at least a 3×3 matrix should be implemented."

The perceptual consequence: mid-saturation colours (oranges, teals, skin, foliage) have a gentle
dominant-channel softening. Pure primaries (only one layer fires) and neutrals (secondary
absorptions cancel) are unaffected. This creates the characteristic depth-without-harshness of
Kodak print colours — a quality not present in purely digital rendering.

---

## Signal

Per-pixel chromatic saturation proxy: `sat_proxy = max(rgb) − min(rgb)`. Zero for neutrals,
maximum for pure primaries. The attenuation ramps in smoothly above a colour masking threshold
of ~0.18 (the activation point observed in masking coupler models, e.g. agx-emulsion project,
Volpato 2024).

---

## Proposed implementation

New block between `FilmCurve` result assignment and the `// ── R19` block in `ColorTransformPS`:

```hlsl
// grade.fx: after FilmCurve lerp, before R19

// R50: dye secondary absorption — dominant channel soft attenuation
// Neutral-preserving: sat_proxy = 0 → no effect. Pure primaries: physically correct ~5% loss.
{
    float lin_max  = max(lin.r, max(lin.g, lin.b));
    float lin_min  = min(lin.r, min(lin.g, lin.b));
    float sat_proxy = lin_max - lin_min;
    float ramp     = saturate(sat_proxy / 0.18);
    float3 dom_mask = saturate((lin - lin_min) / max(sat_proxy, 0.001));
    lin = saturate(lin - 0.06 * dom_mask * sat_proxy * ramp);
}
```

Walkthrough for representative inputs:

| Pixel | sat_proxy | Δ dominant | Δ secondary |
|-------|-----------|-----------|-------------|
| Neutral 0.5³ | 0.00 | **0.000** | 0 |
| Skin (0.65, 0.45, 0.35) | 0.30 | R −0.018 | G −0.006 |
| Orange (0.85, 0.55, 0.10) | 0.75 | R −0.045 | G −0.027 |
| Pure red (0.90, 0, 0) | 0.90 | R −0.054 | 0 |

---

## Placement rationale

Inserted *after* FilmCurve because the secondary absorption is a property of the dye layers
operating on the tone-curved signal (post-exposure density), not on linear scene light. Inserted
*before* R19 because the 3-way corrector's additive offsets are an artistic correction on top of
the physical base rendering — they should operate on the post-absorption image.

---

## Interaction with existing pipeline

- **Chroma lift (R36)**: R50 reduces saturation slightly at mid-saturation. R36 lifts chroma
  based on scene mean_chroma. The two partially counteract — R50 creates a more film-like
  saturation curve (lower mid, higher pure-primary) while R36 applies a global lift. Net effect
  is a reshaping rather than reduction of overall saturation.
- **Density**: R50 reduces the dominant channel, slightly increasing perceived density in
  mid-saturation regions — compatible with the density darkening that follows.
- **Neutrals**: unaffected by construction.

---

## Open questions

1. **Coupling constant 0.06**: derived from the mid-range of published secondary absorption values
   (~5–8%). Could be exposed as `FILM_DYE_COUPLE` (0–100, default 6) if artistic control is
   desired. Initial implementation bakes it in.
2. **Saturation ramp threshold 0.18**: from masking coupler activation models. May need tuning
   against actual game content — foliage and skin are the primary validation targets.
3. **Interaction with R49**: R49 changes per-channel toe lift, increasing shadow warmth. R50
   then softens mid-saturation oranges/teals. The two compound — R49 first (inside FilmCurve),
   R50 second (after). Validate together, not independently.

---

## Risk

Low. Attenuation is always a reduction of the dominant channel — never an amplification. Output
stays in [0,1] by construction (`saturate`). Maximum single-channel change on a fully-saturated
primary is −0.054. No hard stops, no branches, SPIR-V clean.
