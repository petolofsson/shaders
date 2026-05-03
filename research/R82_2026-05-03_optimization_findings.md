# R82 Optimization — Implementation Findings
**2026-05-03 | grade.fx ColorTransformPS**

## What was done

All 11 optimizations from the nightly R82 proposal implemented. No perceptual loss —
10/11 are exact algebraic identities; the one approximation (OPT-7) has max error 4.57×10⁻⁵,
44× below the 0.002 JND threshold.

## Applied optimizations

| # | Title | Saving | Error |
|---|-------|--------|-------|
| OPT-1 | Hoist mip-2 `CreativeLowFreqSamp` read (4→1) | −3 tex2Dlod/px | 0.0 |
| OPT-2 | HELMLAB double-angle identity `sin(2h)→2·sin·cos` | −1 transcendental/px | 0.0 |
| OPT-3 | Share `cbrt(r_tonal)` between L-scale and a/b coupling | −2 transcendentals/px | 0.0 |
| OPT-4 | Eliminate `hist_cache[6]` float4 array from live registers | −24 live scalars | 0.0 |
| OPT-5 | Remove redundant `saturate` inside `PivotedSCurve` | −6 saturate/px | 0.0 |
| OPT-6 | Inline Hunt scale intermediates (−7 named scalars → −4 net) | −4 live scalars | 0.0 |
| OPT-7 | Beer-Lambert: `exp(-x)` → 2nd-order Taylor polynomial | −3 GPU cycles | 4.57×10⁻⁵ |
| OPT-8 | Remove redundant `saturate` in zone S-curve extent | −1 saturate/px | 0.0 |
| OPT-9 | Remove outer `saturate` from Munsell chroma multiplier | −1 saturate/px | 0.0 |
| OPT-10 | Inline `fc_width` single-use scalar | −1 live scalar | 0.0 |
| OPT-11 | Eliminate `green_w` alias for `hw_o2` | −1 live scalar | 0.0 |

## Estimated savings per ColorTransformPS invocation

- **−3 texture fetches** (mip-2 LowFreq: CAT16, Retinex, ambient tint, halation)
- **−5 transcendentals** (2× cbrt, 1× sin, 1× log2/exp2 pair, 1× float3 exp→poly)
- **−~30 live scalars** (hist_cache[6]=24, Hunt=4, fc_width=1, green_w=1)
- **−8 saturate ops** (PivotedSCurve×6, zone S-curve×1, Munsell×1)

OPT-4 is the most impactful on AMD RDNA: the 240-scalar ColorTransformPS is in the
register-spilling regime (threshold ~128); −24 scalars directly reduces spill pressure.
