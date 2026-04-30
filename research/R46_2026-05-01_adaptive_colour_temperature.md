# R46 — Adaptive Colour Temperature

**Date:** 2026-05-01
**Status:** Proposal

---

## Problem

At full creative_values passthrough, yellow bias appears in highlights. The source is
upstream of pro_mist — in the automated pipeline itself. This implies the pipeline has
no scene-colour-temperature awareness: it applies fixed chromatic operations regardless
of whether the scene is warm or cool. The same adaptive principle used for clarity,
chroma, and density (read a scene statistic, derive a correction) should extend to
colour temperature.

---

## How many chain effects could run this principle?

Survey of every fixed chromatic assumption in the current pipeline:

| Effect | Fixed assumption | Adaptive signal available? |
|--------|-----------------|---------------------------|
| grade.fx — FilmCurve R/B offsets | Hardcoded ARRI ALEXA character | No — artistic intent |
| grade.fx — Abney correction | Fixed per-band hue offsets | No — perceptual model, not scene-dependent |
| grade.fx — HK baked at 0.25 | Constant strength | Marginal — C-dependent already |
| grade.fx — chroma S-curve | Automated via mean_chroma | Done |
| grade.fx — density | Automated via mean_chroma | Done |
| grade.fx — shadow_lift | Automated via p25 | Done |
| **grade.fx — highlight colour temperature** | **None — not corrected at all** | **Yes — highlight R-B ratio** |
| **grade.fx — shadow colour temperature** | **None** | **Yes — shadow R-B ratio** |
| pro_mist — scatter chromatic weights | Hardcoded (1.05, 1.00, 0.92) | Yes — scene warmth |
| pro_mist — halation chromatic weights | Hardcoded (1.20, 0.60, 0.25) | Yes — scene warmth |
| retinal_vignette — SCE strength | Automated via p50 | Done |
| retinal_vignette — Purkinje | Automated via p50 | Done |

**Three viable targets:** highlight temperature correction, shadow temperature correction,
and pro_mist chromatic weights. All three can share a single scene-warmth signal.

---

## The signal: highlight R-B ratio

Grey-world AWB assumes the scene-average colour should be neutral. For highlight-specific
temperature detection, restrict the measurement to pixels above p75:

```
warm_bias = mean(R − B) for pixels where luma > p75
```

This is exactly the yellow-in-highlights problem: if warm_bias > 0, highlights are warm.

**Can this be derived from existing data?**

ChromaHistoryTex (col 0–5, row y=0) stores per-hue-band mean C and std C. It does not
store per-channel R/B means directly. So a direct R-B ratio is not currently computable
without a new analysis pass.

However, a proxy is available: the red and yellow hue bands (bands 0 and 1) together
capture most warm-scene energy. If their combined weighted mean chroma is high while blue
and cyan (bands 4 and 5) are low, the scene is warm in the highlight range. This can be
computed inline in grade.fx from the existing 6 ChromaHistoryTex reads (already fetched
for chroma_str) — zero additional texture reads.

```hlsl
// Warm bias proxy from existing ChromaHistoryTex reads
float warm_energy = chroma_bands[0].r * chroma_bands[0].b   // red band mean × weight
                  + chroma_bands[1].r * chroma_bands[1].b;  // yellow band mean × weight
float cool_energy = chroma_bands[3].r * chroma_bands[3].b   // cyan band
                  + chroma_bands[4].r * chroma_bands[4].b;  // blue band
float warm_bias   = saturate((warm_energy - cool_energy) / max(warm_energy + cool_energy, 0.001));
// warm_bias ∈ [0,1]: 0 = cool/neutral, 1 = strongly warm
```

---

## Proposed adaptive corrections

### 1. Highlight temperature auto-correction (grade.fx Stage 1 / 3-way)

```hlsl
// Auto cool highlights when scene warm bias is detected
// Maps warm_bias [0,1] to a highlight temperature offset [0, -25]
float auto_hl_temp = lerp(0.0, -25.0, smoothstep(0.3, 0.7, warm_bias));
// Inject into the existing 3-way highlight temperature path
// (adds to HIGHLIGHT_TEMP — stays within existing architecture)
```

This automates what HIGHLIGHT_TEMP -20 was doing manually. The correction is:
- Zero in cool/neutral scenes
- Up to -25 in strongly warm scenes
- Smooth — no gate

### 2. Shadow temperature auto-correction (grade.fx Stage 1 / 3-way)

Symmetrically: if warm_bias is low (cool scene), shadows may need warming.
The same signal inverted drives a shadow temperature offset. Low priority — shadows
are less perceptually problematic than highlights.

### 3. Pro_mist scatter chromatic weights (pro_mist.fx)

```hlsl
// Current: float3(1.05, 1.00, 0.92) — fixed
// Proposed: adapt R and B channels to scene warmth
float scatter_r = lerp(1.05, 1.00, warm_bias);  // warm scene → neutral scatter
float scatter_b = lerp(0.92, 1.00, warm_bias);  // warm scene → lift blue scatter
float3 scatter_w = float3(scatter_r, 1.00, scatter_b);
```

Requires passing warm_bias from grade.fx to pro_mist.fx — not directly possible
(separate vkBasalt effects). Would need warm_bias written to a shared texture slot,
OR computed inline in pro_mist using the same ChromaHistoryTex reads (already available
there via PercSamp — but ChromaHistoryTex is NOT currently bound in pro_mist).

**Options:**
a) Pack warm_bias into an unused channel of PercTex (PercTex.a is Kalman P — taken)
b) Add a new 1×1 R16F texture for scene warmth (cheapest)
c) Bind ChromaHistoryTex in pro_mist and compute inline (more reads but no new texture)

---

## Open research questions

1. **Proxy accuracy** — does warm_energy − cool_energy from ChromaHistoryTex correlate
   well with actual R-B highlight imbalance? Needs validation against screenshots.

2. **Highlight restriction** — the ChromaHistoryTex bands are global (all pixels), not
   restricted to pixels above p75. Does the global warm bias track the highlight warm bias
   well enough, or do we need a new highlight-restricted statistic?

3. **Correct warm_bias smoothstep range** — `smoothstep(0.3, 0.7, warm_bias)` is a guess.
   Needs tuning against real Arc Raiders scenes (mix of indoor warm, outdoor cool, dusk).

4. **pro_mist sharing** — which of the three options (pack into existing texture, new
   texture, inline recompute) is cheapest given GPU budget constraints?

5. **Interaction with manual HIGHLIGHT_TEMP** — if auto_hl_temp and HIGHLIGHT_TEMP both
   apply, they add. Should auto be additive or should it anchor when HIGHLIGHT_TEMP ≠ 0?

---

## Implementation order (pending findings)

1. Validate warm_bias proxy against screenshots — does it read warm on Arc Raiders hub,
   neutral on outdoor daylight scenes?
2. Implement auto highlight temperature correction in grade.fx (zero new texture reads)
3. If proxy is insufficient, add highlight-restricted R-B stat to analysis_frame.fx
4. Address pro_mist scatter warmth as a follow-on (texture sharing decision)
