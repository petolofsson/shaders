# Session Handoff — 2026-04-29 (night)

Fresh-start reference. Read this + CLAUDE.md before any implementation work.

---

## Pipeline overview

vkBasalt HLSL post-process chain, SDR, linear light. Arc Raiders test platform (UE5/Lumen).
Chain: `analysis_frame → analysis_scope_pre → corrective → grade → pro_mist → analysis_scope`

`grade.fx` is one MegaPass (`ColorTransformPS`) — all color work in registers:

| Stage | Name | What it does |
|-------|------|--------------|
| 1 | CORRECTIVE | `pow(rgb, EXPOSURE)` + FilmCurve (zone-informed, per-channel knee/toe) |
| 1.5 | 3-WAY CORRECTOR | R19: temp/tint per shadow/mid/highlight region (primary grade) |
| 2 | TONAL | Zone S-curve (auto-strength from zone_std) + Spatial norm (auto from zone_std) + Clarity + Shadow lift |
| 3 | CHROMA | Oklab: R22 sat-by-luma → R21 hue rotation → chroma lift + HK (baked 0.25) + Abney + density + gamut compress |

Stage 4 (FILM GRADE) was removed last session — dead code at GRADE_STRENGTH=0.

Analysis textures written by `corrective.fx` before grade.fx runs:
- `ZoneHistoryTex` 4×4 RGBA16F — smoothed zone medians (.r), p25 (.g), p75 (.b)
- `CreativeZoneHistTex` 32×16 R16F — 32-bin luma histogram per zone
- `PercTex` 1×1 RGBA16F — global pixel histogram p25/p50/p75
- `ChromaHistoryTex` 8×4 RGBA16F — per-band Oklab chroma mean/std
- `CreativeLowFreqTex` BW/8×BH/8 RGBA16F — 1/8-res base image (luma in .a)

---

## All knobs (`creative_values.fx` — the ONLY tuning surface)

23 knobs total. SPATIAL_NORM_STRENGTH removed — now fully automated.

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

**Automated (no knob):**
- Zone S-curve strength — `lerp(0.30, 0.18, smoothstep(0.08, 0.25, zone_std))`
- Spatial normalization — `lerp(10, 30, smoothstep(0.08, 0.25, zone_std))` (complementary direction)

---

## This session (2026-04-30)

### SPATIAL_NORM_STRENGTH automated (R24N)
`SPATIAL_NORM_STRENGTH` removed from `creative_values.fx` (both arc_raiders and gzw).
`grade.fx:284` now computes strength directly from `zone_std`:
```hlsl
float r18_str = lerp(10.0, 30.0, smoothstep(0.08, 0.25, zone_std)) / 100.0 * 0.4;
```
Runs in the complementary direction to the existing `zone_str` automation — contrasty
scenes get stronger normalization while getting a gentler S-curve, preventing
double-amplification of large zone differences. 23 knobs remain.

### Nightly job fixes
- All three triggers: added `git config user.email/name` + `git push origin HEAD:alpha`
- Stability audit + Automation research: added `git checkout alpha` at job start (jobs
  were running on `main` branch — wrong codebase)
- Automation research: added Brave curl + arxiv search pattern

### Research filed
- `R24N_2026-04-30_Nightly_Automation_Research.md` — 5-knob automation formulas
  (SHADOW_LIFT and SPATIAL_NORM ready; DENSITY+CHROMA need mean_chroma signal via
  ChromaHistoryTex weighted average; CLARITY deferred — IQR proxy, pumping risk)

---

## This session (2026-04-29 night)

### GZW fully configured
- Rewrote `gzw.conf` to mirror arc_raiders structure
- Created `gamespecific/gzw/shaders/creative_values.fx` (copy of arc_raiders values)
- Created `gamespecific/gzw/shaders/debug_text.fxh` (copy + '8' glyph)
- GZW chain: `analysis_frame:analysis_scope_pre:corrective:grade:pro_mist:analysis_scope`

### Debug label system extended
- Added '8' glyph to both `debug_text.fxh` files: `if (ch == 56u) return 34287u;`
- Slots now: 1ANL / 2SCP / 3COR+4ZON+5CHR (passthrough) / 6GRA / 7PMS / 8SCO
- analysis_scope moved from slot 7 (y=58) to slot 8 (y=66)

### pro_mist — new effect (R23N)
Physical model: Black Pro-Mist glass filter. Additive chromatic scatter (R>G>B, film physics).
Scene-adaptive strength from PercTex IQR. No user knobs.

**Final implementation**: single pass, reads `CreativeLowFreqTex` (1/8-res, free from corrective) as scatter source.
- `diffused = CreativeLowFreqSamp(uv)` — broad low-frequency glow
- `adapt_str = 0.36 * lerp(0.7, 1.3, saturate(iqr / 0.5))` — IQR-adaptive
- Gate onset from p75: `smoothstep(p75-0.12, p75+0.06, luma_in)`
- Additive: `base + max(0, diffused-base) * float3(1.15, 1.00, 0.75) * adapt_str * gate`
- Clarity component: `base - diffused` × bell × adapt_str × 1.10
- Label: 7PMS magenta at y=58

**Crash history**: two-pass Gaussian version crashed Arc Raiders intermittently.
Root cause: UE5/Lumen saturates GPU frame budget; extra passes pushed heavy scenes over
VK_ERROR_DEVICE_LOST threshold. Single-pass fix eliminates DiffuseTex and DiffuseHPS.
If effect is too subtle, increase `adapt_str` base (0.36) — not a knob.

### Bug fixes (stability audit)
1. **`corrective.fx` kHalton** — `static const float2 kHalton[256]` replaced with
   `Halton2(uint)` / `Halton3(uint)` procedural functions ([unroll] fixed-bound loops).
   Static const arrays are SPIR-V-unsafe (wrong output silently). Chroma stats now correct.

2. **`analysis_scope_pre.fx` SCOPE_S** — 16→8 (matches analysis_scope.fx).
   `float samples[256]` → `float samples[64]`. Halved sample count, fixed inconsistency.

3. **`analysis_scope.fx` SCOPE_S** — 16→8 (previous session change, now consistent).

### GPU budget policy (new constraint)
UE5/Lumen fills the frame budget before vkBasalt runs. Every new pass must justify its cost.
Guidelines: prefer small intermediate textures, minimize taps, reuse existing textures
(CreativeLowFreqTex, PercTex, ZoneHistoryTex), reduce sample grids where accuracy allows.
Documented in memory: `feedback_gpu_budget.md`.

---

## What's defined but not in effects chain

Available in `arc_raiders.conf` but inactive:
- `veil` — atmospheric depth haze
- `retinal_vignette` — natural optical vignetting

Not yet built:
- Film grain — highest perceptual impact on filmic feel
- Halation — film emulsion scatter (different from pro_mist, localized to brightest highlights)
- Chromatic aberration

---

## Research queue

**R11 pending:** Stevens + Hunt — researched but not coded. Low ROI currently.

**Nightly jobs (4AM):**
- `research/jobs/job_system_stability.md` — stability audit, unsafe math, register pressure
- `research/jobs/job_automation_research.md` — scene-adaptive formula derivation

**Research files this session:**
- `research/R23N_2026-04-29_pro_mist.md` — pro_mist literature, ProMist-5K paper

---

## Key SPIR-V constraints

- No `static const float[]`, `static const float2[]`, `static const float3` — wrong output
- No variable named `out`
- Row y=0 of BackBuffer is the data highway — every BB-writing pass must guard `if (pos.y < 1.0) return col`
- `[unroll]` on fixed-bound loops — safe and preferred
- No hard conditionals on pixel properties — use `saturate`/`smoothstep`/`step`
- `sincos`, `frac`, `cos`, `sin`, `log`, `exp`, `sqrt`, `pow` — all safe

---

## Active branch

`alpha` — last committed 2026-04-29 night.
