# Handoff — 2026-05-06

## Current branch
`alpha` — active development.

---

## Pipeline state

| Stage | Finished | Novel | Gap |
|-------|----------|-------|-----|
| Stage 0 — Input | 95% | 80% | — |
| Stage 1 — Corrective | 93% | 78% | — |
| Stage 2 — Tonal | 95% | 93% | shadow lift needs retuning post-fix |
| Stage 3 — Chroma | 97% | 93% | — |
| Stage 3.5 — Halation | 95% | 85% | DoG PSF now real — needs tuning |
| Output — Pro-Mist | 91% | 74% | bloom component absent |

---

## Active chain (current testbed)

```
analysis_frame : inverse_grade : inverse_grade_debug : analysis_scope_pre : corrective : grade : analysis_scope
```

grade is a **5-pass technique**: LFDownscale1 → LFDownscale2 → ColorTransform → MistDownsample → ProMist

---

## What shipped this session (latest first)

### R113 — vkBasalt cross-technique mip generation bug (grade.fx)

**The biggest bug found to date.** `CreativeLowFreqTex` mip1 and mip2 were zero
everywhere — vkBasalt only auto-generates mips for render targets written and read
within the same technique. This texture crosses the corrective→grade boundary.

Additionally, `tex2Dlod(BackBuffer, ...)` returns zero in vkBasalt regardless of LOD.
Only `tex2D(BackBuffer, ...)` works on the BackBuffer sampler.

**Effects that were silently broken:**
- LCA gradient (R107) — zero gradient → no edge-directional CA
- CAT16 chromatic adaptation — zero illuminant → identity passthrough
- Retinex multi-scale (R29) — illum_s0/s2 pinned at 0.001 floor
- Shadow lift — denominator 0.001² → 4–50× over-amplified
- R66 ambient shadow tint — zero illuminant → no tint
- Halation DoG ring (R105) — tex2Dlod(BackBuffer) → zero blur → zero ring

**Fix:** Two explicit downscale passes at the top of OlofssonianColorGrade:
- `LFDownscale1PS`: reads CreativeLowFreqSamp mip0 → writes `LowFreqMip1Tex` (1/16-res)
- `LFDownscale2PS`: reads LowFreqMip1Samp → writes `LowFreqMip2Tex` (1/32-res)

ColorTransformPS now reads real multi-scale data. True multi-scale Retinex restored.
Halation switched to proper DoG PSF: `max(0, LowFreqMip2 − LowFreqMip1)`.

Documented fully in `research/R113_2026-05-06_vkbasalt_mip_generation.md`.

### Halation — full debugging and restoration

Halation was silently producing zero output. Three separate issues found and fixed:
1. `tex2Dlod(BackBuffer, ...)` → zero (switched to `tex2D`)
2. Pre-grade vs post-grade comparison mismatch (was comparing mip data against `lin`)
3. DoG ring: mip1/mip2 of CreativeLowFreqTex zero (root cause = R113 above)

Final implementation (R105): `hal_ring = max(0, LowFreqMip2 − LowFreqMip1)` — annular
PSF, peaks adjacent to highlights, zero at source center. R91 (+12% red from outer blur)
and R111 (G Lorentzian attenuation) preserved.

### R101 F2 — H-K exponent scene-adaptation (grade.fx)

Found unimplemented: grade.fx had `sqrt(final_C)` (exponent 0.5) instead of the
adaptive `pow(final_C, lerp(0.52, 0.64, zone_log_key/0.50))` from the R101 research doc.
Fixed to match spec. 2-line change.

---

## Current creative_values.fx (Arc Raiders)

| Knob | Value | Note |
|------|-------|------|
| EXPOSURE | 0.85 | May need slight adjustment post-fix |
| FILM_FLOOR | 0.01 | — |
| FILM_CEILING | 0.95 | — |
| SHADOW_TEMP / MID_TEMP / HIGHLIGHT_TEMP | -5 / +3 / +6 | — |
| ZONE_STRENGTH | 1.25 | — |
| SHADOW_LIFT_STRENGTH | 1.30 | **Needs retuning** — was calibrated against 4–50× over-amplified lift |
| CURVE_R_KNEE / B_KNEE | -0.0102 / 0.0000 | — |
| CURVE_R_TOE / B_TOE | +0.0100 / -0.0218 | — |
| PRINT_STOCK | 0.45 | — |
| COUPLER_STRENGTH | 0.25 | — |
| HAL_STRENGTH | 0.50 | DoG PSF now real — tune to taste |
| HAL_GAMMA | 0.40 | — |
| CHROMA_STR | 0.60 | — |
| ROT_RED/YELLOW/GREEN/CYAN/BLUE/MAG | +0.03/-0.015/-0.02/+0.015/-0.03/0.00 | — |
| MIST_STRENGTH | 2.5 | Confirmed working |
| VEIL_STRENGTH | 0.0 | Off |
| PURKINJE_STRENGTH | 1.15 | — |
| LCA_STRENGTH | 1.0 | Now actually works — may want to reduce to 0.5 |
| INVERSE_STRENGTH | 0.40 | — |
| VIEWING_SURROUND | 1.123 | — |

---

## Known state

- `inverse_grade_debug.fx` in chain — remove once tuning is stable.
- **SHADOW_LIFT_STRENGTH needs retuning** — the fix made shadow lift dramatically weaker
  (was 4–50× over-amplified). Current value 1.30 may feel too dark. Start higher if needed.
- **LCA_STRENGTH = 1.0** — LCA was silently off before; 1.0 full physiological may be strong.
  Try 0.5 if edges look over-fringed.
- CAT16 chromatic adaptation now active for real — scene-illuminant colour shifts are live.
- Pro-Mist confirmed working (within-technique mip auto-generation verified).
- No known compile errors or visual regressions.

Debug log: `/tmp/vkbasalt.log` — check first for SPIR-V issues.

---

## Next session candidates

- **SHADOW_LIFT_STRENGTH retuning** — calibrate from scratch now that denominator is correct
- **Pro-Mist highlight bloom** — old version had bloom (lens scatter from highlights). Add
  highlight extraction + additive scatter using `LowFreqMip2Tex` (already available, zero cost)
- **Nightly job prompt updates** — all 4 scheduled jobs reference stale chain/candidates
