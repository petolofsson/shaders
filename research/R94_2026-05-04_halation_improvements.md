# R94–R97 — Halation Improvements (2026-05-04)

Four directions for pushing Stage 3.5 halation novelty beyond 82%.
R94 is implemented. R95–R97 are proposals.

---

## R94 — Per-Channel Emulsion Gate (implemented)

**Physical basis:** Each emulsion layer (red-sensitive, green-sensitive) has its own
characteristic exposure curve and base+fog threshold. Halation from the red layer fires
when the red channel exposure exceeds threshold — not when luma does. A blue neon sign
(high B, low R) should produce no red halation. The shared luma gate approximates this
but conflates independent layer physics.

**Change:** Replace `hal_gate = smoothstep(0.70, 0.90, hal_luma)` with two independent gates:
```hlsl
float hal_gate_r = smoothstep(0.70, 0.90, lin.r);
float hal_gate_g = smoothstep(0.70, 0.90, lin.g);
lin = saturate(lin + hal_delta * float3(1.2 * hal_gate_r, 0.45 * hal_gate_g, 0.0) * HAL_STRENGTH);
```

**Visual effect:** Colored light sources produce chromatically-correct scatter — a red
practical gives red halation, a cyan light gives green but not red. Neutral white
highlights behave similarly to before (both channels gate together).

**Cost:** +1 smoothstep (compiler shares `lin.r` / `lin.g` already live). 0 new taps.

---

## R95 — Scene-Adaptive Gate Onset

**Physical basis:** The gate threshold (0.70) is scene-blind. In a dark environment, a
highlight at luma 0.65 is well above the scene average and represents a strong source
that would halate in real film. In a bright exterior, luma 0.70 may be mid-grey. The
onset should track scene key.

**Approach:** Use `p75` from PercTex (already read in grade.fx) as a scene-key proxy.
Scale onset: `gate_lo = lerp(0.62, 0.75, saturate(p75 / 0.75))`. Dark scenes get onset
at ~0.62; bright exteriors at ~0.75. Apply to both `hal_gate_r` and `hal_gate_g`.

```hlsl
float hal_gate_lo = lerp(0.62, 0.75, saturate(p75 / 0.75));
float hal_gate_hi = hal_gate_lo + 0.20;
float hal_gate_r  = smoothstep(hal_gate_lo, hal_gate_hi, lin.r);
float hal_gate_g  = smoothstep(hal_gate_lo, hal_gate_hi, lin.g);
```

**Cost:** ~3 ALU. 0 new taps (PercTex already read — confirm p75 is in scope at the
halation block, or hoist it).

**Dependency:** Best implemented after R94.

---

## R96 — Wing Desaturation (Spectral Broadening)

**Physical basis:** The extended wing (lf_mip2) represents light that has travelled far
through the film base before rescattering. Multiple scattering events spectrally broaden
the light — it becomes less saturated, more amber. Currently `hal_wing = lf_mip2.rgb`
inherits the full source colour. A small desaturation pull toward wing luminance models
this physical effect.

**Approach:** Blend `hal_wing` toward its own luma before use:
```hlsl
float  hal_wing_L = dot(hal_wing, float3(0.2126, 0.7152, 0.0722));
float3 hal_wing_d = lerp(hal_wing, float3(hal_wing_L, hal_wing_L, hal_wing_L), 0.25);
// use hal_wing_d in place of hal_wing in the lerp calls
```

A 25% desaturation at the wing is a conservative estimate; real multi-scatter broadening
can be stronger. The value is a tuning point.

**Cost:** ~4 ALU. 0 new taps.

**Interaction:** Affects the colour character of the extended wing only. Core contributions
(hal_core_r, hal_core_g) unchanged.

---

## R97 — WarmBias-Coupled Gain

**Physical basis:** The warm wing bias (`float3(1.2, 0.45, 0.0)`) is scene-invariant.
In real film, the colour of the halation glow is partly driven by the scene illuminant
absorbed in the base layer. A tungsten-lit scene produces warmer halation; overcast/cool
scenes produce slightly cooler scatter. Pro-Mist already reads WarmBiasTex for this
reason. Halation should do the same.

**Approach:** Read WarmBiasTex (1×1 RGBA16F point sample — minimal cost) and modulate
the red:green gain ratio:
```hlsl
float warm_bias   = tex2Dlod(WarmBiasSamp, float4(0.5, 0.5, 0, 0)).r;
float hal_r_gain  = lerp(1.05, 1.30, smoothstep(0.02, 0.12, warm_bias));
float hal_g_gain  = lerp(0.50, 0.40, smoothstep(0.02, 0.12, warm_bias));
lin = saturate(lin + hal_delta * float3(hal_r_gain * hal_gate_r, hal_g_gain * hal_gate_g, 0.0) * HAL_STRENGTH);
```

Warm scene → more red gain (1.30), less green (0.40). Cool/neutral → closer to flat (1.05/0.50).

**Cost:** 1 new point-sample tap (WarmBiasTex, already declared in pro_mist — needs to be
declared in grade.fx too). ~4 ALU.

**Note:** This is the one new tap in these four proposals. Worth doing only after R95/R96
confirm no visual regressions, since it changes the effective gain range.
