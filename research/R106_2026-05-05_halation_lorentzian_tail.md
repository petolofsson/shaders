# Research Findings — Halation Lorentzian Tail — 2026-05-05

## Status: Implemented — `grade.fx` ColorTransformPS, halation block

---

## Problem with Gaussian-only tail

The DoG ring (R105) produces an annular peak but decays as a difference of
Gaussians for pixels beyond the ring radius. Gaussian decay is `exp(-r²/2σ²)` —
it drops very fast. Real film halation has a heavier falloff, reported to decay
closer to `1/r²` (inverse-square law character) at large distances from the source.
This is because the effective scatter is a sum over many bounce orders, each
contributing a Gaussian of different width — the resulting envelope is heavier-tailed
than any single Gaussian.

The practical consequence: with a Gaussian tail, the halation glow disappears
abruptly just outside the ring. With a Lorentzian tail, it lingers perceptibly
into surrounding dark areas, giving the characteristic "glow that won't die"
character of practical film halation around specular sources.

---

## Physical basis

The Lorentzian (Cauchy) distribution `L(d) = γ²/(γ²+d²)` has a `1/d²` tail for
large `d`. For film halation, `d` is parameterized as `1 − hal_bright` (distance
from the bright threshold in luma space):

- `d = 0` (pixel at hal_bright = 1.0): Lorentzian = 1.0 — maximum tail weight at
  the source.
- `d = γ` (pixel at hal_bright = 1 − γ): Lorentzian = 0.5 — 50% point.
- `d → 1` (dark pixel, hal_bright → 0): Lorentzian → γ²/(γ²+1) ≈ small.

`HAL_GAMMA` controls the 50% point — lower values make the tail fall faster;
higher values let the glow linger into darker surroundings.

The Lorentzian used here is a radial falloff analog: the luma threshold `hal_bright`
is a spatial proxy for distance from the source (nearby pixels around a highlight
have higher luma than distant ones). This is an approximation — a true Lorentzian
would require measuring radius from each source — but the proxy is zero-tap and
produces visually accurate character.

---

## Implementation

`grade.fx` — halation block:

```hlsl
// Lorentzian tail weight: γ²/(γ²+d²+ε), d = 1−hal_bright
// ε = 1e-6: NaN guard when HAL_GAMMA = 0 and hal_bright = 1
float  hal_d    = 1.0 - hal_bright;
float  hal_lore = (HAL_GAMMA * HAL_GAMMA)
                / (HAL_GAMMA * HAL_GAMMA + hal_d * hal_d + 1e-6);

// Lorentzian drives the tail fraction of the wing contribution
float3 hal_delta = float3(
    max(0.0, hal_ring_r + hal_wing_tail.r * lerp(0.20, 0.42, hal_lore) - lin.r),
    max(0.0, hal_ring_g + hal_wing_tail.g * lerp(0.10, 0.21, hal_lore) - lin.g),
    0.0
);
```

The `lerp(min, max, hal_lore)` structure means:
- At the threshold (hal_bright ≈ hal_thresh): hal_lore ≈ 0 → tail weight = min (0.20/0.10)
- At a bright source (hal_bright = 1): hal_lore = 1 → tail weight = max (0.42/0.21)

The 2:1 R/G ratio (0.42 vs 0.21) reflects Kodak 2383's antihalation dye OD ratio
(red transmits ~2× more than green on back-reflection). See R96, R111.

**NaN guard:** At `HAL_GAMMA = 0.0` and `hal_bright = 1.0`, the original
implementation produced `0/(0+0) = NaN`. The `+1e-6` guard in the denominator
eliminates this. See CHANGELOG 2026-05-05 bug fix.

---

## HAL_GAMMA tuning

| HAL_GAMMA | Lorentzian 50% point (d) | Character |
|-----------|--------------------------|-----------|
| 0.10 | d = 0.10 → glow only at top 10% luma | Tight, crisp |
| 0.40 | d = 0.40 → glow at top 40% luma | Default — soft but contained |
| 1.00 | d = 1.00 → glow across full range | Very soft, lingering |

Default `HAL_GAMMA = 0.40`.

---

## GPU cost

| Item | Cost |
|------|------|
| Lorentzian compute (fma + div) | 3 ALU |
| lerp for tail fraction | 2 ALU |
| Total | 5 ALU |

Zero new taps.

---

## References

- Nakamura, J. *Image Sensors and Signal Processing for Digital Still Cameras*
  Ch. 3 — film scatter tail character, ISL-like falloff from base reflection.
- Spektrafilm diffusion.py — multi-bounce sum produces Lorentzian-like heavy
  tail at large radii; `halation_bounce_decay` ρ parameter.
- R105 (2026-05-05): DoG PSF ring — the ring this Lorentzian tail extends.
- R111 (2026-05-06): Ring/tail spectral split — `hal_wing_tail` carries warmer
  tint than `hal_wing_ring`.
