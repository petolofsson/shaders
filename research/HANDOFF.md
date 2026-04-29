# Session Handoff — 2026-04-29 (evening)

Fresh-start reference. Read this + CLAUDE.md before any implementation work.

---

## Pipeline overview

vkBasalt HLSL post-process chain, SDR, linear light. Arc Raiders test platform.
Chain: `analysis_frame → analysis_scope_pre → corrective → grade → analysis_scope`

`grade.fx` is one MegaPass (`ColorTransformPS`) — all color work in registers:

| Stage | Name | What it does |
|-------|------|--------------|
| 1 | CORRECTIVE | `pow(rgb, EXPOSURE)` + FilmCurve (zone-informed, per-channel knee/toe) |
| 1.5 | 3-WAY CORRECTOR | R19: temp/tint per shadow/mid/highlight region (primary grade) |
| 2 | TONAL | Zone S-curve (auto-strength from zone_std) + Clarity + Shadow lift |
| 3 | CHROMA | Oklab: R22 sat-by-luma → R21 hue rotation → chroma lift + HK (baked 0.25) + Abney + density + gamut compress |

Stage 4 (FILM GRADE) has been **removed** — was dead code at GRADE_STRENGTH=0. All 6 preset blocks (~220 defines) and ~100 lines of Stage 4 shader code deleted.

Analysis textures written by `corrective.fx` before grade.fx runs:
- `ZoneHistoryTex` 4×4 RGBA16F — smoothed zone medians (.r), p25 (.g), p75 (.b)
- `CreativeZoneHistTex` 32×16 R16F — 32-bin luma histogram per zone
- `PercTex` 1×1 RGBA16F — global pixel histogram p25/p50/p75
- `ChromaHistoryTex` — per-hue chroma stats
- `CreativeLowFreqTex` — 1/8-res base image (luma in .a)

---

## All knobs (`creative_values.fx` — the ONLY tuning surface)

24 knobs total.

```
EXPOSURE            1.04   gamma knob (deliberately manual, no auto-exposure)

SHADOW_TEMP          -20   3-way: shadows cool
SHADOW_TINT            0
MID_TEMP               4   3-way: mids slightly warm
MID_TINT               0
HIGHLIGHT_TEMP        30   3-way: highlights warm
HIGHLIGHT_TINT        -5

SPATIAL_NORM_STRENGTH  20  pull zone medians toward global key
CLARITY_STRENGTH       35  multi-scale local midtone contrast
SHADOW_LIFT            15  raise dark tones

DENSITY_STRENGTH       45  subtractive dye density (film compaction)
CHROMA_STRENGTH        40  per-hue saturation bend

CURVE_R_KNEE        -0.003  FilmCurve per-channel offsets (film stock character)
CURVE_B_KNEE        +0.002
CURVE_R_TOE          0.000
CURVE_B_TOE          0.000

ROT_RED              0.25   hue rotation: skintones → amber
ROT_YELLOW          -0.05   yellows → golden
ROT_GREEN            0.20   foliage → teal
ROT_CYAN             0.15   cyans → deep blue
ROT_BLUE            -0.12   sky → cerulean
ROT_MAG             -0.08   magentas → violet

CORRECTIVE_STRENGTH  100   stage gate — leave at 100
TONAL_STRENGTH       100   stage gate — leave at 100
```

**Knobs removed this session** (were user-facing, now baked/automated):
- `ZONE_STRENGTH` — automated from `zone_std`: `lerp(0.30, 0.18, smoothstep(0.08, 0.25, zone_std))`
- `HK_STRENGTH` — baked at 0.25 (Hellwig 2022 calibrated value)
- `SAT_SHADOW_ROLLOFF` — baked at 20% (Munsell V=1–2 calibration)
- `SAT_HIGHLIGHT_ROLLOFF` — baked at 25% (ACES 2.0 / film shoulder calibration)
- `GRADE_STRENGTH`, `PRESET`, `CREATIVE_SATURATION`, `CREATIVE_CONTRAST` — Stage 4 removed entirely

---

## Implemented research jobs

### R01–R07 (earlier sessions)
- R05: Rank-based zone contrast — **REJECTED** (global darkening/grayish cast in Arc Raiders)
- R07: Shadow lift redesign

### R08N–R20 (2026-04-28/29 morning)

**R08N** — Seong & Kwak 2025 HK model.
**R09N** — Clarity: Cauchy bell + multi-scale Laplacian + chroma co-enhancement.
**R10N** — Optimization: Volkansalma atan2 poly, Chilliant sqrt gamma, [unroll].
**R11** — Stevens + Hunt: researched, **pending implementation** (low ROI currently).
**R12** — Abney: swap Cyan↑/Blue↓, add Red + Magenta bands.
**R13** — Gamut compression: saturate() removes gate.
**R14** — Temporal stability: magnitude-adaptive zone speed.
**R15** — Hellwig 2022 H-K: f(h)·C^0.587 with sincos+double-angle.
**R16** — FilmCurve zone key: geometric mean + zone min/max blend + std scaling.
**R17** — Film stock adaptive tints (now inactive — Stage 4 removed).
**R18** — Spatial normalization: zone_log_key/zone_median^str.
**R19** — 3-Way Color Corrector: six temp/tint knobs.
**R20** — Per-Channel FilmCurve: CURVE_R/B_KNEE/TOE offsets.

### This session (2026-04-29 evening)

**R21** — Hue Rotation: 6 ROT_* knobs in Oklab LCh. Two-phase injection:
  - Phase 1: h_delta computed from original h before chroma lift loop (band-correct saturation)
  - Phase 2: 2×2 rotation matrix on (lab.y, lab.z) after loop — bitwise passthrough at zero
  - Abney and H-K updated to use h_out (rotated hue)
  - Passthrough verified: sin=0, cos=1 at r21_delta=0 → ab_in = float2(lab.y, lab.z) identically

**R22** — Saturation by Luminance: baked Munsell calibration, no user knobs.
  - Shadow rolloff 20% at L=0, fades to L=0.25 (Munsell V=3, L_oklab≈0.41)
  - Highlight rolloff 25% at L=1, fades from L=0.75 (Munsell V=7–8)
  - Injected before R21, acting on C before all downstream chroma work
  - `C *= saturate(1.0 - 0.20 * saturate(1.0 - lab.x / 0.25) - 0.25 * saturate((lab.x - 0.75) / 0.25));`

**Stage 4 removed** — FILM GRADE was dead code (GRADE_STRENGTH=0 always).
  - All 6 `#if PRESET == N` blocks (~220 defines) deleted from grade.fx
  - ~100 lines of Stage 4 shader code deleted
  - Helper functions (RGBtoHSV, HSVtoRGB, LogEncode, LogDecode) removed
  - FilmCurve CURVE_*_OFFSET defines surfaced as 4 direct knobs (CURVE_R/B_KNEE/TOE)
  - Final output: `float4(lin, col.a)` direct from Stage 3

**Zone strength automated** — ZONE_STRENGTH removed from creative_values.fx:
  - `zone_str = lerp(0.30, 0.18, smoothstep(0.08, 0.25, zone_std))`
  - Flat scenes get 0.30, contrasty scenes 0.18, typical Arc Raiders ~0.25

**HK_STRENGTH baked at 0.25** — removed from creative_values.fx.

---

## Research queue

**R11 pending:** Stevens + Hunt researched but not coded. Low ROI currently — skip unless tonal response feels off.

**Deferred (low ROI):** exposure gamma knob, shadow lift psychophysics, log working space.

**No active research jobs.** The pipeline is in a clean, tuned state.

---

## Key SPIR-V constraints

- No `static const float[]` or `static const float3` — silently wrong output
- No variable named `out`
- Row y=0 of BackBuffer is the data highway — every BB-writing pass must guard `if (pos.y < 1.0) return col`
- `log`, `exp`, `sqrt`, `pow`, `log2`, `atan2` — all safe intrinsics
- `[unroll]` on fixed-bound loops — safe and preferred
- No hard conditionals on pixel properties (`if (luma > x)` etc.) — use `saturate`/`smoothstep`/`step`
- `sincos`, `frac`, `cos`, `sin` — safe SPIR-V intrinsics

---

## Active branch

`alpha` — last pushed 2026-04-29 evening.
