# R136 — Film Grain: Research Proposal
**Date:** 2026-05-09
**Stage:** Output (Stage 4) — novelty mechanism

---

## Problem statement

The Output stage sits at 85% novelty. The primary gap versus existing tools is the
absence of temporal film grain. Every major film emulation pipeline (DaVinci Film Look
Creator, FilmConvert, ACES/CTL 2383 print emulation, Resolve FilmGrain, darktable filmic)
includes grain as a first-class output stage. The current pipeline has none.

Grain is not decoration — it is a direct consequence of the silver halide crystal
distribution and dye-cloud formation in colour negative + print emulsion. Its presence
resolves the "too clean" character that digital game capture has and film scans do not.

The output stage currently consists only of the HBM diffusion blur-and-blend. A distinct
spatial-temporal noise mechanism with correct photographic behaviour would constitute a
genuinely novel output stage element.

---

## Research goals

### 1. Selwyn granularity and the exposure–grain relationship

- What is the Selwyn granularity coefficient (G or σ_D) for Kodak 2383 print stock?
- How does RMS granularity vary with diffuse density? The classic Selwyn model predicts
  σ_D ∝ D^α (granularity rises in shadows, falls in highlights).
- What aperture diameter is the standard measurement aperture (typically 48 μm)?
- Is the shadow-peak of grain variance broadly linear with 1/D or does it follow a
  steeper power law?
- Numerical target: what σ values (linear light) should grain amplitude span from
  pure black to diffuse highlight (L ≈ 0 → 0.7 in Oklab)?

### 2. Per-dye-layer decorrelation

- The three dye layers (cyan, magenta, yellow) are independently modulated. What are the
  cross-layer correlation coefficients measured from real 2383 scans?
- Is full RGB decorrelation achievable with independent R/G/B noise seeds, or does
  the coupling in Kodak 2383 require partially correlated noise?
- What is the amplitude ratio between the three channels? (Yellow layer is typically
  2–3× thinner → lower grain contribution; cyan layer dominant).

### 3. Grain spatial frequency character

- Real film grain is not white noise. The Wiener power spectrum of 2383 grain peaks in
  the 10–20 cycles/mm range. In screen pixels at 1080p: what cycle/pixel band does this
  correspond to (given typical pixel pitch ~0.3mm at viewing distance)?
- Is band-limited noise (e.g., gaussian-blurred white noise) a sufficient approximation
  at screen resolution, or does pixel-scale grain alias poorly?
- Can a single-tap hash function (no texture) produce grain with the correct spatial
  character, or is a texture lookup necessary?

### 4. Temporal aliasing and grain animation

- Static grain (same frame every frame) produces a strobing, buzzing artefact.
- Time-varying grain via a frame-counter or time seed is standard — what is the correct
  temporal strategy for a 60 fps display?
- Does frame-to-frame grain need to be temporally filtered (grain turnover rate in
  real film ≈ 4 frames at 24fps → 10 frames at 60fps equivalent), or is
  full independent per-frame noise correct?

### 5. Domain — linear light or perceptual

- Film grain is additive in log-density space → multiplicative in linear light.
- In a display-referred SDR pipeline (our context), should grain be added in linear
  light (pre-sRGB), gamma-expanded (~2.2), or Oklab L domain?
- What does adding grain in linear light look like vs. gamma domain? Difference
  on shadow grain amplitude?

### 6. Existing implementations to survey

- DaVinci Resolve grain node — what model does it use (documented in manual)?
- darktable's grain module — does it use a Selwyn model or ad-hoc?
- FilmConvert — any public description of their grain engine?
- OpenColorIO ACES/CTL — is there a grain node in the reference implementation?
- Any HLSL or GLSL grain implementations with correct exposure-dependence that can
  be adapted for SPIR-V?

---

## Hypotheses to validate or refute

- **H1:** Exposure-dependent grain amplitude `σ(L) = σ_max × (1 − L)^0.5` matches
  observed Selwyn model well enough for visual fidelity in a game context.
- **H2:** Full RGB decorrelation (three independent hash seeds per pixel) captures
  the dye-layer character sufficiently. Correlated noise not needed.
- **H3:** A single-tap frame-seeded hash (e.g., gold-noise, pcg3d) applied in
  gamma-2.2 domain gives perceptually correct grain without a noise texture.
- **H4:** Per-frame independent grain (new seed each frame, no temporal filter) is
  perceptually acceptable at 60fps.
- **H5:** Adding grain in Oklab L-then-convert-back is worse than adding directly
  in gamma domain, because L→lab→sRGB round-trip costs 2 sqrt + trig per pixel.

---

## Constraints

- One new pass or zero new passes preferred. Grain can run inside the final Diffusion
  pass (DiffusionPS already reads BackBuffer-equivalent via DiffusionTex). If added as
  a separate pass, it must add a Passthrough to keep BackBuffer alive.
- No texture. Hash function only — avoids texture memory and mip complications.
- SPIR-V safe: no `static const float[]`, no `out` variable, no tex2Dlod on BackBuffer.
- `GRAIN_STRENGTH` knob in `creative_values.fx`. 0 = off. 1.0 = calibrated default.
- Grain must respect the y=0 data highway guard: `if (pos.y < 1.0) return col`.
- SDR output: grain may not push pixels above 1.0 or below 0.0 — saturate() is the
  intentional SDR ceiling.
- Grain should be exposure-dependent (less in highlights, more in shadows) by construction.

---

## Deliverable

`R136_2026-05-09_film_grain_findings.md` covering:
- Selwyn σ values for 2383 at key density levels (numeric)
- Recommended amplitude curve `σ(L)` — formula + coefficients
- Channel amplitude ratios (R:G:B)
- Domain recommendation (linear / gamma / Oklab) with justification
- Temporal strategy recommendation
- Recommended HLSL hash function
- Implementation sketch — which pass, where in the pixel shader, how many lines
- Stage 4 novelty impact estimate
