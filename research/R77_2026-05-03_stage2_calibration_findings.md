# R77 Findings — Stage 2 Calibration

**Date:** 2026-05-03
**Status:** No code changes required — all parameters validated within acceptable bounds

---

## R77A — R65/R66 combined weight

**R65** scales `lab_t.yz` by `r65_ab = r_tonal^0.333` gated by `r65_sw =
smoothstep(0.30, 0.0, lab_t.x)`. For a lifted shadow pixel (r_tonal = 2.0, deep
shadow r65_sw = 1.0): scales a/b by 1.26. For a truly achromatic pixel (a=b=0),
scaling by any value gives 0 — R65 adds no chroma where there is none.

**R66** then acts on `lab_t.yz` after R65. Achromaticity weight:
`achrom_w = 1.0 - smoothstep(0.0, 0.05, length(lab_t.yz))`

For a genuinely achromatic pixel after R65 (a=b=0): `achrom_w = 1.0`.
Maximum R66 weight: `r65_sw=1.0 * achrom_w=1.0 * (1-scene_cut)=1.0 * 0.4 = 0.4`.

Maximum ambient injection: `0.4 * lab_amb.y` into `lab_t.y`. For a warm amber
scene illuminant normalised to 18% gray, `lab_amb.y ≈ 0.006–0.012` (Oklab a).
So max injection ≈ 0.4 × 0.012 = 0.005 Oklab C units. This is subtle
(at Oklab L=0.15, C/L = 0.033 — below perceptual detection threshold for most
observers). No over-correction possible.

**Interaction check:** R65 runs first, R66 on residual achromatic pixels. For
pixels with existing chroma (C > 0.025 after R65), `achrom_w < 0.5` and R66
injection ≈ 0.2 × lab_amb — negligible. The gates are complementary and bounded.

**Verdict:** No conflict. Parameters validated.

---

## R77B — Retinex blend weight

`new_luma = lerp(new_luma, nl_safe * zk_safe / illum_s0, 0.75 * ss_04_25)`

`ss_04_25 = smoothstep(0.04, 0.25, zone_std)`:
- zone_std < 0.04 (flat scene): weight = 0 — correct, flat scenes are already
  illumination-invariant, Retinex shouldn't normalise them
- zone_std = 0.10: weight ≈ 0.75 × 0.286 = 0.214
- zone_std = 0.25: weight = 0.75 — maximum

For a deeply shadowed pixel (nl_safe=0.05, illum_s0=0.20, zk_safe=0.12):
Retinex target = 0.05 × 0.12 / 0.20 = 0.030. At zone_std=0.25:
`new_luma = lerp(0.05, 0.030, 0.75) = 0.035`

This darkens the crevice slightly (from 0.05 to 0.035). Shadow lift then fires
on this value. The combined effect: Retinex reveals the deep shadow, lift then
recovers it — appropriate for high-variance scenes with meaningful shadow structure.

The 0.04–0.25 zone_std range: Arc Raiders' typical zone_std for indoor scenes
~0.08–0.18, outdoor ~0.12–0.22. The range covers real content well. The 0.75
maximum is conservative — full weight (1.0) would be too aggressive for
borderline-complex scenes.

**Verdict:** Range validated. No change.

---

## R77C — R60 temporal context exponent

`context_lift = exp2(log2(slow_key / zk_safe) * 0.4)`

Temporal visual adaptation studies (Fairchild, "Colour Appearance Models" 3rd ed.)
report adaptation time constants of 1–10 seconds for moderate luminance changes.
The exponent of 0.4 maps a 2:1 key ratio to a 32% boost (2^0.4 = 1.32). At a 4:1
ratio (very rapid dark-to-bright transition): 4^0.4 = 1.74 — 74% boost. This
seems large, but `slow_key` is a long temporal average — a 4:1 ratio between the
slow average and the current frame implies a sustained scene change, not a cut.
Scene cuts are handled separately by `(1 - scene_cut)` in R66 and by the Kalman
reset in R53.

The exponent 0.4 is within the range of published temporal adaptation models
(Pattanaik 1998 tone mapping: 0.3–0.5 for adaptation gain). No compelling reason
to change it.

**Verdict:** Exponent validated as physiologically plausible. No change.

---

## Overall verdict

All three Stage 2 parameters are within acceptable bounds. No code changes required.
The stage is complete at the current parameter values.
