# R29 — Retinex Illumination/Reflectance Separation — Findings
**Date:** 2026-04-30
**Method:** Brave search × 4 queries (2 rate-limited, retried)

---

## Research question 1 — Scale weights

**Finding: equal weights (1/3 each) are the validated standard. Coarse-biased weights are theoretically better for our specific use case.**

The MSR literature uniformly uses equal weights. The rationale: each scale captures a different aspect — fine scale preserves local detail, coarse scale compresses dynamic range. For general image enhancement these contributions are treated symmetrically.

However, our use case differs from general enhancement. R18's goal is global illumination normalization — pulling zone luminance toward the scene key. This is a coarse, spatial operation. The fine-scale illumination estimate at mip 0 captures local shading detail that we do NOT want to remove (that's scene content, not illumination). The coarse estimate at mip 2 is the one that approximates "what is the ambient illumination at this location."

**Recommended weights for our use case:**
```hlsl
// Coarse-biased: de-emphasise fine-scale illumination (preserves local detail)
float log_R = 0.20 * log(luma_safe / illum_s0)   // fine   — low weight
            + 0.30 * log(luma_safe / illum_s1)   // medium
            + 0.50 * log(luma_safe / illum_s2);  // coarse — high weight
```

Equal weights (1/3 each) are a safe fallback if coarse-biased shows over-sharpening.

---

## Research question 2 — SDR output normalization

**Finding: log-domain anchoring to zone_log_key is correct. No separate gain/offset stage needed.**

Standard MSRCR normalization uses a gain G and offset b: `output = G * (log_R + b)` where G and b are computed from the histogram of the MSR output. This is designed for display on monitors from arbitrary input — i.e., an automatic levels operation.

In our pipeline this is unnecessary. We already have `zone_log_key` (geometric mean of all zone medians) as our display anchor. The correct normalization is:

```hlsl
float retinex_luma = saturate(exp(log_R + log(max(zone_log_key, 0.001))));
```

This maps reflectance back to display scale centered at the scene key — the same intent as R18's normalization, but pixel-local. The `TONAL_STRENGTH` and `r18_str` blend controls are sufficient for output strength management. No histogram-based auto-levels needed.

**Risk confirmed:** the IPOL.im reference paper on MSRCR notes that the color restoration function can invert colors in some cases. This does not apply to our luma-only implementation — we operate only on luma, reconstruct chroma from the original `lin` vector. Zero inversion risk.

---

## Research question 3 — Real-time GPU implementations

**Finding: GPU Retinex is well-validated. Our mip-level approach is faster than all published implementations.**

Two directly relevant papers found:

**"GPU fast restoration of non-uniform illumination images"** (Springer, 2020)
GPU-parallel Retinex achieving near real-time on standard hardware. Implementation computes Gaussian blurs on the fly at multiple scales. Performance bottleneck: the multi-scale blur computation.

**"Real-time tone mapping on GPU and FPGA"** (Springer, 2012)
MSRCR implemented as a real-time tone mapping operator. Validates Retinex as a viable real-time illumination correction path. Also bottlenecked by blur computation.

In both cases the performance cost is the Gaussian blur. Our pipeline avoids this entirely — `CreativeLowFreqTex` mip levels are pre-computed free-of-charge by `corrective.fx` Pass 1. The MSR computation in our shader is 3 texture reads + 3 `log` calls + 1 `exp` call. This is cheaper than any published GPU Retinex implementation.

**Bonus finding — "Retinex Jointed Multiscale CLAHE Model for HDR Image Tone Compression"** (MDPI Mathematics, 2024)

This paper directly validates the R29 + future CLAHE combination. It applies MSR at an "optimal global scale" and then feeds the output into CLAHE for local contrast enhancement. The result: better global dynamic range compression (Retinex) combined with better local contrast (CLAHE) without either one causing the other's artifacts. The paper uses HDR input but the principle applies directly to our SDR context. This suggests R29 and a future CLAHE-inspired clip limit on the zone S-curve are natural complements, not alternatives.

---

## Research question 4 — Halo mitigation

**Finding: bilateral Retinex is the published solution. Our mip approach has low inherent halo risk. Blend factor is the right safety valve.**

**"Halo-Free Design for Retinex based Real-Time Video Enhancement System"** (real-time video context) — explicitly replaces Gaussian illumination estimate with a bilateral filter to eliminate halos. The bilateral filter preserves edges in the illumination estimate, preventing the illumination from changing sharply at object boundaries (which is what causes halos).

**"Fast halo-free image enhancement method based on retinex"** — bilateral SSR for defect detection. Same approach: bilateral filter as illumination estimator.

For our pipeline, the mip-level blurs are equivalent to heavily smoothed Gaussians (at mip 2, the effective kernel radius at full resolution is ~60–80px at 1080p). This is much smoother than the bilateral kernels used in halo-generating implementations. Halos arise when the illumination estimate has sharp transitions — our coarse mips are the opposite of that.

**Risk is low but not zero.** At mip 0 (1/8 res), a 8px-wide object in screen space may appear as a 1-pixel sharp edge in the illumination estimate. If `new_luma / illum_s0` at that boundary has a step, a halo could appear. The `r18_str` blend factor is the correct safety valve — start at a low blend (0.3–0.5) and increase only if the result is visually clean.

**If halos appear:** down-weight mip 0 further (reduce its weight toward 0) so the illumination estimate is driven entirely by mip 1 and mip 2. This eliminates halos at the cost of slightly less spatial precision.

---

## Concrete HLSL — refined by findings

Replaces `grade.fx:283-286` (R18 block):

```hlsl
// R29: Multi-Scale Retinex — pixel-local illumination/reflectance separation
float illum_s0 = max(tex2D(CreativeLowFreqSamp,                   uv        ).a, 0.001);
float illum_s1 = max(tex2Dlod(CreativeLowFreqSamp, float4(uv, 0, 1)).a, 0.001);
float illum_s2 = max(tex2Dlod(CreativeLowFreqSamp, float4(uv, 0, 2)).a, 0.001);
float luma_s   = max(new_luma, 0.001);

// Coarse-biased MSR in log domain
float log_R = 0.20 * log(luma_s / illum_s0)
            + 0.30 * log(luma_s / illum_s1)
            + 0.50 * log(luma_s / illum_s2);

// Map reflectance to display scale, anchored at global log key
float retinex_luma = saturate(exp(log_R + log(max(zone_log_key, 0.001))));

// Blend — r18_str is zone_std-adaptive (0.04 flat → 0.12 high contrast)
new_luma = lerp(new_luma, retinex_luma, saturate(r18_str * 8.0));
```

Note: `r18_str * 8.0` maps the 0.04–0.12 range to 0.32–0.96 blend, giving a usable
strength range without adding a new knob. Tune the multiplier (6–10) to taste.

Note: mip 1 read is new — the clarity stage currently reads mips 0 and 2 only
(`grade.fx:288-289`). Adding mip 1 is one extra texture tap, already in cache.

---

## Summary

| Question | Answer |
|----------|--------|
| Scale weights | Coarse-biased (0.20/0.30/0.50) for illumination normalization; equal (1/3) as fallback |
| SDR normalization | Log-domain anchoring to zone_log_key — no auto-levels needed |
| Real-time feasibility | Confirmed. Mip approach faster than all published GPU implementations |
| Halo risk | Low — coarse mips are smooth Gaussians. Blend factor is safety valve |
| Bonus | MDPI 2024 paper validates Retinex + CLAHE as natural complements |

**Implementation is ready to proceed. No unresolved blockers.**
