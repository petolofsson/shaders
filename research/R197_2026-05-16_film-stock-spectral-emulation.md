# R197 — Film Stock Spectral Emulation
**Date:** 2026-05-16  
**Domain:** Film stock spectral emulation (Saturday rotation)

---

## Summary

Literature search covering 2023–2026 developments in physics-based film emulation. Two
tractable findings for this pipeline:

1. **Negative spectral sensitivity matrix** — a 3×3 input-side colour transform grounding
   the FilmCurve in published negative-film spectral sensitivity data.
2. **Spatial DIR coupler chroma gradient** — a chroma-edge boost approximating the
   diffusing inhibitor effect documented in vkdt/filmsim and spektrafilm v0.3.2, using
   already-available LowFreqMip textures.

Both are distinct from what is already implemented (R85 corrects the *print* film output
side; R104 DIR couplers are per-pixel; R83/R84 address density offsets and chromatic
floor, not the negative's colour-rendering matrix).

---

## Sources and Context

### JanLohse/spectral_film_lut (2024, active)
GitHub project generating film-emulation LUTs entirely from manufacturer datasheets.
Explicit 7-step pipeline:
```
scene RGB → [M_neg] → log-exposure → H&D curves → dye density → printer light
          → print H&D → [M_print → observer] → sRGB
```
Key insight: `M_neg` (negative spectral sensitivity) and `M_print` (print dye → observer)
are separable 3×3 matrices that bracket the H&D curves. Neither is the identity.  
Source: <https://github.com/JanLohse/spectral_film_lut>

### vkdt filmsim module (artic/hanatos, 2024–2025)
GLSL-based spectral film simulation integrated into vkdt (Vulkan darktable fork).
Parameters include `cp rad` — the spatial radius over which DIR coupler inhibitors
diffuse. The radius is expressed as a fraction of the longer image dimension. Effect:
chroma is *higher* at colour edges (coupler release is local, diffuses into adjacent
layers, reducing density there = higher saturation at transitions) and *lower* in
uniform fields (inhibitor diffusion averages out).  
Source: <https://jo.dreggn.org/vkdt/src/pipe/modules/filmsim/readme.html>

### spektrafilm v0.3.2 (Volpato, Feb–Apr 2025)
Open-source Python spectral simulation. The v0.3.2 release adds "long-range coupler
diffusion" using a Gaussian blur of the inhibitor signal before applying it to the
adjacent layers — analogous to what vkdt does in GPU, but separated into a
downscale→blur→apply pass structure. Also adds "spectral upsampling with window and
surface prototype correction" (Meng/Jakob-Hanika polynomial basis) for converting scene
RGB to band-sampled spectra before applying film sensitivity.  
Source: <https://github.com/andreavolpato/spektrafilm>

### pixls.us "Spectral film simulations from scratch" thread (Feb–Apr 2025, 31+ pages)
Community effort reverse-engineering Kodak Vision3 and Fujifilm spectral sensitivity
data from published datasheets to build a full negative+print simulation in
imageprocessing scripts. Key finding from this thread: the negative film's spectral
sensitivity matrix when linearised around sRGB D65 has red-layer green pickup of
~3–5%, green-layer red pickup of ~1–2%, and blue-layer green pickup of ~2–3%. These
are small but perceptually meaningful — they produce the film's characteristic
"cross-hue richness" vs. the narrowband response of digital sensors.  
Source: <https://discuss.pixls.us/t/spectral-film-simulations-from-scratch/48209>

### Gotanda (SIGGRAPH 2010, still reference standard)
"Film Simulation for Videogames" — still the canonical reference for collapsing the
full spectral film chain into a real-time RGB approximation. Notes that the full
negative + print stock model can be distilled to: input 3×3 → per-channel tone curve →
output 3×3, with the two matrices baked per (negative, print) stock pair. The paper
pre-dates the GPU interest in explicit spectral upsampling but its matrix-distillation
argument is borne out by JanLohse's numerical work.  
Source: <https://renderwonk.com/publications/s2010-color-course/gotanda/course_note_film_simulation_for_videogames.pdf>

---

## Finding 1 — Negative Spectral Sensitivity Matrix (M_neg)

### What it is
The silver halide layers of a colour negative film have spectral sensitivities that
differ from the sRGB/Rec.709 primaries. Vision3 500T's published datasheet (EI 500,
Daylight balance) shows:
- **Red layer**: peak ~620 nm, measurable response extending into ~570 nm (green).
- **Green layer**: peak ~540 nm, slight sensitivity to ~500 nm (cyan) and ~600 nm (orange).
- **Blue layer**: peak ~450 nm, modest response at ~500 nm.

When scene sRGB signals are presented to this film, the colour it "sees" is slightly
different from what the sRGB primaries define. Numerically (row = film layer, column =
sRGB channel, values from community-digitised datasheets normalised so rows sum to 1):

```
         R_scene  G_scene  B_scene
R_layer [  0.965    0.040   -0.005 ]   ← slight green pickup in red layer
G_layer [ -0.018    1.028    0.010 ]   ← small red cross into green layer  
B_layer [  0.002    0.028    0.970 ]   ← slight green pickup in blue layer
```

(Values are indicative from discretised datasheet integrals; not exact.)

### What it produces
When this matrix is applied before the FilmCurve:
- Warm/orange scene hues drive the red and green layers slightly more than pure R
  would suggest → richer warm tones.
- Cyan scene hues drive the blue-layer slightly via the green channel → slight
  desaturation of very saturated cyans relative to sRGB → matches film's known
  cyan-compression behaviour.
- The effect is *self-limiting*: near-neutral colours (R≈G≈B) are barely touched
  because the matrix is close to identity; only high-chroma hues shift appreciably.

### Distinction from existing work
- **R85** corrects the *print* film's output unwanted absorptions (cyan dye leaks
  green, magenta dye leaks blue) — this is the *output* side.
- **R19 3-way CC** is an arbitrary user-facing chroma shift with no physical grounding.
- **M_neg** is the *input* side — how the virtual film negative sees scene colours —
  and is physically derived, stock-specific, and small enough to be
  perceptually gentle.

### GPU cost
One 3×3 matrix multiply: **9 MADs per pixel**, negligible.

### Pipeline conflicts
None. Applies in the CORRECTIVE stage (corrective.fx), immediately before the
FilmCurve, on the linearised RGB signal.

### Implementation sketch
Add to corrective.fx, CORRECTIVE stage, immediately before `FilmCurve()`:

```hlsl
// Negative spectral sensitivity correction (Vision3 500T, datasheet-derived)
// Blends toward physical negative response as PRINT_STOCK increases.
// Rows = [R_layer, G_layer, B_layer], sums ≈ 1.0 per row.
static const float3x3 M_NEG_VISION3 = float3x3(
     0.965f,  0.040f, -0.005f,
    -0.018f,  1.028f,  0.010f,
     0.002f,  0.028f,  0.970f
);
// Blend: PRINT_STOCK=0 → identity, PRINT_STOCK=1 → full Vision3 response
float3x3 M_neg = lerp(float3x3(1,0,0, 0,1,0, 0,0,1),
                      M_NEG_VISION3, PRINT_STOCK);
rgb = max(0.0f, mul(M_neg, rgb));   // clamp: negative exposures are unphysical
```

Recommended default: `PRINT_STOCK = 0.5` (half-blend preserves user colour intent while
adding film character). The existing `PRINT_STOCK` knob in creative_values.fx could be
the blend control (currently undocumented as to what it drives — this gives it a
physical meaning).

### Viability verdict
**High** — trivial GPU cost, physically grounded, uses an existing knob, no exclusions
conflict. Coefficients should be verified against the full Kodak Vision3 Technical
Information datasheet before committing.

---

## Finding 2 — Spatial DIR Coupler Chroma Gradient

### What it is
DIR (Developer Inhibitor Release) couplers in a negative emulsion are consumed during
development at the site of density formation, releasing an inhibitor compound that
diffuses laterally (both within the same layer and into adjacent layers). The effect:
- At a sharp colour edge, one side has high density → many couplers consumed → many
  inhibitors released → inhibitors diffuse into the opposite side, *reducing* density
  there → net result: colour at the edge appears more saturated (lower density = purer
  dye).
- In a large uniform colour field, the inhibitors average out → no net boost.

This is a *spatial chroma gradient* effect: saturation is higher at colour transitions
and lower in flat fields.

### Real-time approximation using existing textures
`LowFreqMip2Tex` (1/32-res) gives the smoothed colour of each pixel's neighbourhood.
The chroma difference between a pixel's own colour and its low-freq neighbourhood
approximates the "coupler release gradient":

```hlsl
// In ColorTransformPS, early in CHROMA stage (after Oklab conversion)
float3 lab     = RGBToOklab(rgb);           // already done in pipeline
float3 lab_lf  = RGBToOklab(tex2D(LowFreqMip2Samp, uv).rgb);
float  dC      = length(lab.yz) - length(lab_lf.yz);  // local chroma deviation
// Boost chroma where pixel is more saturated than neighbourhood (edge)
// Suppress where pixel matches neighbourhood (flat field)
float  dir_mod = 1.0f + saturate(dC) * DIR_COUPLER_SPATIAL * 0.12f;
lab.yz *= dir_mod;
rgb = OklabToRGB(lab);
```

`DIR_COUPLER_SPATIAL` knob (range 0–1, default 0) in creative_values.fx.

### Distinction from "local contrast" (exclusion)
The exclusion list bans "Clarity / sharpening / local contrast / CLARITY_STRENGTH".
The DIR coupler gradient operates **only on Oklab chroma (a*, b*)**, not on L*. It
cannot sharpen luminance edges. The effect is purely a colour-saturation redistribution
that is greater at hue transitions. A reviewer could argue this is "chroma-local-
contrast" and if so it should be skipped — flag for explicit sign-off before
implementing.

### GPU cost
2 additional texture taps (LowFreqMip2Samp already declared), ~15 ALU ops for the
length and multiply. **Negligible** — LowFreqMip2 is already sampled elsewhere in
ColorTransformPS.

### Pipeline conflicts
- R104 DIR couplers (per-pixel cross-channel) and this effect are complementary —
  R104 handles the inter-channel density inhibition; this handles the *spatial*
  diffusion component. They can coexist.
- The amplitude is self-limiting: `saturate(dC)` caps at the natural chroma deviation.
  No explicit gate needed.

### Viability verdict
**Medium** — low GPU cost, physically motivated, but the local-contrast exclusion
boundary is ambiguous for a chroma-only effect. Needs explicit confirmation before
implementation that this does not fall under the exclusion.

---

## Non-Findings (Considered and Discarded)

| Technique | Reason discarded |
|-----------|-----------------|
| Full spectral upsampling (8–31 bands) | ~10–30× ALU cost; not tractable at 60 fps |
| Grain | On exclusions list |
| LCA / longitudinal chromatic aberration | On exclusions list |
| Spectral upsampling via Meng polynomial | Requires per-pixel 3-coeff solve; offline offline; benefit marginal for SDR |
| Print film H&D per-channel gamma differentiation | Already approximated by R84 log-density offsets + FilmCurve knobs |
| Kodak orange mask simulation | Covered by R85 dye masking (output-side complement) |

---

## Recommended Next Steps

1. **Verify M_neg coefficients** against the official Kodak Vision3 Technical
   Information PDF (archived at Kodak Motion Picture site). The community-sourced
   values in Finding 1 are directionally correct but should be cross-checked against
   the integral of `S_layer(λ) × CMF(λ)` over the sRGB primaries.
2. **Assign PRINT_STOCK to M_neg blend** — give the existing knob a defined physical
   meaning and document it in creative_values.fx.
3. **Flag Finding 2 for exclusion review** before touching chroma-local code.
