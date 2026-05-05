# R80 Findings — Pro-Mist Spectral Scatter Model

**Date:** 2026-05-03
**Status:** Implement (R80B/C confirmed; R80A direction corrected from proposal)

---

## R80A — Wavelength-dependent scatter (direction corrected)

**Research finding:** Diffusion filter polymer particles (~1–20 µm) are in the Mie/
geometric optics regime for visible wavelengths. At d=10 µm and λ=550 nm, the size
parameter x ≈ 57 — firmly in geometric optics where scattering efficiency is
**wavelength-neutral**. The λ⁻⁴ Rayleigh blue-biased scatter does not apply at this
scale. No published spectral MTF measurements for Pro-Mist or comparable filters found.

**Practical character from cinematographers:** Pro-Mist bloom is consistently described
as **warm (red/orange)**, not blue/cool. Tiffen's own product description for Black
Pro-Mist calls out "warm tone becoming more apparent at higher densities." The physical
cause is scene light temperature (tungsten/warm practicals dominate the highlights
being scattered), not particle physics.

**Correction to proposal:** The proposal assumed blue-biased scatter (Rayleigh). This
is wrong at the relevant particle scale. If spectral tinting is added, it must be a
**warm bias** (mild red/orange lean in the scatter), not a cool one.

**Implementation:** Apply a mild warm tint to the scatter delta:
```hlsl
// R80A: warm scatter bias — practical lights are warm; scatter inherits their colour
float3 mist_delta_raw = ...; // existing scatter delta
mist_delta = mist_delta_raw * float3(1.05, 1.0, 0.92);  // slight warm bias
```
Magnitudes: +5% red, neutral green, −8% blue. Very subtle — within the perceptual
JND for this type of effect. Tunable.

---

## R80B — Scene-key adaptive strength (derived)

The proposal formula `pow(zone_log_key, -0.3)` produces a 2× swing at typical zone_log_key
values (0.02–0.25), which is too aggressive. A controlled ±30% variation is appropriate.

Revised formula:
```hlsl
float mist_key_scale = lerp(1.30, 0.80, smoothstep(0.05, 0.25, zone_log_key));
```

| zone_log_key | mist_key_scale | Effect |
|-------------|----------------|--------|
| 0.02 (very dark) | 1.30 | +30% more mist |
| 0.05 (dark indoor) | 1.30 | +30% |
| 0.12 (normal indoor) | ~1.05 | +5% |
| 0.20 (bright) | ~0.88 | −12% |
| 0.25+ (exterior) | 0.80 | −20% |

Rationale: mist visually dominates in low-luminance environments (candlelight, indoor
practicals with dark surround). High-key exterior daylight makes mist less visible
perceptually. The ±30% range is conservative — matches the real perceptual difference
between dark-room and exterior mist visibility without being scene-altering.

---

## R80C — Aperture proxy via EXPOSURE (derived)

EXPOSURE range in creative_values.fx: typically 0.7–1.3.
- EXPOSURE < 1.0: boosting dark/dim scenes → wider aperture equivalent → scatter wider
- EXPOSURE = 1.0: neutral
- EXPOSURE > 1.0: darkening bright scenes → narrower aperture → scatter tighter

A ±10% modulation is appropriate (small effect — EXPOSURE correlates only loosely with
aperture):

```hlsl
float mist_ap_scale = lerp(1.10, 0.90, saturate((EXPOSURE - 0.70) / 0.60));
```

| EXPOSURE | mist_ap_scale |
|---------|--------------|
| 0.70 | 1.10 (+10%) |
| 1.00 | 1.00 (neutral) |
| 1.30 | 0.90 (−10%) |

---

## Combined implementation

Applied to `mist_str` before the scatter calculation:

```hlsl
// R80B: scene-key adaptive
float mist_key_scale = lerp(1.30, 0.80, smoothstep(0.05, 0.25, zone_log_key));
// R80C: aperture proxy
float mist_ap_scale  = lerp(1.10, 0.90, saturate((EXPOSURE - 0.70) / 0.60));
mist_str *= mist_key_scale * mist_ap_scale;
```

R80A (warm tint) applied to the scatter delta after computation.

---

## GPU cost

R80A: ~3 ALU (float3 multiply). R80B: 1 smoothstep + 1 lerp. R80C: 1 lerp + 1 saturate.
No new texture taps.
