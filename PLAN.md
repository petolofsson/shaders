# Pipeline Improvement Plan

> **Purpose (for AI context):** Tracks novelty and completion scores per pipeline stage with reasoning. Use this to understand *why* each score is what it is before proposing new work. Do not inflate scores — the reasoning column is the audit trail.

All stages at or above target. Stage 0 ceiling is content-limited (testbed ~80% achromatic).

| Stage | Finished | Novel |
|-------|----------|-------|
| Stage 0 — Input (inverse_grade) | 98% | 90% |
| Stage 1 — Film Stock | 98% | 91% |
| Stage 2 — Tonal | 97% | 91% |
| Stage 3 — Color + Halation | 98% | 92% |
| Output — Diffusion + Grain | 97% | 91% |

## Score reasoning

**Stage 0 — Input (90% novel)**
Novel: IQR-based compression estimate (R148 Bowley-corrected), Kalman-smoothed slope, mean-C pivot (scene median), per-hue HueCeil gamut ceilings, R156 per-hue slope bias (orange +0.20, teal/cyan −0.05), R157 achromatic-fraction adaptive c_gate (0.10→0.06 above 60% achromatic), R163 dominant-hue alignment bias (±15% complementary/aligned), R164 LUMA_MEAN_PRE slope cap (bright scenes 2.2→1.5), R165 illuminant warmth CCT proxy (CAT16 LMS slot 220 — warm-lit scenes scale back warm-hue bias up to 50%). R159 removed luma expansion (zone S-curve owns luma; pivot-based L expansion caused texture smoothing on bright surfaces). Drag: chroma scaling chassis is standard.

**Stage 1 — Film Stock (91% novel)**
Novel: Kodak 2383 3×3 spectral dye matrix from H-1-2383t data (first-of-kind real-time), full physical chain (H&D curve R84, chromatic floor R83, masking coupler R110, DIR couplers R104), R153 fc_stevens from histogram mode (physically correct for Stevens calibration — was zone_log_key), R160 adaptive print stock (p25 black lift backs off when shadows already elevated; p75 shoulder softens in bright scenes). Drag: S-curve shape and 3-way CC are standard.

**Stage 2 — Tonal (91% novel)**
Novel: Oklab-stable L-substitution (R62), intra-zone pixel variance driver (R116), ambient shadow tint (R66), R133 Munsell per-hue highlight rolloff (12-band exponents from Renotation), R152 zone CDF intra-bin interpolation (~8× precision), R147 histogram mode signal. Drag: Retinex and zone system are established techniques.

**Stage 3 — Color + Halation (92% novel)**
Novel: HELMLAB Fourier correction, MacAdam ellipse ceilings, HK, Abney, Hunt, Purkinje (507nm shift + scotopic desat, R150 mode-gated), R151 halation driven by p90−p50 specular gap, R151 chroma lift by mean_C inverse, R133 Munsell rolloff. Drag: hue rotation and basic chroma lift are common in grading tools.

**Output — Diffusion + Grain (91% novel)**
Novel: dual-component HBM split (shimmer self-limiting on blurred>sharp), R132 polydisperse chromatic scatter (R:G:B = 1.15:1.00:0.85), R136 Selwyn 2383 grain (pcg3d RGB-decorrelated, Selwyn envelope, ~24fps turnover via timer), R149 Bowley-adaptive diffusion. Drag: Gaussian-blur-and-blend chassis is ubiquitous.
