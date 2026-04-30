# Research Proposal — R26N: SPIR-V Register Pressure & Loop Restructuring

**Date:** 2026-04-30  
**Status:** Proposal — pending approval before search execution  
**Triggered by:** R25N stability audit finding (~129 scalar registers in ColorTransformPS,
128-scalar spilling threshold)

---

## The question

`ColorTransformPS` in `grade.fx` reads 16 zone values (r16_z0..z15) as individually-named
floats, each used in 5 downstream accumulations (logsum, zmin, zmax, mean, sqmean). This
forces the compiler to hold all 16 simultaneously live. The proposed fix is a `[unroll]`
loop that accumulates all 5 values per zone read in one pass, reducing peak live registers
from ~16 named temps to ~6 running accumulators.

**The uncertainty**: with `[unroll]`, the SPIR-V compiler expands the loop into a single
basic block. Whether it then treats the loop body's temp as a single reused SSA slot (good)
or allocates a distinct SSA value per unrolled iteration (no improvement) is
compiler-dependent. We don't know which path DXC + the AMD/NVIDIA/Intel Vulkan backends
take for this specific pattern.

---

## What we need to know

### 1. DXC behaviour with [unroll] and register liveness

DXC (DirectX Shader Compiler) translates HLSL → SPIR-V. When `[unroll]` expands a loop:
- Does it emit one SPIR-V `OpVariable` per loop iteration (SSA explosion), or does it
  share the loop-body temp across iterations?
- Does DXC perform phi-node elimination / register coalescing before emitting SPIR-V?
- Is there any documented difference in register pressure between an explicit named-variable
  approach and an `[unroll]` accumulation loop for the same computation?

### 2. Vulkan driver ISA compiler behaviour

The SPIR-V module is then compiled to ISA by the GPU driver:
- **AMD RDNA (RDNA2/3)**: Does ACO (the Mesa Vulkan backend) or AMDVLK handle SPIR-V SSA
  coalescing well for unrolled loops? What is the actual scalar register file size (SGPR/VGPR
  split) and at what point does spilling begin?
- **NVIDIA**: Does the proprietary compiler see through SSA chains from unrolled loops and
  coalesce registers? NVIDIA historically aggressive about this.
- Is there any public documentation or benchmark showing the 128-scalar threshold is real
  for fragment shaders (vs compute shaders where this is better documented)?

### 3. Alternative register pressure reduction patterns

Beyond loop restructuring, what other patterns are used in practice:
- Temporary packing: storing intermediate scalars in float4 components to exploit vector
  register packing.
- Staged computation: writing intermediate results to small render targets mid-pass
  (defeats the MegaPass intent but may be unavoidable).
- SPIR-V annotations: any OpDecorate or execution mode hints that influence register
  allocation?
- Is there literature on the 128-scalar threshold specifically for Vulkan fragment shaders
  vs the well-documented compute shader limits?

### 4. Quality implications of accumulation order reordering

Floating-point summation of 16 `log()` values: does changing from explicit left-to-right
sum to `[unroll]` loop accumulation change the result? Specifically under SPIR-V's
`NoSignedWrap` / `NoUnsignedWrap` / `AssumingValid` flags and GPU FP32 rules.

---

## Search targets

| Source | Query |
|--------|-------|
| Khronos / SPIR-V spec | register allocation, SSA, unroll semantics |
| DXC GitHub issues/docs | `[unroll]` register pressure, SSA emission |
| AMD GPUOpen / RDNA ISA docs | VGPR spilling, fragment shader register limits |
| NVIDIA developer docs | shader register pressure, SPIR-V compilation |
| arxiv.org | SPIR-V register allocation, GPU shader register pressure 2022–2026 |
| ACM/IEEE | shader compiler register pressure, Vulkan fragment shader 2022–2026 |
| Shader playground / godbolt | compare SPIR-V output of named vs loop for the exact pattern |

---

## Expected output

`R26N_2026-04-30_Register_Pressure_Research.md` — replacing this proposal file, containing:

1. **DXC verdict** — what the compiler actually emits for `[unroll]` accumulation vs named vars
2. **Driver-specific behaviour** — AMD / NVIDIA / Intel differences
3. **128-scalar threshold** — confirmed or revised for fragment shaders
4. **Better alternative** (if one exists) — a pattern that provably reduces pressure
5. **Recommendation** — implement loop restructure / find a different approach / do nothing
6. **Literature found** — papers/docs with direct evidence

---

## Scope constraint

No source file changes. Documentation only.  
Do not re-research zone automation (covered by R24N) or stability math correctness (R25N).
