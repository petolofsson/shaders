# Pipeline Improvement Plan

> **Purpose (for AI context):** Tracks novelty and completion scores per pipeline stage with reasoning. Use this to understand *why* each score is what it is before proposing new work. Do not inflate scores — the reasoning column is the audit trail.

Finished scores reflect functional completeness. Novel scores are deliberately conservative — "novel" means not readily available in commercial grading tools or published real-time pipelines, not just "we wrote it ourselves."

| Stage | Finished | Novel |
|-------|----------|-------|
| Stage 0 — Input (inverse_grade) | 98% | 83% |
| Stage 1 — Film Stock | 98% | 88% |
| Stage 2 — Tonal | 97% | 84% |
| Stage 3 — Color + Halation | 98% | 83% |
| Output — Diffusion + Grain | 97% | 87% |

## Score reasoning

**Stage 0 — Input (83% novel)**
The core concept — estimate tonemapper compression from IQR, expand chroma to compensate — is directly analogous to what DaVinci Resolve's colour space transform and similar tools do. Not novel at the concept level. Novel parts: Bowley-corrected IQR slope (R148), per-hue HueCeil gamut ceilings calibrated from Munsell data, R156 per-hue slope bias encoding ACES compression excess, R163 dominant-hue alignment bias, R165 illuminant warmth CCT proxy (CAT16 LMS from NeutralIllumTex to slot 220). R157 achromatic c_gate and R163 alignment bias are sensible signal wiring but not research contributions. R164 dropped (permanently). Drag: the expansion chassis itself is standard.

**Stage 1 — Film Stock (88% novel)**
The 2383 3×3 spectral dye matrix from H-1-2383t primary data is the genuine standout — first-of-kind in real-time SDR post-processing. Full physical chain (H&D curve, chromatic floor, masking coupler, DIR couplers) is a novel combination. R153 fc_stevens from histogram mode is a physically correct insight (mode tracks perceived brightness, was zone_log_key). R160 adaptive print stock (p25 black lift, p75 shoulder) is sensible engineering but not novel — the idea of backing off lift when shadows are already raised is common sense in grading. Drag: S-curve and 3-way CC are found in every grading tool.

**Stage 2 — Tonal (84% novel)**
Zone system (Adams) and Retinex (Land & McCann) are explicitly established techniques. Ambient shadow tint (R66) is standard in colour grading. Intra-zone pixel variance driver (R116) is a reasonable signal choice but not a novel concept. Novel parts: Oklab-stable L-substitution (R62) is a practical insight for luma work in perceptual space, Munsell per-hue highlight rolloff (R133) calibrated from Renotation V=8→10 C_max ratios is genuinely novel, histogram mode for Stevens calibration (R147/R153) is a correct perceptual connection. Zone CDF intra-bin interpolation (R152) is a precision improvement, not a conceptual contribution.

**Stage 3 — Color + Halation (83% novel)**
Most of Stage 3 is implementation of known perceptual models: HELMLAB Fourier (Moroney 2003), Helmholtz-Kohlrausch (published 1858/1972), Abney (1909), Hunt (1952), Purkinje (1825). The combination in a real-time SDR pipeline is novel; the individual effects are textbook. What is genuinely novel: R151 halation gated on p90−p50 specular gap (specific real-time signal), chroma lift pivoting on mean_C inverse (scene-adaptive), R133 Munsell rolloff shared with Stage 2. MacAdam ellipse ceilings are well-known perceptual bounds; applying them as real-time per-hue gamut ceilings is a practical novel step. Drag: hue rotation, basic chroma lift, and all six perceptual corrections have published antecedents.

**Output — Diffusion + Grain (87% novel)**
Grain is the strongest novelty claim: Selwyn 2383 granularity equation adapted to real-time (R136), three-octave value noise with luma-dependent grain size (shadows coarser, R167), per-channel dye layer sizing (G finest, B coarsest, R167), blue noise 1px octave (R167) — this combination is not found elsewhere in real-time post-processing. HBM dual-component split (shimmer self-limiting on blurred>sharp) is a novel decomposition. R132 polydisperse chromatic scatter per-channel is a physical insight. R149 Bowley-adaptive diffusion is signal wiring, not a conceptual contribution. Drag: Gaussian-blur-and-blend diffusion chassis is ubiquitous; value noise for grain is a known technique even if our calibration is novel.
