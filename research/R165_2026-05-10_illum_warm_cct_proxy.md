# R165 — Illuminant Warmth Highway Slot (CCT Proxy)

**Date:** 2026-05-10
**Scope:** highway.fxh (slot 220), grade.fx ColorTransformPS (write),
           inverse_grade.fx InverseGradePS (read)

---

## Motivation

NeutralIllumTex contains the scene's neutral-pixel-weighted illuminant estimate in
linear RGB. Inside grade.fx, BuildSceneCtx converts this to CAT16 LMS and uses it
for the chromatic floor (R83). But NeutralIllumTex is a grade-internal texture —
no earlier stage (inverse_grade, corrective) can access it.

The HueSlopeBias in inverse_grade (R156) encodes ACES/filmic warm-hue compression
excess: reds/oranges get more expansion because ACES compresses them more than cool
hues. This calibration assumes the scene content is neutrally lit. In a warm-illuminant
scene (sunset, firelight, tungsten interior), warm-hue saturation is partly the
illuminant itself — not a tonemapper artifact. Expanding it further over-saturates
the warm channel.

## Signal

`HWY_ILLUM_WARM` (slot 220) — illuminant warmth scalar derived from NeutralIllumTex
via the CAT16 M_fwd transform.

```
warmth = saturate(lms_norm.r − lms_norm.b + 0.5)
```

Where lms_norm is the LMS illuminant estimate normalised by M (green channel):

| Scene | lms_norm.r | lms_norm.b | warmth |
|-------|------------|------------|--------|
| Very cool (blue sky) | ~0.91 | ~1.36 | ~0.06 |
| D65 neutral | ~0.96 | ~1.07 | ~0.39 |
| Moderate warm (indoor) | ~1.01 | ~0.85 | ~0.66 |
| Very warm (sunset/tungsten) | ~1.10 | ~0.65 | ~0.95 |

Raw [0,1] — no encode/decode needed. Fits 8-bit UNORM directly.

## Write — ColorTransformPS highway block (grade.fx)

Written at `xi == HWY_ILLUM_WARM` in the `pos.y < 1.0` highway block of
ColorTransformPS. NeutralIllumTex is populated by the NeutralIllum pass which
runs before ColorTransform within the same technique — texture is valid.

Re-declares M_fwd as a local const (not static const — SPIR-V restriction).

## Read — InverseGradePS (inverse_grade.fx)

**One-frame delay**: ColorTransformPS (grade) runs after inverse_grade in the chain.
Slot 220 is previous frame's illuminant. Acceptable — scene illuminant changes slowly
and the NeutralIllumTex estimate is itself an EMA-smoothed signal.

Frame 0 default: slot 220 reads 0.0 → warm_scene = 0 → bias_adj = bias (unchanged)
→ R156 behaviour exactly as before. Safe initialisation.

```hlsl
float illum_warm = ReadHWY(HWY_ILLUM_WARM);
float warm_scene = saturate((illum_warm - 0.45) / 0.35);  // 0 at D65, 1 at very warm
float bias       = HueSlopeBias(hue);
// Positive bias (warm hues) reduced in warm scenes — illuminant, not tonemapper artifact.
// Negative bias (cool hues) unchanged — always less compressed regardless of illuminant.
float bias_adj   = max(bias, 0.0) * (1.0 - warm_scene * 0.50) + min(bias, 0.0);
float slope_eff  = clamp(slope * (1.0 + bias_adj), 1.0, 2.2);
```

Max reduction: 50% of positive bias at very warm illuminant (illum_warm > 0.80).
At D65 (illum_warm ≈ 0.39, below 0.45 threshold): no reduction — existing R156
calibration fully preserved for neutral content.

## No new knobs

Effect is fully automatic. INVERSE_STRENGTH scales the entire expansion chain.
