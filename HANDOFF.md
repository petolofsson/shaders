# Handoff — 2026-05-04

## Current branch
`alpha` — active development.

---

## Pipeline state

| Stage | Finished | Novel | Gap |
|-------|----------|-------|-----|
| Stage 0 — Input | 95% | 80% | — |
| Stage 1 — Corrective | 93% | 78% | — |
| Stage 2 — Tonal | 93% | 92% | — |
| Stage 3 — Chroma | 97% | 93% | — |
| Stage 3.5 — Halation | 90% | 78% | — |
| Output — Pro-Mist | 91% | 74% | **1% below 75% target** |

**Next session goal:** Push Output/Pro-Mist novelty from 74% → 76%+.

Two concrete targets:
- **R91** — Mie-correct per-channel scatter radius: blue channel uses mip 0 (tighter, shorter λ scatters more in polymer), red uses mip 1 (wider, longer λ penetrates deeper). 3 ALU, no new taps. Spectral-physically motivated — no other real-time mist does this.
- **R92** — Apply IGN blue-noise dither to pro_mist.fx (currently still uses `sin(dot)*43758` white noise from before R89). One-line fix, consistency with grade.fx.

Combined expected: Output novelty 74% → 76–77%.

---

## Active chain (Arc Raiders)

```
analysis_frame : inverse_grade : inverse_grade_debug : analysis_scope_pre : corrective : grade : pro_mist : analysis_scope
```

---

## What shipped this session (latest first)

### Tuning pass — filmic curve + creamy whites (creative_values.fx, both games)
Arc Raiders: `CURVE_B_KNEE` zeroed (removes blue-retention bias from shoulder),
`CURVE_R_TOE +0.010` (Vision3 warm toe), `HIGHLIGHT_TEMP +6` (creamy whites),
`ROT_YELLOW -0.015` / `ROT_CYAN +0.015` (deeper warm/cold palette separation).
GZW: full reset to Arc Raiders baseline; `SHADOW_LIFT_STRENGTH` + `HUNT_LOCALITY`
added (were missing — compile error). `gzw.conf` updated: `inverse_grade` +
`inverse_grade_debug` + `retinal_vignette` added to effects chain.

### R61 — Per-pixel Hunt adaptation (grade.fx)
CAM16 local-field Hunt effect. `hunt_la = lerp(zone_log_key, lab.x, HUNT_LOCALITY)`.
Highlights get stronger chroma boost, shadows get less. `HUNT_LOCALITY 0.35` knob added.

### F1–F3 — Film sensitometry + Stevens (grade.fx)
- **F1** Print stock `desat_w` bounds now track `fc_knee_toe`/`fc_knee` — scene-adaptive desaturation window
- **F2** +6% midtone chroma bell at L≈0.47 in R22 — cinema SDR mastering data (Žaganeli et al. 2026)
- **F3** Stevens exponent sqrt→cbrt in `fc_stevens`, denominator 2.03→2.04 — psychophysically correct

### R90 — Adaptive inverse tone mapping

- **R90** — `general/inverse-grade/inverse_grade.fx` — game-agnostic adaptive inverse tone mapping
  - Oklab chroma-only expansion: luma unchanged, brightness neutral
  - `mid_weight = L*(1-L)*4` protects black/white
  - `c_weight = saturate((C-0.10)/0.15)` protects near-neutrals/warm whites
  - Slope from highway x=197 (Kalman-smoothed, computed in analysis_frame from float16 PercTex)
  - `INVERSE_STRENGTH 0.50` in `creative_values.fx`
- **R86 retired** — `inverse_grade_aces.fx`, `aces_debug.fx` moved to `unused/`
- **Oklab bug fixed** — wrong b-row in inverse_grade.fx caused systematic yellow cast.
  Correct b-row: `[0.0259040371, 0.7827717662, -0.8086757660]` (matches grade.fx)

---

## Current creative_values.fx (Arc Raiders)

| Knob | Value |
|------|-------|
| EXPOSURE | 0.92 |
| FILM_FLOOR | 0.005 |
| FILM_CEILING | 0.95 |
| SHADOW_TEMP / MID_TEMP / HIGHLIGHT_TEMP | -5 / +3 / +6 |
| ZONE_STRENGTH | 1.2 |
| SHADOW_LIFT_STRENGTH | 1.3 |
| CURVE_R_KNEE / B_KNEE | -0.0102 / 0.0000 |
| CURVE_R_TOE / B_TOE | +0.0100 / -0.0218 |
| PRINT_STOCK | 0.40 |
| HAL_STRENGTH | 0.30 |
| ROT_RED / YELLOW / GREEN / CYAN / BLUE | +0.03 / -0.015 / -0.02 / +0.015 / -0.03 |
| VEIL_STRENGTH | 0.00 |
| MIST_STRENGTH | 0.25 |
| PURKINJE_STRENGTH | 1.3 |
| VIEWING_SURROUND | 1.123 |
| LCA_STRENGTH | 0.2 |
| HUNT_LOCALITY | 0.35 |
| INVERSE_STRENGTH | 0.50 |

GZW `creative_values.fx` is now identical to Arc Raiders (reset this session).
GZW `gzw.conf` chain: `analysis_frame : inverse_grade : inverse_grade_debug : analysis_scope_pre : corrective : grade : pro_mist : retinal_vignette : analysis_scope`

---

## Known state

- HAL re-enabled at 0.30 (was zeroed last session to isolate inverse grade). VEIL stays 0 — Arc Raiders has volumetrics.
- `inverse_grade_debug.fx` in both chains — remove once tuning is stable.
- Register pressure verified via RADV shader dump: 59 VGPRs / 87 SGPRs, no spilling.
- `pro_mist.fx` line 125: still uses old `sin(dot)*43758` white-noise dither — R89 IGN not yet applied here (target for R92 next session).
- No known compile errors or visual regressions.

Debug log: `/tmp/vkbasalt.log` — check first for SPIR-V issues.
