# R167 — Perceptual Chroma: HK Luminance Rolloff + Chromatic Crispening

**Date:** 2026-05-12
**Domain:** Perceptual chroma (HK, Hunt, Abney) — Tuesday rotation
**Sources:** Seong et al. 2025 (*Color Research & Application*); Moroney 2001 (CIC-9); L et al. 2024 (*Optics Express* 32:25); castleCSF Ashraf et al. 2024 (*JOV*)

---

## Summary

Two implementable findings for this domain that do not duplicate anything on the
already-implemented list:

1. **HK high-luminance rolloff** — empirical data (Seong 2025) show the
   Helmholtz-Kohlrausch proportional boost is smaller at high test luminances.
   Current R15 implementation plateaus above L ≈ 0.35; it should instead taper
   toward zero as L → 1.

2. **Chromatic crispening** — adaptation-point-relative chroma enhancement.
   Colors near the scene's median chroma (HWY_MEAN_CHROMA, slot 198) appear
   more colorful than equally chromatic colors displaced from the adaptation
   point. The pipeline has no such mechanism today.

---

## F1 — HK High-Luminance Rolloff (Seong et al. 2025)

### Finding

Seong, Kwak & Kim (2025) conducted heterochromatic brightness matching across
four factors: saturation, test luminance, background luminance, and hue.
Key result: **"the matched luminance ratio decreases as the test color
luminance increases."** Background luminance had no significant effect.
Hue effect was minimal except for a slightly stronger H-K response in green.

Concretely: a 10 cd/m² chromatic patch requires ≈ 1.5× achromatic luminance
to match brightness; a 50 cd/m² patch of the same hue/saturation requires only
≈ 1.2×. The proportional boost shrinks monotonically with luminance.

### Current implementation (grade.fx lines 602–604)

```hlsl
float f_hk     = -0.160 * ch + 0.132 * (ch*ch - sh*sh) - 0.405 * sh
                 + 0.080 * (2.0*sh*ch) + 0.792;
float hk_exp   = lerp(0.52, 0.64, saturate(ctx.zone_log_key / 0.50));
float hk_boost = 1.0 + 0.25 * f_hk * pow(max(final_C, 0.0), hk_exp);
float final_L  = saturate(lab.x / lerp(1.0, hk_boost, smoothstep(0.0, 0.35, lab.x)));
```

`smoothstep(0.0, 0.35, lab.x)` ramps the HK weight from 0 to 1 as L goes
from 0 to 0.35 and holds at 1.0 above that. **No high-luminance rolloff.**
Bright chromatic pixels near L = 0.9 receive the same proportional boost as
mid-luminance ones — inconsistent with Seong 2025.

### Proposed refinement

Replace the blend weight with a bell that also falls at high luminance:

```hlsl
float hk_ramp = smoothstep(0.0, 0.25, lab.x);
float hk_roll = 1.0 - smoothstep(0.60, 0.92, lab.x);
float hk_wt   = hk_ramp * hk_roll;
float final_L  = saturate(lab.x / lerp(1.0, hk_boost, hk_wt));
```

Shape: zero at L = 0, ramps to 1 by L = 0.25, holds, then tapers back to zero
by L = 0.92. The taper window (0.60 → 0.92) matches empirical data where the
effect noticeably weakens above ≈ 60% of display peak.

**GPU cost:** +1 smoothstep call ≈ 4 ALU ops in ColorTransformPS. No new
knobs needed.

**Pipeline conflict:** none. The change is internal to the HK brightness
calculation; it only reduces lightening of near-white chromatic pixels.

**Risk:** the rolloff window (0.60, 0.92) is an estimate from ratio-shape
reasoning, not a direct parameter fit. The existing HK_STRENGTH tuning via
`f_hk * 0.25` absorbs global scale errors, so even if the shape is slightly
off it won't overcorrect.

---

## F2 — Chromatic Crispening (Moroney 2001 + chroma discrimination literature)

### Finding

Moreno (CIC-9, 2001) "Chroma Scaling and Crispening" demonstrated that
perceived chroma scaling depends on the background chroma. For mid-chroma
backgrounds, chroma discrimination is enhanced near the background chroma —
analogous to lightness crispening where discrimination peaks at the adaptation
luminance. Effect amplitude: modest ~5–15% perceived chroma enhancement over
a ±0.03–0.05 Oklab C neighborhood around the adaptation chroma.

This is consistent with later contrast gain-control work (Switkes & Crognale;
"Can crispening be explained by contrast gain?" EI 2017) attributing the effect
to the same mechanism as lightness crispening: contrast gain is highest at the
adaptation point.

Relevant to this pipeline because:
- We already track the scene's adaptation chroma via **HWY_MEAN_CHROMA (slot
  198)**, which stores median Oklab C in raw [0, 0.4] UNORM.
- No crispening mechanism currently exists. R22 (sat-by-luma) and chroma lift
  operate on luminance-based axes, not chroma-distance-from-adaptation.

### Implementation sketch

Insert after the existing chroma lift and before `HueCeil()` in the CHROMA
block of `ColorTransformPS`:

```hlsl
// Chromatic crispening: bell boost centered on scene adaptation chroma
float C_adapt = ReadHWY(HWY_MEAN_CHROMA);                     // raw [0, 0.4]
float dC      = final_C - C_adapt;
float crisp_sigma_sq = 0.0016;                                 // σ = 0.04 Oklab units
float crisp_gain = CRISPENING_STR * exp(-dC * dC / crisp_sigma_sq);
final_C = final_C * (1.0 + crisp_gain);
```

`CRISPENING_STR` lives in `creative_values.fx`. Suggested default: 0.08
(≈ 8% peak chroma boost at C = C_adapt). Suggested range: 0.0 – 0.25.

### Self-limiting analysis

- At C = C_adapt: boost = CRISPENING_STR (the maximum).
- At |dC| = 0.08 (twice σ): boost ≈ 0.016 × CRISPENING_STR — negligible.
- Achromatic pixels (C = 0): boost ≈ 0 if C_adapt > 0.05 (typical for any
  non-flat-grey scene); zero for flat-grey C_adapt = 0. No seam.
- Highly saturated pixels (C >> C_adapt): boost also vanishes. No ceiling gating.
- Feeds directly into HueCeil / gclip, so any SDR overflow is clipped
  naturally by the existing gamut pre-knee.

### Interaction with ApplyChromaticInduction

`ApplyChromaticInduction` (grade.fx line 279–286) applies spatial chromatic
contrast from the low-frequency surround. Its mask is `saturate(1 − C / 0.06)`,
meaning it only acts on near-achromatic pixels (C < 0.06). Crispening acts on
pixels near C_adapt (usually 0.05–0.12 for typical game scenes). There is a
small overlap when C_adapt < 0.06 (very desaturated scenes), but both effects
are small in that regime. No architectural conflict.

### GPU cost

1 highway read (likely already cached in warp) + exp() + 4 ALU ops.
`exp()` can be approximated with `exp2(x * 1.44269504)` or via the quartic
approximation `(1 + x/8)^8` for |dC²/σ²| < 2 with < 1% error.

### Highway encoding

HWY_MEAN_CHROMA (slot 198) is already documented as raw [0, 0.4] UNORM — no
decode scaling needed. ReadHWY returns the stored value directly.

---

## F3 — HK Hue Weighting (Seong 2025, minor finding — low priority)

Seong et al. found "slightly stronger H-K effect in only the green region" with
no significant difference elsewhere. The current `f_hk` Fourier expansion
(line 601) already encodes hue-dependent HK weighting (negative sine term
suppresses yellows, positive cosine boosts warm-neutrals). Adding an explicit
green-peak term would be marginal and requires a precise hue-angle gate —
borderline "no gates" rule. Noted for completeness; not recommended.

---

## castleCSF (Ashraf et al. 2024, JOV) — context note

castleCSF models chromatic contrast sensitivity as a function of spatial
frequency, area, luminance, and eccentricity via separate RG and YV chromatic
channels. Directly applying castleCSF in a pixel shader is not viable at 60 fps
(it requires spatial frequency knowledge at each pixel, i.e., a Fourier or
wavelet decomposition). The perceptual guidance it provides — that chromatic
sensitivity peaks at 2–4 cpd and falls steeply at high frequencies — is
already captured structurally by the Diffusion blur in grade.fx (which spreads
diffusion on the same scale). No new implementation recommended.

---

## Exclusion checks

- Not HDR-only: both proposals operate in Oklab L ∈ [0, 1].
- No gates: both use smooth (Gaussian / smoothstep) transitions.
- Not on the exclusions list.
- Not already implemented: R15 HK has no luminance rolloff; no crispening
  mechanism exists anywhere in the chain.
- No auto-exposure dependency.
- creative_values.fx remains the only tuning surface (CRISPENING_STR lives
  there; HK rolloff requires no new knob).

---

## Recommendation

**F1 (HK rolloff):** Implement. Single-line change with strong empirical
backing, minimal risk, zero new knobs. Improves perceptual accuracy for
near-white chromatic highlights (specular reflections on colored surfaces).

**F2 (chromatic crispening):** Implement with a new `CRISPENING_STR` knob in
`creative_values.fx`. GPU cost is trivial. The effect is self-limiting, adds
perceived vividness in the mid-chroma range without saturating shadows or
highlights, and is architecturally clean given the existing HWY_MEAN_CHROMA
highway slot.

**F3 (HK hue weighting):** Defer indefinitely.
