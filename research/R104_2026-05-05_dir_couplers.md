# Research Findings — DIR Couplers (Cross-Channel Inhibition) — 2026-05-05

## Status: Implemented — `grade.fx` ColorTransformPS, CORRECTIVE block

---

## Physical basis

Developer-Inhibitor-Release (DIR) couplers are chemicals present in color negative
film emulsions. When a silver grain develops, the coupler releases an inhibitor
molecule that diffuses into adjacent layers and suppresses further development there.
The effect is two-fold:

1. **Same-layer inhibition:** Locally inhibits over-development in already-dense
   areas, compressing the shoulder of the characteristic curve and increasing
   apparent fine-detail contrast (acutance).
2. **Inter-layer inhibition:** A bright red channel suppresses the green and blue
   channels in the same pixel region. This increases color saturation at high
   exposures (dense development) and reduces inter-channel cross-talk.

The activating condition is silver density, which corresponds to log-exposure in
our pipeline. Bright pixels (high `pow(rgb, EXPOSURE)`) fire the inhibitor.

---

## Implementation

`grade.fx` — CORRECTIVE block, after `pow(rgb, EXPOSURE)`, before `FilmCurveApply`:

```hlsl
// Activation function: x²/(x²+0.09) — smooth, zero at black, saturates near 1 at highlights
// log2-space cross-channel inhibition: each bright channel suppresses adjacent channels
float3 coupler_act = (lin_e * lin_e) / (lin_e * lin_e + 0.09);
float3 coupler_inh = float3(
    coupler_act.r * COUPLER_STRENGTH,
    coupler_act.g * COUPLER_STRENGTH,
    coupler_act.b * COUPLER_STRENGTH
);
lin_e.r = saturate(lin_e.r - coupler_inh.g * 0.5 - coupler_inh.b * 0.3);
lin_e.g = saturate(lin_e.g - coupler_inh.r * 0.4 - coupler_inh.b * 0.3);
lin_e.b = saturate(lin_e.b - coupler_inh.r * 0.3 - coupler_inh.g * 0.4);
```

`COUPLER_STRENGTH` knob — default `0.0` (off). The compiler eliminates the block
at the default value. Non-zero values increase inter-channel saturation at highlights.

---

## Design note: density curve interaction

Spektrafilm (andreavolpato/spektrafilm) notes that published Kodak characteristic
curves are measured *after* coupler interaction. Applying DIR couplers additively
on top of curves calibrated to the final stock output risks double-counting.
For this reason `COUPLER_STRENGTH` defaults to 0.0 and should only be raised if the
CURVE_* knobs are recalibrated to the pre-coupler stock response. The current
CURVE_* values (Vision3 500T presets) reflect post-coupler density — they are
calibrated against in-game screenshots, not raw Kodak data sheets.

---

## GPU cost

| Condition | Cost |
|-----------|------|
| COUPLER_STRENGTH = 0.0 | 0 ALU (compiler eliminates) |
| COUPLER_STRENGTH > 0.0 | ~8 ALU |

Zero new texture taps.

---

## References

- Hunt, R.W.G. *The Reproduction of Colour* 6th ed., Ch. 15 — DIR coupler
  chemistry and inter-layer inhibition.
- Spektrafilm couplers.py — `compute_dir_couplers_matrix()`,
  `apply_density_correction_dir_couplers()` — full 3×3 matrix model with spatial
  diffusion. Our implementation is a simplified 1D approximation (no spatial
  diffusion, no density-curve pre-correction).
