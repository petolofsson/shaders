## Research Job R23N — Pro-Mist Optical Model Improvement

**Type:** One-shot  
**Output:** `research/R23N_{YYYY-MM-DD}_pro_mist.md`  
**Do not modify any source files.**

---

### Context — read these first

1. `CLAUDE.md` — pipeline constraints (no gates, SDR by construction, no knobs preferred)
2. `research/HANDOFF.md` — full pipeline state
3. `general/pro-mist/pro_mist.fx` — current implementation (read the full file carefully)
4. `general/pro-mist/README.md`
5. `gamespecific/arc_raiders/shaders/creative_values.fx` — current knob values
6. `general/corrective/corrective.fx` — what analysis textures are available (PercTex, ChromaHistoryTex, etc.)
7. `research/2026-04-29_clarity.md` — prior clarity/pro_mist research findings

---

### What the current implementation does

The shader runs a separable 9-tap Gaussian on the full-resolution BackBuffer, then composites the blurred result back using a luminance gate. The gate is the primary problem: three hardcoded constants (`DIFFUSE_LUMA_LO=0.55`, `DIFFUSE_LUMA_HI=0.65`, `DIFFUSE_LUMA_CAP=0.95`) create a fixed activation window that assumes all scenes have similar exposure. Two knobs (`DIFFUSE_RADIUS`, `DIFFUSE_STRENGTH`) are user-facing. `CLARITY_STRENGTH` from grade.fx is borrowed — coupling pro_mist's clarity to the grade's clarity setting.

The physical reference: **Black Pro-Mist** is a diffusion filter with embedded micro-crystals that scatter light. Visual signature: soft corona around practical lights, reduced micro-contrast without bloom, characteristic warm tint to highlight halos (warm channels scatter slightly more). Used by Deakins (Blade Runner 2049), Hoyte van Hoytema (Oppenheimer). Not glowy — anchored, subtle.

---

### Research questions

#### Q1 — Scene-adaptive threshold (replacing the three luma gate constants)

The scatter onset should track the scene's bright range, not a fixed 0.55–0.65 window. `PercTex` provides `p25 (.r)`, `p50 (.g)`, `p75 (.b)` every frame.

Research and propose: a smooth, gate-free formula for scatter onset and falloff derived from PercTex that correctly places the diffusion activation in the highlight region of any scene. The formula must:
- Have no hard conditionals on pixel luma
- Produce no visible seam as the scene transitions (temporal stability via PercTex EMA)
- Work correctly for both dark scenes (GZW night maps) and bright outdoor scenes (Arc Raiders)

Candidate anchor: `p75` as the scatter midpoint, IQR (`p75 - p25`) as the activation width. Derive the full expression.

#### Q2 — Kernel shape: Gaussian vs Lorentzian vs sum-of-Gaussians

The current 9-tap Gaussian has an exponential rolloff. The real Black Pro-Mist scatter kernel has longer tails — the corona effect (light spreading into dark surroundings) requires a Lorentzian (Cauchy) profile: `k(r) = 1 / (1 + (r/σ)²)`. 

A Lorentzian is not separable in the standard sense, but it can be approximated as a weighted sum of 2–3 Gaussians at different radii (known as a multi-Gaussian decomposition). This is a standard technique in optics simulation.

Research: what is the correct kernel shape for Black Pro-Mist scatter? Is a sum-of-two-Gaussians (fine + coarse) achievable within the existing two-pass structure? The `CreativeLowFreqTex` (1/8-res base image, already computed by corrective.fx) could serve as the wide-scatter component at zero additional GPU cost.

Propose: a kernel spec that uses the existing full-res blur pass for the fine component and CreativeLowFreqTex for the wide-tail component, combined at composite time. Specify the blend ratio between fine and coarse components.

#### Q3 — Chromatic scatter (warm highlight glow, zero knobs)

The Black Pro-Mist's characteristic warmth comes from wavelength-dependent scattering: polymer crystals scatter long wavelengths (red/yellow) more than short (blue). This is the opposite of standard chromatic aberration (which is blue-heavy). The result is a warm corona around bright lights.

Research: what is the correct per-channel weighting for Black Pro-Mist scatter? Is there manufacturer data (Tiffen) or cinematography literature on the spectral response? Propose a fixed per-channel weight vector `(wr, wg, wb)` with `wr > wg > wb`, normalized so that achromatic pixels remain achromatic. This must be baked — zero user knobs.

#### Q4 — DIFFUSE_STRENGTH elimination

Current: `DIFFUSE_STRENGTH * lerp(0.7, 1.3, saturate(iqr / 0.5))`. The base `DIFFUSE_STRENGTH` is a user knob.

Research: what should the base scatter strength be for a physical Black Pro-Mist #1/2 filter simulation? Tiffen makes #1/4, #1/2, #1, #2, #3, #5 grades. The #1/2 is the most common cinematographic choice (subtle, not dreamlike). Propose a baked base strength with IQR-adaptive scaling that covers the equivalent of #1/4 to #1 grades automatically. Remove the knob.

#### Q5 — DIFFUSE_RADIUS elimination

Current: `DIFFUSE_RADIUS / 4.0` applied uniformly. The scatter radius of a real filter scales with source brightness — brighter highlights produce a larger corona.

Research: propose a scene-adaptive radius driven by `p75` or `p90` (approximated as `p75 + 0.5 * iqr`) from PercTex. High-key bright scenes get wider scatter; low-key dark scenes get tighter. Propose a smooth formula mapping `[p75 range]` to `[radius_min, radius_max]` in UV-space. Remove the knob.

#### Q6 — Clarity decoupling

The current `CLARITY_STRENGTH` reference borrows from grade.fx — changing the grade's midtone clarity unintentionally changes pro_mist's Laplacian residual boost. These should be independent.

Propose: bake the pro_mist clarity contribution at a fixed value (assess what's physically correct for a diffusion filter — does a Black Pro-Mist actually increase local midtone contrast, or is it purely softening?). If baked, at what value? If scene-adaptive, from what signal?

---

### Literature search (use Brave Search)

Search arxiv.org, ACM Digital Library, and optics literature for:

1. `"Black Pro-Mist" optical model scattering kernel` — any quantitative characterization of the filter's scatter profile
2. `diffusion filter simulation real-time GPU "sum of gaussians"` — multi-scale Gaussian approximation of long-tail kernels
3. `"halation" film simulation scatter chromatic wavelength` — spectral scatter in film/glass simulation
4. `Tiffen "Pro-Mist" spectral transmission MTF` — manufacturer or third-party optical measurements
5. `Lorentzian scatter kernel separable approximation GPU` — real-time approximation methods

For each relevant paper found: title, authors, year, URL, 3-sentence relevance summary, and specific mathematical claim that applies to this shader.

---

### Output format

```
# R23N — Pro-Mist Optical Model Research — {YYYY-MM-DD}

## Summary
{3 sentences: what the current model gets wrong, what the biggest improvements are}

## Q1 — Scene-adaptive threshold
### Finding
### Proposed formula (HLSL)
### Literature support

## Q2 — Kernel shape
### Finding
### Proposed architecture (how to combine full-res blur + CreativeLowFreqTex)
### Literature support

## Q3 — Chromatic scatter
### Finding
### Proposed weight vector (wr, wg, wb)
### Literature support

## Q4 — Strength automation
### Finding
### Proposed formula (HLSL)
### Baked base value rationale

## Q5 — Radius automation
### Finding
### Proposed formula (HLSL)

## Q6 — Clarity decoupling
### Finding
### Recommendation (baked value or formula)

## Knob reduction summary
| Knob | Status after this proposal |
|------|---------------------------|
| DIFFUSE_STRENGTH | ... |
| DIFFUSE_RADIUS   | ... |
| CLARITY coupling | ... |

## Implementation priority
{ordered list — which findings to implement first and why}

## Brave Search findings
{papers found, with relevance summaries}
```
