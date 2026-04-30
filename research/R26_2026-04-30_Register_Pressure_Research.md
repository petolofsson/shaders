# R26N — SPIR-V Register Pressure & Loop Restructuring

**Date:** 2026-04-30  
**Status:** Complete — measured on hardware, loop restructure reverted

---

## Question

Does restructuring the 16 individually-named zone reads (`r16_z0..z15`, grade.fx:205–220)
into a `[unroll]` accumulation loop reduce SPIR-V register pressure in `ColorTransformPS`?

---

## Hardware measurement (RADV_DEBUG=shaders, ACO IR)

Shader identified via `V__ZoneHistorySamp` in NIR dump. VGPR count read from highest
physical register index in ACO post-allocation IR.

| Version | Max VGPR | Count |
|---------|----------|-------|
| Original (16 named vars) | v[82] | **83 VGPRs** |
| Loop restructure ([unroll]) | v[83] | **84 VGPRs** |

**No improvement.** ACO re-hoisted all 16 texture fetches before accumulations for ILP,
recreating the simultaneous-liveness pattern the loop was designed to avoid. The loop
restructure was reverted.

**The R25N "~129 scalar registers" estimate was wrong.** Actual count is 83–84 VGPRs.
At 84 VGPRs on RDNA2 (1024 VGPRs/SIMD, wave32): 1024 / 88 (rounded to granule of 8)
= **11 wavefronts/SIMD = ~69% occupancy.** No spilling, comfortable headroom.

---

## Key findings

### 1. DXC + ACO loop unrolling behaviour

DXC's spirv-opt `-O` recipe: `ssa-rewrite → loop-unroll → eliminate-dead-code-aggressive
→ scalar-replacement → copy-propagate-arrays`. After `loop-unroll`, spirv-opt does not
merge 16 unrolled loop-body temporaries into one shared SSA slot — each iteration gets
its own SSA value ID. ACO then re-hoists texture fetches for latency hiding, keeping all
16 z-values simultaneously live regardless of loop vs. named-variable form.

### 2. "128 scalar registers" conflated SGPR and VGPR budgets

AMD GPUOpen explicitly: *"SGPRs are not the limiting factor for occupancy on GCN/RDNA —
there are always enough of those."* The occupancy limiter is VGPRs only.

| File | RDNA2 | RDNA3 | Role |
|------|-------|-------|------|
| VGPR | 1024/SIMD | 1536/SIMD | Primary occupancy limiter |
| SGPR | 512/SIMD | 512/SIMD | Never the bottleneck |

RDNA2 wave32 occupancy thresholds:

| VGPRs/wave | Waves/SIMD | Occupancy |
|---|---|---|
| ≤ 64 | 16 | 100% |
| 65–80 | 12 | 75% |
| 81–128 | 8 | 50% |
| 129–160 | 6 | 37.5% |

`ColorTransformPS` at 83–84 VGPRs sits in the 81–128 band: **8 waves, 50% occupancy.**
Not spilling. Crashes in Arc Raiders are UE5 frame budget saturation, not register pressure.

### 3. Alternatives — not needed at current VGPR count

- **fp16 packing:** Two 16-bit values per VGPR on RDNA. 5 accumulators → 3 VGPRs.
  Would move to ~80 VGPRs (75% occupancy band). Requires precision validation on `log()`.
  Not urgent at 83 VGPRs.
- **MegaPass splitting:** Do not do. Inter-effect BackBuffer is 8-bit UNORM; SDR-by-
  construction constraint makes this architecturally hazardous. UE5 pass cost risk.
- **No SPIR-V register annotations exist** (`OpDecorate`, execution modes) that influence
  register allocation in the driver.

---

## Outcome

- No shader change. `grade.fx` remains as-is (16 named zone reads).
- R25N "spilling" alarm dismissed — actual VGPR count is 83, well within safe range.
- Register pressure is a non-issue for this pipeline at current complexity.
- If VGPRs grow past 128 in future (e.g. after new stages added): try fp16 packing of
  the 5 zone accumulators first before any structural refactor.

---

## Literature

| Source | Key finding |
|--------|-------------|
| AMD GPUOpen — Live VGPR Analysis (RGA) | SGPRs not the bottleneck on GCN/RDNA |
| AMD GPUOpen — Occupancy Explained | RDNA2: 1024 VGPRs/SIMD; wave32 occupancy math |
| AMD GPUOpen — RDNA Performance Guide | fp16 packs two values per VGPR |
| Chips and Cheese — RDNA 2 analysis | RDNA2: 128 KB VGPR/SIMD, 16-wave max |
| Interplay of Light — Shader occupancy | 128 VGPR → occupancy cliff, not spill |
| GameDev.net — NVIDIA GLSL unroll explosion | ACO fetch re-hoist precedent |
| Maister — DXIL to SPIR-V | SSA value proliferation after unroll |
| DXC SPIR-V docs / Khronos SIGGRAPH 2018 | spirv-opt -O pass list |
