# R68 Findings — Spatial Chroma Modulation + Gamut Compression Pre-Knee

**Date:** 2026-05-02
**Status:** Implement

---

## Part A — Spatial chroma modulation

### Signal selection: use `local_var`, not `|luma - illum_s0|`

The proposal suggested `|luma - illum_s0|` as the detail proxy. This is the full-range
luma–illumination difference — it fires on any luminance discontinuity including hard
shadow/light boundaries, specular highlights, and emissive surfaces. These are not
"texture" in the perceptual sense; boosting chroma suppression there would be wrong.

`local_var = abs(illum_s0 - illum_s2)` (already computed, grade.fx line 316) is a
better signal: it is the mid-scale wavelet band (difference between the 1/16-res and
1/32-res illumination estimates). This cancels both fine pixel noise and large-scale
illumination gradients, leaving the mid-scale spatial structure that corresponds to
real surface texture and geometric detail. Hard edges between large flat regions produce
low `local_var`; textured surfaces produce high `local_var`.

Importantly, `local_var` is already computed and in scope — zero extra taps or ops.

### Threshold calibration

The existing `texture_att` gate (shadow lift, grade.fx line 323) uses:
```hlsl
float texture_att = 1.0 - smoothstep(0.005, 0.030, local_var);
```
This was tuned for shadow lift attenuation — it fires aggressively at very small
local_var values (0.005). For chroma modulation, we want the gate to fire at visible
mid-scale texture, not fine noise. A wider range is appropriate:

```hlsl
float detail_gate = smoothstep(0.02, 0.08, local_var);
```

`detail_gate ≈ 0` in flat/uniform regions → full chroma_str.
`detail_gate ≈ 1` in clearly textured regions → attenuated chroma_str.

### Implementation

Insert immediately before the per-band PivotedSCurve loop (grade.fx ~line 418):

```hlsl
// R68A: spatial chroma modulation — attenuate chroma boost in detail regions.
// local_var (mid-scale wavelet band, already computed) is the detail proxy.
float detail_gate = smoothstep(0.02, 0.08, local_var);
chroma_str *= lerp(1.0, 0.65, detail_gate);
```

**GPU cost:** 1 smoothstep + 1 lerp + 1 mul = ~3 ALU ops. No new taps, no new state.

### Should density_str receive the same modulation?

`density_str` controls how much luminance is darkened near the gamut boundary — it is a
gamut protection mechanism, not a colour richness control. Modulating it by detail would
reduce gamut protection in textured regions, which is undesirable. Leave `density_str`
unmodified.

---

## Part B — Gamut compression pre-knee

### ACES RGC formula (confirmed)

The ACES 1.3 Reference Gamut Compression uses:

```
For x < t:   f(x) = x
For x ≥ t:   f(x) = t + (x-t) / (1 + ((x-t)/s)^p)^(1/p)
where:        s = (l-t) / (((1-t)/(l-t))^(-p) - 1)^(1/p)
```

With `p = 1.2`, `t` = per-channel threshold (Cyan: 0.815, Magenta: 0.803, Yellow: 0.88),
`l` = per-channel limit (Cyan: 1.147, Magenta: 1.264, Yellow: 1.312).

Key insight from the specification: **threshold values derive from real-world colour
checker data**, not arbitrary tuning. The compression fires in the last ~18–20% of gamut
space before the boundary. At `p ≈ 1` (Reinhard), the function is a simple scaled
hyperbola.

### Adaptation for the pipeline

The ACES approach operates on per-channel distances from AP1 in a linear RGB space.
The pipeline operates in Oklab with `headroom = 1 - max(rgb_probe)` already expressing
proximity to the sRGB boundary. This is a compatible signal — `headroom` falls to zero
at the gamut boundary, mirroring the ACES per-channel distance reaching the limit.

The Reinhard form (p = 1) simplifies to:
```
f(x) = t + s*(x-t) / (s + (x-t))
```
For our use case: instead of mapping an out-of-range x to a compressed value, we use
`headroom` to modulate f_oka/f_okb *before* they produce out-of-range RGB. The "t"
equivalent is a `headroom` threshold (0.12 → last 12% of gamut space, consistent with
the ~18% of ACES accounting for Oklab's tighter gamut packing).

### Implementation

Insert between the `headroom` computation and the `chroma_rgb` construction
(grade.fx ~line 458, after density_L is computed):

```hlsl
// R68B: gamut pre-knee — Reinhard-inspired soft chroma rolloff near gamut boundary.
// Fires in last 12% of headroom. Preserves hue (equal a/b scale). gclip is safety net.
float ck_near = max(0.0, 0.12 - headroom) / 0.12;          // 0=free, 1=at boundary
float ck_fac  = 1.0 - 0.18 * ck_near / (1.0 + ck_near);    // Reinhard rolloff, max 9%
f_oka *= ck_fac;
f_okb *= ck_fac;
```

`ck_fac` at boundary (headroom = 0): `1 - 0.18 * 1 / 2 = 0.91` → 9% reduction.
`ck_fac` at threshold (headroom = 0.12): `1 - 0` = 1.0 → no effect.

The Reinhard form `x/(1+x)` ensures a smooth asymptotic rolloff rather than a sharp
shoulder, matching the ACES design intent. The 9% maximum reduction is conservative —
enough to keep most chromatic highlights below the `gclip` activation threshold without
visible desaturation. Tune the `0.18` factor upward if `gclip` still fires frequently.

**GPU cost:** 2 ops (max, div) + 1 mul pair on f_oka/f_okb. Same as the current gclip
block it partially replaces.

---

## Implementation order

Part A: insert before chroma band loop. Part B: insert inside gamut section.
No interaction between A and B — they operate on different variables in different
code regions.

## Concerns from research questions

**Q: Does preserving hue direction (equal a/b scaling) outperform L_grey projection?**
A: Yes for typical cases. The `gclip` L_grey projection shifts hue because L_grey
is achromatic — projecting toward it rotates the hue angle as C decreases. Equal a/b
scaling preserves the hue angle exactly. The only case where L_grey projection is
better is when the colour is so far out of gamut that any residual hue is a distraction.
This is rare in SDR game content. Keep `gclip` as safety net for those extremes.

**Q: Should pre-knee be hue-selective (stronger for cyan/blue)?**
A: The ACES approach uses per-channel limits (Yellow limit 1.312 vs Cyan 1.147) to
account for sRGB gamut tightness per hue. In the pipeline, `headroom` is already
computed from `max(rgb_probe)` which implicitly weights by the limiting channel.
A pixel near the sRGB blue/cyan boundary will already have low headroom — the gate
fires naturally for those hues without explicit hue selectivity. Uniform treatment
is sufficient.
