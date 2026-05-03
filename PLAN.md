# Pipeline Improvement Plan
**Goal:** Raise every stage to 90% finished / 75% novel (game-specific sense).
**Created:** 2026-05-03 | **Updated:** 2026-05-03

---

## Phase status

| Phase | Status | Notes |
|-------|--------|-------|
| 1 — Research | **Done** | R74–R80 all researched, findings docs committed |
| 2 — Quick code | **Done** | R74, R75, R47 shipped in `50c1cc4` |
| 3 — Stage 0 | **Blocked** | R76A/B caused all-white screen; reverted. See HANDOFF.md |
| 4 — Stage 2 | Ready | R77 findings: no code changes needed |
| 5 — Stage 3 | Ready | R78 constant-hue gamut projection |
| 6 — Stage 3.5 | Ready | R79A/B/C halation |
| 7 — Output | Ready | R80A/B/C Pro-Mist |

---

## Current state (after Phase 2)

| Stage | Finished | Novel | Remaining gap |
|-------|----------|-------|--------------|
| Stage 0 — Input | 80% | 20% | Phase 3 blocked |
| Stage 1 — Corrective | 90% | 75% | **Done** |
| Stage 2 — Tonal | 90% | 93% | **Done** |
| Stage 3 — Chroma | 90% | 96% | **Done** |
| Stage 3.5 — Halation | 68% | 55% | Phase 6 pending |
| Output — Pro-Mist | 72% | 48% | Phase 7 pending |

Stage 1/2/3 targets reached. Stage 0 blocked on R76 debug.

---

## Research items

### R74 — Highlight Desaturation
**Targets:** Stage 1 finished +5%, Stage 3 finished +3%

R22 applies Munsell-calibrated chroma rolloffs in shadows only. Film print stock
desaturates near paper white — chroma approaches zero as luminance approaches 1.0.
The highlight arm is absent.

Research: Derive correct Oklab C rolloff shape at high Lightness from Munsell data.
Confirm whether R51 print stock desat_w partially covers this or needs a separate term.

Likely implementation (Stage 3, after R22 shadow block):
```hlsl
C *= 1.0 - 0.30 * saturate((lab.x - 0.80) / 0.20);
```

GPU cost: 2 ALU. No new taps, no new knobs.

---

### R75 — Hue-by-Luminance Rotation
**Targets:** Stage 1 finished +4%, Stage 3 finished +3%, Stage 1 novel +3%

Film print stock dye response is not tonally neutral: shadows acquire a blue-green cast
(thin dye layer transparency to base), highlights acquire a warm cast (dye at low
density is warm-biased). Currently `r21_delta` is hue-dependent but luminance-agnostic.
The 3-way CC (R19) applies uniform RGB shifts per zone — it cannot apply hue rotation
that varies by luminance.

Research: Derive sign and magnitude of hue rotation per tonal zone from Kodak 2383
spectral data. Map to Oklab hue-normalised units (0–1).

Likely implementation: luminance-weighted additive delta on `r21_delta` before it feeds
`h_out`. ≤3 lines.

GPU cost: ~3 ALU. No new taps, no new knobs.

---

### R76 — Perceptual Input Normalization
**Targets:** Stage 0 finished +10%, Stage 0 novel +55%

Stage 0 is currently EXPOSURE (power) + FILM_FLOOR/CEILING. No game pipeline has a
perceptual input stage. Two components, implemented sequentially.

**R76A — CAT16 scene-illuminant chromatic adaptation.**
The scene illuminant chromaticity is available from `CreativeLowFreqTex mip 2` (already
used by R66). CAT16 normalises toward D65 in LMS cone space — more principled than
R19's linear RGB shifts, which operate in the wrong physiological space. Unlike the
dismissed Gray World auto-WB, this uses the spatially-measured illuminant from the
analysis infrastructure, not a mean assumption. R19 becomes an artistic deviation from
the CAT16 neutral rather than a scene correction.

Research: Derive CAT16 forward transform in HLSL (linear algebra — no new textures).
Validate illuminant estimate quality from mip 2 across diverse game scenes. Confirm
no double-correction interaction with R19.

**R76B — CIECAM02 viewing condition surround compensation.**
CIECAM02 models how perceived contrast varies with display surround luminance: a
dark-room player needs more contrast than a bright-room player for equivalent appearance.
The surround factor `Fs` adjusts the effective tone response. A single new knob
`VIEWING_SURROUND` (dark / dim / average) applies the correction at the input stage
before FilmCurve shapes the response.

Research: Derive the surround-adaptive exposure correction from CIECAM02 Appendix A.
Validate against standard test patterns at each surround setting.

Note: R76A must be implemented and validated before R76B. The CAT16 neutral is the
reference point for the surround model.

GPU cost: CAT16 = matrix multiply (9 MAD). Surround = 2–3 ALU. No new taps.

---

### R77 — Stage 2 Calibration
**Targets:** Stage 2 finished +3%

Stage 2 is already at 93% novel. This is a finishing pass only — research + parameter
validation, may produce zero code changes.

Three targeted validations:

1. **R65/R66 interaction** — Both R65 (Hunt coupling) and R66 (ambient shadow tint)
   write to `lab_t.y/z` in the shadow region. Validate that combined weight does not
   over-correct in worst-case: low-key scene with strong ambient hue.

2. **Retinex blend weight** — `0.75 * ss_04_25` is empirical. Validate against
   zone_std extremes (flat/uniform vs. high-variance) to confirm the blend doesn't
   over-flatten or under-normalise.

3. **R60 temporal context exponent** — `exp2(log2(slow_key/zk_safe) * 0.4)`: the
   0.4 exponent is unverified. Confirm it correctly tracks typical scene-key change
   rates via analysis of Arc Raiders gameplay log output.

Research deliverable: numerical analysis of R65/R66 combined weight across parameter
space + R60 output value sampling from `/tmp/vkbasalt.log`.

---

### R78 — Constant-Hue Gamut Projection
**Targets:** Stage 3 finished +3%

The `gclip` fallback projects toward `L_grey` when `rmax > 1`. This does not follow
constant-hue lines in Oklab — it produces a visible hue shift on out-of-gamut pixels.
R68B (pre-knee) reduces how often gclip fires, but it remains active as a safety net.

Replace L_grey projection with a constant-hue projection: find scale factor `s` such
that `OklabToRGB(float3(density_L, f_oka*s, f_okb*s)).max == 1`. Preserves the ab
hue direction while compressing chroma.

Research: Derive closed-form constant-hue compression using headroom and current C.
Determine whether a 2-iteration binary search or a direct headroom-based approximation
is sufficient. Validate no visual artifacts on sRGB boundary.

GPU cost: ~4 ALU for closed-form approximation. Replaces current gclip block at same cost.

---

### R79 — Halation Dual-PSF + Gate Refinement + Chromatic Dispersion
**Targets:** Stage 3.5 finished +22%, Stage 3.5 novel +20%

Three components, implemented in order.

**R79A — Soften hal_gate.**
Current threshold `smoothstep(0.80, 0.95, hal_luma)` is too conservative.
Mid-brightness coloured surfaces (luma 0.55–0.75) near light sources receive no
halation in film. Research the correct Kodak 2383 halation onset vs. exposure density.
Likely gate onset at ~0.65.

**R79B — Dual-Gaussian PSF per channel.**
Real film halation has a tight core (~1–2px spread) plus extended wings (~8–12px).
Currently one mip per channel (single spatial scale). Adding a second mip level per
channel (mip 0 for tight core, mip 2 for extended wing) with a split blend weight
models the two-lobe response. Red: mip 1 core + mip 2 wing. Green: mip 0 core + mip 1
wing. Blue: remains 0.

**R79C — Chromatic dispersion in scatter.**
The extended wing is slightly warmer than the tight core — longer wavelengths penetrate
deeper into the film base and scatter further. Tight mip preserves input colour; extended
wing shifts toward warm dye bias (slight amber lean). No new taps — different colour
weighting on core vs. wing contributions per channel.

Research: Kodak 2383 data sheet halation section for gate onset and scatter radius
ratios. Optical two-Gaussian PSF literature for parameter derivation.

GPU cost: +2 tex taps (mip 2 for red and green extended wing). ~6 additional ALU.

---

### R80 — Pro-Mist Spectral Scatter Model
**Targets:** Output finished +18%, Output novel +27%

Three components, R80B/C independent of R80A.

**R80A — Wavelength-dependent scatter.**
Optical diffusion materials scatter shorter wavelengths more (Mie/Rayleigh mix).
A Pro-Mist filter's polymer particles produce slight blue-biased scatter — the bloom
halo is cooler-coloured than a luminance-based scatter implies. Split the mip blend
by channel: blue channel weighted toward finer mip (tighter scatter kernel), red toward
coarser.

**R80B — Scene-key adaptive strength.**
Mist visually dominates in low-luminance conditions (point lights in dark environments).
High-key exterior scenes require less mist for the same knob value. Scale scatter blend
by `zone_log_key^0.3` — dark scenes get more mist, bright scenes less. Zero new taps,
uses existing zone_log_key.

**R80C — Aperture proxy via EXPOSURE.**
Real optical diffusion filters interact with lens aperture — wider aperture converges
rays before the filter, reducing effective diffusion. `EXPOSURE` correlates loosely
with relative aperture. Using `EXPOSURE` as a proxy to modulate scatter radius adds a
physical dimension no other mist implementation has.

Research: Published optical characterisation of diffusion filters (Lindgren 2019 MTF
measurements or equivalent) and Mie scattering approximations for polymer particles.
Derive spectral weighting and aperture-scatter relationship.

GPU cost: R80A = ~2 ALU (weighted channel blend). R80B = 1 pow + 1 mul. R80C = 1 mul.
No new taps.

---

### R47 — Enable Shadow Warm Bias
**Targets:** Stage 1 finished +3%, Analysis infra finished**

Shadow warm bias pass (R47) is implemented in `corrective.fx` but disabled pending
visual validation. Validate against Arc Raiders and GZW. Enable if no seaming artifacts.

---

## Execution order

| Phase | Items | Stages | Status |
|-------|-------|--------|--------|
| 1 — Research | R74–R80 | All | **Done** |
| 2 — Quick code | R74, R75, R47 | Stage 1, 3 | **Done** |
| 3 — Stage 0 | R76A (CAT16), R76B (surround) | Stage 0 | **Blocked — white screen** |
| 4 — Stage 2 | R77 calibration | Stage 2 | **Skip — no code changes needed** |
| 5 — Stage 3 | R78 gamut projection | Stage 3 | Ready |
| 6 — Stage 3.5 | R79A → R79B → R79C | Stage 3.5 | Ready |
| 7 — Output | R80A, then R80B + R80C | Pro-Mist | Ready |

**R76 blocked.** White screen on load after R76A insertion. See HANDOFF.md for
root cause analysis. Phases 5–7 are fully independent and can proceed in parallel.

---

## Projected outcomes

| Stage | Finished | Novel |
|-------|----------|-------|
| Stage 0 | 90% | 75% |
| Stage 1 | 90% | 75% |
| Stage 2 | 90% | 93% |
| Stage 3 | 90% | 96% |
| Stage 3.5 | 90% | 75% |
| Output | 90% | 75% |
