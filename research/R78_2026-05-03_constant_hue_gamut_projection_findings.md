# R78 Findings — Constant-Hue Gamut Projection

**Date:** 2026-05-03
**Status:** Implement — zero-cost reformulation confirmed

---

## Problem analysis

Current gclip projects in sRGB RGB space toward `L_grey`:
```hlsl
float L_grey   = density_L * density_L * density_L;
float gclip    = saturate((1.0 - L_grey) / max(rmax - L_grey, 0.001));
chroma_rgb     = L_grey + gclip * (chroma_rgb - L_grey);
```

This scales the RGB deviation from grey. Because sRGB primaries are not uniformly
distributed in Oklab, scaling RGB deviations from grey does not preserve Oklab ab
direction — it produces a hue shift for out-of-gamut pixels.

---

## Derivation: constant-hue projection cost

A true constant-hue projection requires finding `s` such that
`max(OklabToRGB(density_L, f_oka*s, f_okb*s)) = 1`, then recomputing OklabToRGB.

The Oklab→linear_sRGB transform is linear in (a, b) for fixed L. Therefore:

`max_channel(s) ≈ L_grey + s × (rmax - L_grey)`

Setting to 1: `s = (1 - L_grey) / (rmax - L_grey)` — identical to the current gclip.

The current formula with `gclip = s` applied to `chroma_rgb - L_grey` in RGB space
is approximately equivalent to scaling Oklab (a, b) by `s` because:
- At s=0: chroma_rgb → (L_grey, L_grey, L_grey) = OklabToRGB(density_L, 0, 0) ✓
- At s=1: chroma_rgb → original ✓
- At intermediate s: linear interpolation in RGB vs. linear scale in Oklab ab

The difference is only in the intermediate path. For mildly out-of-gamut values
(rmax 1.02–1.15, which is all that fires after R68B), both approaches produce
nearly identical results. For severely out-of-gamut values (rmax > 1.3), the Oklab
approach is more accurate — but this requires one extra OklabToRGB call.

---

## Reformulation: apply gclip in Oklab space

Instead of projecting the final `chroma_rgb` in RGB space, apply `gclip` to
`(f_oka, f_okb)` before the OklabToRGB call. This requires knowing `rmax` before
the call, which we can estimate from the existing `rgb_probe`:

```hlsl
// rgb_probe = OklabToRGB(final_L, f_oka, f_okb)  [already computed at line 459]
// rmax_est based on probe, adjusted for density_L:
float rmax_probe = max(rgb_probe.r, max(rgb_probe.g, rgb_probe.b));
float L_grey     = density_L * density_L * density_L;
float gclip_ok   = saturate((1.0 - L_grey) / max(rmax_probe - L_grey, 0.001));
float3 chroma_rgb = OklabToRGB(float3(density_L, f_oka * gclip_ok, f_okb * gclip_ok));
lin = saturate(chroma_rgb);
```

This:
1. Uses the same gclip value as before
2. Applies it in Oklab space (scales ab, not RGB)
3. One OklabToRGB call (same as current)
4. Uses `rgb_probe` which is already computed — no new texture taps

The rmax_probe vs. actual rmax difference: `rgb_probe` is at `(final_L, f_oka, f_okb)`
pre-density and pre-R68B. `chroma_rgb` is at `(density_L, f_oka*ck_fac, f_okb*ck_fac)`.
density_L ≤ final_L (density darkens), so rmax_probe ≥ actual rmax. Using the higher
estimate means gclip_ok is slightly more conservative (slightly more compression than
needed). This is the safe direction — under-compression is worse than over-compression
for a safety net.

---

## Implementation

Replace lines 469–474 in grade.fx:

**Before:**
```hlsl
float3 chroma_rgb = OklabToRGB(float3(density_L, f_oka, f_okb));
float  rmax       = max(chroma_rgb.r, max(chroma_rgb.g, chroma_rgb.b));
float  L_grey     = density_L * density_L * density_L;
float  gclip      = saturate((1.0 - L_grey) / max(rmax - L_grey, 0.001));
chroma_rgb        = L_grey + gclip * (chroma_rgb - L_grey);
lin = saturate(chroma_rgb);
```

**After:**
```hlsl
// R78: constant-hue gamut projection — apply gclip in Oklab ab space.
// rmax_probe (from existing rgb_probe) approximates boundary; conservative direction.
float  rmax_probe = max(rgb_probe.r, max(rgb_probe.g, rgb_probe.b));
float  L_grey     = density_L * density_L * density_L;
float  gclip_ok   = saturate((1.0 - L_grey) / max(rmax_probe - L_grey, 0.001));
float3 chroma_rgb = OklabToRGB(float3(density_L, f_oka * gclip_ok, f_okb * gclip_ok));
lin = saturate(chroma_rgb);
```

---

## GPU cost

Same: one OklabToRGB call, 4 ALU for gclip. Net change: zero. Hue accuracy improves
on out-of-gamut pixels by projecting in perceptual space rather than display space.
The `rmax` variable no longer needed — one fewer float in registers.
