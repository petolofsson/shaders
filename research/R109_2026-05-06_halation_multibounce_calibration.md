# Research Findings — Halation Multi-Bounce σ√k Calibration — 2026-05-06

## Status: R91 implemented (red wide tail +12% mip2 additive). Calibration derivation below.

## Motivation

Spektrafilm (andreavolpato/spektrafilm, dev branch) models back-reflection halation as
a multi-bounce Gaussian sum with widths scaled by √k (k = bounce count):

```python
for k in range(1, N+1):
    sigma_k = sigma_h * sqrt(k)   # random-walk: N steps → √N spread
    halation_blur += w_k * Gaussian(sigma_k) * raw
```

This is physically grounded: each round-trip bounce is a 2D random walk of fixed
mean free path. After k bounces, displacement standard deviation scales as √k.

Our R105 DoG ring uses mip1 and mip2 of CreativeLowFreqTex. The sigma ratio between
consecutive mips is ×2 in pixel scale (mip2 has 4× lower resolution in each dimension,
effective Gaussian sigma approximately ×2 vs mip1). In the √k model, consecutive
bounces have ratio σ√(k+1) / σ√k = √((k+1)/k). For k=1→2: √2 ≈ 1.41. For k=1→4: 2.0.

**Our mip2/mip1 sigma ratio ≈ 2.0 corresponds to k=4 in the multi-bounce model.**

The DoG ring = mip1 − mip2 therefore represents the annular region between the
1st-bounce and 4th-bounce radii — a physically meaningful "deep scatter" ring, not
a 2-bounce ring. This is *correct* for Kodak 2383 (antihalation: strong), where
only heavily scattered photons survive the antihalation dye to produce visible halation.

This proposal asks: verify that our HAL_GAMMA tuning is consistent with this
interpretation, and explore whether Mie-correct per-channel sigma differs from
equal-mip treatment (candidate R91 from HANDOFF).

---

## Physical model: 2383 antihalation

Kodak 2383 carries a strong antihalation layer between the emulsion and the base.
The antihalation dye absorbs back-reflected light exponentially. Photons that reach
the base and reflect back must traverse the dye twice. Transmission through dye
follows Beer-Lambert: `T = exp(-α·d·c)` where d = dye layer thickness and c = dye
concentration.

For a photon to produce visible halation, it must survive both transits. The surviving
fraction is proportional to `exp(-2αdc)`. For "strong" antihalation (2383), this
fraction is very small — only photons that scatter widely (long path, many bounces,
large radial displacement) contribute. This selects the high-k tail of the bounce
distribution, consistent with our interpretation that the DoG ring represents k≈4.

**The antihalation dye is wavelength-dependent.** Typical antihalation dyes absorb
across visible but peak in the blue-green (to intercept the blue-sensitive emulsion's
main exposure band). Red photons transmit more easily through the antihalation layer
than blue photons. Result:
- Red channel: more surviving back-reflected light → wider effective halation radius
- Blue channel: heavily attenuated → near-zero halation (already our `hal_b = 0`)
- Green channel: intermediate

---

## R91 candidate (Mie-correct per-channel bounce sigma)

From HANDOFF R91 proposal:
> blue channel uses mip 0 (tighter, shorter λ scatters more in polymer), red uses
> mip 1 (wider, longer λ penetrates deeper). 3 ALU, no new taps.

The physical argument:
1. **Rayleigh/Mie regime in polymer base**: film base polymer scatter is particle-scale
   (sub-micron). Blue light (λ ≈ 450 nm) sits deeper in the Mie regime for typical
   base particles, scattering more strongly — but also *more isotropically*, i.e.,
   shorter mean free path. Red (λ ≈ 650 nm) scatters less per unit path but penetrates
   further laterally before returning.
2. **Antihalation absorption selectivity**: blue absorbed more strongly → only the
   tightest-radius (fewest-bounce) blue photons survive. Red less absorbed → wider
   bounce distribution survives.

Net effect on σ: red should use a *larger* σ than blue for surviving photons.
Our current implementation: red and green both use mip1 as core, blue = 0.

R91 would be:
```hlsl
// Current
float3 hal_core = float3(lf_mip1.r, lf_mip1.g, 0.0);  // red+green mip1, blue=0

// R91: red uses mip1 (standard), green uses mip1 (unchanged), blue could use mip0
// if blue halation is re-enabled at very low strength
// OR: red gets additional mip2 contribution for the extra-wide tail
float hal_red_wide = max(lf_mip2.r - lf_mip1.r * 0.3, 0.0);  // approx k=4 tail
float3 hal_core = float3(lf_mip1.r + hal_red_wide * 0.15, lf_mip1.g, 0.0);
```

Cost: 1 ALU (fma). No new taps (lf_mip2 already read by LCA).

---

## Lorentzian tail calibration

Our R106 Lorentzian weight = γ²/(γ²+d²+ε) where d = 1−hal_bright (normalised distance
from highlight). Default HAL_GAMMA = 0.40.

In the multi-bounce model, the k-th bounce contributes weight `ρ^(k-1)` (geometric
decay). The resulting radial profile for a geometric bounce distribution is:

```
P(r) ∝ Σ_k ρ^(k-1) * G(r; σ√k)
```

This sum over k converges to a profile that is heavier-tailed than Gaussian but lighter
than Cauchy (Lorentzian). The Lorentzian approximation `1/(1+r²/γ²)` has the correct
qualitative shape but over-estimates the tail at very large radii. For 2383 strong
antihalation, only the k=4 tail is visible — the long tail is suppressed by the dye —
so the Lorentzian approximation may slightly over-extend the halo into fully dark areas.

**Calibration question:** Is HAL_GAMMA = 0.40 consistent with ρ ≈ 0.5 decay in the
multi-bounce model? Derivation (approximate): the Lorentzian 50% point is at d = γ.
For the geometric sum, the effective 50% point in d = (1−hal_bright) space requires
matching the bounce decay to HAL_GAMMA numerically. No code change required — this is
a numerical verification that our current tuning sits in the physically plausible range.

---

## What this research produces

1. **Verification:** Confirm DoG ring sigma ratio (×2) corresponds to k=4 bounce
   interpretation. Document in CLAUDE.md halation section.
2. **R91 implementation (if approved):** Per-channel mip usage (red gets mip2-weighted
   wide tail). 1 ALU, 0 new taps. Estimated novelty +1%.
3. **HAL_GAMMA range document:** Map HAL_GAMMA values to effective bounce distribution
   ρ (decay per bounce). Helps future tuning.

---

## GPU cost

| Item | Cost |
|------|------|
| R91 red-wide extra term | 1 ALU (fma) |
| HAL_GAMMA/bounce doc | 0 |
| Total per-pixel | +1 ALU |

---

## Targets

- Stage 3.5 finished: +2% (physically calibrated per-channel sigma differentiation)
- Stage 3.5 novel: +2% (multi-bounce calibrated DoG — not documented in any real-time
  implementation)

---

## References

- Spektrafilm diffusion.py — `apply_halation_um()`, multi-bounce σ√k sum. Dev 2026.
- HANDOFF 2026-05-05 — R91 candidate: "Mie-correct per-channel scatter radius".
- PLAN.md — R105 (DoG PSF ring) and R106 (Lorentzian tail) shipped 2026-05-05.
- Hunt, R.W.G. *The Reproduction of Colour* 6th ed., Ch. 15 — antihalation dye
  spectral absorption and Beer-Lambert transmission.
- James, T.H. (ed.) *The Theory of the Photographic Process* 4th ed., Ch. 2 —
  halation back-reflection and base scatter geometry.
