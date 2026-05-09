# R138 — Hue Bands Calibration: Munsell Mid-Value Ceilings + Luminance-Aware Lower Arm

**Date:** 2026-05-09
**Status:** Proposal — awaiting research

---

## Problem

`hue_bands.fxh` has three layers of calibration quality:

1. **Upper arm (L > 0.75):** R133 / `HueBandRollN` — data-derived from Munsell Renotation
   V=8→9→10 C_max ratios. Well-grounded.

2. **Mid-value flat ceiling (`HueCeil`):** Six anchor bands (Red, Yellow, Green, Cyan, Blue,
   Magenta) have traceable reasoning (MacAdam ellipses, R118 correction). Six intermediate
   bands (Orange, Amber, Teal, Azure, Violet, Rose) were **estimated/interpolated** — no
   `real.dat` lookup behind them.

3. **Lower arm (L < ~0.45):** Not modeled at all. The flat ceiling assumes C_max is constant
   from L=0 up to the R133 onset. In Munsell, dark colors also have limited chroma —
   C_max rises from near-zero at V=0 to its peak at V=4–6, so the flat ceiling
   over-permits saturation in shadows.

The normalization bug (fixed 2026-05-09) is resolved. This proposal addresses the
remaining calibration gaps.

---

## Hypotheses

**H1:** The six intermediate band ceilings (Orange 0.16, Amber 0.15, Teal 0.15, Azure 0.17,
Violet 0.20, Rose 0.22) are inaccurate. Pulling C_max from `real.dat` at V=5–6 (the
typical Munsell peak, L≈0.55–0.61) for each hue group will yield different values and
correct the mid-value ceiling shape.

**H2:** The lower arm matters for at least one hue in the testbed. If the pipeline produces
saturated shadows (L < 0.40), the current flat ceiling permits overshoot that the Munsell
gamut does not support.

**H3:** A luminance-aware ceiling — combining the mid-value `HueCeil` with a lower-arm term
— can be expressed without a texture lookup, using a simple multiplicative factor
`f_low(L) = smoothstep(0.0, 0.45, L)` that ramps C_max from 0 at black to full ceiling
at L≈0.45. This adds ~2 ALU ops and no new sampler.

**H4 (to refute or confirm):** Adding the lower arm produces visible change on the testbed.
If the testbed has no saturated dark pixels (display-referred SDR from a tonemapper), H4
is refuted and the lower arm is deferred.

---

## Research tasks

### Task A — Calibrate intermediate band ceilings from real.dat

Pull Munsell Renotation `real.dat` (coloria-dev/color-data) and extract C_max at V=5
(L≈0.55) for the six intermediate hue groups. Map each hue group to the nearest
Munsell hue page. Convert Munsell C to Oklab C via the same chain used in R133:
Munsell → XYZ (Illuminant C) → linear sRGB → Oklab.

Target hue groups and current estimated ceilings:

| Band | Center (norm. hue) | Current HB_CEIL | Target Munsell page |
|------|--------------------|-----------------|---------------------|
| Orange | 0.181 | 0.16 | 5YR |
| Amber | 0.242 | 0.15 | 10YR |
| Teal | 0.469 | 0.15 | 5BG |
| Azure | 0.639 | 0.17 | 5PB |
| Violet | 0.825 | 0.20 | 5P |
| Rose | 0.997 | 0.22 | 5RP |

Also re-verify the six anchor bands (Red, Yellow, Green, Cyan, Blue, Magenta) against
the same data at V=5 — confirm they are consistent or note discrepancies.

### Task B — Profile the lower arm shape

From `real.dat`, extract C_max at V=2, V=3, V=4, V=5 for three representative hues
(Red, Yellow, Green). Fit a simple ramp shape to the V=0→V=5 segment. Confirm whether
`smoothstep(0.0, 0.45, L)` is a good approximation, or whether a different onset is
needed.

### Task C — Check testbed for saturated shadows

Using ImageMagick on a testbed screenshot, measure the Oklab C distribution for pixels
with L < 0.40. If median C < 0.08 in that region, H4 is refuted — the lower arm
has no practical effect and should be deferred.

---

## Proposed implementation (if research confirms)

### Step 1: Update HB_CEIL_* constants

Replace the six intermediate band estimated values with Munsell-derived values from
Task A. No code change — just constant updates in `hue_bands.fxh`.

### Step 2: Lower arm multiplier (only if H4 confirmed)

Add a luminance scale factor to `HueCeil`:

```hlsl
float HueCeil(float hue, float L)
{
    // ... existing 12-band normalized weighted sum → raw_ceil ...
    float low_arm = smoothstep(0.0, 0.45, L);   // 0 at black, 1 at L≥0.45
    return raw_ceil * low_arm;
}
```

All callsites pass `lab.x` as the second argument. The `max(ceil, incoming_C)` guard
at callsites already prevents clamping existing content — the lower arm would only
restrict expansion of already-dark pixels, which is correct behavior.

**Callsite updates required:**
- `inverse_grade.fx` line 94: `HueCeil(hue)` → `HueCeil(hue, lab.x)` (or equivalent L)
- `grade.fx` line 598: `HueCeil(h_out)` → `HueCeil(h_out, lab.x)`

ALU cost: +1 smoothstep (~3 ops), +1 multiply. Negligible.

### Step 3 (optional, only if H4 confirmed and lower arm shape is non-trivial)

If `smoothstep(0.0, 0.45, L)` doesn't fit the data, use a two-segment approximation:
- Below L=0.20: linear ramp from 0
- L=0.20–0.45: smoothstep to 1

---

## What is NOT proposed

- A full 2D (hue × L) ceiling surface. The current split — flat ceiling + R133 upper arm
  + optional lower arm factor — is a separable approximation sufficient for SDR display-
  referred content. A full Munsell surface would require a texture sampler or a per-hue
  polynomial, at significant ALU cost.
- Changes to `HueBandRollN` or R133 rolloff exponents — those are data-derived and correct.
- Changes to band centers or `HB_BAND_WIDTH` — not addressed here.

---

## Success criteria

- All 12 `HB_CEIL_*` values have a `real.dat`-traceable source, not interpolation.
- If H4 confirmed: lower arm fires only on dark-shadow pixels, no visible seam.
- If H4 refuted: proposal closes with Step 1 only (constant recalibration).
- No new passes, no new samplers, no new textures.
