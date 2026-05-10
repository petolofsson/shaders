# R143 — Highlight Reconstruction from Clipped SDR: Findings

**Date:** 2026-05-10
**Author:** AI research session
**Scope:** Single-frame, per-pixel highlight unclipping from 8-bit UNORM SDR for real-time vkBasalt post-process use.

---

## 1. Problem Definition

The SDR BackBuffer entering `inverse_grade.fx` is 8-bit UNORM, linearized by vkBasalt's sRGB→linear decode. Any pixel that was brighter than peak display white at the time the game rendered it arrives here as fully saturated — the game's tone mapper or renderer has already hard-clipped those values to 1.0. The information is permanently gone in the all-channels-clipped case.

The useful case is **partial clipping**: where 1 or 2 channels are clipped but at least 1 survives below 1.0. Partial clipping creates strongly wrong colors — a pixel whose R clips while G and B stay below 1.0 will appear orange/yellow when the game intended near-white. Recovering the hue information from the surviving channels is the goal.

There is no spatial neighborhood available without extra texture reads — the design constraint is single-pass, per-pixel only, no extra render targets.

---

## 2. Taxonomy of Clipping States

For a linear-light RGB pixel `(r, g, b)` post-vkBasalt-linearize, with clip threshold `T` (typically 1.0):

| State | Definition | Info available |
|-------|-----------|----------------|
| Unclipped | all channels < T | Full color and luma |
| 1-channel clipped | exactly one channel == T | 2 surviving channels give hue; luma unknown |
| 2-channel clipped | exactly two channels == T | 1 surviving channel gives partial hue; luma unknown |
| 3-channel clipped (fully blown) | all channels == T | No color info; only "bright white" known |

From the darktable, dcraw, and RAW processing literature: the **1-channel-clipped case is cleanly recoverable** for hue. The **2-channel case** is partially recoverable if the surviving channel is sufficiently different from the two clipped ones. The **fully blown case** is unrecoverable without spatial neighborhood data.

---

## 3. Academic Context

### 3.1 Banterle et al. (2006) — Inverse Tone Mapping

Banterle's iTMO framework is concerned with SDR→HDR expansion for Image-Based Lighting, not highlight unclipping per se. The core idea: segment high-luminance regions using density estimation (median-cut), build an "Expand Map" that encodes per-region HDR headroom, then apply the inverse of Reinhard's global operator:

```
L_HDR = k × L_SDR / (1.0 − L_SDR)
```

where `k` is estimated per-region from the expand map. This is a luma-only expansion — it does not address per-channel color distortion from partial clipping. Not directly applicable to the channel reconstruction problem.

### 3.2 Elboher & Werman — Color Line Reconstruction

The "Color Line" model observes that in natural scenes, the RGB values within a spatially coherent region lie along a 1D line in RGB space (a consequence of the scene having one dominant illuminant and one dominant surface color). The algorithm:

1. Detects clipped regions.
2. Groups pixels into "Color Line" clusters by bilateral filtering in color space.
3. For each cluster, extrapolates the clipped channel(s) by extending the Color Line beyond the clipping boundary.

**Limitation:** Requires spatial neighborhood data across many pixels. Not feasible in a single-pass per-pixel shader.

### 3.3 Rouf et al. (2012) — Gradient Domain Color Restoration

Uses gradient domain optimization: solves a Poisson equation where the gradient of the reconstructed channel in clipped regions is encouraged to match the gradient of the surviving channel(s). Produces smooth, artifact-free results in spatially extended blown regions. Entirely offline/iterative — requires solving a linear system over the image. Not real-time applicable.

### 3.4 dcraw -H 2 (LCH Blend) and the Cyril Bugayevich Patch

The most instructive real-world single-pixel algorithm. dcraw with `-H 2` blends two decoded versions of each highlight pixel:

- **Version A (unclipped):** Each clipped channel is reconstructed by copying the minimum unclipped channel to it. This gives correct luminance but wrong (desaturated/magenta) color.
- **Version B (clipped):** Standard clamp to white. Wrong color but correct luma.

The LCH blend patch (Cyril Bugayevich, 2006) does:

1. Convert both A and B to LCH (Lightness, Chroma, Hue).
2. Take **L** and **H** from version A (unclipped reconstruction — these are closer to correct).
3. Take **C** (chroma) from version B (clipped — clipping naturally desaturates, so this prevents over-saturation artifacts).
4. Convert back to RGB.

**Rationale:** Clipping desaturates (it shifts the pixel toward (1,1,1) = white), so the clipped version has lower C. The unclipped version may have erroneously high C if the reconstruction is wrong. Blending gives a plausible compromise: approximately correct hue with appropriately reduced chroma.

This is the closest precedent to what a real-time single-pixel shader can do.

### 3.5 darktable Highlight Reconstruction Methods

darktable operates in RAW linear space on a Bayer sensor before demosaicing, so it has access to neighboring Bayer pixels of the same channel. That context is unavailable here. The relevant transferable insights:

- **"Reconstruct in LCh"**: Analyzes the pixel in LCh; tries to preserve hue from surviving channels. Works well on smooth, homogeneous highlights. Fails on fine structure at exposure boundaries.
- **"Clip Highlights"**: For fully blown regions, simply set to (1,1,1). Recommended when highlights are naturally achromatic (sky, clouds). This is the baseline.
- **"Color Propagation" / 3D bilateral grid**: Transfers color from unclipped surroundings. Requires spatial neighborhood — not applicable here.
- **Guided Laplacians**: Iterative gradient propagation — offline only.

---

## 4. The Math: Per-Pixel Channel Reconstruction

### 4.1 Fundamental constraint: the ratio model

In linear light, under a single illuminant, the per-channel color of a surface is fixed. If channel R is the clipped channel and G, B survive:

```
R_true / G_true = R_obs / G_obs   (for unclipped pixels nearby)
```

But we don't have "nearby" in a per-pixel pass. What we do have is the pixel's own surviving channels and a global scene statistic.

**The only per-pixel operation that is mathematically sound:**

If at least one channel survives unclipped, we can infer the chromaticity from the surviving channels alone. Chromaticity is hue (the angle in the (G−R, B−R) plane or equivalently in Oklab ab-plane). Luminance is lost — we know only that it is at or above `T`.

### 4.2 Case: 1 channel clipped (e.g., R = 1.0, G < 1.0, B < 1.0)

The surviving channels G and B encode the full hue of the pixel. The correct reconstruction would be:

```
R_reconstructed = T + Δ   (where Δ > 0, unknown)
```

We cannot know Δ. What we can do: set R_reconstructed = T (the minimum consistent with what we observe), which gives the most saturated possible hue. Or we can use a ratio extrapolation based on a global scene white or the pixel's own luminance:

**Simple max-channel copy (dcraw -H 1):**

```
R_reconstructed = max(R_obs, G_obs, B_obs)
```

This desaturates the pixel toward achromatic. Correct approach for "neutralize the color cast" when you don't care about preserving hue.

**Ratio from surviving channels:**

If G is the brightest surviving channel:

```
R_reconstructed = G_obs × (R_safe_neighbor / G_safe_neighbor)
```

Requires neighbor data — not per-pixel.

**Luminance-preserving reconstruction (OKLab-space):**

The pixel has a reconstructed RGB after max-channel copy. Its Oklab L is approximately correct (all channels are now at max). Its chroma/hue is wrong (too desaturated). We cannot recover the original hue without knowing R_true.

**Conclusion for 1-channel-clipped case:** The surviving 2 channels fully determine the hue direction. We do not need R_obs at all. The reconstructed pixel's hue should be taken entirely from G and B. This is the key insight.

Concretely in Oklab: compute Oklab of `(min(R_obs, T), G_obs, B_obs)` — replacing R with something below T to un-clip it — and the ab vector (hue direction) will be correct if the replacement is within plausible range. The problem is what replacement value to use for R.

**Plausible replacements for R in 1-channel case:**

a) `R = G` (or `R = max(G, B)`) — max-channel copy. Achromatic in saturated cases; often too aggressive.

b) `R = 1.0` — keep the clip. Preserves the wrong hue (orange cast if R clips on a yellow highlight).

c) `R = G × f` where `f` is a ratio derived from unclipped pixels — requires neighborhood.

d) `R = max(R_obs, OklabHueLuminanceEstimate)` — project the pixel's Oklab L onto the hue direction given by G and B. This gives the theoretical R value consistent with the observed G/B and an assumed luminance. Requires knowing the "natural" R/G ratio for this hue.

**Most practical real-time approach for case (a): hue-preserving desaturation**

Take the pixel's Oklab representation using the raw (partially wrong) RGB, extract the hue direction, then constrain the chroma to be no more than what the surviving channels can support. Specifically:

```
// Input: rgb where one or more channels = 1.0
float3 lab = RGBtoOklab(rgb);         // hue direction in lab.yz is approximately correct if
                                       // surviving channels dominate the ab projection
float hue  = atan2(lab.z, lab.y);
float C    = length(lab.yz);

// Max supportable C given no channel exceeds T:
// Find what C would make the clipped channel exactly T.
// For the channel that clipped, the limit is determined by when
// OklabToRGB of (L, C×cos(hue), C×sin(hue)) = T on that channel.
// In practice: binary search or simply reduce C until all channels < T+ε.
float C_max = FindMaxChromaAtHueL(lab.x, hue, T);
float C_out = min(C, C_max);
lab.yz = (C < 1e-6) ? lab.yz : lab.yz * (C_out / C);
return OklabToRGB(lab);
```

**Problem:** `RGBtoOklab` in `common.fxh` applies `saturate(rgb)` first — it cannot take a partially-wrong input RGB where one channel is 1.0 and the others are below. Since the Oklab conversion starts with `saturate()`, any RGB with channels > 1.0 gets clamped there. For channels exactly at 1.0 (the SDR clip case), `saturate()` returns 1.0 — this is fine. The issue is that `RGBtoOklab(float3(1.0, 0.7, 0.4))` gives wrong hue if R truly exceeds 1.0 but is clamped.

### 4.3 Case: 2 channels clipped (e.g., R = 1.0, G = 1.0, B < 1.0)

Only B survives. The hue direction is poorly constrained — any hue that corresponds to a high-R, high-G color is consistent with the observation. This is the magenta/pink highlight artifact case in cameras (when R and B clip but G doesn't).

In Oklab: with `(1, 1, B_obs)` where B_obs < 1, the ab projections will reflect the blue contribution but with heavily biased luminance. The hue direction from Oklab on `(1, 1, B_obs)` points roughly toward yellow (opposite of blue), which is physically plausible for a near-white highlight that leans warm.

**Practical treatment:** Desaturate toward white. The max-channel copy `(1, 1, 1)` is actually defensible here — with only one surviving channel, hue recovery is speculative. The most neutral assumption is to move the pixel toward achromatic. The transition should be smooth: as the number of clipped channels increases, blend toward white.

### 4.4 Case: 3 channels clipped (fully blown)

Nothing to reconstruct per-pixel. Set to (1, 1, 1) or leave as-is.

---

## 5. The Blend/Transition Zone

The transition between unclipped color and clipped reconstruction is a classic aliasing problem. A hard threshold at T = 1.0 produces a visible ring artifact at the boundary of specular highlights: the interior is white, the exterior has normal color, and the transition is discontinuous in hue space.

### 5.1 Near-clip softening zone

The standard approach (used in darktable, dcraw, Lightroom) is to define a **near-clip zone** starting below 1.0 where the reconstruction is blended in with a smooth weight:

```
float clip_weight = smoothstep(T_soft, T_hard, max3(r, g, b));
// T_soft = 0.92–0.96, T_hard = 1.0
// clip_weight = 0 below T_soft, = 1 at T_hard
```

For pixels in the near-clip zone where no channel is actually at 1.0, the "reconstruction" is a desaturation blend toward the reconstructed value:

```
float3 reconstructed = Desaturate(rgb);   // hue-preserving desaturate toward luma
float3 output = lerp(rgb, reconstructed, clip_weight);
```

The smooth gradient prevents the ring artifact.

### 5.2 Threshold values from the literature

- **darktable:** Uses a per-channel white level threshold (derived from camera white balance vector). Effectively near-clip detection uses the minimum per-channel threshold. For sRGB/display-referred signals without raw data: T = 1.0 is the only available threshold.
- **dcraw -H 2:** Blends unclipped and clipped reconstructions across the entire highlight region, not just the near-clip zone.
- **Practical recommendation for SDR post-process:** T_soft = 0.93 to 0.97 in linear light. Below T_soft: no reconstruction. Above T_hard = 1.0: full reconstruction. Between: smooth blend. A value of 0.95 corresponds to approximately 100 out of 255 in gamma-encoded 8-bit (≈ ~90 out of 255 after linear decode, depending on the exponent). After vkBasalt's sRGB decode, 0.95 in linear ≈ 0.975 in sRGB (since sRGB gamma is ~2.2, 0.975^2.2 ≈ 0.946). So the near-clip zone in gamma-space is roughly 241–255 out of 255 — the topmost 14 levels. This is the right order of magnitude.

**Important SDR-specific note:** Because vkBasalt receives an 8-bit sRGB image, the finest granularity in linear light near 1.0 is about 1/255 ≈ 0.004 after linearization. The near-clip "zone" between 0.95 and 1.0 in linear corresponds to approximately 3–4 discrete 8-bit levels in gamma-space. This means:

- The transition gradient has only 3–4 steps of resolution.
- Any smoothstep over this range will alias in a visible ring on screen-size specular blobs.
- Softer transition (T_soft = 0.85 or lower) covers more steps but blends reconstruction into clearly-unclipped pixels.

---

## 6. What SDR Games Actually Present

The SDR BackBuffer arriving at `inverse_grade.fx` has been through the game's own tone mapper. Common cases:

1. **Simple saturating tone mapper** (Reinhard, ACES Filmic): Output channels approach 1.0 asymptotically. Channels near 1.0 are already strongly compressed; partial clipping indicates extreme over-exposure in scene-linear. Hue is preserved by the tone mapper if it operates on luminance only (e.g., Reinhard global), but hue rotates if it operates per-channel (ACES per-channel, generic per-channel Hable). After per-channel tone mapping, a specular highlight that was neutral scene-linear will remain neutral — all three channels hit 1.0 together. **Partial clipping at output is rare with per-channel tone mappers on neutral scene content.**

2. **Per-channel tone mapper with non-neutral highlights:** A red specular on a metallic surface may have R tone-mapped through a different region of the curve than G and B, landing with R closer to 1.0 than G/B. This can produce the classic orange-specular artifact. **This is the case where highlight reconstruction has value.**

3. **Clamp without rolloff:** Some games hard-clamp scene HDR to 1.0 before or instead of tone mapping. The result is large flat-white regions with color at the edges. **This is the most damaging case and the hardest to reconstruct.**

4. **Bloom/glow baked in:** Many games add bloom pre-tone-map. The bloom is tone-mapped into the SDR frame; the highlight core may be clipped but the surrounding bloom halo is not. The halo pixels carry hue information. **This is where per-pixel reconstruction can help most:** the halo pixels near the core are in the near-clip zone and have correct hue, allowing smooth reconstruction.

**Practical expectation:** For the Arc Raiders testbed (UE5), the ACES-like tone mapper is per-channel with a shoulder. Near-white highlights will have all channels pushed near 1.0 roughly together for neutral surfaces. Colored metal speculars are the partial-clipping case. The effect is most useful for those.

---

## 7. Real-Time Implementation Survey

### 7.1 PumboAutoHDR (ReShade, Filoppi)

The most relevant existing real-time shader. It implements inverse Reinhard per-component:

```hlsl
// Per-component inverse Reinhard (expands into HDR headroom)
fixTonemapColor = rgb / max(1.0 - rgb, 1e-6);  // = L_sdr / (1 - L_sdr), per channel

// Re-normalize to preserve midtone brightness
fixTonemapColor *= mid_gray / average(fixTonemapColor_at_mid_gray);
```

Then optionally restores hue via Oklch:

```hlsl
// Blend perceptual C and H back toward SDR values while keeping expanded L
float3 postOklch = linear_srgb_to_oklch(expanded);
float3 preOklch  = linear_srgb_to_oklch(original_sdr);
postOklch.yz = lerp(postOklch.yz, preOklch.yz, 0.75);
result = oklch_to_linear_srgb(postOklch);
```

**Note:** This is SDR→HDR expansion for HDR display output, not SDR-in SDR-out reconstruction. The "hue restoration" step is relevant: it shows that the standard approach to preventing hue error from per-channel expansion is to apply the expansion in luminance only and restore chroma/hue from the original.

### 7.2 darktable filmic rgb (v6/v7, high-quality mode)

Internally works on RGB ratios (chromaticity) separately from luminance. Clips the luminance through a sigmoid S-curve but preserves the RGB ratio vector. This prevents the hue rotation that per-channel tone mapping causes. **This is the correct architectural approach for avoiding the problem upstream** — if the game's tone mapper had used ratio-preserving tone mapping, there would be no partial-clipping hue error.

### 7.3 Existing inverse_grade.fx (R90)

`inverse_grade.fx` already does Oklab chroma expansion with `HueCeil()` clamping. It does not touch pixels with C < 0.10 (the near-neutral gate). A highlight reconstruction pass would target the opposite population: high-L, near-clipped, potentially any C.

---

## 8. Failure Modes

### 8.1 Fully blown highlights — unrecoverable

When all three channels are 1.0, there is no per-pixel color information. Any "hue" assigned is speculation. Spatial neighborhood approaches (darktable "color propagation") can inpaint from surrounding pixels, but that is a multi-tap operation.

### 8.2 Wrong-hue reconstruction amplifies color error

If the near-white pixel's Oklab hue direction is computed from a biased RGB (e.g., R clips first due to the game's per-channel tone mapper amplifying R relative to G/B at the shoulder), the "corrected" hue will be in the wrong direction. Reconstruction can make the artifact more visible if it shifts hue sharply at the reconstruction boundary.

### 8.3 Near-clip zone aliasing (8-bit quantization)

As described in section 5.2, the transition zone near 1.0 has only 3–4 distinct 8-bit levels. A smoothstep from 0.95 to 1.0 in linear is nearly a step function in gamma space. This produces a visible halo ring at the boundary of blown-out highlights.

**Mitigation:** Widen the transition zone to 0.85–1.0 in linear (≈ 228–255 in gamma-encoded 8-bit). This blends reconstruction into clearly-valid territory but prevents the ring. The blend weight at 0.85 should be very small (< 0.05) to avoid affecting obviously-correct colors.

### 8.4 Game-dependent tone mapper incompatibility

If the game uses a luma-only (global) Reinhard or similar, highlights are desaturated toward white uniformly — all three channels clip together. Per-pixel reconstruction has nothing to work with. If the game uses ACES per-channel with strong per-channel shoulder, the hue rotation of the SDR output is a complex function of the ACES primaries and the specific shader version. Reconstruction without knowing the game's tone curve cannot invert this.

### 8.5 Oklab conversion saturate() clamp (pipeline-specific)

`common.fxh:RGBtoOklab()` applies `saturate(rgb)` before the LMS matrix multiply. For SDR signals at exactly 1.0, this is a no-op. But it means that the Oklab representation of a partially-clipped pixel `(1.0, 0.7, 0.4)` is computed correctly — R = 1.0 is within [0,1]. The hue computed from this Oklab triple will be biased because R should have been > 1.0 in scene-linear but is clamped. There is no per-pixel fix for this; it is the fundamental information loss.

### 8.6 Reconstruction introduces hue error on neutral-ish highlights

A pixel with `(0.98, 0.96, 0.93)` in linear has a slight warm tint (orange). Its max channel is R. The reconstruction machinery might "decide" R is near-clipping and partially desaturate it toward white — removing the warm tint that was intentional (e.g., an incandescent lamp rim light). The near-clip detection should not fire on clearly-colored pixels even if their max channel is high.

**Mitigation:** Apply reconstruction only when the pixel's C in Oklab is below a threshold consistent with "highlight that should be neutral but isn't." High-C pixels near 1.0 are saturated colored lights — they should not be reconstructed.

---

## 9. Recommended Real-Time Algorithm for inverse_grade.fx

Based on the research, a per-pixel, single-pass highlight reconstruction for this pipeline should do:

### 9.1 Detection

```hlsl
float L_rgb    = Luma(rgb);                    // BT.709 luma
float max_ch   = max(max(rgb.r, rgb.g), rgb.b);
float min_ch   = min(min(rgb.r, rgb.g), rgb.b);
float ch_range = max_ch - min_ch;              // 0 = achromatic, >0 = chromatic

// Clip indicator: how many channels are at or above T_hard = 1.0
bool r_clip    = (rgb.r >= 0.999);
bool g_clip    = (rgb.g >= 0.999);
bool b_clip    = (rgb.b >= 0.999);
int  n_clipped = int(r_clip) + int(g_clip) + int(b_clip);

// Reconstruction strength: 0 for fully unclipped, 1 for near-fully-clipped
// T_soft chosen wide enough to cover 8-bit quantization steps.
float recon_w  = smoothstep(0.88, 0.995, max_ch);

// Don't touch clearly-saturated colored pixels (lamp cores, etc.)
float3 lab     = RGBtoOklab(rgb);
float  C       = length(lab.yz);
recon_w       *= smoothstep(0.18, 0.08, C);   // suppress reconstruction for C > 0.18
```

### 9.2 Reconstruction target

For pixels in the reconstruction zone, compute a target RGB:

```hlsl
// Target: desaturate the pixel toward its luma (BT.709) while preserving hue direction.
// This is equivalent to moving along the hue line toward achromatic.
float L_target   = max(L_rgb, max_ch);         // use max channel as luma proxy in highlights
float3 rgb_desat = lerp(rgb, float3(L_target, L_target, L_target), recon_w);

// Clamp to SDR ceiling (no HDR expansion — output stays [0,1]).
rgb_desat = saturate(rgb_desat);
```

Alternative target using Oklab:

```hlsl
// Reduce C toward 0 as reconstruction weight increases.
// This is the smoothest hue-preserving desaturation.
float3 lab_out = lab;
lab_out.yz    *= (1.0 - recon_w);     // reduce chroma
float3 rgb_out = saturate(OklabToRGB(lab_out));
```

### 9.3 Full algorithm sketch

```hlsl
float3 HighlightReconstruct(float3 rgb, float strength)
{
    if (strength <= 0.0) return rgb;

    float max_ch  = max(max(rgb.r, rgb.g), rgb.b);
    float3 lab    = RGBtoOklab(rgb);
    float  C      = length(lab.yz);

    // Blend weight: active near 1.0, suppressed for colorful pixels.
    float recon_w = smoothstep(0.88, 0.995, max_ch)
                  * smoothstep(0.18, 0.08, C)
                  * strength;

    // Chroma rolloff: reduce ab toward 0.
    float3 lab_out = lab;
    lab_out.yz    *= (1.0 - recon_w);
    return saturate(OklabToRGB(lab_out));
}
```

Key properties:
- No extra texture samples.
- No new render passes.
- Hue preserved (ab direction unchanged); only magnitude reduced.
- Self-limiting: recon_w = 0 for C > 0.18 (doesn't touch colored lights).
- Self-limiting: recon_w = 0 for max_ch < 0.88 (doesn't touch clearly-unclipped pixels).
- Output stays [0,1] via `saturate()`.
- No gates (the smoothstep transitions are continuous).

### 9.4 Where to insert in inverse_grade.fx

Before the R90 chroma expansion. Highlight reconstruction should operate on the raw SDR signal before any expansion. If applied after R90, the expansion may have already pushed near-clipped pixels above 1.0 (before `saturate()` clips them), which would make the reconstruction logic pointless.

Proposed pass ordering in `InverseGradePS`:

1. Read BackBuffer pixel.
2. Apply `HighlightReconstruct()`.
3. Apply R90 chroma expansion (existing logic).
4. Return.

### 9.5 Knob placement

Per the non-negotiable rule: all user-adjustable values must live in `creative_values.fx`. One suggested knob:

```hlsl
uniform float HIGHLIGHT_RECONSTRUCT <
    ui_label   = "Highlight Reconstruction";
    ui_tooltip = "Desaturates near-clipped highlights to recover plausible hue. 0=off.";
    ui_type    = "slider"; ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.0;
```

Default 0.0 (off). The function's `strength` parameter is this value.

---

## 10. Open Questions

1. **What tone mapper does the testbed game use?** If it is luma-only Reinhard or a ratio-preserving operator, all three channels clip together on neutral highlights and there is nothing to recover. Reconstruction would then only affect artificially saturated highlights (colored lights, colored metal speculars). The effect may be subtle.

2. **Is the SDR clip truly at 1.0 in linear?** After vkBasalt's sRGB decode, values at 255/255 in 8-bit sRGB decode to exactly 1.0 in linear. But are there any values > 1.0 arriving at `inverse_grade.fx`? vkBasalt applies sRGB decode before passing to shaders; the decode is clamped by the UNORM format. So yes, the ceiling is exactly 1.0.

3. **Can the softening threshold be empirically measured?** The data highway already carries p90 (x=200) and p75 (x=194). A highlight reconstruction pass could use p90 as a signal for whether highlights are actively clipping. If p90 > 0.97, the scene has significant clipping and reconstruction is more justified.

4. **Interaction with R90 inverse grade:** R90 expands chroma for colorful midtone pixels (C > 0.10 gate, mid-luminance weight). Highlight reconstruction targets the opposite: low-C (near-white), high-L pixels. The two operations should be non-overlapping in pixel population if the gates are tuned correctly. Verify that the C gate in R90 (`(C - 0.10) / 0.15`) does not fire on pixels that highlight reconstruction just desaturated toward C ≈ 0. It should not, since R90's `c_weight` would be 0 for those pixels.

5. **Does the testbed exhibit visible channel-clipping color casts?** The known issue "yellow/orange chroma over-saturation" (documented in `project_arc_raiders_known_issues.md`) may be partially explained by orange/warm channel clipping rather than (or in addition to) the chroma expansion from R90. Investigating whether that artifact tracks with `max_ch > 0.9` would determine if highlight reconstruction is a useful fix.

6. **Performance budget:** Adding Oklab conversion is approximately 12 MAD operations plus atan2. Since `InverseGradePS` already does Oklab conversion (R90), the highlight reconstruct step needs no additional conversion if it is integrated into the same Oklab block. Marginal cost is then just the 2 smoothstep calls and the chroma scale. Negligible.

7. **Spatial reconstruction (future):** If a lightweight spatial pass is ever added (e.g., a pre-pass that writes highlight masks to the data highway row), the gradient-propagation methods become feasible. This would require one extra render target and one extra pass — significant GPU budget cost in the vkBasalt chain. Not recommended given the GPU crash risk documented in `feedback_gpu_budget.md`.

---

## 11. Summary / Recommendation

**Theoretical verdict:** Per-pixel highlight reconstruction from SDR can recover hue direction information only when 1–2 channels remain below clip, and only if the surviving channels genuinely encode a different hue than the clipped ones. For neutral highlights (all channels clipping together due to luma-only tone mapping), there is nothing to recover.

**Practical algorithm:** Chroma rolloff in Oklab as max_ch approaches 1.0, gated on C to protect colored lights. No extra passes, no extra texture reads. Integrates cleanly into the existing Oklab block in `InverseGradePS`. Two smoothsteps plus one multiply. Self-limiting and free of hard gates.

**Priority assessment:** Medium. The effect is visible only on colored-specular or saturated-highlight pixels that are near the SDR ceiling. If the testbed game's tone mapper desaturates highlights (as most ACES-based ones do), the visible area of operation is small. However, the cost is near-zero and the algorithm is safe (only desaturates, never introduces color, always stays [0,1]).

**Before implementing:** Verify that the yellow/orange over-saturation known issue is actually caused by channel clipping and not by R90 overexpansion or R73/R133 calibration error. If it is a clipping artifact, highlight reconstruction is the correct fix. If it is an expansion artifact, adjustment of R90's `INVERSE_STRENGTH` or the `HueCeil` values is the correct fix.

---

## Sources

- [darktable 4.8 Highlight Reconstruction Manual](https://docs.darktable.org/usermanual/4.8/en/module-reference/processing-modules/highlight-reconstruction/)
- [Blown-highlight recovery with dcraw in LCH coordinates (Cyril Bugayevich patch)](http://people.zoy.org/~cyril/dcraw_lchblend/highlight_recovery_dcraw_lch_patch.html)
- [darktable Color Reconstruction (3D bilateral grid method)](https://www.darktable.org/2015/03/color-reconstruction/)
- [darktable Visualizing Raw Highlight Clipping](https://www.darktable.org/2016/10/raw-overexposed/)
- [Banterle et al. — Inverse Tone Mapping (Semantic Scholar)](https://www.semanticscholar.org/paper/Inverse-tone-mapping-Banterle/a74981735bbe94344264da0384b0c3d5a7a5444b)
- [Banterle — Inverse Tone Mapping Lecture Slides (HDRI 2015)](https://www.banterle.com/francesco/courses/2015/hdri/slides/lecture_inverse_tone_mapping.pdf)
- [Correction of Over-Exposure Using Color Channel Correlations (Abebe & Pouli, IEEE)](https://ieeexplore.ieee.org/document/7032287/)
- [Recovering Color and Details of Clipped Image Regions — Elboher & Werman (Semantic Scholar)](https://www.semanticscholar.org/paper/Recovering-Color-and-Details-of-Clipped-Image-Elboher-Werman/3ac9d98f41e294a67f9d2a7e5b7948e2f61d3549)
- [Gradient Domain Color Restoration of Clipped Highlights — Rouf et al. (UBC)](https://www.cs.ubc.ca/labs/imager/tr/2012/GradientDomainColorRestoration/)
- [PumboAutoHDR HLSL source — AdvancedAutoHDR.fx (GitHub)](https://github.com/Filoppi/PumboAutoHDR/blob/master/Shaders/Pumbo/AdvancedAutoHDR.fx)
- [Fast Inverse Tone Mapping with Reinhard's Global Operator (IEEE)](https://ieeexplore.ieee.org/document/7952501/)
- [Lightroom Highlight Recovery Analysis — Jim Kasson](https://blog.kasson.com/z9/lightroom-highlight-recovery/)
- [RawTherapee highlight clip handling — GitHub issue #2837](https://github.com/Beep6581/RawTherapee/issues/2837)
- [Tone Mapping — Wikipedia](https://en.wikipedia.org/wiki/Tone_mapping)
- [Semantic Aware Diffusion Inverse Tone Mapping (arXiv)](https://arxiv.org/html/2405.15468)
