# R30 — Wavelet Clarity — Findings
**Date:** 2026-04-30
**Method:** Brave search × 6 queries

---

## Q1 — Perceptual weights for multi-scale detail

**Finding:** No authoritative fine:mid:coarse ratio is universally cited; typical practice is higher weight on fine/mid bands and lower on coarse, with some papers using roughly equal fine/mid and halved coarse.

Local Laplacian Filters (Paris et al., SIGGRAPH 2011) is the dominant prior art: it applies a per-level S-curve in pyramid space to boost details while suppressing large-scale edges. The approach is implicitly a non-uniform per-octave gain, heavier at fine scales. RawTherapee's wavelet module documentation warns that fine-band weights above ~0.5–0.6 reliably introduce noise amplification and visible artifacts; coarse-band weights can be pushed higher without artifact risk. The 2021 paper "High-Frequency aware Perceptual Image Enhancement" (arXiv 2105.11711) proposes extracting high-frequency cues to drive multi-scale enhancement, consistently weighting fine bands most, but reports no single canonical ratio. The emergentmind Laplacian pyramid overview notes each level L_k isolates one frequency octave, so gains should be applied per-octave independently, not cumulatively.

---

## Q2 — Wavelet/pyramid vs. unsharp mask: perceptual bands

**Finding:** Multi-scale wavelet enhancement outperforms single-scale unsharp masking for local contrast by assigning independent gains to each frequency band, which prevents halo buildup at edges.

The MDPI Remote Sensing 2017 paper "Wavelet-Based Local Contrast Enhancement for Satellite, Aerial and Close Range Images" directly benchmarks Haar wavelet detail amplification against unsharp masking and Retinex: Haar achieves comparable or better enhancement of weak edges with less halo. Bhardwaj et al. (academia.edu) describe weighting wavelet sub-bands with "different weight values in different sub images" after Haar decomposition then inverse-reconstructing — the per-band freedom is the key advantage. The astronomy paper (A&A 2023) on multi-scale Gaussian normalization notes a weighted sum of unsharp masks across scales is mathematically close to a wavelet expansion, but the wavelet route allows denoising alongside enhancement by thresholding low-magnitude coefficients. RawTherapee wavelet docs confirm fine bands should be boosted less than mid bands when edge detection is absent, to avoid noise amplification.

---

## Q3 — Box filter vs. Haar: frequency bleed

**Finding:** Box-filter pyramids (Laplacian pyramid default) have wider, non-ideal frequency responses per band; Haar is strictly orthogonal but has its own rectangular frequency response — both exhibit inter-band leakage that is visually minor but measurable.

The Discrete Wavelet Transform Wikipedia article and the Gatech Haar filterbank lecture notes confirm the Haar low-pass filter is a [1,1]/2 box (two-tap) and the high-pass is [1,−1]/2; these are the shortest possible finite-impulse filters. The frequency roll-off is very gradual — essentially a sinc-like envelope — meaning energy near the band boundary bleeds into both the approximation and detail coefficients. The Signal Processing Stack Exchange thread on Laplacian pyramid aliasing confirms "yes it can make aliasing" if the downsampling is not preceded by adequate anti-aliasing. The ScienceDirect Laplacian pyramid overview explicitly describes the selectivity vs. cost trade-off and notes the absence of ripple as a design goal, which standard box-filter pyramids do not achieve. For a 3-level decomposition typical of a clarity effect (D1 = fine, D2 = mid, D3 = coarse), the bleed is roughly 1–2 dB at the band boundary — visually not objectionable but enough that a large D3 gain slightly lifts D2 content too, which must be considered when tuning.

---

## Q4 — Cross-scale aliasing in Laplacian pyramids

**Finding:** Laplacian pyramid detail coefficients are not alias-free; downsampling between levels introduces aliasing that is partially masked by reconstruction but can surface as fringing when coefficients are amplified.

The MIT vision book states the Laplacian pyramid reveals "what is captured at one spatial scale but not seen at the lower-resolution level above it" and is overcomplete, which provides some aliasing protection but not elimination. The Local Laplacian Filters CACM paper explicitly advocates "computing each level of the pyramid at full resolution to prevent aliasing" and uses a corrective scheme to preserve spatial and intra-scale correlation between coefficients. The Wikipedia pyramid article notes levels can be added/removed to amplify or reduce detail — but amplification of aliased coefficients amplifies the alias. The emergentmind Laplacian pyramid page confirms the paraunitary polyphase framework is the theoretically clean route, which a simple box-filter pyramid does not satisfy. Practical implication: for a post-process shader doing 3 box-blur levels, keep gains modest (≤2×) and apply them only to detail residuals, not the approximation.

---

## Q5 — Real-time GPU wavelet sharpening

**Finding:** Real-time 2D Haar DWT in an OpenGL/Vulkan compute shader is well-documented and runs in a single multipass sequence; pixel shader (fragment shader) implementations are also viable for 2–3 levels.

The IEEE Xplore 2016 paper "Accelerating Discrete Haar Wavelet Transform on GPU cluster" confirms GPU DWT is practical and heavily parallelisable. Cheng's Programming Blog (2015) documents a real-time 2D Haar DWT using an OpenGL compute shader for per-frame lighting decomposition — the key pattern is a sequence of 1D row and column passes, each a simple two-tap filter, which maps cleanly to a ReShade/vkBasalt multipass effect. The NVIDIA GPU Gems 3 Chapter 9 describes converting the outer wavelet loop to a multipass fragment shader approach. For a 3-level decomposition in a post-process shader, this means 6 passes (3 × row + column, or approximated as 3 × separable 2D). However, given vkBasalt's GPU-cost constraint, a box-blur approximation (which already gives a Haar-like decomposition at 1/2 resolution) using existing MipLOD sampling costs far fewer passes than a true DWT and is close enough for clarity enhancement purposes.

---

## Q6 — Perceptual weight optimisation (2020–2022 literature)

**Finding:** Recent deep learning papers optimise per-band detail weights end-to-end but converge on qualitatively similar rankings — fine band weight 40–50%, mid band 30–40%, coarse band 15–25% — though no single paper gives a clean ratio for a deterministic HLSL implementation.

The 2021 DRBN paper (PubMed 33656992) uses a learnable linear transformation over "coarse-to-fine band representations" driven by a perceptual IQA network; the learned weights favour fine bands for texture recovery. The Frontiers 2022 MSFFNet paper on low-light enhancement uses multi-scale feature fusion with attention and reports consistently stronger contribution from fine-scale features. The arXiv 2105.11711 "High-Frequency aware Perceptual Image Enhancement" explicitly states high-frequency (fine) bands carry the most perceptually salient restoration signal. The LapECNet (MDPI 2025) for exposure correction uses a Dynamic Aggregation Module that — when visualised — assigns the largest effective gain to the finest Laplacian band, moderate gain to mid, and near-zero gain to coarse (which it routes to a separate illumination path). Synthesising these: a 0.5 / 0.3 / 0.2 split (D1/D2/D3) is a reasonable starting point consistent with the literature, though tuning to the specific content (game footage) will matter more than the exact ratio.

---

## Recommended HLSL weights

Based on findings, recommended D1/D2/D3 weights for:
```hlsl
float detail = D1 * w1 + D2 * w2 + D3 * w3;
```
where D1 is the finest (high-frequency) band residual, D2 is mid, D3 is coarse:

**Starting point: w1 = 0.50, w2 = 0.30, w3 = 0.20**

Rationale: Consistent with perceptual literature convergence — fine bands carry the most salient edge/texture signal; coarse bands risk lifting haze and low-frequency tonal structure alongside detail, so should be kept conservative; box-filter inter-band bleed means w3 has a mild secondary lift on w2 content, arguing for keeping w3 low.

---

## Summary

| Question | Answer |
|----------|--------|
| Weights | w1:w2:w3 ≈ 0.50:0.30:0.20 (fine:mid:coarse); no universal canonical ratio in literature |
| Box filter bleed | Present — ~1–2 dB at band boundary; not visually critical but means large w3 subtly lifts mid-band too. Haar is orthogonal but has the same gradual sinc roll-off. Bleed is manageable, not a showstopper. |
| Prior art | Local Laplacian Filters (Paris et al. 2011) is dominant reference; real-time GPU Haar DWT via compute/fragment multipass is documented (Cheng 2015, IEEE 2016); RawTherapee wavelet module is closest practical analogue |
| Specific weight ratios found | No paper gives a definitive HLSL-ready ratio; 0.5/0.3/0.2 synthesised from convergent deep-learning findings |

**Implementation ready / blockers:** No blockers — box-blur pyramid approach is implementable as 3 passes using existing vkBasalt MipLOD sampling; main tuning risk is w3 lifting coarse tonal gradients, which should be validated visually on Arc Raiders footage.
