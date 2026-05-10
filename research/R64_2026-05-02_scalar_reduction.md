# R64 — Register Pressure / Scalar Reduction

**Date:** 2026-05-02
**Status:** Proposal — see findings file.

---

## Motivation

`ColorTransformPS` is estimated at ~165–169 scalars. RDNA spill threshold is ~128. R61 and R62
optimisations improved throughput and latency but are register-neutral — they don't reduce peak
liveness. Spilling to scratch memory adds unpredictable latency and, under sustained GPU pressure
(UE5), could cause crashes.

The unrolled `hist_cache` loop (6 × float4 = 24 scalars) is the dominant single block. Several
float4 variables carry unused components through Stage 3. These are the leverage points.

---

## Open questions

1. What is the true scalar count after R61+R62? Need SPIR-V disassembly or RGP to confirm
   the estimate — hand-count misses compiler-generated temporaries.

2. Does the compiler track per-component liveness for `col`, `perc`, `lf_mip1` float4s,
   or does it hold the full vector? If per-component: RED-2/3/4 in the findings are already
   handled by the compiler and savings are zero.

3. Do HLSL lexical scope blocks (`{ }`) affect SPIR-V register allocation on this toolchain?
   If yes: scoping the `hunt_scale` chain and `fc_*` coefficients could yield 7–17 more scalars.

4. If in-shader reductions bring us to ~146 and not below 128: is the spill cost measurable
   in frame time on the actual GPU, or is it within noise?
