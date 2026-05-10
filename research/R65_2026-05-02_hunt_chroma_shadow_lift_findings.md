# R65 Findings — Hunt-Effect Chroma Coupling for Shadow Lift

**Date:** 2026-05-02
**Status:** Implement

---

## Root cause confirmed

The current chroma-stable tonal block (grade.fx ~line 322) scales Oklab L by
`r_tonal^(1/3)` while leaving a/b unchanged. In Oklab, saturation is defined as the
C/L ratio (chroma over lightness). When L rises and C stays fixed, C/L drops —
the lifted shadows become achromatic relative to their new luminance level.

Concrete example — dark olive pixel, r_tonal = 2 (lift doubles linear luma):
```
Before:  L_ok = 0.22,  C = 0.020  →  C/L = 0.091
After:   L_ok = 0.28,  C = 0.020  →  C/L = 0.071   (22% saturation loss)
Coupled: L_ok = 0.28,  C = 0.025  →  C/L = 0.089   (saturation preserved)
```

---

## Perceptual science support

### CIECAM02 — saturation is luminance-stable
CIECAM02 defines three distinct chromatic attributes:

| Attribute | Symbol | Luminance dependency |
|-----------|--------|----------------------|
| Colorfulness | M = C × F_L^0.25 | **Increases** with luminance |
| Chroma | C | Approximately luminance-independent |
| Saturation | s = √(M/Q) | **Approximately constant** across illumination levels |

Saturation is specifically designed to be stable under varying illumination — it is the
perceptually correct invariant when performing a luminance lift. Maintaining C/L in Oklab
maps directly onto CIECAM02 saturation stability. This is the mathematical basis for
coupling.

The Hunt effect (M ∝ F_L^0.25) is a secondary consideration: at lifted shadow
luminances, colors become slightly more colorful for free. This argues for **slightly
below full coupling** (n < 1/3) to avoid HK overcorrection.

### darktable UCS (Aurelien Pierre, 2022)
Saturation in perceptual spaces is parametrized as the angle γ = arctan(C/L) around
the black point. Lifting L without scaling C reduces this angle. To maintain
saturation, C must scale proportionally with L — geometrically identical to n = 1/3.

> "Saturation changes rotate vectors around the origin (black point)"

---

## Implementation

Insert immediately after the existing Oklab L scale (grade.fx line 324):

```hlsl
// R65: chroma coupling — maintain Oklab saturation (C/L) during shadow lift.
// n = 1/3 exactly preserves C/L when L scales by r_tonal^(1/3).
float r65_ab  = exp2(log2(max(r_tonal, 1e-5)) * 0.333);
float r65_sw  = smoothstep(0.30, 0.0, lab_t.x);
lab_t.y = lab_t.y * lerp(1.0, r65_ab, r65_sw);
lab_t.z = lab_t.z * lerp(1.0, r65_ab, r65_sw);
```

This goes between lines 324 and 325 (after `lab_t.x` scaling, before `OklabToRGB`).

**GPU cost:** 2 muls + 1 smoothstep + 2 lerps inside existing Oklab block. Effectively
zero — all scalars, no new taps, no new passes.

### Why n = 1/3

| n value | Behaviour |
|---------|-----------|
| 0 | Current — C/L drops, ashy gray |
| 1/3 | Exact Oklab saturation preservation (C/L = const) — correct starting point |

**Correction from initial proposal:** the two arguments for n < 1/3 were unsound:

1. **"Hunt effect free colorfulness"** — wrong in this context. The Hunt effect's FL
   factor in CIECAM02 is a function of *adapting luminance* LA (global viewing
   conditions — room, screen). LA does not change per-pixel within a frame. Lifting a
   shadow pixel does not change FL; there is no free colorfulness to offset against.

2. **"HK cascade"** — weak. Stage 3 HK applies a *luminance* correction proportional
   to chroma (chromatic colors appear slightly brighter). It does not amplify chroma.
   Feeding marginally more chroma in nudges a pixel's apparent brightness by a small
   amount; it does not compound the saturation correction.

n = 1/3 is the correct starting value. Pull to ~0.20 only if empirical observation shows
shadow oversaturation.

### Shadow gate
`smoothstep(0.30, 0.0, lab_t.x)` applies the coupling only where `L_ok < 0.30`
(approximately linear luma < 0.027). At that level r_tonal is large (heavy lift) and
the correction is most needed. At midtones and highlights, `r65_sw → 0`, coupling
silently disengages.

---

## Null result: neutral pixels

If `lab_t.y ≈ 0` and `lab_t.z ≈ 0` (genuinely achromatic shadows), scaling them has
no effect. Purely neutral dark regions remain neutral after lift — the coupling cannot
inject color that was not there. This is correct and expected.

---

## Interaction with existing stages

| Stage | Interaction |
|-------|-------------|
| Stage 2 shadow lift (R57–R60) | Coupling runs after L scaling, using same `lab_t` block. Gated to shadow region. |
| Stage 3 Purkinje (R52) | Operates on Oklab b-axis separately; shadow gate here means minimal overlap. |
| Stage 3 HK | Receives slightly higher C from lifted shadows — this is desirable; HK adjusts apparent brightness, not chroma. No cascade. |
| Stage 3 chroma lift / density | These operate on all pixels via `lab` (separate from `lab_t`). No interaction. |

---

## Verdict

Implement with n = 1/3. Two multiplies inside the existing Oklab block.
If shadow regions read over-saturated: pull n toward 0.20.
`creative_values.fx` does not need a new knob — n can be hardcoded as a define in
grade.fx if tuning is needed, then baked once stable.
