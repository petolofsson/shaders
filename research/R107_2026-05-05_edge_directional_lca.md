# Research Findings — Edge-Directional LCA (Replacing Radial) — 2026-05-05

## Status: Implemented — `grade.fx` ColorTransformPS, pre-stage LCA block

---

## Problem with radial LCA

The prior LCA implementation offset red and blue UV coordinates radially from
screen center: `offset = (uv - 0.5) * LCA_STRENGTH`. This models lens chromatic
aberration (CA) which is indeed radially symmetric in a centered, rotationally
symmetric lens.

Two problems:
1. **Wrong for game cameras:** In-game cameras are rarely centered (gameplay camera
   is offset, cinematic cameras have tilt). Radial CA from screen center is
   uncorrelated with in-game optics.
2. **No edge-following:** Real CA manifests along luminance edges — the color fringe
   follows the edge direction. Radial offset is edge-direction-agnostic.

---

## Physical basis

Longitudinal (axial) CA is wavelength-dependent focal length — the lens focuses red
and blue at different distances. The visual signature is a color fringe that follows
luminance edges: red shifts in one direction along the gradient, blue shifts the
opposite direction. The magnitude scales with edge contrast (gradient magnitude) and
is zero in flat areas.

Edge-directional LCA uses the luminance gradient (∇L) as the CA offset direction:
- Red shifts *opposite* the gradient (toward bright side)
- Blue shifts *with* the gradient (toward dark side)
- Flat areas (|∇L| ≈ 0): zero offset — self-limiting by construction

This produces fringes that follow edges, matching the perceptual signature of real
axial CA, without any assumed radial geometry.

---

## Implementation

`grade.fx` — ColorTransformPS, pre-stage (before stage 1):

```hlsl
// R107: edge-directional LCA — gradient from lf_mip2.a (luminance channel)
// 4 reads at ~32px stride in mip2 space — reuses hoisted lf_mip2 cache
float2 g = float2(
    tex2Dlod(CreativeLowFreqSamp, float4(uv + float2( step, 0), 0, 2)).a
  - tex2Dlod(CreativeLowFreqSamp, float4(uv + float2(-step, 0), 0, 2)).a,
    tex2Dlod(CreativeLowFreqSamp, float4(uv + float2(0,  step), 0, 2)).a
  - tex2Dlod(CreativeLowFreqSamp, float4(uv + float2(0, -step), 0, 2)).a
);
float glen = saturate(length(g) * 8.0);    // edge magnitude gate — zero in flat areas
float2 gdir = glen > 0.001 ? normalize(g) : float2(0, 0);
float2 ca_offset = gdir * LCA_STRENGTH * 0.0015;

col.r  = tex2D(BackBuffer, uv - ca_offset).r;   // red: opposite gradient
col.b  = tex2D(BackBuffer, uv + ca_offset).b;   // blue: with gradient
```

`step` is derived from `lf_mip2` pixel size (~32 full-res pixels). The gradient
reads reuse the `CreativeLowFreqSamp` sampler at mip2, consistent with the already-
hoisted `lf_mip2` fetch. The 4 gradient reads replace the previous 0 gradient reads
(radial was analytic) but the same tex tap count is maintained by removing the
radial offset's 2 BackBuffer reads.

**Tap accounting:**
- Before: `col.r = tex2D(BB, uv + radial_r)`, `col.b = tex2D(BB, uv + radial_b)` → 2 BB taps
- After: 4 `CreativeLowFreqSamp` mip2 taps (gradient) + 2 BB taps (shifted r/b) → same
  total, but gradient reads are at low-res mip2 (cheap) vs. full-res BB (expensive)

---

## Self-limiting property

`saturate(length(g) * 8.0)` clamps `glen` to [0, 1]. In texturally flat areas
(uniform sky, solid walls) the gradient is zero → `glen = 0` → `ca_offset = 0`.
CA only fires where there is a genuine edge. This is correct physically (CA requires
a luminance transition to be visible) and avoids injecting color noise into flat areas.

---

## Calibration

`LCA_STRENGTH = 0.3` (testbed). Max UV offset = `0.3 * 0.0015 = 0.00045` at `glen = 1`.
At 1920px wide: ~0.86px shift per channel. Perceptible at high-contrast edges (window
frames, bright geometry against dark background) but below threshold on natural textures.

Base scale `0.0015` was derived from the prior radial implementation (base scale
`0.002`, halved to `0.001` in R83 session, re-calibrated to `0.0015` for edge-
directional with `LCA_STRENGTH` re-tuned accordingly).

---

## GPU cost

| Item | Cost |
|------|------|
| 4 mip2 gradient reads (low-res) | 4 tex taps (replaces 0 analytic) |
| normalize + saturate | ~5 ALU |
| 2 BackBuffer reads (R, B) | same as before |
| Net tap delta | +4 mip2 taps (much cheaper than BB taps) |

---

## References

- Smith, W.J. *Modern Optical Engineering* 4th ed., Ch. 6 — longitudinal chromatic
  aberration: wavelength-dependent focus shift and edge-fringe signature.
- R81A (2026-05-03): Original Eye LCA research — per-pixel radial channel separation.
  R107 supersedes the radial implementation with an edge-following model.
