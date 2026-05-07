# Job — Shader Research Nightly

**Schedule:** 0 1 * * * (1 AM UTC)
**Output:** `research/R{next}_{YYYY-MM-DD}_{slug}.md`

## Summary

Domain-rotation literature search. Finds novel findings from adjacent fields and
filters them for architectural viability. Writes a dated findings file to the repo.
Use native WebSearch for all searches — no Brave MCP.

## Domain rotation (date +%u)
1 Mon — Tone mapping & film sensitometry
2 Tue — Perceptual chroma (HK, Hunt, Abney)
3 Wed — Temporal filtering & state estimation
4 Thu — Zone/histogram analysis
5 Fri — Film stock spectral emulation
6 Sat — Color appearance models
7 Sun — Wild card (adjacent domain of model's choice)

## Key exclusions (permanent, no exceptions)
- Clarity / sharpening / local contrast / CLARITY_STRENGTH
- Film grain
- Lateral chromatic aberration (LCA) — removed permanently; no way to exclude UI text
- Longitudinal chromatic aberration — same problem
- Any HDR-only technique
- Viewing surround / CIECAM02 surround compensation — removed; not pipeline's responsibility
- OPT-2/3 (zone_log_key guard removal, saturate(lin) removal) — cold-start regression
  confirmed; do not re-propose without explicit cold-start frame proof

## Already implemented — do not re-propose

**Tuesday/chroma domain:**
- **R101 F1 / R125 — Bezold-Brücke** (2026-05-05 / 2026-05-07): Anchor fixed to Oklab invariant hues
  (h=0.25 unique yellow, h=0.75 unique blue). Two-harmonic `(ch_h + 0.9*sh2_h)` via double-angle.
  Teal direction bug corrected. Amplitude 0.006 → 0.015.
- **R101 F2 — H-K exponent scene-adaptation** (2026-05-05): `lerp(0.52, 0.64, saturate(zone_log_key / 0.50))`. Nayatani 1997 + CIECAM02 F_L backed.
- **R101 F3 — Abney C_stim** (2026-05-05): Burns et al. 1984; coefficients scale by pre-lift stimulus chroma.

**Tone mapping / film domain:**
- **R83 — Chromatic FILM_FLOOR** (2026-05-03): Per-channel D-min pedestal modulated by CAT16 illum.
- **R84 — Log-density FilmCurve** (2026-05-03): CURVE_* knobs as log₂-density offsets.
- **R85 — Inter-channel dye masking** (2026-05-03): Cyan→green 2.0%, magenta→blue 2.2%.
- **R90 — Adaptive inverse tone mapping** (2026-05-04): IQR-based Oklab chroma expansion, Kalman-smoothed slope.
- **F1–F3 — Film sensitometry + Stevens** (2026-05-04): desat_w bounds, midtone chroma bell, cbrt fc_stevens.

**Halation (Stage 3.5):**
- **R105 — Halation DoG PSF** (2026-05-05): Annular ring via max(mip1 − mip2, 0).
- **R106 — Lorentzian tail** (2026-05-05): γ²/(γ²+d²+ε). HAL_GAMMA knob.
- **R114 — Chromatic fringe** (2026-05-06): hal_b component; gains float3(1.05, 0.45, 0.03). hal_b = hal_ring.b * lerp(0.22, 0.38, hal_lore). White → orange/amber fringe.

**Pro-Mist (Output):**
- **R115 — Additive shimmer model** (2026-05-06): `base + max(0, blurred − base) * strength`. Highlights only.
- **R117C — Three-scale blur** (2026-05-07): MistDiffuseTex MipLevels=3; mist_broader at LOD 2; broad_w ramps above MIST_STRENGTH ~0.5.

**Pipeline audit:**
- **R116 — 9-issue color pipeline audit** (2026-05-06): chroma median CDF p50, linear zone_log_key, intra-zone pixel variance, pure global p25/p75, adaptive CAT16 blend, ceiling before vibrance, HWY_SLOPE min clamp.
- **R117 — Uniform chroma expansion** (2026-05-07): Directional bias removed from inverse_grade — multi-hue scenes were under-expanding off-axis colours.

## Pipeline state as of 2026-05-07

**Chain:** `analysis_frame : inverse_grade : analysis_scope_pre : corrective : grade : analysis_scope`

`grade` is a 5-pass technique: LFDownscale1 → LFDownscale2 → ColorTransform → MistDownsample → ProMist.
Pro-Mist is merged inside grade.fx — not a separate effect.

**Active knobs:** INVERSE_STRENGTH, EXPOSURE, FILM_FLOOR, FILM_CEILING, PRINT_STOCK,
CURVE_R/B_KNEE/TOE, ZONE_STRENGTH, SHADOW_LIFT_STRENGTH, SHADOW_TEMP/MID_TEMP/HIGHLIGHT_TEMP,
COUPLER_STRENGTH, CHROMA_STR, ROT_* (6 values), HAL_STRENGTH, HAL_GAMMA, MIST_STRENGTH, PURKINJE_STRENGTH

**Highway slots:** 0–128 luma hist · 130–193 hue hist · 194–196 p25/p50/p75 · 197 R90 slope ·
198 median Oklab C · 199 scene cut · 200 p90 · 201 chroma angle · 202 achromatic fraction ·
210 warm bias · 211 zone key (linear mean) · 212 zone std (intra-zone pixel variance) · 213 fc_stevens (÷1.3 / ×1.3)

## Last updated
2026-05-07 — Updated chain, knobs, highway slots. Added R114–R117 to implemented list.
Removed LCA, VIEWING_SURROUND, VEIL_STRENGTH. Switched to native WebSearch.
