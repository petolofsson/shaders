# R97 Findings — Halation WarmBias-Coupled Gain (2026-05-04)

## Status: Physically confirmed, proceed with empirical tuning

## Physical basis

Web research confirms illuminant-dependent halation colour:

- Incandescent/tungsten (3200K) produces obvious, warm halation — high red energy drives
  strong red-layer exposure
- LED sources with weak red spectrum produce minimal or near-neutral halation
- The richer the red content of the scene light, the more strongly the red-sensitive
  layer is re-exposed on scatter return

The current gain vector `float3(1.2, 0.45, 0.0)` is scene-invariant. In a cool/blue
scene (WarmBias near 0), the warm bias of 1.2 overestimates red; in a tungsten scene
(WarmBias high), it may underestimate.

No published quantification of the ratio shift — parameters must be empirically tuned.

## WarmBiasTex availability in grade.fx

WarmBiasTex and WarmBiasSamp are already declared in grade.fx (lines 93–102).
**No new declaration needed.** The only cost is the `tex2Dlod` fetch itself —
1 new point-sample read, 0 new declarations.

## Proposed implementation

```hlsl
float hal_warm   = tex2Dlod(WarmBiasSamp, float4(0.5, 0.5, 0, 0)).r;
float hal_r_gain = lerp(1.05, 1.35, smoothstep(0.02, 0.12, hal_warm));
float hal_g_gain = lerp(0.50, 0.38, smoothstep(0.02, 0.12, hal_warm));
lin = saturate(lin + hal_delta * float3(hal_r_gain * hal_gate_r, hal_g_gain * hal_gate_g, 0.0) * HAL_STRENGTH);
```

- Cool scene (hal_warm ≈ 0): gain float3(1.05, 0.50, 0) — softer, more neutral scatter
- Warm/tungsten scene (hal_warm ≈ 0.12+): gain float3(1.35, 0.38, 0) — stronger red, less green

The total effective red:green ratio shifts from 2.1:1 (cool) to 3.6:1 (warm). This is
a meaningful but not extreme change; current fixed ratio is 2.67:1.

## Cost

1 new point-sample tap (WarmBiasTex). ~4 ALU (1 smoothstep shared for r_gain + g_gain,
2 lerp, 2 mul in final line).

## Interaction

Depends on R94. Can be implemented independently of R95/R96. Recommend implementing
last — it's the only proposal with a new tap, and R95/R96 should be validated first.

## Tuning note

The WarmBias value in Arc Raiders with current settings is typically in the 0.04–0.08
range (moderately warm scene illuminant from the lighting). Verify with a debug overlay
before finalizing gain range.
