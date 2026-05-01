# Session Changelog — 2026-05-01

## Commits this session

| Hash | Summary |
|------|---------|
| `ed16dce` | implement R48–R50; remove clarity; fix Retinex bloom via LOD 1 illuminant |
| `28831ab` | tune: EXPOSURE 1.10, SHADOW_LIFT 1.7, deeper shadow bell curve |
| *(pending)* | implement R51–R53; findings for R51–R53; tune knobs |

---

## What changed

### R48 — Luminance-adapted zone contrast (`grade.fx`)
`zone_log_key` drives `lum_att`, scaling zone S-curve: dark scenes +15%, bright scenes −7%.
Matches Stevens effect. `ZONE_STRENGTH` knob added.

### R49 — Per-channel FilmCurve gamma (`grade.fx`)
H&D sensitometry: `shoulder_w = float3(0.91, 1.00, 1.06)`, `toe_w = float3(0.95, 1.00, 1.04)`.
Warm shadows, neutral-to-cool highlights. < 0.3% channel separation at midtone.

### R50 — Dye secondary absorption (`grade.fx`, after FilmCurve, before R19)
Dominant-channel soft attenuation. Coupling 0.06, `smoothstep(0.0, 0.25, sat_proxy)`. ~5% max.
Neutral-preserving by construction. Validated — skin/foliage acceptable.

### R51 — Print stock emulsion / Kodak 2383 (`grade.fx`, after FilmCurve, before R50)
Black lift to 0.025, steeper toe (`x*x*3.2`), harder shoulder, ~15% mid desaturation,
warm shadow cast (R+0.012, B−0.008). `PRINT_STOCK` knob, default 0.20.
Literature: Kodak H-1-2383t official sensitometry; ACES RRT two-stage model.

### R52 — Purkinje shift (`grade.fx` Oklab block, before R22)
Rod-vision blue-green bias in deep shadows (`new_luma < 0.12`). Oklab b-axis shift:
`lab.z -= 0.018 * scotopic_w * C * PURKINJE_STRENGTH`. Neutrals unaffected (C=0 → zero).
`PURKINJE_STRENGTH` knob, default 1.1. Literature: Cao et al. (2008); Ghost of Tsushima SIGGRAPH 2021.

### R53 — Scene-change Kalman reset (`analysis_frame.fx` + `corrective.fx`)
`SceneCutTex` (1×1 RGBA16F) — written by new `SceneCutPS` pass in analysis_frame.
Delta between consecutive Kalman-smoothed p50 values → `scene_cut = smoothstep(0.10, 0.25, delta)`.
`SmoothZoneLevelsPS` and `UpdateHistoryPS` in corrective read scene_cut and override
`K = lerp(K, 1.0, scene_cut)` — instant snap on hard cuts, zero change during stable play.

### Clarity — removed
Wavelet clarity (R30/R43/R44) caused bloom via 1/8-res illuminant bleed. Redundant with
driver/in-game sharpening. `CLARITY_STRENGTH` removed.

### Retinex — single-scale LOD 1
Multi-scale dropped. LOD 0 caused 8-pixel block-boundary halos. LOD 1 (1/16-res mipmap) clean.

---

## Current creative_values.fx

```
EXPOSURE          1.00
ZONE_STRENGTH     1.0
CHROMA_STRENGTH   0.9
SHADOW_LIFT       2.0
PRINT_STOCK       0.20
PURKINJE_STRENGTH 1.1
MIST_STRENGTH     0.40  (pro_mist not in active chain)
```
All 3-way corrector, hue rotation, film curve offsets at passthrough/default.

---

## Active chain

```
analysis_frame : analysis_scope_pre : corrective : grade : analysis_scope
```
pro_mist excluded from chain.

---

## Open items for next session

- **R54 proposal**: camera signal floor/ceiling — real camera sensors don't go to true 0 or 1.
  ARRI lifts blacks ~7.3%, white ceiling below clipping. Previously in `inverse_grade` (pulled).
  Proposal: simple remap at top of `ColorTransformPS` before EXPOSURE — two-line change, no new pass.
- **Nightly jobs**: next run 2026-05-02 at 1–4 AM UTC.

## Closed this session

- **R50** — validated (skin/foliage, 0.06 coupling).
- **R51** — validated (print stock look confirmed, PRINT_STOCK=0.20 tuned).
- **R52** — validated (Purkinje shadow richness confirmed, PURKINJE_STRENGTH=1.1).
- **R53** — implemented (correctness fix, fires only on scene cuts).
- **Retinex strength** — signed off at `0.75 * smoothstep(0.04, 0.25, zone_std)`.
- **SHADOW_LIFT** — self-limiting confirmed, current 2.0.
