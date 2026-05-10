# Pipeline Improvement Plan

> **Purpose (for AI context):** Tracks novelty and completion scores per pipeline stage with reasoning. Use this to understand *why* each score is what it is before proposing new work. Do not inflate scores — the reasoning column is the audit trail. Novelty is assessed against the video game post-processing domain, not color science literature.

| Stage | Finished | Novel |
|-------|----------|-------|
| Stage 0 — Input (inverse_grade) | 98% | 92% |
| Stage 1 — Film Stock | 98% | 94% |
| Stage 2 — Tonal | 97% | 91% |
| Stage 3 — Color + Halation | 98% | 90% |
| Output — Diffusion + Grain | 97% | 93% |

## Score reasoning

**Stage 0 — Input (92% novel)**
No game post-processing pipeline attempts to undo tonemapper compression. The IQR-based chroma recovery, Bowley-corrected slope, per-hue HueCeil ceilings, R156 hue-specific slope bias, R163 dominant-hue alignment, R165 illuminant warmth CCT proxy — none of this exists in any game engine. The data highway architecture itself (passing scene statistics via BackBuffer row 0) is not a pattern found in game post-processing. Drag: "chroma boost" as a concept exists in saturation knobs; the expansion direction is the same even if the mechanism is different.

**Stage 1 — Film Stock (94% novel)**
Games approximate film stocks with LUTs — even RDR2's celebrated film look is LUT-based. The 2383 3×3 spectral dye matrix from H-1-2383t primary data, H&D curve, DIR couplers, masking coupler, and chromatic floor are not found anywhere in game post-processing. fc_stevens driven by histogram mode, adaptive print stock from p25/p75 — not in games. Drag: 3-way CC exists in UE5's color grading stack; S-curve tone shaping is universal.

**Stage 2 — Tonal (91% novel)**
Games have auto-exposure. Nothing else in this stage exists in game pipelines: zone system contrast from histogram statistics, Retinex illumination decomposition, Oklab-stable L-substitution, intra-zone pixel variance driver, Munsell per-hue highlight rolloff calibrated from Renotation data, ambient shadow tint from scene illuminant. Drag: auto-exposure is structurally related to the zone key signal; adaptive contrast as a concept exists in some engines (e.g. UE5 eye adaptation).

**Stage 3 — Color + Halation (90% novel)**
Purkinje shift, Abney effect, Hunt effect, Helmholtz-Kohlrausch, HELMLAB Fourier hue correction — none of these are implemented in any commercial game engine. Halation as emulsion physics (p90−p50 specular gap, per-layer dye depth) is not found in games; bloom is. MacAdam ellipse gamut ceilings are not in games. Drag: hue rotation exists in UE5 and most grading stacks; basic saturation/vibrance is universal. The perceptual effects are novel in the domain; their individual components are textbook color science.

**Output — Diffusion + Grain (93% novel)**
Game grain is universally simple: white noise or at best single-octave blue noise with a flat amplitude. The Selwyn 2383 granularity envelope, three-octave value noise, luma-dependent grain size, per-channel dye layer sizing (G finest, B coarsest) — not found in any game. HBM dual-component diffusion split (shimmer self-limiting, midtone overlay separately gated) is not a pattern in game bloom/diffusion. Polydisperse chromatic scatter per channel is not in games. Drag: film grain and bloom both exist as concepts; the Gaussian blur chassis is universal.
