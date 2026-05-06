# Research Findings — vkBasalt Mip Generation Constraints — 2026-05-06

## Status: Bug confirmed and fixed — grade.fx, corrective.fx chain

---

## The Bug

`CreativeLowFreqTex` is declared with `MipLevels=3` and written by `corrective.fx`
(ComputeLowFreqPS renders to mip0). `grade.fx` read from mip1 and mip2 via
`tex2Dlod(CreativeLowFreqSamp, float4(uv, 0, 1))` and `tex2Dlod(..., float4(uv, 0, 2))`.
Both returned zero on every pixel.

Additionally, `tex2Dlod(BackBuffer, float4(uv + offset, 0, 0))` returned zero even at
LOD=0. `tex2D(BackBuffer, uv + offset)` works correctly.

---

## Root Cause

Two separate vkBasalt constraints:

### 1. Cross-technique render targets — no auto-mip generation

vkBasalt generates mips automatically only for render targets written and read **within
the same technique**. `CreativeLowFreqTex` crosses a technique boundary:
- Written by `corrective.fx` (technique: OlofssonianCorrective)
- Read by `grade.fx` (technique: OlofssonianColorGrade)

`MipLevels=3` allocates storage for three mip levels but does not populate them.
Only the mip level explicitly rendered to (mip0) contains data. Mip1 and mip2 are
zeroed GPU memory from allocation.

**Confirmed working:** `MistDiffuseTex` (written by MistDownsamplePS, read by
ProMistPS — both within OlofssonianColorGrade) auto-generates mip1 correctly.

### 2. `tex2Dlod` on BackBuffer returns zero

The BackBuffer sampler does not support `tex2Dlod` in vkBasalt. Calls compile and
run without error but return zero. `tex2D(BackBuffer, uv)` works correctly. This
affects offset reads (e.g. the halation box blur used `tex2Dlod(BackBuffer, float4(uv+offset, 0, 0))`).

---

## Effects Silently Broken

All of the following were returning zero or minimum-clamp values:

| Effect | Variable | Was reading | Result |
|--------|----------|-------------|--------|
| LCA gradient (R107) | `gr/gl/gu/gd` | `CreativeLowFreqSamp` LOD=2 | Zero gradient → no LCA |
| CAT16 chromatic adaptation | `illum_rgb` | `lf_mip2.rgb` | (0,0,0) → identity passthrough |
| Retinex illum scale 0 (R29) | `illum_s0` | `lf_mip1.a` | Clamped to 0.001 |
| Retinex illum scale 2 (R29) | `illum_s2` | `lf_mip2.a` | Clamped to 0.001 |
| Shadow lift denominator | via `illum_s0` | `lf_mip1.a` | 0.001² → 30–50× too strong |
| R66 ambient shadow tint | `illum_s2_rgb` | `lf_mip2.rgb` | (0,0,0) → no tint |
| Halation DoG ring (R105) | `hal_ring` | `BackBuffer` via `tex2Dlod` | Zero blur → zero ring |

### Shadow lift over-amplification detail

Shadow lift uses `0.149169 / (illum_s0² + 0.003)`. With `illum_s0 = 0.001`:
`0.149169 / 0.003001 ≈ 49.7`. With real data (`illum_s0 ≈ 0.10` for dark regions):
`0.149169 / 0.013 ≈ 11.5`. The lift was running **~4–8× too strong** in shadow
regions, and ~30× too strong in mid-tones (where it barely fires anyway due to `lift_w`).
`SHADOW_LIFT_STRENGTH` was calibrated against broken data — needs retuning upward.

---

## Fix

### 1. LCA gradient — LOD=2 → LOD=0

Changed all 4 gradient reads from `tex2Dlod(CreativeLowFreqSamp, ..., 2)` to
`tex2Dlod(CreativeLowFreqSamp, ..., 0)`. Also updated `mpx` stride comment from
"mip2 space" to "mip0 space" (texel = 8/BUFFER px, stride adjusted accordingly).

### 2. Two explicit downscale passes within grade.fx technique

Added `LowFreqMip1Tex` (1/16-res) and `LowFreqMip2Tex` (1/32-res) as new render
targets declared in `grade.fx`. Two passes run at the top of `OlofssonianColorGrade`
before `ColorTransform`:

```
pass LFDownscale1  →  reads CreativeLowFreqSamp (mip0, 1/8-res)   →  writes LowFreqMip1Tex
pass LFDownscale2  →  reads LowFreqMip1Samp     (1/16-res)         →  writes LowFreqMip2Tex
```

Each pass is a 4-tap box filter at ±half-texel stride. Textures are within the same
technique so data is guaranteed populated when `ColorTransformPS` runs.

`illum_s0` now reads `LowFreqMip1Samp` (1/16-res). `illum_s2` and `illum_s2_rgb`
now read `LowFreqMip2Samp` (1/32-res). True multi-scale Retinex restored.

### 3. Halation DoG PSF restored (R105)

`tex2Dlod(BackBuffer, ...)` replaced with `tex2D(BackBuffer, ...)` as interim fix,
then replaced entirely with the proper DoG model using the new in-technique textures:

```hlsl
float3 hal_inner = tex2D(LowFreqMip1Samp, uv).rgb;   // 1/16-res inner ring
float3 hal_outer = tex2D(LowFreqMip2Samp, uv).rgb;   // 1/32-res outer wing
float3 hal_ring  = max(0.0, hal_outer - hal_inner);   // annular PSF
```

Ring is zero at the highlight source center, peaks adjacent to it, fades with distance.

---

## Rules Going Forward

- **Cross-technique render targets: mip0 only.** Do not declare `MipLevels > 1` on
  textures written by one technique and read by another. Only mip0 is populated.
- **Within-technique render targets: auto-mip works.** `MistDiffuseTex` confirmed.
- **`tex2Dlod(BackBuffer, ...)` → always use `tex2D`.** tex2Dlod on BackBuffer
  returns zero in vkBasalt regardless of LOD parameter.
- **Multi-scale blur within grade:** Use `LowFreqMip1Tex` and `LowFreqMip2Tex` —
  already available in ColorTransformPS at zero additional cost.

---

## GPU Cost

| Item | Cost |
|------|------|
| LFDownscale1PS (1/16-res, 4 taps) | Negligible — 160×90 at 1440p |
| LFDownscale2PS (1/32-res, 4 taps) | Negligible — 80×45 at 1440p |
| LowFreqMip1Tex VRAM | 160×90×RGBA16F = ~112 KB |
| LowFreqMip2Tex VRAM | 80×45×RGBA16F = ~28 KB |
| Net ColorTransformPS tap change | −4 BackBuffer taps (halation box blur removed) +2 LowFreq taps |
