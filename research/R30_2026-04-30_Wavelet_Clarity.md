# R30 — Wavelet Multi-Scale Decomposition for Clarity
**Date:** 2026-04-30
**Type:** Proposal
**ROI:** Medium — same GPU cost, cleaner frequency separation, no cross-scale bleed

---

## Problem

The clarity stage uses a hand-rolled 2-level Laplacian pyramid:

```hlsl
float detail = lerp(luma - illum_s0, illum_s0 - illum_s2, 0.6);
```

Where:
- `luma - illum_s0` = fine detail (full-res minus 1/8-res)
- `illum_s0 - illum_s2` = coarse detail (1/8-res minus 1/32-res)
- The `lerp(…, 0.6)` blends between the two — a tuning guess with no theoretical basis

The problem: `illum_s0` is a box-filter downsample (mip 0), not a proper low-pass. Box filters
have poor frequency response — they pass energy at multiples of the cutoff frequency (aliasing
lobes). So `luma - illum_s0` is not a clean bandpass. Energy from one scale bleeds into another,
and the `lerp` weight is compensating for that bleed empirically rather than separating it cleanly.

---

## Haar wavelet decomposition

A 1D Haar wavelet decomposes a signal into:
- **Low pass:** `L = (A + B) / 2` — the average (same as a 2-tap box filter)
- **Detail:** `D = (A - B) / 2` — the difference

The mip chain IS a box-filter low-pass — `illum_s0` ≈ `(A+B)/2` at 1/8 scale. The key insight:
**the detail coefficient is `D = luma - illum_s0` only if `illum_s0` is the true Haar low-pass.**
A bilinear mip is close but not exact — it introduces sub-pixel energy that bleeds into D.

The proper 2-level Haar detail signals are:

```
D1 = luma     - illum_s0     (fine band:   full-res minus 1/8-res low-pass)
D2 = illum_s0 - illum_s1     (mid band:    1/8-res minus 1/16-res low-pass)
D3 = illum_s1 - illum_s2     (coarse band: 1/16-res minus 1/32-res low-pass)
```

Note: the current implementation uses `illum_s0 - illum_s2` for the coarse band, skipping mip 1.
This conflates D2+D3 into one term and explains why the 0.6 blend is needed — it's compensating
for the mixed-frequency content.

---

## Proposed replacement

```hlsl
// 3-level Haar approximation — each detail band is orthogonal to the others
float D1 = luma     - illum_s0;   // fine:   full-res → 1/8-res
float D2 = illum_s0 - illum_s1;   // mid:    1/8-res  → 1/16-res
float D3 = illum_s1 - illum_s2;   // coarse: 1/16-res → 1/32-res

// Weighted recombination — D1 sharpens micro-detail, D3 sharpens macro-contrast
float detail = D1 * 0.5 + D2 * 0.3 + D3 * 0.2;
```

The weights are still tunable, but now each term is a clean frequency band rather than a
mixed signal. D1 alone = micro sharpening. D3 alone = large-scale contrast lift. The weights
have semantic meaning: how much of each frequency band to enhance.

Note: `illum_s1` (mip 1) is already read by the R29 Retinex block — zero extra texture taps.

---

## Advantages over current clarity

| | Current | Wavelet |
|--|---------|---------|
| Frequency bands | 2 (conflated) | 3 (orthogonal) |
| Cross-scale bleed | Yes — empirical lerp corrects it | No — bands are independent |
| Tuning | One magic `0.6` blend | Three semantically meaningful weights |
| GPU cost | 2 taps (mip 0, 2) | 3 taps (mip 0, 1, 2) — mip 1 already read by R29 |
| Extra passes | 0 | 0 |

---

## Risks

**Different look:** the current clarity result is tuned to the implicit 0.6 blend. The wavelet
version will produce a different output at equivalent weights. Needs visual re-tuning.

**Weight sensitivity:** three independent weights (vs. one blend) increases the tuning surface.
Recommend exposing only a single `CLARITY_STRENGTH` knob that scales all three uniformly, and
baking the relative ratios (e.g. 0.5/0.3/0.2) as defines.

---

## Research questions for web search

1. What relative weights (D1/D2/D3) do satellite imagery processors use for Haar-based
   detail enhancement? Is there a perceptually optimal ratio?
2. Are mip-level box filters close enough to Haar low-passes that the orthogonality
   assumption holds, or is a correction factor needed for the bleed?
3. Has Haar wavelet decomposition been applied to real-time sharpening/clarity in graphics?

---

## Success criteria

- Clarity block rewritten using D1/D2/D3 Haar decomposition
- No new texture reads (mip 1 already read by R29)
- No new passes
- `CLARITY_STRENGTH` single knob still works
- Visual result: finer detail and coarser contrast enhancement are independently controllable
