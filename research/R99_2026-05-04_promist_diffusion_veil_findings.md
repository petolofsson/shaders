# R99 — Pro-Mist Redesign: Global Diffusion + Veil Tuning

**Date:** 2026-05-04  
**Status:** Done

---

## Problem

Pro-Mist was implemented as an additive highlight bloom: threshold extract above 0.5,
blur to 1/2-res MistBloomTex, add back additively. This caused two problems:

1. Fires on white UI text (high luminance but not a light source)
2. Character is "highlight glow" — not what a Pro-Mist filter physically does

A real Black Pro-Mist filter works by scattering light in all directions through polymer
particles embedded in the glass. The dominant perceptual effect is global micro-contrast
softening, not highlight bloom. Highlight bloom is a secondary artifact, better handled
by halation (red fringe, specular sources) and veil (DC additive lift from intraocular
scatter).

## Redesign

Replaced additive highlight bloom with global diffusion:

**Pass 1 — DownsamplePS** (writes MistDiffuseTex):
- Full BackBuffer downsampled to 1/4-res RGBA16F, MipLevels=4
- No threshold — all tones, all luminances
- Highway guard: `if (pos.y < 1.0) return float4(0,0,0,0)`

**Pass 2 — ProMistPS** (reads MistDiffuseTex + BackBuffer):
- `float3 blurred = tex2Dlod(MistDiffuseSamp, float4(uv, 0, 2)).rgb`
- Mip 2 of 1/4-res = 1/16-res effective = ~16px smooth spread at 1080p
- `float3 result = lerp(base.rgb, blurred, saturate(adapt_str))`
- adapt_str = `MIST_STRENGTH * 0.06 * scene_adaptive_scalars`

At MIST_STRENGTH=1.0: ~6% blend. At 2.75 (Arc Raiders current): ~16% blend.

## Scene adaptivity retained

- IQR adaptive: `lerp(0.8, 1.2, saturate(iqr / 0.5))` — high-contrast scenes get more diffusion
- Zone key: `lerp(1.20, 0.85, smoothstep(0.05, 0.25, zone_log_key))` — dark scenes more, bright less
- Aperture proxy: `lerp(1.10, 0.90, saturate((EXPOSURE - 0.70) / 0.60))` — low exposure = more diffusion

## Confirmation test

Set MIST_STRENGTH=5.0. User reported "slight bloom" — confirmed mip generation is working.
The bloom character at high strength is expected: blurred image spreads bright pixels into
neighboring dark areas, which looks like a glow. At normal strength (1.5–2.75) this reads
as haze and softness, not bloom.

## Veil changes

- Doc fix: comment "scene median (p50)" corrected to "scene p75" (actual sampled channel: `perc.b`)
- VEIL_STRENGTH: 0.10 → 0.15 on both games ("filmic soft" — visible contrast floor lift)

## Current tuned values

| Knob | Arc Raiders | GZW |
|------|------------|-----|
| MIST_STRENGTH | 2.75 | 1.50 |
| VEIL_STRENGTH | 0.15 | 0.15 |
| EXPOSURE | 0.90 | 0.90 |
| HAL_STRENGTH | 0.40 | 0.35 |
| SHADOW_LIFT_STRENGTH | 1.30 | 1.15 |

## Responsibility separation

After this change:
- **Halation** — red fringe around specular sources (tight chromatic scatter)
- **Veil** — additive DC lift from scene p75 (intraocular scatter, contrast floor)
- **Pro-Mist** — global micro-contrast softening (diffusion, all tones equally)

No overlap. Each effect has a distinct physical mechanism and distinct spatial character.
