# R126 — Film Spectral Emulation: Print Film Stage and DIR Coupler Inhibition

**Date:** 2026-05-08
**Domain:** Film stock spectral emulation (Friday rotation)
**Status:** Viable — two independent findings; see conflict flags before implementation

---

## Summary of literature surveyed

- vkdt `filmsim` module (jo.dreggn.org) — GPU-accelerated two-stage negative+print pipeline with DIR coupler model
- JanLohse/spectral_film_lut (GitHub) — LUT generation from Kodak/Fuji published datasheets using spectral sensitivity matrices
- andreavolpato/spektrafilm (GitHub, 2025) — full analog process simulation (spectral sensitivity → characteristic curve → dye couplers → print)
- Plutino 2024, *Color Research & Application* — review of motion picture film digitization color systems (ADX/APD replacing Cineon)
- MDPI 2023, "Digital Unfading of Chromogenic Film" — spectral dye density decomposition into per-layer contributions

---

## Finding 1 — Print film second-stage S-curve

### What the literature shows

Every physically-based film emulator surveyed (vkdt filmsim, Filmbox, spectral_film_lut) models a **two-stage pipeline**:

1. **Negative stage** — scene exposure → per-layer density via spectral sensitivity + characteristic curve (γ ≈ 0.50–0.65 for Vision3 500T).
2. **Print stage** — negative optical print → print stock characteristic curve (γ ≈ 2.5–3.0 for Kodak 2383 / Fuji 3513).

The combined system gamma is ~ γ_neg × γ_print ≈ 0.60 × 3.0 = **1.8**, which is what produces the characteristic "pop" and tonal compression of projected cinema.

The print stage contributes three distinct effects not present in the negative curve alone:

| Effect | Cause | Visual result |
|--------|-------|---------------|
| High midtone gamma (~3) | Print stock characteristic curve slope | Punchy/saturated midtones |
| Per-channel shoulder compression | Blue layer saturates before green before red | Warm highlight roll-off (shadows cool, highlights warm) |
| Print D-min additive | Unexposed print base fog | Lifted black floor — blue leans slightly (Kodak 2383 D-min_B ≈ 0.07, D-min_R ≈ 0.04) |

The per-channel shoulder order (blue → green → red saturation order) is the physical origin of the warm-highlight, cool-shadow split seen in almost all cinema print looks. It is *not* a grading decision — it is the physics of the print dye absorption ordering.

### Relevance to this pipeline

The existing pipeline:
- **R84** covers the negative characteristic curve (log₂-density offsets for CURVE_R/B_KNEE/TOE).
- **R83** covers the negative D-min pedestal (FILM_FLOOR, per-channel, CAT16-modulated).
- **FILM_CEILING** provides a soft highlight shoulder.

**What is missing:** a print film gamma pass. The existing curve is negative-only; there is no second-stage densitometric amplification. The `PRINT_STOCK` knob exists but its implementation is unknown from the research context — this finding proposes whether it encodes a per-channel S-curve or a single scalar.

### Implementation sketch

Apply in the FilmCurve section of `grade.fx`, after negative characteristic curve, before tone/chroma stages:

```hlsl
// Print film stage — log-density amplification (per-channel)
// dens_r/g/b already in log-density from negative stage
// Kodak 2383 approximation: gamma_print ~ 3.0
// In our log₂-density space, this means multiply by print_gamma
// and apply a per-channel shoulder at saturation density D_max

float PRINT_GAMMA = 1.55; // in creative_values.fx; net effect gamma_neg*gamma_print ~ 1.8
// Per-channel D_sat (density at which print dye saturates, normalized 0-1):
float PRINT_DSAT_R = 0.92;
float PRINT_DSAT_G = 0.87;
float PRINT_DSAT_B = 0.78; // blue saturates first

float3 dens = float3(dens_r, dens_g, dens_b);

// Shoulder: soft clip at per-channel saturation density
dens.r = dens.r - max(0, dens.r - PRINT_DSAT_R) * 0.55;
dens.g = dens.g - max(0, dens.g - PRINT_DSAT_G) * 0.55;
dens.b = dens.b - max(0, dens.b - PRINT_DSAT_B) * 0.55;

// Print gamma amplification
dens = pow(dens, PRINT_GAMMA);

// Print D-min additive (separate from negative FILM_FLOOR)
// Small per-channel offset: blue > green > red
dens += float3(0.00, 0.006, 0.015) * PRINT_FLOOR_STR;
```

All variables in `creative_values.fx`. No new passes, no new textures.

### GPU cost

| Operation | Cost |
|-----------|------|
| 3× `max(0, x - sat)` shoulder | 3 MAD |
| 3× `pow(dens, PRINT_GAMMA)` | 3 ALU (compiler typically maps to exp/log) |
| D-min additive | 3 ADD |
| **Total** | **~9 ALU** |
| New taps | 0 |
| New passes | 0 |

### Conflicts and constraints

- **FILM_CEILING knob** already provides a highlight shoulder — the per-channel print shoulder above may overlap. Recommend: keep FILM_CEILING as the negative shoulder (before print stage), add PRINT_DSAT_* as print stage shoulders. They work at different densities.
- **SDR constraint satisfied** — `pow(dens, PRINT_GAMMA)` output is bounded if input dens ≤ 1.0; the shoulder clamp ensures this. `saturate()` at final output is the intended SDR ceiling.
- **No gates** — the shoulder is `max(0, x - thresh) * factor`, a continuous ramp with no discontinuity. Not a hard conditional.
- **`PRINT_STOCK` knob** — if already in use, this finding may overlap. Inspect current PRINT_STOCK implementation before adding new per-channel parameters.

---

## Finding 2 — DIR coupler inter-layer density inhibition (per-pixel, non-spatial)

### What the literature shows

vkdt filmsim's technical documentation distinguishes two coupler types:

1. **Masking couplers** (already covered by R85): constant inter-channel dye absorption cross-talk. The orange base mask of C-41/ECN-2 negatives. Implemented as a 3×3 matrix.

2. **Direct Inhibitor Couplers (DIR)**: release inhibitor *proportional to local dye density* during development. High density in one layer → inhibitor diffuses into adjacent layer → suppresses density formation there. Effect is **density-modulated**, not constant.

The inter-layer spatial diffusion of DIR inhibitors produces a sharpening effect (explicitly noted in vkdt docs as "increases local contrast and perceived sharpness"). This spatial component is **excluded** by pipeline rules (no sharpening/clarity).

However, DIR also has a per-pixel inter-layer component: saturation in one channel reduces density in adjacent channels at the same pixel. This is color-only, not a sharpening effect, and is not excluded.

Published models (spektrafilm, Bayer/Walowit 1985 referenced in spectral simulation literature):
- Cyan layer at high density → inhibits magenta layer formation → reduces G-channel effective density by ~5–12% at D_max
- Magenta layer at high density → inhibits yellow layer formation → reduces B-channel effective density by ~4–9% at D_max
- Effect onset is above a threshold density (~40% of D_max) and scales roughly linearly to D_max

This produces **saturation roll-off in dense (dark) regions** — colors in the shadows become less saturated relative to midtones. Not a gate; it is a density-dependent continuous function.

### Distinction from R85

R85 implements constant cross-contamination: cyan dye absorbs 2% of green light, magenta dye absorbs 2.2% of blue light. These are fixed percentage offsets applied at all densities.

DIR inhibition is **density-weighted**: the more cyan dye there is, the more it suppresses magenta formation. At low densities (bright areas) the inhibition is near zero; at high densities (shadows/darks) it is maximum. The two effects coexist in real film and are not redundant.

### Implementation sketch

Applied in the density domain, after R85 masking correction, before inversion to RGB:

```hlsl
// DIR coupler inter-layer inhibition (per-pixel, non-spatial)
// dens_c, dens_m, dens_y are log-density values [0,1]
float DIR_STR = DIR_COUPLER_STRENGTH; // creative_values.fx, default 0.5

// Onset above ~40% D_max
float3 onset = float3(0.40, 0.40, 0.40);
float dir_cy_excess = max(0.0, dens_c - onset.r); // how far above onset
float dir_mg_excess = max(0.0, dens_m - onset.g);

// Inhibition magnitudes from literature (Bayer/Walowit, vkdt calibration)
// Cyan suppresses magenta ~8% per unit density above onset
// Magenta suppresses yellow ~6% per unit density above onset
float inh_cy_on_mg = dir_cy_excess * 0.08 * DIR_STR;
float inh_mg_on_ye = dir_mg_excess * 0.06 * DIR_STR;

dens_m = max(0.0, dens_m - inh_cy_on_mg);
dens_y = max(0.0, dens_y - inh_mg_on_ye);
```

Effect: in dense shadow regions, magenta and yellow are slightly suppressed relative to cyan, which is the per-pixel source of the mild cross-color desaturation in film shadows. Not a full desaturation — subtly hue-shifts shadows toward cyan/blue in dense areas.

### GPU cost

| Operation | Cost |
|-----------|------|
| 2× `max(0, dens - onset)` | 2 MAD |
| 2× multiply + scale | 4 MAD |
| 2× `max(0, dens - inh)` | 2 MAD |
| **Total** | **~8 MAD** |
| New taps | 0 |
| New passes | 0 |
| New highway slots | 0 |

### Conflicts and constraints

- **No gates** — `max(0, x - threshold)` is a continuous ramp; no seams.
- **SDR safe** — densities are clamped by their own upstream saturate(); output goes through the same inversion.
- **Exclusion check: sharpening** — only the spatial DIR diffusion (cross-pixel inhibition) would produce sharpening. The implementation above is strictly per-pixel. No spatial read. Not sharpening.
- **R85 interaction** — apply DIR inhibition *before* R85 if R85 is post-density-inversion (i.e., in linear RGB space). Apply *after* R85 if R85 is in the density domain. The ordering must match whichever domain R85 currently operates in. Check grade.fx before implementing.
- **Density-domain availability** — requires working in the log-density representation already used by FilmCurve (R84). If the density domain is transient (local to FilmCurve pass), DIR inhibition slots in naturally there.

---

## Finding 3 (informational, lower priority) — Spectral sensitivity input matrix

### What the literature shows

JanLohse/spectral_film_lut and spektrafilm both derive a **3×3 input matrix** by sampling each film stock's published spectral sensitivity curves at the sRGB primary wavelengths (R≈630nm, G≈530nm, B≈460nm). This matrix converts sRGB input into per-layer effective log-exposure before the characteristic curve is applied.

Kodak 500T (5219) datasheet shows the red-sensitive layer has meaningful response down to ~530nm, creating a cross-talk between red and green exposures not present in digital cameras. This is the mechanism behind "Kodak skin tones" — the red-layer absorbs more of the green channel than a pure colorimetric transform would predict.

### Why not implementing now

- The pipeline receives sRGB video, not spectral radiance. A 3×3 input matrix would be an approximation at best (sRGB primaries are not monochromatic; the matrix derived by sampling them against film spectral sensitivities has significant metameric failure at saturated hues).
- R85 already captures some of this cross-talk phenomenologically for the output/print stage.
- The input sensitivity matrix would interact with every subsequent stage and requires calibration against real film footage.
- Viable, but complex and not self-validating. Worth a dedicated research file when the input matrix pathway is confirmed to be missing from the pipeline.

---

## Stage impact estimate

| Finding | Novelty | GPU cost | Risk |
|---------|---------|----------|------|
| F1 Print S-curve | High (second stage, not in existing pipeline) | ~9 ALU | Low — check PRINT_STOCK overlap |
| F2 DIR inhibition | Medium (density-dependent version of R85 mechanism) | ~8 MAD | Low — check R85 domain |
| F3 Input matrix | Low (partially covered by R85) | 9 MAD | Medium — metameric failure risk |

Recommended order of implementation: F1 → F2. F3 deferred pending pipeline confirmation.
