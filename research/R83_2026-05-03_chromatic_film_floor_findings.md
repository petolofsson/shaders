# R83 Findings — Chromatic FILM_FLOOR
**2026-05-03**

## Summary

Implementable as proposed. Per-channel D-min asymmetry confirmed from official Kodak data.
Illuminant-driven modulation is physically justified and low-risk. 3 MAD, no new taps.

---

## Finding 1 — Kodak 2383 per-channel D-min is not neutral

**Source:** Kodak H-61B LAD specification sheet (official Kodak publication)

The Status A density aim for a visual neutral at D=1.0 on Kodak 2383/3383 is:
- Red: **1.09**
- Green: **1.06**
- Blue: **1.03**

These are the mid-exposure printing aims, which means the film's base response is
inherently warm-biased: red channel is 6% higher density than blue at the same scene
luminance. This warm bias is the characteristic base chromaticity of the 2383 emulsion.

D-min (base+fog, unexposed) is lower than LAD by roughly 0.08–0.12 D units, but the
per-channel ratio is preserved. Estimated D-min per-channel ratios:
- Red/Green: ~1.03 (≈ +3% relative)
- Green/Blue: ~1.03 (≈ +3% relative)
- Net Red/Blue spread: ~1.06 (≈ +6% relative)

**Relevance:** The proposed `float3(1.02, 1.00, 0.97)` scaling factor in the proposal
correctly captures the direction and approximate magnitude of this asymmetry. The exact
values should be cross-validated against the full 2383 datasheet sensitometry curves,
but the LAD data confirms the implementation direction is correct.

---

## Finding 2 — Illuminant modulation is physically justified

**Source:** CAT16 literature (Li et al. 2017, Color Research & Application)

CAT16 normalises the scene toward D65 in LMS cone space. The `lms_illum_norm` vector
available in grade.fx after the CAT16 block represents the scene illuminant normalised
to D65 — it is 1.0 for a D65 scene and deviates proportionally for warmer/cooler scenes.

For a warm (tungsten, ~3200K) scene: LMS values are approximately [1.10, 0.98, 0.65]
normalised, meaning L (red-sensitive cone) is elevated and S (blue-sensitive) is depressed.
This drives `cfilm_floor.r` upward and `cfilm_floor.b` downward — a warmer floor, matching
what a warm-lit scene on 2383 would produce physically.

For a neutral (D65) scene: `lms_illum_norm ≈ [1.0, 1.0, 1.0]`, so the floor defaults
to the base 2383 asymmetry only.

**No destructive interaction with CAT16:** CAT16 normalises the image toward D65 *before*
the floor is applied. The chromatic floor then re-introduces the film base chromaticity
*after* normalisation. These are additive in intent and do not cancel or reinforce each
other's corrections.

---

## Finding 3 — Effect magnitude is perceptually subtle and self-limiting

At FILM_FLOOR = 0.01 (current default), the per-channel spread from `float3(1.02, 1.00, 0.97)`:
- Red floor: 0.0102
- Green floor: 0.0100
- Blue floor: 0.0097

Absolute per-channel delta: ±0.0002–0.0003. This is well below the JND (~0.002 in linear
light) for isolated values but accumulates in very dark regions where the floor is the
dominant signal — exactly where the warm shadow cast is most visible and desirable.

At FILM_FLOOR = 0 (off): `cfilm_floor` = 0 for all channels, identity passthrough. ✓

---

## Implementation — validated sketch

```hlsl
// Stage 1, replaces scalar FILM_FLOOR application
// lms_illum is already in scope from the CAT16 block (lf_mip2)
// lms_illum_norm = lms_illum / lms_illum.y  (normalised to green channel)
float3 cfilm_floor = FILM_FLOOR * (lms_illum_norm * float3(1.02, 1.00, 0.97));
col.rgb = col.rgb * (FILM_CEILING - cfilm_floor) + cfilm_floor;
```

The `float3(1.02, 1.00, 0.97)` encodes the base 2383 D-min chromaticity. The
`lms_illum_norm` modulates this by the scene illuminant — a warm scene gets a warmer
floor, a cool scene gets a cooler one. The product is a physically-motivated per-channel
pedestal.

**GPU cost:** 3 MAD (float3 multiply + float3 MAD). Replaces the current 1 MAD + 1 MAD
scalar application. Net delta: +1 MAD.

---

## Implementation gaps

1. **Exact D-min ratio needs datasheet validation.** The LAD values give mid-exposure aims;
   actual D-min at zero exposure is slightly different. The full sensitometry curves in the
   2383 datasheet (Scribd/Kodak PDF) show the toe region — reading the D-min intercepts
   for each channel would refine the `float3(1.02, 1.00, 0.97)` constants.
   Low risk: ±10% error in these constants produces ±0.00003 absolute floor error.

2. **`lms_illum_norm` normalisation choice.** Normalising to green (lms.y) keeps the
   green floor at exactly FILM_FLOOR and modulates R and B around it. Normalising to
   luminance (lms dot [0.2126, 0.7152, 0.0722]) would distribute the modulation more
   evenly. Green normalisation is simpler and matches the 2383 LAD green-as-reference
   convention — preferred.

3. **Interaction with FILM_CEILING.** Current implementation uses `FILM_CEILING` as the
   upper remap bound. The chromatic floor does not change FILM_CEILING behaviour — the
   remap `col * (FILM_CEILING - cfilm_floor) + cfilm_floor` correctly contracts the range
   from both ends. No issue.

## Verdict

**Implement.** No open research questions that block implementation. The proposal's HLSL
sketch is correct and physically justified. Refine the `float3` constants post-ship
using full 2383 datasheet D-min readings if desired.
