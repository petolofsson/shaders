# R72 Findings — Reflectance-Based Local Contrast

**Date:** 2026-05-02
**Status:** Implemented

---

## Implementation

Inserted after the Retinex normalisation step (grade.fx ~line 321):

```hlsl
float clarity_gate = smoothstep(0.06, 0.25, new_luma);
new_luma = saturate(new_luma + 0.10 * log_R * clarity_gate * (1.0 - new_luma));
```

---

## Signal validity

`log_R` is computed at line 318 using the pre-Retinex `new_luma` vs. `illum_s0`. This
is correct: the Retinex step at line 320 adjusts global scene key, while `log_R` captures
local reflectance deviation which is spatially independent of the global normalisation.
Applying R72 to the post-Retinex `new_luma` is consistent — the detail boost works on
the key-normalised signal.

---

## Gate design

`smoothstep(0.06, 0.25, new_luma)` suppresses the boost below luma 0.06. Numerical
validation (illum_s0=0.10, new_luma=0.04, log_R=-1.32):
- clarity_gate = smoothstep(0.06, 0.25, 0.04) = 0.0
- Effect: 0 — deep shadows fully protected

Mid-tone case (illum_s0=0.10, new_luma=0.14, log_R=+0.49):
- clarity_gate = smoothstep(0.06, 0.25, 0.14) ≈ 0.42
- Effect: 0.10 × 0.49 × 0.42 × 0.86 ≈ +0.018 — visible local contrast lift

`(1.0 - new_luma)` prevents the boost from compounding near white. At new_luma=0.90,
factor is 0.10 — effectively zero influence in bright highlights.

---

## Difference from R30

R30 sharpened `luma - illum` (linear subtraction). That signal is dominated by the
illumination boundary frequency band, causing halos/bloom at light transitions.
`log_R = log2(luma/illum_s0)` divides out the illumination in log space, leaving only
reflectance variation. The root cause of R30's failure does not apply here.

---

## Coefficient 0.10

Starting point. If scenes feel over-sharpened (texture edges too crispy), reduce to
0.07. If clarity is still insufficient vs. pre-R30-removal, raise to 0.14.

---

## Verdict

Implemented. Illuminant bleed risk eliminated by construction. Shadow and highlight
protection in place via gate and `(1-luma)` rolloff.
