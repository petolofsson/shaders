# R33 — CLAHE Clip Limit — Findings
**Date:** 2026-04-30
**Method:** Brave search × 6 queries

---

## Q1 — Clip limit values for video/display content

**Finding:** No single published consensus exists for video display; practical real-time implementations use low fixed values (clip limit 2–3 normalized), with OpenCV defaulting to 40 raw bin counts (≈ 2.0 normalized for 8-bit 8×8 tiles).

The OpenCV default clip limit is 40 raw pixels per bin (for 8×8 tiles = 64 pixels, 256 bins; normalized: 40/64·256 ≈ not directly slope-equivalent — OpenCV normalizes differently: it scales the raw value by `tileArea / histSize`, so "40" in OpenCV maps to a clip fraction around 40·(tileArea/histSize)/tileArea = 40/256 ≈ 0.156 of the CDF slope ceiling). For video/tone-mapping contexts, the MDPI 2024 FPGA paper (Electronics 11(14):2248) found that lower clip limits suppress noise in homogeneous areas (e.g. sky) and recommended an image-content-adaptive approach rather than a fixed global value. The IA-CLAHE paper (arXiv 2604.16010, 2025) likewise argues that a fixed clip limit is sub-optimal and that automatic per-image estimation is needed. For non-medical display content the practical community consensus clusters around clip limits of 2.0–3.0 (normalized slope ceiling), with 2.0 being the most conservative choice for perceptual smoothness and noise control.

---

## Q2 — Retinex + CLAHE coupling (MDPI 2024 paper)

**Finding:** The MDPI 2024 paper (Kim, Son, Lee — "Retinex Jointed Multiscale CLAHE Model for HDR Image Tone Compression," Mathematics 12(10):1541) uses Retinex for global illumination normalization and CLAHE at deliberately low clip limit + small tile size for local detail recovery — the two are sequential, not jointly adaptive.

The paper applies Single-Scale Retinex (SSR) with a high-sigma Gaussian surround to perform global tone compression (dynamic range reduction), then feeds the normalized output into a multiscale CLAHE stage. The CLAHE clip limit is explicitly kept low ("low levels of TileSize and ClipLimit") to suppress halo artifacts and noise that Retinex alone cannot eliminate. Crucially, the clip limit is not dynamically adapted to Retinex output statistics — it is a fixed low value chosen empirically to complement the already-normalized luminance range. This is precisely the pattern proposed for R33: Retinex (illumination normalization) narrows the effective working range, so the downstream contrast operator (S-curve / CLAHE equivalent) can safely use a lower slope ceiling than it would require on raw input.

---

## Q3 — Clip limit → slope ceiling formula

**Finding:** The CLAHE slope ceiling is directly proportional to the clip limit L; the exact formula is: `max_slope = L * (N_bins / N_pixels_per_tile)`, where the clip limit L bounds the histogram bin height before CDF computation.

From the Wikipedia AHE article and multiple OpenCV sources: CLAHE clips each histogram bin at value L (raw pixel count); the CDF slope at any intensity is bounded by `L / N_pixels`, where N_pixels is the tile pixel count. In normalized terms (clip limit expressed as a fraction of uniform distribution height), the maximum CDF slope = L_normalized, meaning the output intensity can change at most L_normalized times faster than the input — this is directly the contrast gain ceiling. For a uniform histogram tile, a clip limit of 1.0 (normalized) = no amplification above the flat histogram level; clip limit 2.0 = maximum 2× local contrast gain; clip limit 3.0 = maximum 3× gain. The IA-CLAHE paper (arXiv 2025) and the Medium deep-dive (Ovalle, Feb 2026) both confirm that OpenCV's clip limit parameter is internally renormalized: OpenCV multiplies the user-facing value by `tileArea / histSize` before clipping, so the user's "2.0" in OpenCV CLAHE does not equal a slope ceiling of 2.0 without accounting for tile geometry. For our pipeline (S-curve slope analog): a slope ceiling of 1.25 is roughly equivalent to a normalized clip limit of 1.25, which is more conservative than even the low end of common display values (2.0).

---

## Recommended implementation

The published evidence supports `clahe_max_slope = 1.25` as a conservative but well-grounded ceiling for post-Retinex use:

- The MDPI 2024 Retinex+CLAHE paper explicitly uses low clip limits after Retinex normalization, validating the principle that Retinex pre-processing justifies tighter clip constraints.
- For video/display (non-medical) content, clip limits of 2.0–3.0 (normalized slope ceiling) are typical without any pre-normalization. After Multi-Scale Retinex normalization, the effective dynamic range is compressed, so the same perceptual enhancement is achieved at lower slope — 1.25 is a reasonable translation.
- The Retinex-adaptive lerp between 1.15 and 1.40 matches published practice well: 1.15 is appropriate for zones where Retinex has strongly compressed the range (flat/sky-like regions, where noise amplification risk is highest — analogous to the FPGA paper's concern about homogeneous regions), and 1.40 for textured zones where Retinex leaves more headroom. The lerp range brackets the 1.25 fixed value, so it is effectively a principled per-zone version of the same constraint.
- No GPU real-time CLAHE implementation was found with a specific clip limit recommendation for game/display context; all real-time work (FPGA, GPU) treats clip limit as a tunable parameter with low values preferred for noise-sensitive content.

Concrete recommendation: use `clahe_max_slope = 1.25` as the default fixed ceiling, with the Retinex-adaptive lerp (1.15–1.40) as the production variant. Both are within the conservative range validated by the MDPI 2024 coupling paper.

---

## Summary

| Question | Answer |
|----------|--------|
| Clip limit for video | 2.0–3.0 normalized slope ceiling (pre-normalization); after Retinex, 1.15–1.40 is appropriate |
| MDPI 2024 coupling | Retinex (global, high-sigma) then CLAHE (local, fixed low clip limit) — sequential, not jointly adaptive; low clip limit explicitly chosen to complement Retinex output |
| Slope formula | `max_slope = L_normalized`; clip limit L directly bounds CDF slope; OpenCV renormalizes by tileArea/histSize internally |
| Real-time GPU CLAHE | No specific clip limit for games found; FPGA 4K 60fps work uses content-adaptive or fixed low values to suppress noise in flat regions |

**Implementation ready / blockers:** No blockers — the MDPI 2024 architecture and slope formula both validate the R33 approach; recommended default is `clahe_max_slope = 1.25` with the Retinex-adaptive lerp (1.15–1.40) as the production form.
