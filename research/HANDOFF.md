# Pipeline Handoff

Fresh-start reference. Read this + CLAUDE.md before any implementation work.
Session history is in `research/CHANGELOG.md` and `research/CHANGELOG_2026-05-01_session.md`.

---

## Pipeline

vkBasalt HLSL post-process chain, SDR, linear light. **Game-agnostic** — each game
supplies its own `creative_values.fx` and conf. Arc Raiders is the primary test platform.

Chain (defined per game in conf):
```
analysis_frame → analysis_scope_pre → corrective → grade → pro_mist → analysis_scope
```

`grade.fx` is one MegaPass (`ColorTransformPS`) — all color work in registers:

| Stage | Name | What it does |
|-------|------|--------------|
| 0 | FILM RANGE | R54: `col × (CEILING−FLOOR) + FLOOR` — camera signal floor/ceiling before EXPOSURE |
| 1 | CORRECTIVE | `pow(rgb, EXPOSURE)` + FilmCurve (zone-informed, per-channel H&D knee/toe) |
| 1.5 | PRINT STOCK | Kodak 2383: black lift, steeper toe, mid desaturation, warm cast |
| 1.6 | DYE ABSORPTION | R50: dominant-channel soft attenuation on saturated pixels |
| 1.7 | 3-WAY CORRECTOR | Temp/tint per shadow/mid/highlight region (primary grade) |
| 2 | TONAL | Zone S-curve (lum_att × zone_std auto) + CLAHE clip + Retinex (LOD 1) + Shadow lift |
| 3 | CHROMA | Purkinje shift → sat-by-luma → hue rotation → chroma lift + HK + Abney + density + gamut compress |
| 3.5 | HALATION | R56: tight chromatic scatter from specular highlights — R(mip1) > G(mip0), B=0 |
| OUT | DITHER | ±0.5/255 screen-space noise — converts 8-bit BackBuffer quantization to imperceptible noise |

`pro_mist.fx` runs after `grade.fx` as a separate effect (single-pass, re-enabled R55):

| Stage | Name | What it does |
|-------|------|--------------|
| — | MIST | Bidirectional scatter from CreativeLowFreqTex (mip blend 0+1, IQR-driven radius) |

Analysis textures written by `corrective.fx` before `grade.fx` runs:

| Texture | Size | Format | Layout |
|---------|------|--------|--------|
| `ZoneHistoryTex` | 4×4 | RGBA16F | per zone: .r=smoothed median, .g=p25, .b=p75, .a=Kalman P |
| `CreativeZoneHistTex` | 32×16 | R16F | 32-bin luma histogram per zone |
| `PercTex` | 1×1 | RGBA16F | .r=p25, .g=p50, .b=p75, .a=Kalman P (global luma) |
| `SceneCutTex` | 1×1 | RGBA16F | .r=scene_cut [0,1], .g=p50 prev frame |
| `ChromaHistoryTex` | 8×4 | RGBA16F | x=0..5: .r=mean C, .g=std C, .b=wsum, .a=Kalman P — x=6: .r=zone_log_key, .g=zone_std, .b=zmin, .a=zmax |
| `CreativeLowFreqTex` | BW/8×BH/8 | RGBA16F | 1/8-res base image; luma in .a, MipLevels=3 |

---

## Knobs

30 user-facing knobs. **Values below are Arc Raiders tuning.**

```
EXPOSURE            1.03
FILM_FLOOR          0.005
FILM_CEILING        0.95

PRINT_STOCK         0.20
HAL_STRENGTH        0.35

SHADOW_TEMP          0 / SHADOW_TINT 0
MID_TEMP             0 / MID_TINT    0
HIGHLIGHT_TEMP       0 / HIGHLIGHT_TINT 0

ZONE_STRENGTH        1.0
SHADOW_LIFT          1.7
PURKINJE_STRENGTH    1.3
CHROMA_STRENGTH      0.9

CURVE_R_KNEE        0.000 / CURVE_B_KNEE 0.000
CURVE_R_TOE         0.000 / CURVE_B_TOE  0.000

ROT_RED 0.00 / ROT_YELLOW 0.00 / ROT_GREEN 0.00
ROT_CYAN 0.00 / ROT_BLUE 0.00 / ROT_MAG 0.00

CORRECTIVE_STRENGTH 100 / TONAL_STRENGTH 100
MIST_STRENGTH 0.25

VIGN_STRENGTH 0.00 / VIGN_RADIUS 0.40 / VIGN_CHROMA 0.00  (retinal_vignette not in chain)
VEIL_STRENGTH 0.00                                          (veil not in chain)
```

**Automated (no knob):**
- Zone S-curve strength — `lerp(0.26, 0.16, smoothstep(0.08, 0.25, zone_std)) * lerp(1.10, 0.93, lum_att)`
- Retinex blend — `0.75 * smoothstep(0.04, 0.25, zone_std)`
- Spatial normalization — `lerp(10, 30, smoothstep(0.08, 0.25, zone_std))`
- Chroma/density strengths — driven by mean_chroma from ChromaHistoryTex
- Scene-cut Kalman gain — `lerp(K, 1.0, scene_cut)` from SceneCutTex

---

## Automation pipeline

Goal: reduce knobs by automating scene-descriptive ones. All viable automation complete (R41).
17 artistic knobs locked by design. No further automation proposed.

---

## SPIR-V constraints

- No `static const float[]`, `static const float2[]`, `static const float3` — wrong output
- No variable named `out`
- Row y=0 of BackBuffer is the data highway — every BB-writing pass must guard `if (pos.y < 1.0) return col`
- `[unroll]` on fixed-bound loops — safe and preferred
- No hard conditionals on pixel properties — use `saturate` / `smoothstep` / `step`

---

## Game-specific: arc_raiders

**GPU budget (critical constraint):** UE5/Lumen saturates the GPU frame budget before
vkBasalt runs. Every new pass must justify its cost. Additional passes in heavy scenes risk
`VK_ERROR_DEVICE_LOST`.

**pro_mist — must stay single-pass.** Two-pass version caused `VK_ERROR_DEVICE_LOST`.
`DiffuseTex` and `DiffuseHPS` removed. R55 rework (2026-05-01): bidirectional scatter,
multi-scale mip blend, clarity boost removed, halation removed (→ R56 in grade.fx).
Now back in the active chain. Output dithered.

**Inactive effects (available in arc_raiders.conf — not in effects line):**
- `veil` — atmospheric depth haze. Use for games without volumetric fog. Skip for Arc
  Raiders — Lumen handles atmospheric depth natively.
- `retinal_vignette` — natural optical vignetting. Use for games without a built-in
  vignette. Skip for Arc Raiders — engine vignette already present.

**Not yet built:** nothing. Chain is feature-complete as of 2026-05-01.

---

## Research queue

**R48 complete** — luminance-adapted zone contrast (zone_log_key × zone_std dual-axis).

**R49 complete** — per-channel FilmCurve H&D gamma weights.

**R50 complete** — dye secondary absorption (dominant-channel soft attenuation).

**R51 complete** — print stock emulsion (Kodak 2383 approximation). `PRINT_STOCK 0.20`.

**R52 complete** — Purkinje shift in deep shadows. `PURKINJE_STRENGTH 1.3`.

**R53 complete** — scene-change Kalman reset. SceneCutTex 1×1; fires on hard cuts only.

**R54 complete** — camera signal floor/ceiling. `FILM_FLOOR 0.005`, `FILM_CEILING 0.95`. Remap before EXPOSURE in `ColorTransformPS`.

**R55 complete** — pro_mist rework. Bidirectional scatter, mip 0+1 blend (IQR-driven), clarity boost removed, R37 halation removed (→ R56), output dithered. `MIST_STRENGTH 0.25`. Re-enabled in chain.

**R56 complete** — film halation. Tight chromatic scatter inside `ColorTransformPS` end of Stage 3. R(mip1) > G(mip0), B=0. Gate: smoothstep(0.80, 0.95, luma). `HAL_STRENGTH 0.35`. Self-regulating against game bloom.

**Nightly jobs (04:00 local):** output to `R{next}_{YYYY-MM-DD}_{topic}.md`, push to `alpha`.
- `Shader Research — Nightly` — domain-rotation literature search
- `Shader Automation Research` — knob-reduction formula derivation
- `Shader System Stability Audit` — register pressure, unsafe math, row guard audit

---

## Active branch

`alpha` — v1.0 stable committed 2026-05-01.
