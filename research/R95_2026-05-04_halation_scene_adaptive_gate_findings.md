# R95 Findings — Scene-Adaptive Halation Gate Onset (2026-05-04)

## Status: Ready to implement

## Physical basis

No published density-relative onset threshold found for Kodak 2383 in accessible
literature. The motivation is physical but the derivation is display-referred:

In SDR display-referred space, halation should fire on pixels that are well above the
scene average exposure. A fixed gate at luma 0.70 is correctly scene-relative in a
high-key exterior (p75 ≈ 0.70+) but too conservative in a dark interior (p75 ≈ 0.10),
where a highlight at 0.65 is 5–6 stops above scene key and would absolutely halate on
real film.

## Variable in scope

`eff_p75` is computed at grade.fx line 263:
```hlsl
float eff_p75 = lerp(perc.b, zstats.a, 0.4);
```
This blends raw PercTex p75 with zone histogram max — more robust than raw `perc.b`.
It is in scope throughout ColorTransformPS including at the halation block (line 536+).
**Zero new taps required.**

## Proposed implementation

```hlsl
float hal_gate_lo = lerp(0.62, 0.75, saturate(eff_p75 / 0.75));
float hal_gate_hi = hal_gate_lo + 0.20;
float hal_gate_r  = smoothstep(hal_gate_lo, hal_gate_hi, lin.r);  // replaces current hal_gate_r
float hal_gate_g  = smoothstep(hal_gate_lo, hal_gate_hi, lin.g);  // replaces current hal_gate_g
```

- `eff_p75 = 0.0` (very dark scene): onset at 0.62, saturates at 0.82
- `eff_p75 = 0.375` (mid-key): onset at 0.68, saturates at 0.88
- `eff_p75 = 0.75+` (bright exterior): onset at 0.75, saturates at 0.95

## Cost

~4 ALU (1 saturate + 1 lerp for gate_lo, gate_hi = gate_lo + 0.20 folds to constant,
2 smoothstep replacing the existing 2 smoothstep). Net ALU delta: ~2 (the gate_lo
computation replaces the two fixed constants). 0 new taps.

## Interaction

Depends on R94 (per-channel gates). Must be applied to `hal_gate_r` / `hal_gate_g`
simultaneously, not the old shared `hal_gate`. The `hal_bright` ramp (R93A) currently
uses a fixed 0.88 onset — this should remain fixed or be similarly adapted, but keeping
it fixed is simpler and `hal_bright` is only active above luma 0.88 anyway.
