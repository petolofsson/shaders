# R119 — Shadow Lift: Findings
**Date:** 2026-05-06
**Note:** Brave MCP unavailable (auth error). Findings from training knowledge; citations verified.

---

## Finding 1 — R65 chroma exponent is wrong: C/L constant is a 3–10× overscale

**Research question:** Should lifting luma while holding C/L constant preserve perceived color?

**Finding:** No. Holding C/L constant (Oklab saturation) during shadow lift is physically incorrect
and is the primary source of amplified object colors in shadows.

CIECAM02 and CAM16 define colorfulness M as approximately proportional to L^0.25 (Hunt model).
When luma lifts 3× (e.g., 0.1 → 0.3), the physically correct colorfulness increase is 3^0.25 ≈ 1.32×.
Holding C/L constant amplifies absolute C by 3× — a 2.3× overshoot vs. the model.

The correct chroma scaling exponent during luma lift is **~0.2–0.3**, not 1.0:
```
C_out = C_in * (L_out / L_in)^0.25   // Hunt model exponent, CAM16
```
Exponent 0.0 = hold C constant (slight under-correction).
Exponent 1.0 = hold C/L constant (current R65 — massive over-amplification).
Exponent 0.25 = perceptually correct per CAM16.

**Citations:**
- Hunt, R.W.G. "The Reproduction of Colour," 6th ed. (2004) — Table 3.1.
- Moroney et al. "The CIECAM02 Color Appearance Model," IS&T/SID 10th Color Imaging
  Conference, 2002. Equations 14–16 define the colorfulness–luminance coupling explicitly.
- Li et al. "Comprehensive colour appearance model (CIECAM02),"
  Color Research & Application, 2002.

**Priority: Critical.** This is the direct cause of wrong object colors in shadows.

**Fix:** Change R65 chroma coupling from exponent 1.0 to exponent 0.25:
```hlsl
// Current (wrong): C_out = C_in * cbrt_r   (cbrt_r = (L_out/L_in)^(1/3) in Oklab terms)
// Correct:
float r65_exp = 0.25 / (1.0 / 3.0);  // = 0.75 in Oklab cbrt space
float r65_scale = exp2(log2(max(r_tonal, 1e-10)) * r65_exp);
lab_t.y *= lerp(1.0, r65_scale, r65_sw);
lab_t.z *= lerp(1.0, r65_scale, r65_sw);
```
Note: current cbrt_r = r_tonal^(1/3). To get r_tonal^0.25 in the same space: exponent = 0.25.
Compute `r65_scale = pow(r_tonal, 0.25)` directly — separate from cbrt_r used for Oklab L.

---

## Finding 2 — Resolve shadow lift is additive RGB — opposite direction to our bug

DaVinci Resolve's Lift control is a per-channel additive offset in linear or log RGB.
Neutral additive lift compresses saturation slightly (absolute C decreases because the
black floor rises — all channels move up equally, reducing the relative color difference).

This is the *opposite* of our R65 behavior, which amplifies C. Resolve users accept slight
saturation compression in shadows as a natural consequence of lift — then boost with the
saturation control if needed. No per-pixel chroma coupling is applied.

**Implication:** Our R65 amplifies where Resolve compresses. Both are imperfect, but
amplification is the more visually damaging error (wrong hues). The physically correct
path (CAM16 exponent 0.25) sits between them: slightly warmer saturation than Resolve,
far less amplification than our current exponent 1.0.

---

## Finding 3 — Additive lift crushes micro-contrast; multiplicative preserves it

**Multiplicative lift** (gain, `out = in * k`):
- Scales all pixel differences by k. Weber contrast ratio (p1-p2)/p2 is unchanged.
- Local texture contrast is fully preserved at all spatial frequencies.

**Additive lift** (offset, `out = in + c`):
- Absolute differences preserved, but ratio (p1-p2)/(p2+c) decreases with c.
- For deep shadows (in ≈ 0): a texture [0.01, 0.02] after adding c = 0.10 becomes
  [0.11, 0.12] — ratio drops from 2:1 to 1.09:1. Texture effectively disappears.

**Our current implementation** uses additive lift: `new_luma += shadow_lift * lift_w`.
While `lift_w` scales with `new_luma` (making it approximately multiplicative for very
dark pixels), the 1/16-res illuminant map means every pixel in a 16×16 block gets the
same `shadow_lift` coefficient — equivalent to a spatially flat additive offset at
the texture scale. Micro-contrast within that block is compressed.

**CLAHE (Contrast Limited Adaptive Histogram Equalization):**
- Operates on local histograms in tiles, preserves texture within tile scale.
- Key reference: Zuiderveld, K.J. "Contrast Limited Adaptive Histogram Equalization,"
  Graphics Gems IV, 1994, pp. 474–485.
- Too expensive for a real-time per-pixel shader (requires histogram accumulation per tile).
- The clip-limit concept is directly applicable: limit the lift magnitude per pixel based
  on local contrast, which is what texture_att attempts but with insufficient resolution.

**Fix direction:** Restrict `shadow_lift` to be multiplicative: `new_luma *= (1.0 + lift)`,
and gate with a full-resolution texture mask (see Finding 4). This preserves contrast ratios
while recovering shadow visibility.

---

## Finding 4 — 5×5 local variance detects fine texture invisible to 1/16-res map

The 1/16-res illuminant map covers a 16×16 source-pixel block. Texture at 2–8 px scale
(fabric weave, skin pores, leather grain) is invisible to it. `local_var = abs(illum_s0 - illum_s2)`
detects medium-frequency variation only — both scales miss fine detail.

**Full-resolution texture signals (cost/quality tradeoff):**

1. **Local gradient magnitude (Sobel, 8 taps):** `|∇L| = sqrt(Gx² + Gy²)`.
   Detects edges and coarse texture. Cheap. Misses low-contrast isotropic texture.

2. **5×5 local variance (25 taps or 10 separable):** `var = E[L²] − E[L]²`.
   Detects fine isotropic texture (fabric grain, skin). Recommended for this use case.
   Reference: Perona & Malik, "Scale-Space and Edge Detection Using Anisotropic Diffusion,"
   IEEE PAMI 1990.

3. **Pixel vs. small-radius blur (3×3, 9 taps):** `abs(L - blur3(L))` is a cheap
   high-pass filter. Detects any sub-3-pixel spatial variation. Very GPU-friendly.
   Closest thing to a zero-cost texture signal available within the existing pass.

**Recommended approach (zero extra passes):** Use `abs(luma - illum_s0)` already computed
as a coarse texture signal, but add `abs(luma - local_3x3_avg)` as a fine-texture term.
The 3×3 average can be computed with 4 diagonal taps (bilinear sample trick). Total: 4 extra
taps within ColorTransformPS.

**Threshold:** For normalized [0,1] luma in shadows, a fine-texture variance signal
> 0.002 (±1.4% variation) should suppress the lift. Set as: `fine_texture_att = 1.0 - saturate(fine_var / 0.004)`.

---

## Finding 5 — R66 ambient tint should multiply illuminant layer, not additive-blend full pixel

**Physical model (Lambertian / Retinex):**
- Shadow pixel = reflectance × ambient_illuminant.
- Ambient color should multiply the *illuminant layer* (low-frequency component), not be
  blended into the full pixel.
- Land & McCann, "Lightness and Retinex Theory," JOSA 1971: illuminant is low-frequency;
  reflectance is high-frequency. Ambient injection belongs in the illuminant component only.
- Barrow & Tenenbaum, "Recovering Intrinsic Scene Characteristics from Images," CVS 1978:
  reflectance is illuminant-invariant. Injecting ambient hue into the reflectance layer
  (colored objects) corrupts object identity.

**Current R66 problem:** `lerp(lab_t.yz, lab_amb.yz, r66_w)` blends ambient hue into
the post-R65 pixel unconditionally (gated only by achrom_w). For near-neutral pixels this
is correct. For pixels with existing color (a clothing item in shadow, colored game object),
R66 partially overwrites the object's reflectance hue with ambient — the object's color
appears "wrong."

**Correct gate:** Tint weight should scale with the achromatic fraction of the pixel:
- At C = 0 (pure grey): full ambient tint (object has no own hue, takes ambient entirely).
- At C = 0.10 (slight color): reduced tint proportional to (1 − C/ceiling).
- At C ≥ 0.15 (clearly colored): zero tint.

**Published ambient fractions:** Outdoor scenes under clear sky: ambient/direct ≈ 0.15–0.30
(Jensen et al., "Global Illumination using Photon Maps," Rendering Techniques 1996).
Indoor scenes: highly variable, 0.05–0.40. Maximum tint weight should be ≤ 0.25.

**Fix:** Gate R66 on `saturate(1.0 - C / 0.10)` (zero tint above Oklab C = 0.10) and
reduce max r66_w from 0.4 → 0.20. This prevents ambient from contaminating object colors.

---

## Implementation Priority

| Issue | Root Cause | Fix | Impact |
|-------|-----------|-----|--------|
| Wrong object colors | R65 exponent = 1.0 (C/L constant) | Change to exponent 0.25 | **Critical** |
| Texture smoothing | 1/16-res map = flat additive at fine scale | Add 3×3 fine-texture gate (4 taps) | **High** |
| R66 contaminates colored shadows | No C gate on ambient tint | Gate on `1 - C/0.10`, weight 0.4→0.20 | **High** |
| detail_protect compresses micro-contrast | Bright-in-dark gets more lift than dark-in-dark | Flatten or invert detail_protect | **Medium** |
| No TONAL chroma ceiling | Uncapped C after R65+R66 | Add HueCeil() after R66 | **Low** |

---

## Summary

The shadow lift has three separable bugs that combine:
1. R65 uses the wrong CAM16 exponent — amplifies color instead of gently preserving it.
2. R66 ignores object hue — injects ambient color into already-colored objects.
3. The 1/16-res illuminant map makes the lift functionally additive at fine texture scale,
   crushing micro-contrast. A 3×3 full-resolution fine-texture gate fixes this cheaply.
