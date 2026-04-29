# Session Handoff — 2026-04-29

Fresh-start reference. Read this + CLAUDE.md before any implementation work.

---

## Pipeline overview

vkBasalt HLSL post-process chain, SDR, linear light. Arc Raiders test platform.
Chain: `analysis_frame → analysis_scope_pre → corrective → grade → analysis_scope`

`grade.fx` is one MegaPass (`ColorTransformPS`) — all color work in registers:

| Stage | Name | What it does |
|-------|------|--------------|
| 1 | CORRECTIVE | `pow(rgb, EXPOSURE)` + FilmCurve (R16: zone-informed, R20: per-channel knee/toe) |
| 1.5 | 3-WAY CORRECTOR | R19: temp/tint per shadow/mid/highlight region (primary grade) |
| 2 | TONAL | Zone S-curve (R18 spatial norm) + Clarity + Shadow lift |
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
EXPOSURE             1.10  gamma knob (deliberately manual, no auto-exposure)

SHADOW_TEMP           -20  3-way: shadows cool (R down, B up)
SHADOW_TINT             0  3-way: shadows tint (+ = magenta, - = green)
MID_TEMP                8  3-way: mids slightly warm
MID_TINT                0
HIGHLIGHT_TEMP         30  3-way: highlights warm
HIGHLIGHT_TINT        -10  3-way: highlights green counter-tint (prevents orange cast)

ZONE_STRENGTH          25  zone contrast S-curve depth
SPATIAL_NORM_STRENGTH  20  pull zone medians toward global key (R18)
CLARITY_STRENGTH       35  multi-scale local midtone contrast
SHADOW_LIFT            17  raise dark tones

DENSITY_STRENGTH       60  subtractive dye density (film compaction)
CHROMA_STRENGTH        40  per-hue saturation bend
HK_STRENGTH            25  Hellwig 2022 hue-dep. brightness correction

GRADE_STRENGTH          0  film grade gate (0=off)
PRESET                  1  camera preset 0–5
CREATIVE_SATURATION  1.00
CREATIVE_CONTRAST    1.00

CORRECTIVE_STRENGTH   100  stage gate — leave at 100
TONAL_STRENGTH        100  stage gate — leave at 100
```

Preset 0=Soft base, 1=ARRI ALEXA, 2=Kodak Vision3, 3=Sony Venice, 4=Fuji Eterna, 5=Kodak 5219.
Each preset defines WHITE_*, FILM_*, TOE_TINT_*, SHADOW_TINT_*, HIGHLIGHT_TINT_*, BLACK_LIFT_*,
TINT_ADAPT_SCALE, CURVE_R_KNEE_OFFSET, CURVE_B_KNEE_OFFSET, CURVE_R_TOE_OFFSET, CURVE_B_TOE_OFFSET.

---

## Implemented research jobs

### R01–R07 (earlier sessions)
- R01: FilmCurve anchor quality
- R02: Zone median accuracy (IQR scaling)
- R03: Zone S-curve shape (adequate as-is)
- R04: FilmCurve / zone interaction (benign, no fix)
- R05: Rank-based zone contrast — **REJECTED** after testing (see findings)
- R07: Shadow lift redesign

### R08N–R18 (2026-04-28/29)

**R08N** — Seong & Kwak 2025 HK model: `1/(1 + HK_STRENGTH/100 * C)` saturation correction.

**R09N** — Clarity upgrade: Cauchy bell edge gate + multi-scale Laplacian (mip 1→3) + chroma co-enhancement.

**R10N** — Optimization: Volkansalma atan2 poly, Chilliant sqrt/MAD gamma, small-angle sin/cos, `[unroll]` on chroma loop.

**R11** — Stevens + Hunt: CIECAM02 sqrt curve for Stevens, FL^(1/4) for Hunt. Status: research complete, **pending implementation**.

**R12** — Abney hue shift: swap Cyan↑/Blue↓, add Red band, add Magenta band.

**R13** — Gamut compression: `saturate()` removes `if (rmax > 1)` gate; axis-scale desaturation.

**R14** — Temporal stability: magnitude-adaptive zone speed `speed = base*(1 + 10*|delta|)`, self-initialising.

**R15** — Hellwig 2022 H-K: `f(h)*C^0.587` with sincos+double-angle identities.

**R16** — FilmCurve zone key: zone geometric mean replaces p50; zone min/max blended 40% with p25/p75; zone std dev scales factor (0.7–1.1).

**R17** — Film stock adaptive tints: `r17_stops = log2(zone_log_key / 0.18)`; per-preset TINT_ADAPT_SCALE.

**R18** — Spatial normalization: `pow(zone_log_key / zone_median, str*0.4)` after zone S-curve.

### This session (2026-04-29 morning)

**Clarity Finding 1** — `pro_mist.fx`: Laplacian residual (`base − diffused`) recycled as midtone clarity lift. Bell `luma*(1−luma)*4` weights it to mids. Uses same `CLARITY_STRENGTH/100.0` scale as grade.fx. Zero GPU cost.

**R05 removed** — Rank-based zone contrast implemented then rejected. Correct equalization behavior still produced global darkening and grayish cast in Arc Raiders because zone histograms are dense in darks/mids with sparse highlights — equalization always compresses highlights. `ZONE_STRENGTH` S-curve is strictly better for this content. Removed from grade.fx and creative_values.fx.

**R19** — 3-Way Color Corrector: six temp/tint knobs (SHADOW/MID/HIGHLIGHT × TEMP/TINT). ASC CDL offset approach, linear light, after Stage 1. Luminance masks partition-of-unity verified. Injected between Stage 1 and Stage 2 in ColorTransformPS.

**R20** — Per-Channel FilmCurve: added `r_knee_off`, `b_knee_off`, `r_toe_off`, `b_toe_off` parameters to FilmCurve. Per-preset `CURVE_*_OFFSET` defines in grade.fx preset blocks. Models physical dye-layer cross-over (Kodak cyan compresses ~0.4 stops earlier than magenta/yellow).

---

## Research queue

**R21** — Hue Rotation: per-band hue angle rotation in Oklab via existing bell weights. 6 new knobs. Spec written, **research not yet executed** — findings file is empty.

**R22** — Saturation by Luminance: luma-driven chroma rolloff at toe and shoulder. 2 new knobs. Spec written, **research not yet executed** — findings file is empty.

**R11 pending:** Stevens + Hunt researched but not coded. Low ROI currently.

**Deferred (low ROI):** exposure gamma knob, shadow lift psychophysics, log working space.

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

`alpha` — last pushed 2026-04-29 morning.
