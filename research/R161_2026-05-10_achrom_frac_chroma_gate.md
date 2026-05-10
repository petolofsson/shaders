# R161 — Achromatic Fraction Gate for Grade Chroma Lift

**Date:** 2026-05-10
**Scope:** grade.fx `BuildSceneCtx` — `chroma_str_base` computation

---

## Problem

`chroma_str_base` was modulated by two signals:
- `zone_log_key` — scene brightness (lift more in dark scenes)
- `mean_C_scene` (R151) — scene mean chroma (back off in already-saturated scenes)

Neither signal prevented aggressive chroma lift in **genuinely achromatic scenes** — fog,
overcast skies, desaturated interiors. In those scenes, near-neutral pixels have very small
but non-zero chroma. Lifting them pushes noise into false color rather than recovering
real signal.

`mean_C` can be low even in colorful scenes with many neutral pixels. `achrom_frac`
specifically measures the *fraction* of pixels with Oklab C < 0.05 — a direct count
of how many pixels are genuinely colorless. These are complementary signals.

## Highway slot

`HWY_ACHROM_FRAC` (202) — written by `analysis_frame`, available to all downstream
stages. Was already used in `inverse_grade.fx` (R157) to lower the chroma expansion
gate in achromatic scenes. Was not read by `grade.fx` — identified as a gap in a
full highway slot audit (2026-05-10).

## Implementation

In `BuildSceneCtx`:

```hlsl
float achrom_frac   = ReadHWY(HWY_ACHROM_FRAC);
ctx.chroma_str_base = CHROMA_STR * 0.04
                    * lerp(0.80, 1.20, smoothstep(0.05, 0.35, ctx.zone_log_key))
                    * lerp(1.2, 1.0, saturate(mean_C_scene / 0.12))
                    * lerp(1.0, 0.60, smoothstep(0.60, 0.85, achrom_frac));
```

The achrom_frac multiplier uses the same 0.60–0.85 window as R157 in inverse_grade
for consistency. At achrom_frac < 0.60: no attenuation. At achrom_frac > 0.85:
chroma_str_base reduced to 60% of its R151-modulated value. Maximum 40% reduction —
not zeroing out, since even achromatic scenes have some genuinely coloured elements.

## Interaction with R151

Both gates are multiplicative. A scene that is both low mean_C (R151 boosts) and high
achrom_frac (R161 attenuates) will have the two effects partially cancel — appropriate,
since a desaturated scene with many achromatic pixels doesn't need aggressive lift.

## No new knobs

CHROMA_STR already scales the entire chain. R161 is a self-limiting correction, not
a user-adjustable parameter.
