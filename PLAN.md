# Pipeline Improvement Plan

> **Purpose (for AI context):** Tracks novelty and completion scores per pipeline stage with reasoning. Use this to understand *why* each score is what it is before proposing new work. Do not inflate scores — the reasoning column is the audit trail. Novelty is assessed against the video game post-processing domain, not color science literature.
>
> **On sourcing (2026-05-13):** All physics-direction constants are now sourced from literature (audit complete). Calibration amplitudes throughout all stages (scale factors, lerp endpoints, coupler magnitudes) are empirically tuned — direction is literature-grounded, specific value is observation-calibrated. This is standard practice; film lab constants are proprietary. The remaining 1% gap in Stage 3 finished = those calibration amplitudes.

| Stage | Finished | Novel |
|-------|----------|-------|
| Stage 0 — Input (inverse_grade) | 99% | 92% |
| Stage 1 — Film Stock | 98% | 94% |
| Stage 2 — Tonal | 97% | 91% |
| Stage 3 — Color + Halation | 99% | 92% |
| Output — Diffusion + Grain | 97% | 94% |

## Score reasoning

**Stage 0 — Input (92% novel)**
No game post-processing pipeline attempts to undo tonemapper compression. The IQR-based chroma recovery, Bowley-corrected slope, per-hue HueCeil ceilings, R156 hue-specific slope bias, R163 dominant-hue alignment, R165 illuminant warmth CCT proxy — none of this exists in any game engine. R187 zero-anchored expansion (`C × factor`, ACES toe_inv-matched) with `(1 − lab.x)` continuous luma weight — full expansion at L=0, zero at L=1 — replaces the R186 bilateral zone system and correctly reflects that highlights cannot recover chroma due to gamut geometry at high luminance (cinema mastering data: highlight ΔC = −0.008, shadows/mids gain ~67% chroma). Single-pass; no bilateral blur textures. The data highway architecture itself (HighwayTex 256×1 R16F, passing scene statistics across effects) is not a pattern found in game post-processing. Drag: "chroma boost" as a concept exists in saturation knobs; the expansion direction is the same even if the mechanism is different.

**Stage 1 — Film Stock (94% novel)**
Games approximate film stocks with LUTs — even RDR2's celebrated film look is LUT-based. The 2383 3×3 spectral dye matrix from H-1-2383t primary data, H&D curve, DIR couplers, masking coupler, and chromatic floor are not found anywhere in game post-processing. Rational film curve with histogram-mode-derived knee, adaptive print stock from p25/p75 — not in games. Drag: 3-way CC exists in UE5's color grading stack; S-curve tone shaping is universal.

**Stage 2 — Tonal (91% novel)**
Games have auto-exposure. Nothing else in this stage exists in game pipelines: zone system contrast from histogram statistics, Retinex illumination decomposition, Oklab-stable L-substitution, intra-zone pixel variance driver, Munsell per-hue highlight rolloff calibrated from Renotation data, ambient shadow tint from scene illuminant. Drag: auto-exposure is structurally related to the zone key signal; adaptive contrast as a concept exists in some engines (e.g. UE5 eye adaptation).

**Stage 3 — Color + Halation (92% novel)**
Purkinje shift, Abney effect, Hunt effect, Helmholtz-Kohlrausch, HELMLAB Fourier hue correction — none of these are implemented in any commercial game engine. Halation as emulsion physics (p90−p50 specular gap, per-layer dye depth) is not found in games; bloom is. MacAdam ellipse gamut ceilings are not in games. Three effects now scene-adaptive: (1) illuminant-adaptive halation rem-jet — G channel weights modulated by CAT16 warmth proxy (NeutralIllumTex), first physically-motivated adaptive halation in any game pipeline; (2) scene-adaptive HK magnitude — `lerp(0.32, 0.18, zone_log_key / 0.50)`, correctly scales photopic correction with adapting luminance per Hellwig 2022 + Nayatani 1997 (HK is STRONGER at low luminance — direction inversion bug fixed in audit); (3) scene-adaptive Abney scale — `1 + median_C × 0.25`, amplifies hue shifts in chromatically-rich environments per surround-induction literature (Pridmore 2007, Kirschmann). Hardcoded constant audit complete: HK per-hue `f_hk` from Hellwig 2022 Fourier fit, C^0.587 exponent same source; Abney per-hue coefficients from Pridmore 2007 bimodal data (YELLOW near-null, CYAN largest — both corrected); halation G weights from emulsion spectral physics (R:G:B ≈ 30:3:1, G/R corrected from 0.43 → 0.10); halation g_mod scale 0.25 and Abney scene-scale 0.25 are conservative calibrations directionally supported by literature, not directly measured. No game implements any of these perceptual effects, let alone adaptively coupled to scene statistics. Drag: hue rotation exists in UE5 and most grading stacks; basic saturation/vibrance is universal.

**Output — Diffusion + Grain (94% novel)**
Game grain is universally simple: white noise or at best single-octave blue noise with a flat amplitude. The Selwyn 2383 granularity envelope, two-octave value+blue-noise, luma-dependent grain size, per-channel dye layer sizing (G finest, B coarsest), and temporal cross-dissolve eliminating screen-space snap — none of this exists in any game. R168 physical halation as a DoG PSF with separate AH-layer (rem-jet) attenuation on the tight ring is an emulsion physics model, not a bloom effect; no game implements it. HBM dual-component diffusion split (shimmer self-limiting, midtone overlay separately gated) is not a pattern in game bloom/diffusion. Polydisperse chromatic scatter per channel is not in games. Drag: film grain and bloom both exist as concepts; the Gaussian blur chassis is universal.
