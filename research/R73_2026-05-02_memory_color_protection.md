# R73 — Memory Color Protection

**Date:** 2026-05-02
**Status:** Proposed

## Problem

`chroma_str` is driven by `mean_chroma`: in low-chroma scenes (pale, overcast, shadowed),
`chroma_str` is high. If a small saturated region exists in an otherwise muted scene
(cyan sky behind grey clouds, green foliage at frame edge), that region receives the
same high lift applied to the desaturated surroundings and pushes toward neon.

There is no per-hue saturation ceiling. The pipeline has no concept of "this hue is
already at its perceptual optimum — stop lifting."

## Memory colors

These are the hue regions where incorrect saturation is most visually conspicuous
because observers have strong chromatic memories for them:

| Band | Memory color | Target Oklab C |
|------|-------------|----------------|
| RED | Saturated reds | 0.28 (rarely fires; sRGB red ~0.26) |
| YELLOW | Warm sunlight, gold | 0.22 |
| GREEN | Foliage, grass | 0.16 |
| CYAN | Sky, water | 0.18 |
| BLUE | Deep sky, shadow blue | 0.26 |
| MAGENTA | Flowers, neon | 0.22 |

## Solution

Compute a per-pixel chroma ceiling via band-weight interpolation, then cap `final_C`:

```hlsl
float C_ceil = hw_o0 * 0.28 + hw_o1 * 0.22 + hw_o2 * 0.16
             + hw_o3 * 0.18 + hw_o4 * 0.26 + hw_o5 * 0.22;
float final_C = min(vib_C, max(C_ceil, C));
```

`max(C_ceil, C)` ensures original input chroma is never reduced — only the lift delta
is constrained. A pixel already at C=0.20 in the cyan band (C_ceil=0.18) keeps its
C=0.20; the lift is suppressed. A pixel at C=0.10 in the cyan band can lift to 0.18.

The `hw_oX` weights are already computed from `h_out` (post-R21 hue rotation) —
no additional band weight computation needed.

## GPU cost

6 MADs for the weighted ceiling + 1 min + 1 max = ~8 ALU ops. No new taps, no new knobs.

## Success criterion

In scenes with a muted overall palette and a vivid sky or foliage region: those regions
do not push neon when chroma_str is high. Saturated game elements in vivid scenes are
unaffected (ceiling fires only when lift would push past the target).
