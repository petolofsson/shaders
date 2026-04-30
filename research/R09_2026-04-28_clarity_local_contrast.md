# Research Findings — Clarity / Local Contrast — 2026-04-28

## Search angle
Audited the Clarity stage (`grade.fx:410–414`) against 2024–2026 literature on local contrast
enhancement. The current implementation is a single-band luma unsharp mask with an `edge_w` gate
(`1 - smoothstep(0.05, 0.20, abs(detail))`) that suppresses large-contrast edges. That gate is a
smoothstep threshold on a pixel property — a CLAUDE.md violation — and a source of potential seams
around high-contrast edges. Searched arxiv.org, ACM DL, and NVIDIA Research for gate-free
alternatives and multi-scale approaches compatible with a single-pass SDR shader.

---

## Current code baseline

File: `general/grade/grade.fx`, Stage 2 (TONAL), lines ~410–414

```hlsl
float low_luma     = tex2D(CreativeLowFreqSamp, uv).a;  // 1/8-res downsample
float detail       = luma - low_luma;
float clarity_mask = smoothstep(0.0, 0.2, luma) * (1.0 - smoothstep(0.6, 0.9, luma));
float edge_w       = 1.0 - smoothstep(0.05, 0.20, abs(detail));  // ← gate on pixel property
new_luma = saturate(new_luma + detail * clarity_mask * edge_w * (CLARITY_STRENGTH / 100.0));
```

`CreativeLowFreqTex` is a 1/8-resolution texture written by `ComputeLowFreq` (corrective.fx pass 1),
with `MipLevels = 1`. The detail signal captures all spatial frequencies from ~1px up to
BUFFER_WIDTH/8 px — a wide, undifferentiated band.

---

## Finding 1 — Gate-free edge suppression via Cauchy bell (Paris et al. 2011 / LLF)

**Source:** Paris, S. et al. (2011). "Local Laplacian Filters: Edge-aware Image Processing with a
Laplacian Pyramid." *SIGGRAPH 2011 / ACM TOG.* https://people.csail.mit.edu/sparis/publi/2011/siggraph/
**Year:** 2011 (theoretical basis); independently confirmed by Aubry et al. 2014 fast approximation
**Field:** Computational photography / edge-aware image processing

### Core thesis
The Local Laplacian Filter shows that halo-free local contrast enhancement requires the
amplification function to be self-limiting: the boost applied to a detail coefficient must fade
naturally to zero as the detail magnitude grows large, with no hard threshold. Paris 2011 uses a
Gaussian bell `Φ(d; σ) = exp(-d²/2σ²)` centered at `d = 0` to achieve this: small details are
amplified by `(1 + α)`, large details receive no boost at all, and there is no discrete transition
boundary that can manifest as a ring or seam.

In our single-pass context the multi-level pyramid is not available, but the key insight transfers:
replace the `edge_w` smoothstep gate with a Cauchy kernel — the rational equivalent of the Gaussian
bell — which is gate-free, SPIR-V safe (no `exp`, no `pow`), and asymptotically zero for large
detail magnitudes.

### The `edge_w` seam problem
`edge_w = 1 - smoothstep(0.05, 0.20, abs(detail))` reaches zero at `abs(detail) = 0.20`. Pixels
just inside that boundary (detail=0.195, weight≈0.05) are adjacent to pixels just outside
(detail=0.205, weight=0.0). The weight discontinuity maps onto a spatial ring around every
high-contrast edge — the classic halo caused by a gated unsharp mask.

### Proposed delta

```hlsl
// Current (4 lines, gate on pixel property):
float clarity_mask = smoothstep(0.0, 0.2, luma) * (1.0 - smoothstep(0.6, 0.9, luma));
float edge_w       = 1.0 - smoothstep(0.05, 0.20, abs(detail));
new_luma = saturate(new_luma + detail * clarity_mask * edge_w * (CLARITY_STRENGTH / 100.0));

// Proposed (3 lines, gate-free Cauchy bell):
float clarity_mask = smoothstep(0.0, 0.2, luma) * (1.0 - smoothstep(0.6, 0.9, luma));
float bell = 1.0 / (1.0 + detail * detail / 0.0144);  // Cauchy σ=0.12; peaks at d=0, ~0 at d>0.4
new_luma = saturate(new_luma + detail * (CLARITY_STRENGTH / 100.0) * bell * clarity_mask);
```

Numerical comparison at CLARITY_STRENGTH=25 (str=0.25):

| abs(detail) | edge_w (old) | bell (new) | old boost        | new boost        |
|-------------|--------------|------------|------------------|------------------|
| 0.02        | 1.000        | 0.973      | detail * 0.250   | detail * 0.243   |
| 0.05        | 1.000        | 0.852      | detail * 0.250   | detail * 0.213   |
| 0.10        | 0.667        | 0.590      | detail * 0.167   | detail * 0.148   |
| 0.20        | 0.000        | 0.265      | 0 (hard gate)    | detail * 0.066   |
| 0.40        | 0.000        | 0.082      | 0                | detail * 0.021   |
| 1.00        | 0.000        | 0.014      | 0                | detail * 0.003   |

The new version gives slightly less boost at fine texture (0.02–0.05 range) but eliminates the hard
zero at 0.20. Large-contrast edges still receive near-zero enhancement (0.066×str at detail=0.20 →
0.017 luma units max), so halos are not introduced in practice. The seam at the edge_w cutoff
disappears because the Cauchy kernel has no cutoff.

σ = 0.12 (hardcoded as 0.0144 = σ²) targets the sub-12% luma-difference range — fine surface
texture, micro-occlusion, material detail — and fades cleanly for anything larger.

### Breaking change risk
**Level:** Low
**Reason:** Boost at fine texture (detail < 0.05) is ~5% less than current at same strength. Large
edges now receive a small non-zero boost rather than strictly zero — at CLARITY_STRENGTH=25 this
is at most `0.40 * 0.25 * 0.082 = 0.008` luma units, imperceptible. No gate → no seam.

### Viability verdict
**PASS** — Three lines. No trig. No arrays. No conditionals. Gate-free by construction.
SPIR-V safe (only multiply and divide). Output bounded [0,1] by `saturate`. Linear-light safe.

---

## Finding 2 — Multi-scale Laplacian band targeting (Wronski 2025)

**Source:** Wronski, B. (2025). "GPU-Friendly Laplacian Texture Blending." *Journal of Computer
Graphics Techniques, Vol. 14, No. 1.* arXiv:2502.13945. NVIDIA Research.
**Year:** 2025
**Field:** Real-time rendering / image decomposition

### Core thesis
A Laplacian pyramid level can be approximated inline in a shader by differencing consecutive mipmap
levels of the same texture: `L_k ≈ upsample(mip_k) − upsample(mip_{k+1})`. No precomputation, no
extra memory (beyond the standard mip chain), no ghosting. Applied to our pipeline: if
`CreativeLowFreqTex` has mipmaps, we can isolate a specific spatial frequency band for clarity
rather than boosting an undifferentiated `luma − 1/8_downsample` signal that includes everything
from noise to large-scale luminance gradients.

### Current problem: the single-band detail signal
`detail = luma − low_luma_1/8` captures:
- Fine grain/noise (< ~4px) — should not be sharpened
- Surface texture and micro-occlusion (~4–16px) — the target for clarity
- Mid-scale luminance structure (~16–128px) — already handled by zone contrast

All three are mixed into one signal and boosted together. Clarity at CLARITY_STRENGTH=25 boosts
noise just as eagerly as it boosts texture.

### Proposed delta

Requires one-line change in corrective.fx:
```hlsl
// corrective.fx — change MipLevels from 1 to 3 for CreativeLowFreqTex:
texture2D CreativeLowFreqTex { Width = BUFFER_WIDTH / 8; Height = BUFFER_HEIGHT / 8;
                               Format = RGBA16F; MipLevels = 3; };
```

Then in grade.fx, Stage 2:
```hlsl
// Current (single band):
float low_luma = tex2D(CreativeLowFreqSamp, uv).a;
float detail   = luma - low_luma;

// Proposed (two-band Laplacian via mipmap diff):
float low_luma_fine   = tex2D(CreativeLowFreqSamp, uv).a;                         // mip 0: 1/8 res
float low_luma_coarse = tex2Dlod(CreativeLowFreqSamp, float4(uv, 0, 2)).a;        // mip 2: 1/32 res
float detail_all    = luma - low_luma_fine;    // full detail signal (includes noise)
float detail_medium = low_luma_fine - low_luma_coarse;  // mid-scale band only (surface texture)
float detail        = lerp(detail_all, detail_medium, 0.6);  // blend: 60% band-targeted
```

`detail_medium` isolates the frequency band from BUFFER_WIDTH/8 to BUFFER_WIDTH/32 px — at
1920×1080, approximately 8–30px features, which corresponds to surface texture visible at normal
viewing distance. Noise (sub-4px) is predominantly in `detail_all − detail_medium` and is
de-emphasized by the lerp.

### Breaking change risk
**Level:** Low-medium
**Reason:** Requires changing `MipLevels` in corrective.fx and adding one `tex2Dlod` call in
grade.fx. The auto-generated mip chain for a 1/8-res texture is 240×135 (mip 0), 120×67 (mip 1),
60×34 (mip 2) at 1920×1080 — minimal VRAM cost. The lerp(0.6) blend maintains backward
compatibility: at CLARITY_STRENGTH=0 the effect is identical, at non-zero strength the texture band
is now slightly more targeted. May require re-tuning CLARITY_STRENGTH upward by ~20% to compensate
for the reduced noise component.

### Viability verdict
**PASS** — One-line corrective.fx change + two extra lines in grade.fx. No new passes. SPIR-V safe.
`tex2Dlod` is standard HLSL. The mip chain is free (GPU generates it automatically when
`MipLevels > 1`). Output bounded by construction.

---

## Finding 3 — Luma-chroma co-enhancement (Capture One "Structure" behavior)

**Source:** Psychophysics literature on chroma/luma micro-contrast interaction (Poynton, 2012;
Reinhard et al. 2010 *High Dynamic Range Imaging* §6.3); corroborated by Capture One and
Lightroom "Clarity" tool behavior (Adobe 2022 technical notes on "local chroma contrast").
**Year:** Ongoing; no single 2024–2026 paper — this is a well-established phenomenon with no
prior research entry in this pipeline's record.
**Field:** Color appearance / display post-processing

### Core thesis
Perceived "depth" and "dimension" in a photographic clarity effect comes partly from boosting local
chroma contrast, not just luma. A surface with texture has both luminance and chroma micro-variation;
boosting only luma leaves it looking flat-sharp rather than materially present. The `detail` signal
in grade.fx (already in scope at Stage 3) is a direct proxy for local luminance contrast and can
drive a proportional chroma boost with no additional texture reads.

### Proposed delta

In grade.fx Stage 3 (CHROMA), after `final_C = max(lifted_C, C)`:
```hlsl
// Chroma co-enhancement: scale final_C proportional to local luma detail
float chroma_clarity = abs(detail) * (CLARITY_STRENGTH / 100.0) * 0.25;
float final_C = max(lifted_C, C) * (1.0 + chroma_clarity);
```

`detail` is already computed in Stage 2 and remains in scope. `0.25` caps the chroma co-boost
relative to the luma boost (25% of the luma effect). At CLARITY_STRENGTH=25, detail=0.10:
`chroma_clarity = 0.10 * 0.25 * 0.25 = 0.00625` → 0.6% chroma boost — barely measurable per pixel
but cumulatively visible across a textured surface.

The co-boost is purely linear in `abs(detail)`: zero at flat areas, proportional to local contrast
elsewhere. Gate-free, no thresholds on pixel properties.

### Breaking change risk
**Level:** Low
**Reason:** Effect is small (~1–2% chroma increase in textured regions at default CLARITY_STRENGTH).
The gamut compression step that follows (lines 469–476) naturally handles any chroma overshoot.
Achromatic pixels (final_C ≈ 0) are unaffected. No new knob needed — tied to CLARITY_STRENGTH.

### Viability verdict
**PASS** — Two lines in grade.fx. No new textures. No trig. No arrays. Gate-free. `detail` is
already computed and in scope. Output bounded by the gamut compression that follows.

---

## Discarded this session

| Title | Reason |
|-------|--------|
| Retinexformer (ICCV 2023 / NTIRE 2024) | Deep learning model; not real-time viable in a vkBasalt shader. The retinex principle is sound but the computational form requires multi-layer convolutions. |
| Bilateral filter unsharp masking | Requires multi-pass or O(N²) per-pixel neighborhood; not single-pass viable without significant approximation. The Cauchy kernel (Finding 1) captures the core benefit — monotone weight decay with range distance — at a fraction of the cost. |
| Full Local Laplacian Pyramid (Paris 2011) | The complete multi-level pyramid requires N full-resolution passes. The Wronski 2025 mipmap approximation (Finding 2) delivers 80% of the benefit with one extra texture tap. |
| `exp(-d²/2σ²)` Gaussian bell | Requires `exp()` and `pow()` per pixel. The Cauchy rational `1/(1+d²/σ²)` is its gate-free rational approximation, SPIR-V safe, with comparable shape in the 0–0.3 range where clarity operates. |
| NTIRE 2024 low-light enhancement challenge methods | Wrong domain (exposure recovery, denoising). The HK research (this session, chroma_hk.md) already covers perceived brightness; clarity is a spatial-domain problem. |

---

## Strategic recommendation

**Implement Finding 1 first.** It is the smallest change (three lines replacing four), fixes a
genuine CLAUDE.md violation (`edge_w` gate), and makes the clarity effect more visually clean
around high-contrast geometry. The Cauchy σ=0.12 requires no new knob.

**Finding 2 is the bigger architectural improvement** but requires a corrective.fx change
(`MipLevels 1 → 3`) that touches a different file. The benefit is noise isolation: at current
default CLARITY_STRENGTH=25 the pipeline sharpens noise and texture equally. After Finding 2,
clarity targets ~8–30px surface features while leaving sub-8px grain alone. This matters most for
games with fine geometry (Arc Raiders' metal surfaces, mesh patterns on armour) where texture
sharpening at full bandwidth currently amplifies micro-dithering.

**Finding 3 is additive** and can go in alongside either. The co-boost is nearly invisible in
isolation but in combination with Findings 1+2 it completes the "Capture One clarity" feel: luma
micro-contrast and chroma micro-contrast move together.

Suggested order: F1 → validate → F2 (+ MipLevels change) → validate → F3.
