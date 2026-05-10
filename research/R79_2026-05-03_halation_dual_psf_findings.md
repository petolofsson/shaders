# R79 Findings — Halation Dual-PSF + Gate Refinement + Chromatic Dispersion

**Date:** 2026-05-03
**Status:** Implement

---

## R79A — Gate onset

No hard published density threshold found. Consensus from open implementations (Dehancer,
Color Finale, xjackyz DCTL) and physical reasoning: onset is in the range **0.70–0.85
linear display-referred** — where scene luminance enters the shoulder of the H&D curve
(~1.5–2 stops above scene key).

The current gate `smoothstep(0.80, 0.95, hal_luma)` is within range but slightly
conservative. **Lower onset to 0.70:**

```hlsl
float hal_gate = smoothstep(0.70, 0.90, hal_luma);
```

This brings mid-bright saturated surfaces (coloured specular at luma 0.70–0.80) into
the halation region without firing on midtones.

---

## R79B — Two-Gaussian PSF

No peer-reviewed PSF measurement found. Implementation consensus (Dehancer "local +
global diffusion", xjackyz DoG+Lorentzian DCTL, Thatcher Freeman DCTL) establishes:

- **Tight core** (local diffusion): the primary scatter — a few pixels at 2K
- **Extended wing** (global diffusion): broad, very low amplitude — up to ~10% of frame
  width at near-zero gain. Survives anti-halation only for very bright sources.
- **Wing sigma ratio**: 5–15× core sigma (no published measurement; inferred from
  implementation descriptions)
- **Red ~1.5–2× green**: confirmed by emulsion layer depth ordering (red layer deepest,
  closest to base)

On 2383 print stock specifically: Kodak's anti-halation data sheet claims "superior
halation protection — no coloured fringes in titles." Extended wing is largely suppressed.
Residual wing exists only for the brightest sources.

**Mapping to mip levels** (mip 0 = 1/8-res, mip 1 = 1/16-res, mip 2 = 1/32-res):
- Core: mip 0 (green) / mip 1 (red) — current usage
- Wing: mip 2 (both channels) — 1/32-res ≈ 60×34 at 1080p = broad low-amplitude scatter

**Blend weights**: Wing should be low amplitude. Proposed: 70% core, 30% wing. This
is conservative — print stock anti-halation suppresses most of the wing, so 30% of
the total hal_delta is a ceiling, not a floor. Tunable post-implementation.

```hlsl
float3 hal_core_r = lf_mip1.rgb;                                          // red core (mip 1)
float3 hal_wing   = tex2Dlod(CreativeLowFreqSamp, float4(uv, 0, 2)).rgb;  // both channels wing (mip 2)
float3 hal_core_g = tex2Dlod(CreativeLowFreqSamp, float4(uv, 0, 0)).rgb;  // green core (mip 0)
float3 hal_r = lerp(hal_core_r, hal_wing, 0.30);  // red: core + wing blend
float3 hal_g = lerp(hal_core_g, hal_wing, 0.30);  // green: core + wing blend
```

---

## R79C — Chromatic dispersion in extended wing

**Warm bias confirmed.** Physical mechanism: red layer closest to base, captures
reflected scatter first at highest intensity. Progression:
- Moderate overexposure: red halo only
- High overexposure: orange/yellow tint (green layer partially exposed by rebound)
- Blue: negligible (too far from base; anti-halation suppresses almost completely)

At print stock level (2383), this is mostly suppressed. For the extended wing (mip 2
blend), the warm bias means the wing's green contribution should lean warm. A simple
approach: the wing colour can be attenuated in the blue channel and boosted in red:

```hlsl
// Wing warm bias: red channel uses wing directly, green uses wing slightly attenuated
// Blue wing remains 0 (anti-halation)
float3 hal_r = float3(
    max(0.0, lerp(hal_core_r, hal_wing, 0.30).r - lin.r),  // red: full wing
    max(0.0, lerp(hal_core_g, hal_wing, 0.20).g - lin.g),  // green: less wing (warm bias)
    0.0                                                      // blue: none
);
```

---

## Final implementation

```hlsl
// R79: halation dual-PSF + softened gate + warm wing bias
{
    float3 hal_core_r = lf_mip1.rgb;
    float3 hal_core_g = tex2Dlod(CreativeLowFreqSamp, float4(uv, 0, 0)).rgb;
    float3 hal_wing   = tex2Dlod(CreativeLowFreqSamp, float4(uv, 0, 2)).rgb;
    float  hal_luma   = dot(lin, float3(0.2126, 0.7152, 0.0722));
    float  hal_gate   = smoothstep(0.70, 0.90, hal_luma);   // R79A: softer onset
    float3 hal_delta  = float3(
        max(0.0, lerp(hal_core_r, hal_wing, 0.30).r - lin.r),  // red: core+wing
        max(0.0, lerp(hal_core_g, hal_wing, 0.20).g - lin.g),  // green: core+less wing
        0.0
    );
    lin = saturate(lin + hal_delta * float3(1.2, 0.45, 0.0) * hal_gate * HAL_STRENGTH);
}
```

Net change vs. R56: +1 tex tap (mip 2), gate onset softened 0.80→0.70, wing blend
on red and green. Strength coefficients (1.2, 0.45) unchanged.

---

## GPU cost delta

+1 `tex2Dlod` call (mip 2 for extended wing). ~4 additional ALU.
