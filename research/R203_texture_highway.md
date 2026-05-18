# R203 — Unified Texture Highway

**Status:** Research  
**Date:** 2026-05-18  
**Scope:** Architecture — inter-effect texture consolidation

---

## Motivation

The pipeline currently communicates between effects via a proliferation of separately-declared textures. The scalar highway (HighwayTex, 256×1 R16F) is the only principled shared bus — everything else is ad-hoc, with textures declared redundantly in multiple files and matched by name at runtime.

A "texture highway" (TexHwyTex) would extend this pattern to 2D spatial data: one texture declared once in common.fxh, all effects read what they need and write their lane, pass-through for unowned regions — identical in principle to HighwayTex.

---

## Full Texture Audit

### Chain order
`analysis_frame : inverse_grade : corrective : grade`

### Cross-effect textures (declared in multiple files, matched by name)

| Texture | Format | Size | Written by | Read by | Declared in |
|---|---|---|---|---|---|
| HighwayTex | R16F | 256×1 | analysis_frame, corrective | all effects | highway.fxh ✓ |
| PercTex | RGBA16F | 1×1 | analysis_frame | corrective, grade | 3 files ✗ |
| NeutralIllumTex | RGBA16F | 1×1 | grade | inverse_grade | 2 files ✗ |
| CreativeLowFreqTex | RGBA16F | BUFFER_WIDTH/8 × BUFFER_HEIGHT/8 | corrective | grade | 2 files ✗ |
| ZoneHistoryTex | RGBA16F | 4×4 | corrective | grade | 2 files ✗ |
| CreativeZoneHistTex | R16F | 32×16 | corrective | grade | 2 files ✗ |
| ChromaHistoryTex | RGBA16F | 8×4 | corrective | grade | 2 files ✗ |
| LumHistTex | R16F / R32F | 64×1 | analysis_frame | analysis_scope | Not in active chain — dormant |

### Within-analysis_frame only (private — inaccessible to downstream effects)

| Texture | Format | Size | Contains |
|---|---|---|---|
| DownsampleTex | RGBA16F | 32×18 | Pre-correction scene RGB, histogram source |
| LumHistRawTex | R16F | 64×1 | Raw per-frame luma histogram |
| SceneCutTex | RGBA16F | 1×1 | scene_cut signal, previous p50 |
| MeanChromaTex | RGBA16F | 1×1 | median_C, mean_a, mean_b, achrom_frac |
| PercHighTex | RG16F | 1×1 | p90, p10 |
| ChromaExtraTex | RG16F | 1×1 | p75_C, κ (hue concentration) |
| ModeTex | R16F | 1×1 | histogram mode (EMA) |
| EntropyTex | R16F | 1×1 | histogram entropy H_norm |

### Within-corrective only (private)

| Texture | Format | Size | Contains |
|---|---|---|---|
| CreativeZoneLevelsTex | RGBA16F | 4×4 | CDF → zone medians (intermediate) |

### Within-grade only (within-technique, never cross-effect)

| Texture | Format | Size (1440p) | Contains |
|---|---|---|---|
| LowFreqMip1Tex | RGBA16F | 160×90 | 1/16-res Retinex illum_s0, CLARITY base |
| LowFreqMip2Tex | RGBA16F | 80×45 | 1/32-res Retinex illum_s2, ambient tint |
| GuidedCoeffTex | RG16F | 320×180 | Guided filter coefficients (a_k, b_k) |
| BilateralLogTex | R16F | 320×180 | Guided filter base layer |
| DiffusionTex | RGBA16F | 640×360 | Diffusion blur intermediate / final |
| DiffusionHorizTex | RGBA16F | 640×360 | Diffusion H-blur intermediate |

### Full BackBuffer reads per frame (1440p = 2560×1440 × RGBA16F = ~29 MB each)

| Pass | Effect | Output size | Cost |
|---|---|---|---|
| DownsamplePS | analysis_frame | 32×18 | 1× full read |
| InverseGradePS | inverse_grade | full-res | 1× full read |
| ComputeLowFreqPS | corrective | BUFFER_WIDTH/8 | 1× full read |
| ColorTransformPS | grade | full-res | 1× full read |
| DiffusionDownsamplePS | grade | BUFFER_WIDTH/4 | 1× full read |

**5 full BackBuffer reads per frame minimum. DownsamplePS and ComputeLowFreqPS are redundant — both read the full BackBuffer to produce spatial downsamples at different scales.**

### VRAM footprint at 1440p

| Category | Approx VRAM |
|---|---|
| Cross-effect textures | ~450 KB (dominated by CreativeLowFreqTex 320×180×8B) |
| Within-grade | ~4 MB (dominated by DiffusionTex pair at 640×360×8B×2) |
| Within-analysis | ~5 KB |
| Scalar highway | < 1 KB |
| **Total pipeline** | **~4.5 MB** |

---

## Problems Identified

1. **Redundant declarations**: 6 cross-effect textures declared in 2–3 files each. No single source of truth.

2. **LumHistTex format mismatch** (dormant): analysis_frame declares R16F, analysis_scope declares R32F. analysis_scope is not in the active chain so this has no current impact. Landmine if scope is ever re-enabled — worth fixing then.

3. **analysis_frame data island**: 8 private 1×1 textures in analysis_frame carry rich scene statistics (median_C, achrom_frac, p10, p90, p75_C, κ, entropy, scene_cut). Downstream effects access these only through the scalar highway's lossy encoding. Direct texture reads would be cleaner and allow richer queries.

4. **Two redundant full BackBuffer reads**: DownsamplePS (→ 32×18) and ComputeLowFreqPS (→ 1/8-res) both read the full BackBuffer. One unified 1/8-res downsample could replace both.

5. **Resolution-inconsistency**: DownsampleTex is fixed at 32×18 regardless of resolution. At 1440p each cell = 80×80px; at 4K = 120×120px. The spatial textures (CreativeLowFreqTex etc.) correctly scale with BUFFER_WIDTH/8. Zone luma using DownsampleTex degrades at higher resolutions.

---

## Proposed Architecture: Texture Highway

### TexHwyTex layout

```
texture2D TexHwyTex {
    Width  = BUFFER_WIDTH  / 8;
    Height = BUFFER_HEIGHT / 8 + TEX_HWY_ROWS;  // spatial lane + packed data rows
    Format = RGBA16F;
    MipLevels = 1;
};
```

At 1440p: 320 × (180 + TEX_HWY_ROWS). At 4K: 480 × (270 + TEX_HWY_ROWS). Scales correctly.

**Spatial lane** (rows 0 → BUFFER_HEIGHT/8 − 1):  
Written by analysis_frame. r=R, g=G, b=B, a=Luma — pre-correction scene image at 1/8-res.  
Replaces: DownsampleTex (32×18) and CreativeLowFreqTex (1/8-res, written by corrective).

**Data rows** (rows BUFFER_HEIGHT/8 + 0 → + TEX_HWY_ROWS−1):  
Fixed-layout small data. Each row is BUFFER_WIDTH/8 pixels wide; data occupies leftmost pixels.

Proposed row layout (TEX_HWY_ROWS = 8):

| Row offset | Pixels used | Content | Written by |
|---|---|---|---|
| +0 | 0–1 | NeutralIllumTex RGB (3 floats) | grade |
| +1 | 0–3 | PercTex: p25, p50, p75, Kalman P | analysis_frame |
| +2 | 0–3 | MeanChromaTex: median_C, mean_a, mean_b, achrom_frac | analysis_frame |
| +3 | 0–3 | Misc: p90, p10, p75_C, κ | analysis_frame |
| +4 | 0–3 | SceneCutTex: scene_cut, p50_prev, entropy, mode | analysis_frame |
| +5 | 0–15 | ZoneHistoryTex 4×4 → 16 RGBA pixels | corrective |
| +6 | 0–31 | ChromaHistoryTex 8×4 → 32 RGBA pixels | corrective |
| +7 | reserved | — | — |

### Pass-through mechanism

Each effect that writes to TexHwyTex runs a TexHwyWritePS pass:
```hlsl
float4 TexHwyWritePS(float4 pos, float2 uv) : SV_Target {
    int row = int(pos.y);
    int col = int(pos.x);
    // owned regions: compute and return
    // unowned regions: return tex2D(TexHwySamp, uv)  — pass-through
}
```

Identical principle to HighwayWritePS, extended to 2D.

### common.fxh helpers

```hlsl
float  ZoneLuma(float2 uv)    // Oklab L from spatial lane
float3 ReadIlluminant()       // NeutralIllum RGB from data row
float4 ReadPerc()             // p25/p50/p75/P from data row
float4 ReadMeanChroma()       // median_C/mean_a/mean_b/achrom_frac
```

---

## Expected Outcomes

| Metric | Before | After |
|---|---|---|
| Full BackBuffer reads | 5 | 4 (DownsamplePS + ComputeLowFreqPS → 1 pass) |
| Cross-effect texture declarations | 6 textures × 2–3 files = ~14 declarations | 0 (all in common.fxh) |
| Private analysis_frame textures | 8 | 0 (all in TexHwyTex data rows) |
| Resolution-independent zone luma | No (32×18 fixed) | Yes (BUFFER_WIDTH/8 scales) |
| LumHistTex format mismatch | Present ⚠ | Fixed (separate concern) |

**Textures eliminated**: DownsampleTex, SceneCutTex, MeanChromaTex, PercHighTex, ChromaExtraTex, ModeTex, EntropyTex, PercTex (standalone), NeutralIllumTex (standalone), CreativeLowFreqTex (standalone), ZoneHistoryTex (standalone), ChromaHistoryTex (standalone) — all absorbed into TexHwyTex or scalar highway.

---

## Risks

1. **Behavioral**: CreativeLowFreqTex currently reads post-inverse_grade BackBuffer (corrective runs after inverse_grade). Moving write to analysis_frame = pre-inverse_grade source. Retinex illumination estimate changes subtly.

2. **Histogram quality**: Switching from 32×18 DownsampleTex source to 1/8-res TexHwyTex source for histogram gather. Histogram iterates same 576 samples but now from a higher-resolution source — identical or better quality.

3. **Pass-through cost**: TexHwyWritePS covers BUFFER_WIDTH/8 × (BUFFER_HEIGHT/8 + 8) pixels. At 1440p: ~59,840 pixels per write pass. Each effect that writes adds one pass of this size. Cheap but non-zero.

4. **ZoneHistoryTex / ChromaHistoryTex packing**: These are RGBA16F textures (4×4 and 8×4). Packing them into data rows of TexHwyTex requires row-major linearisation. Read helpers must reverse this correctly.

5. **NeutralIllumTex write order**: grade writes NeutralIllumTex in its NeutralIllum pass, then inverse_grade reads it on the NEXT frame (one-frame delay). This delay must be preserved in the texture highway.

---

## Questions for Research

1. Does vkBasalt match cross-effect textures by name only, or name+format? (Confirms whether LumHistTex mismatch is a live bug.)
2. Is there prior art on "render target atlas" patterns in post-process pipelines with explicit pass-through mechanisms?
3. What is the actual GPU cost of a 320×180-pixel pass-through shader at 1440p/60fps?
4. Do other ReShade effects use a similar shared-texture-as-bus pattern?
