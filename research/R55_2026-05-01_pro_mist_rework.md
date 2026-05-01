# R55 — Pro Mist Rework

**Date:** 2026-05-01
**Status:** Proposal — needs findings before implementation.

---

## Current state

`pro_mist.fx` is a single-pass effect using `CreativeLowFreqTex` (1/8-res, 3 mip levels,
written for free by `corrective.fx`) as its scatter source. It is **not in the active
effects chain** — `arc_raiders.conf` line 22 excludes it. `MIST_STRENGTH 0.40` knob
is preserved but has no effect on the running chain.

The existing pass does four things in one shader:
1. **Mist scatter** — additive composite of `max(0, diffused − base)` with chromatic
   weights (R scatters most, B least), scene-adaptive via IQR, luma-gated around p75.
2. **Clarity boost** — Laplacian residual `(base − diffused)` bell-weighted to midtones,
   added back additively. Counteracts the softening of step 1.
3. **Warm-bias adaptation** — `WarmBiasTex` adjusts chromatic scatter weights so warm
   scenes get neutral scatter instead of extra red.
4. **Halation (R37)** — chromatic glow from highlights using mip 1 and mip 2 of
   `CreativeLowFreqTex`. Proposed to split out entirely → R56.

---

## Problems to solve

### 1. Clarity boost fights the mist intent
`result += adapt_str * 1.10 * detail * bell` adds Laplacian sharpening inside the mist
pass. A real Black Pro-Mist filter works by scattering light, not by sharpening. The
clarity boost was likely added to compensate for the perceived softening, but the two
operations partially cancel each other. Research question: should clarity be removed
entirely from this pass, or moved into `grade.fx` as a separate tonal stage?

### 2. Single mip level gives fixed spatial scale
The scatter source is fixed at mip 0 (1/8 res). Real diffusion filters scatter at
multiple spatial scales simultaneously — a tight halo plus a wider soft glow. A blend of
`lerp(mip0, mip1, t)` weighted by scene contrast (IQR) would better approximate the
physical multi-scale character without a second pass.

### 3. Halation coupling
Halation (R37) is baked into the mist pass with a hardcoded auto strength
(`lerp(0, 0.22, smoothstep(0.55, 0.85, perc.b))`). With R56 splitting halation out,
the mist pass can be simplified and its interaction with the highlights layer becomes
explicit rather than implicit.

### 4. Not in active chain — root cause unknown
The two-pass version crashed Arc Raiders intermittently; `DiffuseTex`/`DiffuseHPS` were
removed and it was pulled. The current single-pass version should be stable but has never
been re-added. Research question: is there a known reason the single-pass version is also
excluded, or is it safe to re-enable?

---

## Constraints

- **Must stay single-pass.** Two-pass version caused `VK_ERROR_DEVICE_LOST` in Arc Raiders.
  No `DiffuseTex`, no `DiffuseHPS`, no new render targets.
- **No new textures.** Use `CreativeLowFreqTex` (mip 0–2), `PercTex`, `WarmBiasTex` —
  all already written by earlier passes at zero additional cost.
- **Must not stomp game bloom.** The additive `max(0, diffused − base)` formulation
  already handles this at the pixel level — diffused is the low-frequency version, so the
  delta is only positive where surrounding area is brighter than the pixel, not at peaks.
  Verify this holds after halation is removed.

---

## Research tasks

1. Find published optical characterisation of Black Pro-Mist / Hollywood Black Magic
   filters — what is the spatial frequency response? Is the effect purely additive scatter
   or does it also reduce local contrast?
2. Determine whether the clarity boost should be removed from the mist pass or preserved
   as a deliberate "pro-mist with retained micro-contrast" behaviour.
3. Evaluate the multi-scale approach: blend mip 0 + mip 1 with IQR-driven weighting vs.
   fixed mip 0. What is the GPU cost difference? (both are already-resident mip levels —
   one extra `tex2Dlod` call, no additional texture fetch.)
4. Confirm single-pass re-enable is safe — check if there are any shared texture write
   hazards between `corrective.fx` and `pro_mist.fx` that caused the earlier crash.
5. Write findings to `R55_2026-05-01_pro_mist_rework_findings.md`.

---

## Proposed implementation sketch

```hlsl
// Remove clarity block entirely (or move to grade.fx)
// Remove halation block (→ R56)
// Blend two mip levels for multi-scale scatter:
float3 diffuse0 = tex2Dlod(CreativeLowFreqSamp, float4(uv, 0, 0)).rgb;
float3 diffuse1 = tex2Dlod(CreativeLowFreqSamp, float4(uv, 0, 1)).rgb;
float  scene_softness = smoothstep(0.1, 0.4, iqr);
float3 diffused = lerp(diffuse0, diffuse1, scene_softness * 0.4);

float3 scatter_delta = max(0.0, diffused - base.rgb);
float3 result = base.rgb
    + scatter_delta * float3(scatter_r, 1.00, scatter_b) * adapt_str * luma_gate;
```

One additional `tex2Dlod` call. No new passes, no new textures.
