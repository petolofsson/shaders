# R176 — CHROMA_STR Scene-Adaptive Automation
**Date:** 2026-05-10
**Status:** Proposal

## Problem

`CHROMA_STR` is a fixed user scalar (currently 1.10) applied uniformly regardless of scene
colorfulness. Two published psychophysical phenomena argue it should adapt inversely to scene
mean chroma:

1. **Gamut expansion effect** (Webster & Mollon 1994, 1997): The visual system adapts to both
   the mean and variance of the chromatic signal. In a low-chroma (achromatic) scene, chromatic
   contrast sensitivity increases — the visual system effectively expands perceived gamut. A
   desaturated scene warrants more chroma lift to reach equivalent perceptual colorfulness.

2. **Hunt effect** (CIECAM02 / CAM16): Colorfulness `M = C × FL^0.25` where `FL` scales with
   adapting luminance. In dim or desaturated viewing, `FL` is lower, so more physical chroma `C`
   is needed for equivalent perceived colorfulness `M`. The effect is ~±15% across typical SDR
   monitor luminance ranges.

Neither effect is currently compensated in the pipeline. A high-chroma scene gets the same
chroma lift as a low-chroma scene, over-saturating scenes that are already vibrant and
under-saturating achromatic scenes where the eye is in gamut-expansion mode.

## Signal

`HWY_CHROMA_MEAN` (highway slot 198) — median Oklab C, EMA-smoothed by the Kalman in
`corrective.fx`. Already on the highway. Temporally stable. Scene-cut spikes handled by
existing `scene_cut` mechanism.

This is the correct signal: CHROMA_STR should respond to scene *chroma* statistics, not luma.
R87's proposal used luma p50 — that would correlate incidentally (bright scenes are often
colorful) but not causally.

## Proposed formula

```hlsl
// In BuildSceneCtx, after ctx.scene_mode is set:
float mean_C       = ReadHWY(HWY_CHROMA_MEAN);   // slot 198, already decoded ×0.10 scale
float chroma_adapt = lerp(1.25, 0.85, smoothstep(0.04, 0.18, mean_C));
ctx.chroma_str_base = CHROMA_STR * 0.04
                    * chroma_adapt
                    * lerp(0.80, 1.20, smoothstep(0.05, 0.35, ctx.zone_log_key));
```

| mean_C | chroma_adapt | Scene character          |
|--------|--------------|--------------------------|
| 0.02   | 1.25         | Near-achromatic          |
| 0.04   | 1.25         | Low chroma threshold     |
| 0.08   | ~1.10        | Normal mixed scene       |
| 0.14   | ~0.95        | Colorful scene           |
| 0.18+  | 0.85         | High-chroma ceiling      |

Range: ×0.85–1.25 on top of CHROMA_STR. At CHROMA_STR 1.10: effective range 0.94–1.38.

## Key questions before implementation

1. **HWY_CHROMA_MEAN encoding**: slot 198 encodes `median_C / 0.10`. Must decode as
   `ReadHWY(198) * 0.10` before plugging into smoothstep. Verify this is correct.

2. **Smoothstep range**: `smoothstep(0.04, 0.18, mean_C)` assumes arc_raiders mean_C
   typically sits 0.06–0.14. If the game's content saturates outside this range, the
   automation is inert. Need to observe actual mean_C values in play.

3. **Interaction with ACHROM_FRAC**: R161 was dropped because achrom_frac multiplier on
   chroma_str_base flattened simultaneous contrast. mean_C is a different signal (median
   chroma, not achromatic pixel fraction) but risk of similar flattening exists. Must verify
   in desaturated environments that the boost doesn't gray-out blacks.

4. **Double-dipping**: `ctx.chroma_str_base` already includes `zone_log_key` modulation.
   Adding a second adaptive factor could create instability if both signals move together
   (e.g., dark low-chroma scene: zone_log_key low → 0.80× AND mean_C low → 1.25× — these
   partially cancel, which may be correct or may fight each other).

## Risk: Medium-Low

- Signal is stable (EMA-smoothed, already in use)
- Formula is smooth (no gates or hard conditionals)
- Range is conservative (±25% max)
- Worst case: revert to `chroma_adapt = 1.0`

## Verdict: FEASIBLE — propose for next session

Literature grounding: Webster & Mollon (1997) variance adaptation; Hunt effect in CIECAM02;
iCAM06 local colorfulness enhancement. No standard CAM uses scene median chroma as a direct
automation signal — this is novel but physically motivated.
