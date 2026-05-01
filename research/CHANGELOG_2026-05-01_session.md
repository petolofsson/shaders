# Session Changelog — 2026-05-01

## Commits this session

| Hash | Summary |
|------|---------|
| `ed16dce` | implement R48–R50; remove clarity; fix Retinex bloom via LOD 1 illuminant |
| `28831ab` | tune: EXPOSURE 1.10, SHADOW_LIFT 1.7, deeper shadow bell curve |

---

## What changed

### R48 — Luminance-adapted zone contrast (`grade.fx`)
`zone_log_key` (geometric mean of zone medians) now drives a `lum_att` factor that scales
zone S-curve strength: bright scenes get less contrast (~0.93×), dark scenes get more
(~1.10×). Matches Stevens effect. `ZONE_STRENGTH` knob added to `creative_values.fx`.

### R49 — Per-channel FilmCurve gamma (`grade.fx` FilmCurve)
H&D sensitometry: red dye layer has lowest γ, blue highest. Encoded as float3 weights:
- `shoulder_w = float3(0.91, 1.00, 1.06)` — red compresses less, blue more
- `toe_w      = float3(0.95, 1.00, 1.04)` — red toe lifts less, blue more
Net: warm shadows, neutral-to-cool highlights. < 0.3% channel separation at midtone.

### R50 — Dye secondary absorption (`grade.fx`, after FilmCurve, before R19)
Dominant-channel soft attenuation on saturated pixels. Neutral-preserving by construction
(`sat_proxy = max - min = 0` → no effect). Coupling constant 0.06, ramp via
`smoothstep(0.0, 0.25, sat_proxy)`. Max attenuation on fully-saturated primary: ~5%.

### Clarity — removed
Wavelet clarity (R30/R43/R44) caused bloom via 1/8-res illuminant bleed: dark pixels
adjacent to bright objects had elevated `illum_s0`, producing large negative D1 →
clarity subtracted from those pixels → dark halos → perceived as bloom. Effect is
redundant with driver-level (NVIDIA/AMD) and in-game sharpening. Removed entirely.
`CLARITY_STRENGTH` knob removed from `creative_values.fx`.

### Retinex — single-scale LOD 1 (`grade.fx`)
Dropped from multi-scale to single-scale. LOD 0 (1/8-res) caused edge bleed at 8-pixel
block boundaries. LOD 1 (1/16-res, hardware mipmap) gives a smoother illuminant —
eliminates block-boundary halos without losing the spatial contrast normalisation.
Formula: `log_R = log2(new_luma / illum_s0); new_luma = lerp(new_luma, exp2(log_R + log2(zone_log_key)), 0.75 * smoothstep(0.04, 0.25, zone_std))`

### Shadow lift — bell curve tightened (`grade.fx`)
`lift_w = new_luma * smoothstep(0.30, 0.0, new_luma)` — peak shifted from luma ≈ 0.20
to ≈ 0.15. Lifts deeper into shadows, less effect on midtones.

### Other fixes
- **CORRUPT fix** (`analysis_frame.fx`): `saturate()` added to EMA coefficient in both
  histogram smooth passes — prevents runaway gain on high frametime spikes.
- **OPT-1**: Single `hist_cache[6]` loop replaces two separate ChromaHistory passes.
- **OPT-3/4/5**: Hunt FL fold (k², k⁴, one_mk4), RGBtoOklab sign/abs removed.
- **Knobs added**: `ZONE_STRENGTH`, `CHROMA_STRENGTH`, `MIST_STRENGTH`, `SHADOW_LIFT`
  all wired through `creative_values.fx`. Per-pixel shadow lift with `illum_s0` darkness
  driver and `zone_iqr` contrast gate (suppresses lift in already-contrasty zones).

---

## Current creative_values.fx

```
EXPOSURE        1.10
ZONE_STRENGTH   1.0
CHROMA_STRENGTH 0.9
MIST_STRENGTH   0.40   (pro_mist not in active chain)
SHADOW_LIFT     1.7
```
All 3-way corrector, hue rotation, vignette, film curve offsets at passthrough/default.

---

## Active chain

```
analysis_frame : analysis_scope_pre : corrective : grade : analysis_scope
```
pro_mist excluded from chain.

---

## Open items for next session

- **R50 validation**: skin tones and foliage. If oranges read too saturated, lower `0.06`
  coupling constant in R50 block.
- **Retinex strength**: currently `0.75 * smoothstep(0.04, 0.25, zone_std)`. Can be
  reduced if spatial contrast normalisation reads too aggressive in certain scenes.
- **SHADOW_LIFT upper bound**: currently self-limiting via `exp(-5.776 * illum_s0)` and
  `zone_iqr` gate. Watch for crushing in very dark, low-contrast scenes.
- **Nightly jobs**: next run 2026-05-02 at 1–4 AM UTC. New research files will be R51+.
