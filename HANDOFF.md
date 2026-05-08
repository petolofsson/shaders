# Handoff — 2026-05-08

## Current branch
`alpha` — active development.

---

## Pipeline state

| Stage | Finished | Novel | Notes |
|-------|----------|-------|-------|
| Stage 0 — Input | 97% | 86% | R117A uniform expansion; per-hue gamut ceilings |
| Stage 1 — Film Stock | 97% | 85% | CAT16 removed R127; FilmCurve body S revised R127B |
| Stage 2 — Tonal | 95% | 92% | Chroma lift pivot fixed R127; zone_std thresholds recalibrated R116 |
| Stage 3 — Chroma | 98% | 93% | — |
| Stage 3.5 — Halation | 97% | 90% | — |
| Output — Pro-Mist | 96% | 87% | Three-scale blur R117C |

---

## Active chain (current testbed)

```
analysis_frame : inverse_grade : analysis_scope_pre : corrective : grade : analysis_scope
```

grade is a **6-pass technique**: LFDownscale1 → LFDownscale2 → NeutralIllum → ColorTransform → MistDownsample → ProMist

---

## What shipped this session (latest first)

### R127B — FilmCurve body S-curve revised (`grade.fx`)

R126 formula `x*(1-x)*(1-2x)*0.12` lifted shadows (+9% at x≈0.2) and barely touched
highlights — net image flattening. Replaced with one-sided midrange-weighted S:
`max(0, (x*(1-x))²*(2x-1))*0.65`. Shadows (x≤0.5) untouched. Upper mids lift peaks
+1.2% at x≈0.72, falls to zero at x=1. Effect concentrated in upper midrange,
not deep shadows.

### R127 — CAT16 removed; chroma lift pivot fixed (`grade.fx`, `corrective.fx`)

**CAT16 removal:** Game content is display-referred (sRGB→D65). CAT16 was treating
artistic warm lighting (fire, lava, torchlight) as a calibration error and systematically
cooling it — causing "homeostasis" that fought against deliberate warm lighting design.
Removed the pixel correction entirely. `NeutralIllumTex` and `lms_illum_norm` kept to
feed R83 (chromatic floor) and R66 (ambient shadow tint). Highway slot 216 removed.

**Chroma lift pivot fix:** `MIN_WEIGHT = 1.0` was adding unconditional weight to every
pixel regardless of chroma C, pulling the per-band pivot toward zero. With pivot≈0,
`LiftChroma`'s `t = 1 − C/pivot` saturates to 0 for all colored pixels — chroma lift
was silently doing nothing. Fixed: weight = `HueBandWeight * smoothstep(0.03, 0.08, C)`.
Achromatic pixels contribute zero weight; pivot is now the actual mean chroma of colored
pixels. Chroma lift now works as designed.

### Highway extension (diagnostic)

Slots 203–205 (zone_key, zone_std, slow_key) written by corrective PassthroughPS.
Slots 214, 215, 217–219 written by grade. All write-only from the pipeline — capture.py
reads them for external diagnostics only.

---

## Known state

- **Chroma lift now actually works** — values tuned before R127 were calibrated against
  a broken (inert) lift. Recalibrate CHROMA_STR from scratch.
- **CAT16 gone** — warm lighting (fire, lava) is now uncompensated. This is correct.
  If a scene has a strong colour cast from engine fog/colour grading, use 3-way CC instead.
- **Shadow lift stacked** — SHADOW_LIFT_STRENGTH + R119 fixes + FilmCurve toe all lift
  shadows. If shadows feel too bright, dial SHADOW_LIFT_STRENGTH down first.
- No known compile errors or visual regressions.

Debug log: `/tmp/vkbasalt.log` — check first for SPIR-V issues.

---

## Next session candidates

- **Retune creative_values** — many knobs (CHROMA_STR, SHADOW_LIFT_STRENGTH, BLEACH_BYPASS)
  were calibrated against a broken chroma lift and active CAT16. Fresh calibration pass warranted.
- **Nightly job prompt updates** — scheduled jobs still reference stale pipeline state (CAT16,
  old highway slots).
- **GZW testbed** — conf was updated this session to full pipeline; needs first tuning pass.
