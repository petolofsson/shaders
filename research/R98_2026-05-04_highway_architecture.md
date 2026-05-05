# R98 — Data Highway Architecture

**Date:** 2026-05-04  
**Status:** Proposal

## Problem

The pipeline has two classes of shared data today:

1. **Shared textures** — PercTex, MeanChromaTex, WarmBiasTex, SceneCutTex, ChromaHistoryTex, ZoneHistoryTex, LumHistTex, SatHistTex. Every effect that reads any of these must redeclare the texture with an identical descriptor. If the format or size ever changes, every file touches it needs updating. A new effect can't simply plug in — it has to know which textures to declare and where they come from.

2. **Data highway** — BackBuffer row y=0. Already carries luma histogram, hue histogram, and a handful of scalar stats (x=194–197). Every effect already guards this row. But coverage is incomplete — most scalar stats live in textures instead.

The result is tight coupling. Effects are bound to specific textures from specific writers. There's no single place to learn what scene data is available.

## Proposal

Make the data highway the **canonical shared datastream**. Every scalar scene statistic computed by `analysis_frame` (or any other analysis pass) gets a numbered highway slot. Consumer effects read what they need by slot index. No special-case texture declarations for scalar values.

### Layers

```
┌──────────────────────────────────────┐
│  analysis_frame  (data layer)        │  writes all scene stats to highway
│  analysis_scope_pre (pre-corr stats) │  writes pre-correction histogram
└────────────────┬─────────────────────┘
                 │ BackBuffer y=0 — the bus
┌────────────────▼─────────────────────┐
│  corrective / grade / pro_mist / …   │  pure consumers — read by slot index
│  (any future effect)                 │  no texture declarations, no coupling
└──────────────────────────────────────┘
```

### What moves to the highway

Currently on the highway (keep):

| Slot x | Value | Writer |
|--------|-------|--------|
| 0–127 | Pre-correction luma histogram | analysis_scope_pre |
| 128 | Pre-correction mean luma | analysis_scope_pre |
| 129 | Post-correction mean luma | analysis_scope |
| 130–193 | Pre-correction hue histogram | analysis_scope_pre |
| 194 | p25 | analysis_frame |
| 195 | p50 | analysis_frame |
| 196 | p75 | analysis_frame |
| 197 | R90 slope (encoded: `(slope-1.0)/1.5`) | analysis_frame |

Proposed additions from analysis_frame:

| Slot x | Value | Encoding | Replaces |
|--------|-------|----------|---------|
| 198 | scene mean Oklab C | raw [0, 0.4] fits in [0,1] | MeanChromaTex |
| 199 | scene cut signal [0,1] | raw | SceneCutTex .r |
| 200 | Kalman variance P | `P / 0.1` clamped | PercTex .a |
| 201 | IQR (p75 − p25) | raw | derived, not stored |

Proposed additions from corrective (corrective already writes after analysis_frame, so these need a corrective-pass write):

| Slot x | Value | Encoding | Replaces |
|--------|-------|----------|---------|
| 210 | warm bias EMA | raw [0,1] | WarmBiasTex |
| 211 | zone log key | `log_key / 0.5` | ChromaHistoryTex col 6 .r |
| 212 | zone std | raw | ChromaHistoryTex col 6 .g |
| 213 | scene key (from ChromaHistoryTex) | raw | ChromaHistoryTex col 6 .b |

Slots 220–255 reserved for future per-channel or per-zone stats.

### What stays as textures

Some data structures are inherently multi-dimensional and can't flatten to the highway without consuming hundreds of slots:

- **LumHistTex / SatHistTex** — 64-bin histograms used internally between analysis_frame passes. These are intermediate, not shared by consumer effects. Keep as internal textures.
- **DownsampleTex** — internal to analysis_frame. Keep.
- **ZoneHistoryTex / ChromaHistoryTex** — 8×4 zone stats arrays. These could eventually be flattened to 32 highway slots, but are non-trivial to migrate. Phase 2.
- **CreativeLowFreqTex** — spatial, 1/8-res. Not a scalar, cannot be a highway slot.

### Encoding convention

The highway is 8-bit UNORM between effects. All values must round-trip through [0,1]:

- Values naturally in [0,1]: store raw. No encoding needed.
- Slope `[1.15, 1.8]`: encode `(v - 1.0) / 1.5` → decode `v * 1.5 + 1.0`. (Already in use at x=197.)
- Any future value outside [0,1]: document its range and encoding formula in the table above.

Reading convention:
```hlsl
// Read a highway slot
float val = tex2Dlod(BackBuffer, float4((SLOT + 0.5) / BUFFER_WIDTH, 0.5 / BUFFER_HEIGHT, 0, 0)).r;
```

### Effect contract

Every BackBuffer-writing pass must already preserve y=0 (`if (pos.y < 1.0) return col`). That rule is unchanged. Highway data persists through the entire chain as long as no pass overwrites it.

Consumer effects declare **only BackBuffer**. No shared texture declarations. Slot indices are defined in a single header (`highway.fxh`) included by any effect that needs them:

```hlsl
// highway.fxh
#define HWY_P25          194
#define HWY_P50          195
#define HWY_P75          196
#define HWY_SLOPE        197
#define HWY_MEAN_CHROMA  198
#define HWY_SCENE_CUT    199
#define HWY_WARM_BIAS    210
#define HWY_ZONE_KEY     211
#define HWY_ZONE_STD     212

#define ReadHWY(slot) tex2Dlod(BackBuffer, float4(((slot) + 0.5) / BUFFER_WIDTH, 0.5 / BUFFER_HEIGHT, 0, 0)).r
```

Any effect then does:
```hlsl
float p75      = ReadHWY(HWY_P75);
float mean_C   = ReadHWY(HWY_MEAN_CHROMA);
float warm_bias = ReadHWY(HWY_WARM_BIAS);
```

## Migration plan

**Phase 1 — scalar stats from analysis_frame**
- Add highway writes for x=198–201 in `DebugOverlayPS` (or a new `HighwayWritePS` pass)
- Remove `MeanChromaTex` redeclarations; have `inverse_grade.fx` read x=198 instead
- Remove `SceneCutTex` redeclaration in corrective; read x=199
- Create `highway.fxh`

**Phase 2 — corrective scalar stats**
- Move warm_bias and zone stats to highway slots 210–213 (corrective writes them, all subsequent effects read from highway)
- Remove `WarmBiasTex` declarations from `pro_mist.fx`

**Phase 3 — optional: flatten ZoneHistoryTex / ChromaHistoryTex**
- Only if the zone stat array stays small enough to fit in ≤32 highway slots

## Constraints and risks

- **Order dependency**: slots written by corrective (210+) aren't valid when read by effects that run before corrective. Slot index ranges encode write order by convention (0–209 = analysis_frame, 210+ = corrective).
- **8-bit precision**: encoding any value with a dynamic range wider than ~100 loses precision. Values like Kalman P (very small) need careful range normalization.
- **BUFFER_WIDTH floor**: at 1920, 255 named slots is far below the ceiling. Fine for the foreseeable future.
