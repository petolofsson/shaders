# Research Findings — Halation DoG PSF Ring — 2026-05-05

## Status: Implemented — `grade.fx` ColorTransformPS, halation block

---

## Problem with prior implementation

The previous halation blend used a filled-disk lerp: `lerp(lin, lf_mip1, hal_bright)`.
This produced a filled glow centered on the bright source — the entire disk interior
glows at uniform intensity. Real film halation is an annular ring: the source itself
is unaffected (its image is sharp), and back-scattered light forms a halo around it,
not on top of it. The filled-disk model made bright sources bloom rather than fringe.

---

## Physical basis

Film halation occurs when light transmits through the emulsion, reflects off the film
base or pressure plate, and re-exposes the emulsion from behind. The geometry creates
an annular exposure ring:

- The point directly behind the source receives reflected light that has traveled zero
  lateral distance — but this coincides with the source itself, which is already fully
  exposed. The net additive contribution is zero or suppressed by the `- lin` term.
- Points at some lateral displacement from the source receive reflected light that has
  scattered outward, creating an annular fringe.

A Difference-of-Gaussians (DoG) naturally models this annular shape:
`ring = max(tight_gaussian - wide_gaussian, 0)`. The tight (mip1) gaussian captures
the scattered light field; the wide (mip2) gaussian approximates what would be present
if the light scattered all the way to zero. Subtracting leaves only the annular zone.

---

## Implementation

`grade.fx` — halation block:

```hlsl
// DoG ring: mip1 (tight) minus mip2 (wide) — annular PSF around bright sources
float  hal_ring_r = max(lf_mip1.r - hal_wing_ring.r, 0.0);
float  hal_ring_g = max(lf_mip1.g - hal_wing_ring.g, 0.0);
```

where `hal_wing_ring` is a spectrally-weighted version of `lf_mip2` (see R111).

No extra texture taps — `lf_mip1` and `lf_mip2` are already read upstream (LCA,
Retinex, ambient tint). The mip subtraction is 2 ALU.

**Audit correction (same session):** Green channel was incorrectly using mip0 as
its core (`hal_core_g = tex2Dlod(…, mip0)`). Film physics requires green to use
mip1 (same as red) — mip0 gives a tighter-than-physical ring and an extra tex tap.
Fixed to `lf_mip1.g`; the redundant tap was removed.

---

## Multi-bounce interpretation (R109)

The DoG sigma ratio (mip2 / mip1) ≈ ×2 in linear pixel scale. In the Spektrafilm
multi-bounce model (`sigma_k = sigma_h * sqrt(k)`), a ratio of ×2 corresponds to
k=4 bounces. This is physically appropriate for Kodak 2383 (antihalation: strong) —
only deeply-scattered photons that survive 4 dye transits produce visible halation.
The ring therefore represents the deep-bounce population, consistent with the
Lorentzian tail added in R106.

---

## GPU cost

| Item | Cost |
|------|------|
| DoG subtraction (2 channels) | 2 ALU |
| Tap delta vs. prior | −1 tap (redundant mip0 green read removed) |

---

## References

- James, T.H. (ed.) *The Theory of the Photographic Process* 4th ed., Ch. 2 —
  halation geometry and back-reflection annular ring shape.
- Spektrafilm diffusion.py — `apply_halation_um()`, multi-bounce `sigma * sqrt(k)`.
- R79 (2026-05-03): Prior halation dual-PSF (filled-disk lerp) — replaced by DoG.
- R109 (2026-05-06): Multi-bounce calibration — σ ratio derivation and R91 red
  wide tail.
- R111 (2026-05-06): Ring/tail spectral split — ring near-neutral, tail warm.
