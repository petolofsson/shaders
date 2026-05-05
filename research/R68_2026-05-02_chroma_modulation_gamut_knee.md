# R68 — Spatial Chroma Modulation + Gamut Compression Pre-Knee

**Date:** 2026-05-02
**Status:** Proposed

Two Stage 3 improvements in the same code region, implementable in the same pass.

---

## Part A — Spatial chroma modulation

### Problem

`chroma_str` is computed globally per pixel from `mean_chroma` and `hunt_scale` — every
pixel in the same luminance/chroma band receives identical treatment regardless of whether
it sits in a flat featureless region or a highly textured one. In flat areas (sky, dark
walls, large colour fields), the eye is sensitive to chroma and benefits from a stronger
lift. In detailed texture regions, spatial contrast already implies colour variation — an
additional chroma boost reads as over-processed or artificial.

### Hypothesis

Attenuating `chroma_str` in high-detail regions (where `D1 = |luma - illum_s0|` is
large) and applying it fully in flat regions will improve perceived naturalness without
reducing overall colour richness. The signal is a 1-subtraction proxy for the R30
wavelet fine band — already free in registers at Stage 3 entry.

### Implementation sketch

At Stage 3 entry, before `chroma_str` feeds the per-band PivotedSCurve loop:

```hlsl
// R68A: spatial chroma modulation — attenuate in detail regions, full in flat
float detail_sig = smoothstep(0.0, 0.08, abs(luma - illum_s0));
chroma_str *= lerp(1.0, 0.65, detail_sig);
```

`detail_sig ≈ 0` in flat regions → `chroma_str` unchanged.
`detail_sig ≈ 1` in fine-detail regions → `chroma_str` × 0.65 (35% attenuation).

`0.08` threshold: empirical estimate for where luma-illum_s0 meaningfully indicates
texture vs noise. `0.65` attenuation: starting point, tune to taste.

**GPU cost:** 1 sub + 1 smoothstep + 1 mul = ~3 ALU ops. No new taps, no new state.

### Research questions

1. Does `|luma - illum_s0|` correlate well enough with perceived detail density, or does
   it misfire on hard luminance edges (shadow/light boundary, not texture)?
2. Is 35% attenuation the right ceiling, or should it be stronger (50%) / softer (20%)?
3. Should density_str receive the same modulation (same code path) or be independent?

### Success criterion

Flat coloured regions (sky, walls, floors) look richer after chroma lift. Textured
regions (foliage, complex geometry) do not look oversaturated. No hard seams at
detail/flat boundaries.

---

## Part B — Gamut compression pre-knee

### Problem

The current gamut compression (grade.fx ~line 464) uses a reactive hard projection:

```hlsl
float gclip = saturate((1.0 - L_grey) / max(rmax - L_grey, 0.001));
chroma_rgb  = L_grey + gclip * (chroma_rgb - L_grey);
```

`gclip` fires only when `rmax > 1` — after the pixel is already out of gamut. The
projection toward `L_grey` does not follow constant-hue lines in Oklab, producing
a hue shift on chromatic highlights (energy effects, saturated UI elements, specular
on coloured surfaces). There is no soft shoulder before the boundary.

### Hypothesis

Using the already-computed `headroom = 1 - max(rgb_probe)` to apply a small chroma
rolloff when `headroom` is near zero will smoothly compress chromatic highlights into
gamut before the hard projection fires, reducing hue shifts at the boundary.

### Implementation sketch

Between the `headroom` computation and the `chroma_rgb` construction, insert a
pre-knee scale on `f_oka/f_okb`:

```hlsl
// R68B: gamut pre-knee — soft chroma rolloff in last 10% of headroom
float ck_gate = smoothstep(0.10, 0.0, headroom);
float ck_fac  = 1.0 - 0.15 * ck_gate;
f_oka *= ck_fac;
f_okb *= ck_fac;
// existing chroma_rgb construction follows unchanged
```

`ck_fac` reaches 0.85 at headroom = 0 (boundary) and 1.0 at headroom ≥ 0.10 (free
space). Both a and b are scaled equally → hue direction preserved. `gclip` remains as
the safety net for anything that still escapes.

**GPU cost:** 1 smoothstep + 2 muls (a and b). Net zero change vs current — replaces
equivalent ALU in the `gclip` path that fires less often.

### Research questions

1. Does preserving hue direction (equal a/b scaling) visually outperform the current
   L_grey projection, or are there cases where projecting toward achromatic is better?
2. `0.10` headroom threshold and `0.15` max rolloff — empirical starting points. Does
   the visual result warrant a softer (0.20) or harder (0.25) rolloff?
3. Should the pre-knee be hue-selective (stronger for cyan/blue where sRGB gamut is
   tightest) or uniform?

### Success criterion

Saturated game elements (energy effects, coloured specular, UI) retain their hue
character as they approach the sRGB ceiling rather than shifting toward gray. The
`gclip` projection fires less frequently or not at all in normal scenes.

---

## Implementation order

Part A first (self-contained, no interaction with Part B). Part B second (modifies
`f_oka/f_okb` before they enter `chroma_rgb` — verify Part A does not affect the
chroma path that Part B operates on).
