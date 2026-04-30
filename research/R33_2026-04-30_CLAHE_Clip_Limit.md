# R33 — CLAHE-Inspired Clip Limit on Zone S-Curve
**Date:** 2026-04-30
**Type:** Proposal
**ROI:** High — directly addresses the over-amplification artifact Retinex (R29) can surface;
no new passes, no new textures, 2 lines of math

---

## Problem

After R29, Retinex normalizes per-pixel illumination. Zones that were previously
modulated by a broad illumination gradient now appear locally flat — their reflectance
is isolated. The zone S-curve then applies to this already-normalized signal:

```hlsl
float iqr_scale = smoothstep(0.0, 0.25, zone_iqr);
float bent      = dt + zone_str * iqr_scale * dt * (1.0 - saturate(abs(dt)));
```

The problem: `zone_iqr` is derived from `ZoneHistoryTex` (smoothed p75−p25), which was
built from the pre-Retinex luminance distribution. In scenes where Retinex has already
compressed the illumination range, the zone IQR no longer reflects the effective local
contrast. The S-curve amplifies at full IQR-driven strength into what is now a compressed
signal — over-amplifying fine noise and creating a grainy look in previously-uniform zones.

This is exactly the artifact CLAHE avoids with its clip limit.

---

## CLAHE clip limit — what it does

In CLAHE (Contrast Limited Adaptive Histogram Equalization), the histogram of each local
tile is clipped before equalization: any bin exceeding the clip limit L has its excess
redistributed uniformly across all bins. The effect: the maximum contrast gain (effective
slope of the equalization curve) is bounded by L / mean_bin_count.

For our S-curve, the analogous quantity is the slope at the pivot (zone_median):

```
slope_at_pivot = 1 + zone_str * iqr_scale
```

Without a clip: slope can reach 1 + 0.30 * 1.0 = 1.30 (flat scene, high IQR zone).
After Retinex, this amplification is applied on top of illumination-normalized signal —
equivalent to CLAHE with no clip limit, which produces halos and noise amplification.

---

## Proposed implementation

Add a slope ceiling. Clip `iqr_scale` so the S-curve slope never exceeds a configurable
maximum at the pivot:

```hlsl
// CLAHE-inspired clip limit on zone S-curve slope
float clahe_max_slope = 1.25;  // pivot slope ceiling (CLAHE clip equivalent)
float iqr_raw   = zone_lvl.b - zone_lvl.g;
float iqr_scale = min(smoothstep(0.0, 0.25, iqr_raw),
                      (clahe_max_slope - 1.0) / max(zone_str, 0.001));
float dt        = luma - zone_median;
float bent      = dt + zone_str * iqr_scale * dt * (1.0 - saturate(abs(dt)));
float new_luma  = saturate(zone_median + bent);
```

The clip limit `(clahe_max_slope - 1.0) / zone_str` automatically adapts to `zone_str`
(which is itself driven by `zone_std`). In high-contrast scenes where zone_str is reduced
(0.18), the clip is looser (slope allowed to 1.25). In flat scenes where zone_str is at
full (0.30), the clip tightens (iqr_scale capped at 0.83).

The constant `1.25` is the CLAHE analogue of the clip limit — tune in range [1.1, 1.5]:
- 1.0 = no S-curve at all (clip defeats the effect entirely)
- 1.5 = same as current maximum (clip has no effect)
- 1.25 = 25% maximum gain at pivot — recommended starting point

---

## Interaction with Retinex (R29)

The clip limit should adapt to how much Retinex has already compressed the scene:

```hlsl
// Tighter clip when Retinex is fully engaged (high zone_std → full blend)
float retinex_blend  = smoothstep(0.04, 0.25, zone_std);
float clahe_max_slope = lerp(1.40, 1.15, retinex_blend);
```

In flat scenes (Retinex barely engaged): looser clip (1.40 → more S-curve latitude).
In contrasty scenes (Retinex fully engaged): tighter clip (1.15 → protect normalized signal).

This makes the clip limit complementary to Retinex rather than a separate constant.

---

## Redistribution (optional extension)

Standard CLAHE redistributes clipped excess uniformly. For our S-curve, the equivalent
is a small additive lift to shadows when the slope is clipped. Implementation:

```hlsl
float clipped_gain = saturate(iqr_scale_unclamped - iqr_scale);
float redistribute = clipped_gain * zone_str * 0.5 * (1.0 - luma);  // lift shadows
new_luma = saturate(new_luma + redistribute);
```

This is optional — start without redistribution and add only if tone compression is visible.

---

## Advantages

| | Current | With CLAHE clip |
|--|---------|----------------|
| S-curve slope ceiling | None (up to 1.30) | Bounded (tunable 1.1–1.5) |
| Post-Retinex noise amplification | Risk in flat zones | Suppressed |
| Retinex interaction | Independent | Clip adapts to Retinex engagement |
| GPU cost | — | 1 division + 1 min (negligible) |
| New passes | 0 | 0 |
| New textures | 0 | 0 |

---

## Research questions

1. What clip limit values (slope ceiling) do published CLAHE implementations use for
   video/display-referred content? Standard image CLAHE uses L=3–4 (contrast gain
   limit), but display content differs.
2. Does the Retinex-adaptive clip (lerp between 1.15 and 1.40) match the MDPI 2024
   "Retinex Jointed Multiscale CLAHE" paper's approach, or does the paper implement
   the coupling differently?

---

## Success criteria

- `iqr_scale` capped by the clip limit before the S-curve computation
- Clip limit adapts to Retinex engagement via `zone_std`
- No visual change in high-variance scenes (where clip has no effect)
- Reduced grainy noise in flat/uniform zones compared to R29 alone
- No new passes, no new textures, no new knobs
