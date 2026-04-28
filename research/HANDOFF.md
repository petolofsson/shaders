# Session Handoff — 2026-04-29

Fresh-start reference. Read this + CLAUDE.md before any implementation work.

---

## Pipeline overview

vkBasalt HLSL post-process chain, SDR, linear light. Arc Raiders test platform.
Chain: `analysis_frame → analysis_scope_pre → corrective → grade → analysis_scope`

`grade.fx` is one MegaPass (`ColorTransformPS`) — all color work in registers:

| Stage | Name | What it does |
|-------|------|--------------|
| 1 | CORRECTIVE | `pow(rgb, EXPOSURE)` + FilmCurve (R16: zone-informed) |
| 2 | TONAL | Zone S-curve (R05: rank blend) + R18 spatial norm + Clarity + Shadow lift |
| 3 | CHROMA | Oklab chroma lift + HK (R15: Hellwig 2022) + Abney + density + gamut compress |
| 4 | FILM GRADE | Log matrix per preset + R17 adaptive tints + sat rolloff |

Analysis textures written by `corrective.fx` before grade.fx runs:
- `ZoneHistoryTex` 4×4 RGBA16F — smoothed zone medians (.r), p25 (.g), p75 (.b)
- `CreativeZoneHistTex` 32×16 R16F — 32-bin luma histogram per zone
- `PercTex` 1×1 RGBA16F — global pixel histogram p25/p50/p75
- `ChromaHistoryTex` — per-hue chroma stats
- `CreativeLowFreqTex` — 1/8-res base image (luma in .a)

---

## All knobs (`creative_values.fx` — the ONLY tuning surface)

```
CORRECTIVE_STRENGTH  100   passthrough gate
EXPOSURE             1.17  gamma knob (deliberately manual, no auto-exposure)

TONAL_STRENGTH       100   tonal stage gate
ZONE_STRENGTH         30   zone contrast S-curve depth
RANK_CONTRAST_STRENGTH 30  rank-based zone contrast blend (0=median S-curve, 100=CDF equalization)
SPATIAL_NORM_STRENGTH  20  pull zone medians toward global key (R18)
CLARITY_STRENGTH       25  multi-scale local midtone contrast
SHADOW_LIFT            15  raise dark tones

CHROMA_STRENGTH        10  per-hue saturation bend
DENSITY_STRENGTH       45  subtractive dye density
HK_STRENGTH            12  Hellwig 2022 hue-dep. brightness correction

GRADE_STRENGTH          0  film grade gate (0=off)
PRESET                  1  camera preset 0–5
CREATIVE_SATURATION  1.00
CREATIVE_CONTRAST    1.00
```

Preset 0=Soft base, 1=ARRI ALEXA, 2=Kodak Vision3, 3=Sony Venice, 4=Fuji Eterna, 5=Kodak 5219.
Each preset defines WHITE_*, FILM_*, TOE_TINT_*, SHADOW_TINT_*, HIGHLIGHT_TINT_*, BLACK_LIFT_*, TINT_ADAPT_SCALE.

---

## Implemented research jobs

### R01–R07 (earlier session)
- R01: FilmCurve anchor quality
- R02: Zone median accuracy (IQR scaling)
- R03: Zone S-curve shape
- R04: FilmCurve / zone interaction
- R05: Rank-based zone contrast ← implemented 2026-04-29
- R07: Shadow lift redesign

### R08N–R18 (this session, 2026-04-28/29)

**R08N** — Seong & Kwak 2025 HK model: `1/(1 + HK_STRENGTH/100 * C)` saturation correction.

**R09N** — Clarity upgrade: Cauchy bell edge gate + multi-scale Laplacian (mip 1→3) + chroma co-enhancement.

**R10N** — Optimization: Volkansalma atan2 poly, Chilliant sqrt/MAD gamma, small-angle sin/cos, `[unroll]` on chroma loop.

**R11** — Stevens + Hunt: CIECAM02 sqrt curve for Stevens, FL^(1/4) for Hunt. Status: research complete, **pending implementation**.

**R12** — Abney hue shift: swap Cyan↑/Blue↓, add Red band, add Magenta band.

**R13** — Gamut compression: `saturate()` removes `if (rmax > 1)` gate; axis-scale desaturation.

**R14** — Temporal stability: magnitude-adaptive zone speed `speed = base*(1 + 10*|delta|)`, self-initialising.

**R15** — Hellwig 2022 H-K: `f(h)*C^0.587` with sincos+double-angle identities. Replaces Seong linear model. Oklab hue usable directly (offset < 7°). HK_STRENGTH 20→12.

**R16** — FilmCurve zone key: zone geometric mean replaces p50 in Stevens factor; zone min/max blended 40% with p25/p75; zone std dev scales factor (0.7–1.1).

**R17** — Film stock adaptive tints: `r17_stops = log2(zone_log_key / 0.18)`; highlight/shadow tint scaled by stops; per-preset TINT_ADAPT_SCALE.

**R18** — Spatial normalization: `pow(zone_log_key / zone_median, str*0.4)` after zone S-curve; no new pass — LINEAR sampler on 4×4 ZoneHistoryTex provides inherent ~25% screen-width spatial transitions.

**R05** (implemented 2026-04-29) — Rank-based zone contrast: 32-bin CDF walk `r05_cdf += bv * saturate(luma*32 - b)` gives per-pixel rank [0,1]; `dt_rank = rank - 0.5`; blended with median S-curve at RANK_CONTRAST_STRENGTH. IQR scaling retained (rank amplifies flat zones without it).

---

## Research queue

All priority items from ROADMAP.md are done. Queue is empty.

**Deferred (low ROI):** exposure gamma knob, shadow lift psychophysics, saturation rolloff near white.

**R11 pending:** Stevens + Hunt implementations are researched but not coded. Low ROI (Stevens: range barely changes; Hunt: meaningful correction but not urgent).

---

## Key SPIR-V constraints

- No `static const float[]` or `static const float3` — silently wrong output
- No variable named `out`
- Row y=0 of BackBuffer is the data highway — every BB-writing pass must guard `if (pos.y < 1.0) return col`
- `log`, `exp`, `sqrt`, `pow`, `log2`, `atan2` — all safe intrinsics
- `[unroll]` on fixed-bound loops — safe and preferred
- No hard conditionals on pixel properties (`if (luma > x)` etc.) — use `saturate`/`smoothstep`/`step`

---

## Active branch

`alpha` — 7 commits ahead of `origin/alpha` as of 2026-04-29.

Last commit: `aaec889 implement R05: rank-based zone contrast`
