# Pipeline Improvement Plan

> **Purpose (for AI context):** Tracks novelty and completion scores per pipeline stage with reasoning. Use this to understand *why* each score is what it is before proposing new work. Do not inflate scores — the reasoning column is the audit trail.

All stages at or above target. Stage 0 ceiling is content-limited (testbed ~80% achromatic).

| Stage | Finished | Novel |
|-------|----------|-------|
| Stage 0 — Input (inverse_grade) | 97% | 83% |
| Stage 1 — Film Stock | 97% | 90% |
| Stage 2 — Tonal | 96% | 91% |
| Stage 3 — Color + Halation | 98% | 92% |
| Output — Diffusion | 96% | 85% |

## Score reasoning

**Stage 0 — Input (83% novel)**
Core op is plain chroma scaling (`lab.yz *= factor`) — the operation itself is non-novel. Novel parts: IQR-based compression estimate, Kalman-smoothed slope, mean-C pivot, per-hue HueCeil gamut ceilings, C-gate. Ceiling confirmed by diagnostic: all per-hue band wsums ≈ 0 even in the most colorful testbed scene. Cannot improve without content with measurable per-hue chroma.

**Stage 1 — Film Stock (90% novel)**
R130 Kodak 2383 3×3 spectral dye matrix from published H-1-2383t data is first-of-kind in real-time post-process. Full physical chain: log-density H&D curve (R84), chromatic floor (R83), masking coupler (R110), DIR couplers (R104). Drag: S-curve shape and 3-way CC are standard.

**Stage 2 — Tonal (91% novel)**
Novel: Oklab-stable L-substitution (R62), intra-zone pixel variance driver (R116), temporal context ratio (R60), ambient shadow tint (R66), fine-texture shadow gate (R119), R133 Munsell per-hue highlight rolloff (12-band exponents from Munsell Renotation — yellow n=0.22 late onset, orange n=0.81 fast; physically grounded C→0 at L=1.0). Drag: Retinex (Land & McCann 1971) and zone system (Adams 1940s) carry real visual weight despite the novel implementation details.

**Stage 3 — Color + Halation (92% novel)**
Densest science in the pipeline. Chroma: HELMLAB Fourier correction, MacAdam ellipse ceilings, HK, Abney, Hunt, Purkinje (a*+b* blue-green shift + scotopic desaturation). Halation: blur-minus-sharp annular PSF, Lorentzian tail, emulsion-derived chromatic gains (all in the same MegaPass — Stage 3.5 dissolved). Drag: R21 hue rotation and basic chroma lift are common in grading tools.

**Output — Diffusion (85% novel)**
Novel: scene-adaptive strength (IQR + zone_key + EXPOSURE), dual-component split where shimmer fires only on `blurred > sharp` (self-limiting), R132 polydisperse chromatic scatter (red ×1.15, blue ×0.85). Drag: the Gaussian-blur-and-blend chassis is the ubiquitous game bloom mechanism — non-novel mass is larger than initially accounted.
