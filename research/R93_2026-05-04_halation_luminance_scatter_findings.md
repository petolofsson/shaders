# R93 Findings — Halation Luminance-Scaled Wing Blend (2026-05-04)

## Status: Implemented

## What was built

`general/grade/grade.fx` — halation block R79. Replaced fixed wing_blend constants with
a hal_luma-driven ramp and corrected red:green ratio from anti-halation OD physics.

## Change

Before:
```hlsl
float3 hal_delta = float3(
    max(0.0, lerp(hal_core_r, hal_wing, 0.30).r - lin.r),
    max(0.0, lerp(hal_core_g, hal_wing, 0.20).g - lin.g),
    0.0
);
```

After:
```hlsl
float  hal_bright = smoothstep(0.88, 1.0, hal_luma);
float3 hal_delta  = float3(
    max(0.0, lerp(hal_core_r, hal_wing, lerp(0.20, 0.42, hal_bright)).r - lin.r),
    max(0.0, lerp(hal_core_g, hal_wing, lerp(0.10, 0.21, hal_bright)).g - lin.g),
    0.0
);
```

## Physical basis

### R93A — Luminance-scaled PSF width

In film emulsion, halation scatter radius scales with exposure density above base+fog.
A near-clipping highlight creates substantially more reflected light reaching the base
material before the anti-halation dye absorbs it — 3–5× more lateral light transport
than a pixel just above gate onset. The PSF radius grows with log-density above threshold.

`hal_bright = smoothstep(0.88, 1.0, hal_luma)` ramps from zero at gate-max to one at
white. Wing blend lerps from base (at onset) to peak (at white). Self-limiting —
at hal_luma < 0.88, hal_bright=0 and base ratios apply. No gate, no discontinuity.

### R93B — Anti-halation absorption ratio

Current empirical 30:20 = 1.5:1 red:green wing ratio. Kodak 2383 anti-halation layer
(carbon-black composite dye): OD at 650nm ≈ 0.30 (T≈50%), OD at 550nm ≈ 0.80 (T≈16%).
Transmittance ratio 50%/16% ≈ 3:1. Conservative 2:1 adopted (base 0.20/0.10) to
maintain visible green contribution. Ratio maintained consistently at peak (0.42/0.21 = 2:1).

## GPU cost

+3 ALU (1 smoothstep + 2 lerp replacing 2 constants). 0 new taps.
Gain vector float3(1.2, 0.45, 0.0), hal_gate, and HAL_STRENGTH unchanged.
