# Handoff — 2026-05-06

## Current branch
`alpha` — active development.

---

## Pipeline state

| Stage | Finished | Novel | Gap |
|-------|----------|-------|-----|
| Stage 0 — Input | 97% | 84% | — |
| Stage 1 — Corrective | 96% | 83% | — |
| Stage 2 — Tonal | 94% | 92% | zone_std/zone_key character change; may need ZONE_STRENGTH retune |
| Stage 3 — Chroma | 98% | 93% | — |
| Stage 3.5 — Halation | 97% | 90% | Chromatic fringe tuned; HAL_STRENGTH/HAL_GAMMA at new calibration |
| Output — Pro-Mist | 95% | 86% | Shimmer model tuned; MIST_STRENGTH at new calibration |

---

## Active chain (current testbed)

```
analysis_frame : inverse_grade : analysis_scope_pre : corrective : grade : analysis_scope
```

grade is a **5-pass technique**: LFDownscale1 → LFDownscale2 → ColorTransform → MistDownsample → ProMist

---

## What shipped this session (latest first)

### R116 — Full color pipeline audit (9 issues)

Seven statistical/logic improvements across `grade.fx`, `corrective.fx`, `analysis_frame.fx`, and
`inverse_grade.fx`. Research papers: `research/R116_2026-05-06_color_pipeline_audit.md` and
`research/R116_2026-05-06_color_pipeline_audit_findings.md`.

**Issue 3 — Intra-zone pixel variance** (`corrective.fx`)
`zone_std` now measures mean intra-zone pixel variance using histogram moments (E[X²] − E[X]²)
per zone, averaged across 16 zones. Previously measured inter-zone std-dev (spread between zone
medians) — which responded to the zone structure, not to per-pixel texture. `ZoneHistoryTex.a`
repurposed from Kalman P (unused downstream) to smoothed `intra_std`. R88 VFF Kalman Q adaptation
removed from `SmoothZoneLevelsPS`; replaced with fixed-K EMA, scene-cut reset via HWY_SCENE_CUT.

**Issue 2 — Zone log key linear mean** (`corrective.fx`)
`zone_log_key` now uses linear mean of zone medians (`sum/16`) instead of geometric mean
(`exp2(sum(log2)/16)`). Linear mean gives equal weight to all zones. Geometric mean was
dark-biased — high-contrast (split interior/window) scenes read too dark. `ZONE_STRENGTH` may
need adjustment; calibrate from current default.

**Issue 4 — Pure global percentiles** (`grade.fx`)
`eff_p25`/`eff_p75` now use `perc.r`/`perc.b` directly (pure global histogram p25/p75).
Previously `lerp(global_p25, zone_zmin, 0.4)` blended a percentile with a spatial zone extreme
— incompatible statistics. FilmCurve now responds to the histogram only.

**Issue 1 — Chroma median** (`analysis_frame.fx`)
`MeanChromaPS` replaced with 32-bin CDF-walk p50 (same architecture as `CDFWalkPS`). Arithmetic
mean was biased by outlier pixels (neons, bright primaries) → over-expansion in shadows.
Highway x=198 now carries median Oklab C. `INVERSE_STRENGTH` raised from 0.40 → 0.55
(median is lower than mean → more headroom before saturation).

**Issue 5C — Adaptive CAT16 blend** (`grade.fx`)
`illum_dev = length(lms_illum_norm − 1)` drives CAT16 blend: 0.80 when illuminant is near-neutral
(reliable estimate, correct aggressively), 0.60 when strongly tinted (suspect estimate, keep
safety valve). 3–5 ALU, zero new taps.

**Issue 8 — Chroma ceiling before vibrance** (`grade.fx`)
Ceiling applied to `lifted_C` before vibrance masking (not after). The ceiling is now a hard
guarantee on the chroma that enters vibrance. Vibrance masks within the ceiling-bounded range.

**Issue 9 — HWY_SLOPE minimum clamp** (`inverse_grade.fx`)
`max(slope_enc * 1.5 + 1.0, 1.15)` enforces minimum slope 1.15 at decode. Cold-start frame
uninit (0) previously decoded as slope=1.0 (below the valid floor), causing one-frame identity
behaviour. Eliminated.

---

### R115 — Pro-Mist shimmer model (grade.fx)

`ProMistPS` changed from symmetric lerp diffusion to additive unilateral bloom:
```hlsl
float3 bloom  = max(0.0, blurred - base.rgb);
float3 result = base.rgb + bloom * adapt_str;
```
Previous lerp model muted dark areas alongside brightening highlights — physically incorrect for
scatter optics. New model only adds scatter from highlights; shadows/midtones are unaffected.
`MIST_STRENGTH` recalibrated from 5.0 → 1.5.

---

### R114 — Halation chromatic fringe (grade.fx)

Added `hal_b` component with Lorentzian attenuation (`hal_ring.b * lerp(0.38, 0.22, hal_lore)`).
Gains changed from `float3(1.05, 0.50, 0.0)` to `float3(1.05, 0.30, 0.03)`. White surfaces now
produce correct orange/amber fringe. Red dominance preserved (deepest dye layer; yellow filter
layer attenuates blue but passes red/orange). `HAL_STRENGTH` 0.50 → 2.0, `HAL_GAMMA` 0.40 → 2.50.

---

### R113 — vkBasalt cross-technique mip generation bug (grade.fx)

**The biggest bug found to date.** `CreativeLowFreqTex` mip1 and mip2 were zero
everywhere — vkBasalt only auto-generates mips for render targets written and read
within the same technique. This texture crosses the corrective→grade boundary.

Additionally, `tex2Dlod(BackBuffer, ...)` returns zero in vkBasalt regardless of LOD.
Only `tex2D(BackBuffer, ...)` works on the BackBuffer sampler.

**Fix:** Two explicit downscale passes at the top of OlofssonianColorGrade:
- `LFDownscale1PS`: reads CreativeLowFreqSamp mip0 → writes `LowFreqMip1Tex` (1/16-res)
- `LFDownscale2PS`: reads LowFreqMip1Samp → writes `LowFreqMip2Tex` (1/32-res)

Documented fully in `research/R113_2026-05-06_vkbasalt_mip_generation.md`.

---

## Current creative_values.fx (Arc Raiders)

| Knob | Value | Note |
|------|-------|------|
| INVERSE_STRENGTH | 0.55 | Raised after chroma median (median < mean → more headroom) |
| EXPOSURE | 0.95 | — |
| FILM_FLOOR | 0.01 | — |
| FILM_CEILING | 0.95 | — |
| SHADOW_TEMP / MID_TEMP / HIGHLIGHT_TEMP | -5 / +3 / +6 | — |
| ZONE_STRENGTH | 1.25 | May need retune after linear zone_log_key change |
| SHADOW_LIFT_STRENGTH | 1.30 | — |
| CURVE_R_KNEE / B_KNEE | -0.0102 / 0.0000 | — |
| CURVE_R_TOE / B_TOE | +0.0100 / -0.0218 | — |
| PRINT_STOCK | 0.45 | — |
| COUPLER_STRENGTH | 0.20 | — |
| HAL_STRENGTH | 2.0 | Recalibrated after R114 chromatic fringe |
| HAL_GAMMA | 2.50 | Wider Lorentzian tail for broad diffuse scatter |
| CHROMA_STR | 0.60 | — |
| ROT_RED/YELLOW/GREEN/CYAN/BLUE/MAG | +0.03/-0.015/-0.02/+0.015/-0.03/0.00 | — |
| MIST_STRENGTH | 1.5 | Recalibrated after R115 additive shimmer model |
| PURKINJE_STRENGTH | 1.2 | — |

---

## Known state

- **ZONE_STRENGTH may need retuning** — linear zone_log_key raises key in high-contrast scenes
  → zone contrast may fire less aggressively. Current 1.25 is a reasonable starting point.
- **INVERSE_STRENGTH at 0.55** — calibrated against median chroma (lower than arithmetic mean).
  If colours feel under-expanded, try 0.65–0.70.
- CAT16 adaptive blend live — neutral scenes get stronger correction (0.80), tinted scenes
  more conservative (0.60).
- Pro-Mist shimmer: only adds light from highlights. If diffusion (all-tone softening) is
  wanted, revert to lerp model. Current character is shimmer/glow, not diffusion.
- No known compile errors or visual regressions.

Debug log: `/tmp/vkbasalt.log` — check first for SPIR-V issues.

---

## Next session candidates

- **ZONE_STRENGTH retune** — calibrate from scratch after linear zone_log_key change
- **INVERSE_STRENGTH fine-tune** — 0.55 is conservative; test 0.60–0.70 in varied scenes
- **Nightly job prompt updates** — all 4 scheduled jobs reference stale chain state
- **Remove inverse_grade_debug from chain** — once halation + inverse grade tuning is stable
