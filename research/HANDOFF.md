# Pipeline Handoff

Fresh-start reference. Read this + CLAUDE.md before any implementation work.
Session history is in `research/CHANGELOG.md`.

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
| 1 | CORRECTIVE | `pow(rgb, EXPOSURE)` + FilmCurve (zone-informed, per-channel knee/toe) |
| 1.5 | 3-WAY CORRECTOR | Temp/tint per shadow/mid/highlight region (primary grade) |
| 2 | TONAL | Zone S-curve (auto) + Spatial norm (auto) + Clarity + Shadow lift |
| 3 | CHROMA | Oklab: sat-by-luma → hue rotation → chroma lift + HK + Abney + density + gamut compress |

Analysis textures written by `corrective.fx` before `grade.fx` runs:

| Texture | Size | Format | Layout |
|---------|------|--------|--------|
| `ZoneHistoryTex` | 4×4 | RGBA16F | per zone: .r=smoothed median, .g=p25, .b=p75, .a=Kalman P |
| `CreativeZoneHistTex` | 32×16 | R16F | 32-bin luma histogram per zone |
| `PercTex` | 1×1 | RGBA16F | .r=p25, .g=p50, .b=p75, .a=iqr (global luma) |
| `ChromaHistoryTex` | 8×4 | RGBA16F | x=0..5: .r=mean C, .g=std C, .b=wsum, .a=Kalman P — x=6: .r=zone_log_key, .g=zone_std, .b=zmin, .a=zmax |
| `CreativeLowFreqTex` | BW/8×BH/8 | RGBA16F | 1/8-res base image; luma in .a, MipLevels=3 |

---

## Knobs

23 user-facing knobs. **Values below are Arc Raiders tuning** — each game tunes its own
`gamespecific/<game>/shaders/creative_values.fx`.

```
EXPOSURE            1.04

SHADOW_TEMP          -20 / SHADOW_TINT 0
MID_TEMP               4 / MID_TINT    0
HIGHLIGHT_TEMP        30 / HIGHLIGHT_TINT -5

CLARITY_STRENGTH       35
SHADOW_LIFT            15
DENSITY_STRENGTH       45
CHROMA_STRENGTH        40

CURVE_R_KNEE        -0.003 / CURVE_B_KNEE +0.002
CURVE_R_TOE          0.000 / CURVE_B_TOE  0.000

ROT_RED 0.25 / ROT_YELLOW -0.05 / ROT_GREEN 0.20
ROT_CYAN 0.15 / ROT_BLUE -0.12 / ROT_MAG -0.08

CORRECTIVE_STRENGTH 100 / TONAL_STRENGTH 100
```

**Automated (no knob — universal, game-agnostic by construction):**
- Zone S-curve strength — `lerp(0.30, 0.18, smoothstep(0.08, 0.25, zone_std))`
- Retinex blend — `smoothstep(0.04, 0.25, zone_std)` — flat scenes: no correction; contrasty: full
- Spatial normalization — `lerp(10, 30, smoothstep(0.08, 0.25, zone_std))` (complementary)

---

## Automation pipeline

Goal: reduce 23 knobs to ~9 artistic knobs by automating scene-descriptive ones.
See `R24_2026-04-30_Nightly_Automation_Research.md` for full formula derivations.

| Knob | Status | Signal | Notes |
|------|--------|--------|-------|
| SPATIAL_NORM_STRENGTH | **Done** | zone_std | Removed from creative_values.fx |
| SHADOW_LIFT | **Ready** | PercTex.r (p25) | `lerp(20,5,smoothstep(0.04,0.28,p25))` — implement next |
| DENSITY_STRENGTH | **Ready (pending signal)** | ChromaHistoryTex mean_chroma | Weighted avg of .r×.b across 6 bands — no new pass needed |
| CHROMA_STRENGTH | **Ready (pending signal)** | same mean_chroma | Implement together with DENSITY |
| CLARITY_STRENGTH | **Deferred** | PercTex IQR | IQR is indirect proxy; pumping risk on scene cuts |

**mean_chroma formula** (for DENSITY + CHROMA — reads ChromaHistoryTex in grade.fx Stage 3):
```hlsl
float cm_total = 0.0, cm_w = 0.0;
[unroll] for (int b = 0; b < 6; b++) {
    float4 h = tex2D(ChromaHistory, float2((b + 0.5) / 8.0, 0.5 / 4.0));
    cm_total += h.r * h.b;
    cm_w     += h.b;
}
float mean_chroma = cm_total / max(cm_w, 0.001);
```

---

## SPIR-V constraints

- No `static const float[]`, `static const float2[]`, `static const float3` — wrong output
- No variable named `out`
- Row y=0 of BackBuffer is the data highway — every BB-writing pass must guard `if (pos.y < 1.0) return col`
- `[unroll]` on fixed-bound loops — safe and preferred
- No hard conditionals on pixel properties — use `saturate` / `smoothstep` / `step`
- `sincos`, `frac`, `cos`, `sin`, `log`, `exp`, `sqrt`, `pow` — all safe

---

## Game-specific: arc_raiders

**GPU budget (critical constraint):** UE5/Lumen saturates the GPU frame budget before
vkBasalt runs. Every new pass must justify its cost. Prefer small intermediate textures,
minimize taps, reuse existing textures. Additional passes in heavy scenes risk
`VK_ERROR_DEVICE_LOST`.

**pro_mist — must stay single-pass:** A two-pass Gaussian version crashed Arc Raiders
intermittently (UE5 frame budget). `DiffuseTex` and `DiffuseHPS` were removed. If the
effect is too subtle, increase `adapt_str` base (currently `0.09` in `pro_mist.fx`) — not a knob.
The `adapt_str` calibration (`lerp(0.7, 1.3, saturate(iqr / 0.5))`) is Arc Raiders-specific.

**Inactive effects (available in arc_raiders.conf):**
- `veil` — atmospheric depth haze
- `retinal_vignette` — natural optical vignetting

**Not yet built:**
- Halation — film emulsion scatter, localized to brightest highlights
- Chromatic aberration

---

## Research queue

**R28 complete — Kalman temporal filter:** Replaces EMA in SmoothZoneLevelsPS +
UpdateHistoryPS. P stored in .a of both history textures. Q=0.0001, R=0.01, K_inf=0.095.

**R29 complete — Multi-Scale Retinex:** Replaces R18 zone normalization. Pixel-local
illumination separation using CreativeLowFreqTex mips 0/1/2. Coarse-biased weights
(0.20/0.30/0.50). Blend auto-driven by zone_std.

**R30 complete — Wavelet clarity:** 3-band Haar decomposition (D1/D2/D3) replaces
2-level Laplacian. Weights 0.50/0.30/0.20. Mip 1 shared with R29.

**R31 complete — Nyquist sampling:** No change. 8 samples + Kalman accumulation ≈ p95.
16 zones above literature reference but sound.

**R32 complete — Zone stats pre-computation:** ChromaHistoryTex col 6 stores
zone_log_key/zone_std/zmin/zmax. grade.fx reads 1 tap instead of 16-tap gather.

**R27 complete — data highway integrity audit:** All active BB-writing passes have guards.
Two open items in scope display only: `analysis_frame` DebugOverlay missing guard (latent),
and pixel-129 smoothing broken (removed in R27 fix B).

**R11 pending:** Stevens + Hunt — researched, not coded. Low ROI until automation
knobs are validated. Relevant as secondary trim on CLARITY and CHROMA (≤20% weight).

**Next:** CLAHE-inspired clip limit on zone S-curve (natural Retinex complement per
MDPI 2024), Kalman for PercTex (analysis_frame.fx EMA), register pressure re-audit.

**Nightly jobs (04:00 local):** output to `R{next}_{YYYY-MM-DD}_{topic}.md`, push to `alpha`.
- `Shader Research — Nightly` — domain-rotation literature search (Brave + arxiv)
- `Shader Automation Research` — knob-reduction formula derivation (Brave + arxiv)
- `Shader System Stability Audit` — register pressure, unsafe math, row guard audit

---

## Active branch

`alpha` — last committed 2026-04-30.
