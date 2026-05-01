# R48 — Luminance-Adapted Zone Contrast

**Date:** 2026-05-01
**Status:** Implemented

---

## Problem

Zone contrast strength (`zone_str`) currently adapts only to spatial scene structure via `zone_std`
(standard deviation of zone medians). A flat scene gets more contrast; a contrasty scene gets less.
This is correct as far as it goes, but it ignores the Stevens effect: perceived contrast scales with
adaptation luminance. A dark scene and a bright scene with identical spatial structure should receive
different contrast treatment — the dark-adapted visual system is more sensitive to contrast
differences and needs less artificial enhancement; the bright-adapted system needs more.

The fix applied in this session to Stevens (FilmCurve) and Hunt (chroma lift) used `zone_log_key`
(geometric mean of zone medians, already in linear space) as the adaptation luminance anchor. The
same signal is available here.

---

## Signal

`zone_log_key` — already computed at line 228 of `ColorTransformPS`. Geometric mean of the 16
spatial zone medians: `exp(mean(log(zone_medians)))`. Correct for adaptation modelling because it
weights all scene regions equally in log space rather than by pixel count.

---

## Proposed implementation

```hlsl
float lum_att  = smoothstep(0.10, 0.40, zone_log_key);
float zone_str = lerp(0.30, 0.18, smoothstep(0.08, 0.25, zone_std))
               * lerp(1.15, 0.90, lum_att);
```

The `smoothstep(0.10, 0.40, zone_log_key)` ramp covers the practical SDR range:
- Below 0.10 (very dark scene): full bright-end multiplier (1.15) — dark adaptation, more sensitive
- Above 0.40 (bright scene): full dark-end multiplier (0.90) — bright adaptation, less enhancement needed
- Mid scenes blend continuously

Net `zone_str` range with both terms active:

| zone_std | zone_log_key | zone_str (old) | zone_str (new) |
|----------|-------------|----------------|----------------|
| 0.04 (flat) | 0.08 (dark) | 0.30 | 0.345 |
| 0.04 (flat) | 0.25 (mid) | 0.30 | 0.285 |
| 0.04 (flat) | 0.50 (bright) | 0.30 | 0.270 |
| 0.17 (contrasty) | 0.08 (dark) | 0.18 | 0.207 |
| 0.17 (contrasty) | 0.25 (mid) | 0.18 | 0.171 |
| 0.17 (contrasty) | 0.50 (bright) | 0.18 | 0.162 |

The spatial term (`zone_std`) remains primary. The luminance term adds ±15% modulation on top.

---

## Interaction with Retinex

The Retinex blend `lerp(new_luma, retinex_luma, smoothstep(0.04, 0.25, zone_std))` also engages on
high `zone_std` scenes — the same scenes where zone contrast backs off. Adding luminance adaptation
to `zone_str` does not disturb this relationship because the two terms operate on orthogonal axes
(`zone_std` vs. `zone_log_key`).

---

## Risk

Low. The multiplier range is ±15% around the current calibrated values. The change is continuous —
no hard stops. The worst case is a slightly over-contrasty dark indoor scene or a slightly
under-contrasty outdoor bright scene, both easily dialled back via `zone_str` base values if needed.

The main validation question is whether the dark-boost direction (1.15× on very dark scenes) is
perceptually correct or whether it creates noise amplification in shadow regions. The Naka-Rushton
gate in the clarity path already suppresses noise there, but zone contrast operates on `new_luma`
before that gate.

---

## Alternatives considered

- **Additive rather than multiplicative term:** less predictable interaction with the spatial term.
- **Direct zone_str = f(zone_std, zone_log_key) surface:** more expressive but harder to calibrate.
- **Separate dark/bright clamps:** would introduce hard stops, ruled out by pipeline policy.
