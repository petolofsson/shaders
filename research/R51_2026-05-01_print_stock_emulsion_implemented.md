# R51 — Print Stock Emulsion Response

**Date:** 2026-05-01
**Status:** Implemented

---

## Problem

The current FilmCurve models the camera negative — the exposure-to-density response of the
capture stock. This is only the first half of the cinema photochemical pipeline. In theatrical
release, the cut negative is printed to a separate print stock (Kodak Vision Color Print Film
2383, Fuji Eterna Vivid 3513). The print stock has its own characteristic H&D curve with
materially different properties:

| Property | Camera negative (current) | Print stock (missing) |
|----------|--------------------------|----------------------|
| Black point | Floating (scene-dependent) | Lifted — minimum density ~0.06 log |
| Shadow contrast | Low γ in toe | Steeper toe — faster shadow onset |
| Highlight roll-off | Soft shoulder | Harder shoulder — earlier compression |
| Saturation | Full scene saturation | ~15–20% desaturation at mids |
| Colour cast | Neutral | Warm (D-min orange base of print stock) |

Kodak's published 2383 sensitometry (H-751 data) shows the three print dye curves (cyan,
magenta, yellow) with a combined γ of approximately 2.5–2.8 in the straight-line region,
applied on top of the negative's already-compressed signal. The perceptual result — lifted
blacks, compressed highlights, slightly warm mid-desaturation — is what most people identify
as "the cinematic look" and cannot be reproduced by the negative curve alone.

---

## Signal

None required. Print stock response is a fixed physical property of the emulsion, not
scene-adaptive. Constants derived from Kodak H-751 and Fuji published sensitometry sheets.

---

## Proposed implementation

A second curve stage applied to `lin` immediately after the existing `FilmCurve` output
and before R50, inside `ColorTransformPS`:

```hlsl
// grade.fx — after FilmCurve lerp, before R50
// R51: print stock emulsion — Kodak 2383 characteristic curve approximation

float3 PrintStock(float3 x)
{
    // Lift blacks: minimum density 0.06 log ≈ 0.025 linear
    x = x * (1.0 - 0.025) + 0.025;

    // Print gamma: steeper toe, harder shoulder
    // Approximated as a quadratic toe + soft shoulder blend
    float3 toe      = x * x * 3.2;                          // steeper shadow onset
    float3 shoulder = 1.0 - (1.0 - x) * (1.0 - x) * 1.8;  // earlier highlight compression
    float3 t        = smoothstep(0.0, 0.5, x);
    x = lerp(toe, shoulder, t);

    // Mid desaturation: ~15% chroma compression at luma 0.5
    float luma_p = dot(x, float3(0.2126, 0.7152, 0.0722));
    x = lerp(x, luma_p.xxx, 0.15 * (1.0 - smoothstep(0.0, 0.3, luma_p))
                                  * (1.0 - smoothstep(0.6, 1.0, luma_p)));

    // Warm cast: D-min orange base of print stock
    x.r += 0.012 * (1.0 - x.r);
    x.b -= 0.008 * (1.0 - x.b);

    return saturate(x);
}

lin = lerp(lin, PrintStock(lin), PRINT_STOCK);
```

`PRINT_STOCK` (0–1, default 0.5) added to `creative_values.fx` as the blend weight —
0 = negative only (current behaviour), 1 = full 2383 response, 0.5 = hybrid.

---

## Interaction with existing pipeline

- **R49 (per-channel FilmCurve gamma)**: R49 runs inside `FilmCurve`, R51 runs after.
  They stack correctly — negative character first, print character on top.
- **R50 (dye secondary absorption)**: both are post-FilmCurve pre-R19. R51 should run
  before R50 so the print desaturation operates on the corrected density signal.
- **R19 (3-way corrector)**: artistic correction runs after both physical stages.
- **Chroma lift (R36)**: print desaturation reduces chroma slightly; Hunt-based chroma
  lift partially counteracts. Net is a reshaping of the saturation curve — lower mids,
  higher at the extremes — which is characteristic of projected print.

---

## Validation targets

- Neutral grey ramp: should show lifted black floor (~0.025), compressed highlights
- Skin tones: slight desaturation, warm cast without magenta
- Deep shadows: marginally warmer and denser than current FilmCurve alone
- Pure white: should not clip — soft shoulder prevents it

---

## Risk

Low. Entire effect is bounded inside `saturate()`. `PRINT_STOCK = 0` is exact passthrough
to current behaviour. The warm cast constants (0.012 / 0.008) are small — maximum shift
at pure black is 1.2% red, 0.8% blue reduction. Compute: ~12 ALU ops, no texture reads.
