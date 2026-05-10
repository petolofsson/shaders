# R92 Findings — IGN Blue-Noise Dither in pro_mist.fx (2026-05-04)

## Status: Implemented

## What was built

`general/pro-mist/pro_mist.fx` line 127 — replaced `sin(dot)*43758` white-noise dither with
Jimenez IGN (Interleaved Gradient Noise).

## Change

Before: `float dither = frac(sin(dot(pos.xy, float2(127.1, 311.7))) * 43758.5453) - 0.5;`

After: `float dither = frac(52.9829189 * frac(dot(pos.xy, float2(0.06711056, 0.00583715)))) - 0.5;`

Identical formula to grade.fx line 553 (R89). Spectrally blue — quantization error pushed to
high spatial frequencies where the HVS is insensitive. Reduces visible banding in mist gradients
over fog, sky, and dark backgrounds. No texture, same ALU count.
