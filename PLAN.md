# Pipeline Improvement Plan

> **Purpose (for AI context):** Tracks novelty and completion scores per pipeline stage with reasoning. Use this to understand *why* each score is what it is before proposing new work. Do not inflate scores — the reasoning column is the audit trail. Novelty is assessed against the video game post-processing domain, not color science literature.
>
> **On sourcing (2026-05-15):** All physics-direction constants are now sourced from literature (audit complete). Calibration amplitudes throughout all stages (scale factors, lerp endpoints, coupler magnitudes) are empirically tuned — direction is literature-grounded, specific value is observation-calibrated. This is standard practice; film lab constants are proprietary.

| Stage | Finished | Novel |
|-------|----------|-------|
| Stage 0 — Input (inverse_grade) | 99% | 90% |
| Stage 1 — Film Stock | 99% | 93% |
| Stage 2 — Tonal | 98% | 90% |
| Stage 3 — Color + Halation | 98% | 89% |
| Output — Diffusion + Grain | 98% | 93% |

## Score reasoning

**Stage 0 — Input (90% novel)**
No game post-processing pipeline attempts to undo tonemapper compression — that domain claim is solid. The data highway architecture (HighwayTex 256×1 R16F, scene statistics across effects) is not a pattern in game post-processing. Per-hue HueCeil ceilings from Munsell Renotation data, FilmCurve pre-inverse (`FilmCurveInvCh`) applied before chroma expansion — not found in games. R198: piecewise exact FilmCurve inverse with histogram-derived knee per frame — genuinely novel in real-time.

Drag reducing score: (1) INVERSE_LUMA now uses Mertens et al. 2007 bell weight from exposure fusion literature — the technique is published and the application is an adaptation, not an invention. (2) Chroma expansion using IQR-derived slope borrows from statistical signal processing; the Oklab color space is Ottosson 2020. (3) "Chroma boost / vibrance" as a concept exists in every game's post-process stack — the mechanism here is more principled but the concept is not new. (4) ACES closed-form inverse is published math; the novelty is in the context (game post-processing), not the formula itself.

Remaining 1%: the slope `lerp(1.8, 1.15, saturate(median_C / 0.15))` is calibrated against ACES specifically — would need re-derivation for Hejl, GT Tone Mapper, or custom curves.

**Stage 1 — Film Stock (93% novel)**
Games approximate film stocks with LUTs — even RDR2's celebrated film look is LUT-based. The 2383 3×3 spectral dye matrix from H-1-2383t primary data, H&D curve, DIR couplers, chromatic floor, masking coupler — none of this exists in any game post-processing pipeline. Rational film curve with histogram-mode-derived knee, adaptive print stock from scene percentiles — not in games. R192 P3: PRINT_STOCK/BLEACH_BYPASS in `ApplyLook` post-chroma — correct physical LMT placement.

Drag reducing score: (1) 3-way CC exists in UE5 and most real-time grading stacks — not novel. (2) S-curve tone shaping is universal. (3) DIR-adjacent couplers exist in desktop photo tools (DxO FilmPack, Silver Efex) — novel in real-time games but not in the broader tooling ecosystem. (4) DIR_COUPLER is now hardcoded at 0.30 rather than user-exposed — minor reduction in implemented scope. Drag from (1)+(2) is substantial since CC and curves together represent a large fraction of Stage 1's functional surface area.

Remaining 1%: BLEACH_BYPASS shadow desaturation calibration pending visual evaluation against real footage references.

**Stage 2 — Tonal (90% novel)**
Zone system contrast from histogram statistics, Retinex illumination decomposition (2-scale: 1/16-res + 1/32-res), Oklab-stable L-substitution, ambient shadow tint from scene illuminant — none of this is in any commercial game engine. R190: guided filter (Hu et al. IET IP 2023) with adaptive ε replaces bilateral — eliminates halo artifacts, content-adaptive smoothing.

Drag reducing score: (1) CLARITY is conceptually Lightroom Clarity — the guided filter implementation is more principled than bilateral but the concept is well-known in desktop color tools. The upper highlight gate (just bug-fixed today) was documented behavior that was missing from code — a completion, not a novelty claim. (2) Shadow lift is adaptive but fundamentally a shadow brightening operation — every game has some form of shadow detail preservation. (3) Retinex (Land 1971 / Jobson 1997) is a classic algorithm; novelty is in the application context only. (4) Auto-exposure is structurally adjacent to zone key — UE5 eye adaptation overlaps conceptually even if the mechanism differs. (5) LUMA_CONTRAST_* hue-selective clarity shares the same guided filter signal — more of a UI extension than a new technique.

Remaining 2%: GF_EPS=0.05 is a fixed regularization — content-adaptive ε scheduling against actual scene variance is the principled completion.

**Stage 3 — Color + Halation (89% novel)**
Purkinje shift, Abney effect, Hunt effect, Helmholtz-Kohlrausch — none implemented in any commercial game engine; all literature-grounded with correct scale factors. HELMLAB Fourier hue correction and Munsell Renotation gamut ceilings (HueCeil) are not found in games. R196-E: cusp-relative chroma compression mapping [0.85,∞)→[0.85,1.0) asymptotically matches ACES2 principle in Oklab space.

Drag reducing score: (1) Halation has a fundamental modeling limitation: the effect fires on the source pixel itself (DoG detects the source, adds orange there), not on a genuine ring around it. True film halation scatters from the source outward — this requires a dedicated blur pass that doesn't exist. The sky suppression (exp(−max(0,B−R)×7)) is a practical heuristic, not an emulsion model. The luma-neutral tint (subtracting the luma component) is trivial linear algebra. The halation is visually useful but physically approximate. (2) Hue rotation, saturation, and vibrance knobs exist in UE5 and every real-time grading stack — 6-band per-hue control is more granular than most games but the concept is not new. (3) Shadow cast (bipolar warm/cool) is a tinting operation — conceptually not different from a shadow CC wheel with two modes. (4) The three scene-adaptive effects (halation rem-jet, HK magnitude, Abney scale) are each individually literature-grounded but the adaptation constants are empirically calibrated, not derived from display-referred psychophysical measurements.

Remaining 2%: halation without a dedicated scatter pass remains a DoG source-tint approximation; Abney and HK scale calibration against display-referred measurements is unresolved.

**Output — Diffusion + Grain (93% novel)**
Selwyn 2383 granularity envelope `sqrt(1−L_gamma)` with per-channel dye layer sizing (R:G:B = 1.00:0.80:1.50 matched to 2383 cyan/magenta/yellow dye depth), single 24fps slot snap — none of this exists in any game. HBM dual-component diffusion (additive shimmer + midtone overlay, separately gated) is not a pattern in game bloom. Polydisperse chromatic scatter per channel not in games.

Drag reducing score: (1) Film grain as a concept is universal in games — the novelty is in the envelope and channel model, not in grain per se. (2) Bloom/diffusion is universal in games — the Gaussian blur chassis underlying the diffusion passes is entirely standard. The dual-component model and radial oval PSF sit on top of stock Gaussian blur infrastructure. (3) Half-res grain clustering (floor(pos×0.5)×2 snap) is a creative implementation detail but similar techniques exist in procedural texture generation — low novelty on its own. (4) The HBM radial PSF shape (xs=1.6, ys=0.08) is observation-calibrated, not derived from measured diffusion PSF data from actual lenslet characterization.

Remaining 2%: Selwyn amplitude coefficient (0.018) is empirical, not derived from densitometric measurements of actual 2383 stock; HBM radial shape is not physically measured.
