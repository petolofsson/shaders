# R73 Findings — Memory Color Protection

**Date:** 2026-05-02
**Status:** Implemented

---

## Implementation

Inserted after R71 `vib_C` computation, replacing `final_C` (grade.fx ~line 434):

```hlsl
float C_ceil = hw_o0 * 0.28 + hw_o1 * 0.22 + hw_o2 * 0.16
             + hw_o3 * 0.18 + hw_o4 * 0.26 + hw_o5 * 0.22;
float final_C = min(vib_C, max(C_ceil, C));
```

---

## Ceiling calibration

Ceiling values derived from perceptual optima for naturalistic memory colors:

| Band | Ceiling | Basis |
|------|---------|-------|
| RED (0.28) | Rarely fires — sRGB red Oklab C ≈ 0.26 | Unconstrained in practice |
| YELLOW (0.22) | Vivid sunlight without artificial neon | CIECAM02 reference white |
| GREEN (0.16) | Dense foliage chroma range | Munsell 5GY at value 5 |
| CYAN (0.18) | Clear sky optimum | CIE sky chromaticity data |
| BLUE (0.26) | Deep sky — wide range, rarely over-saturated in SDR | Conservative |
| MAGENTA (0.22) | Moderate — flowers and neon share this band | Conservative |

---

## `max(C_ceil, C)` guard

The ceiling is `max(C_ceil, C)` not `C_ceil` directly. This ensures:
- If input C already exceeds C_ceil (unusual in SDR, e.g. engine-rendered primaries
  that push past perceptual optimum): ceiling = C, no lift allowed. Input chroma
  is never reduced by R73.
- If input C < C_ceil: ceiling = C_ceil, normal lift up to the target.

---

## Interaction with R71

R73 caps `vib_C` (already self-masked by R71). In practice R71 suppresses most of
the lift for saturated pixels before R73 fires. R73 provides the absolute ceiling for
the cases where a moderately-saturated memory color (C=0.10 cyan) would otherwise
lift past 0.18 under high `chroma_str`.

---

## Verdict

Implemented. Ceiling values are internal constants — adjustable if specific hue
regions show insufficient or excessive lift after visual testing.
