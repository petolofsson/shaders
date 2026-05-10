# R77 — Stage 2 Calibration

**Date:** 2026-05-03
**Status:** Proposed

## Problem

Stage 2 is 87% finished and 93% novel. This is a parameter validation pass — three
empirically-set values that need numerical verification. May produce zero code changes.

## R77A — R65/R66 interaction

R65 (Hunt coupling) and R66 (ambient shadow tint) both write to `lab_t.y/z` in the
shadow region (gated by `r65_sw = smoothstep(0.30, 0.0, lab_t.x)`).

R65 scales `lab_t.y/z` by `r65_ab` (luminance ratio^0.333), moving a/b toward the
lifted-chroma position. R66 then lerps `lab_t.y/z` toward `lab_amb.yz` by weight
`r66_w = r65_sw * achrom_w * (1 - scene_cut) * 0.4`.

Combined effect in worst case (low-key scene, strong ambient hue, fully achromatic pixel):
- r65_ab could push a/b away from zero (if r_tonal > 1, lifting shadows lifts chroma)
- r66_w at 0.4 then pulls toward ambient hue

Research: compute combined weight numerically across the (r_tonal, achrom_w, scene_cut)
parameter space. Confirm no region produces over-correction (|lab_t.yz| > |lab_amb.yz|).

## R77B — Retinex blend weight

`new_luma = lerp(new_luma, saturate(nl_safe * zk_safe / illum_s0), 0.75 * ss_04_25)`

The blend weight `0.75 * ss_04_25` was set empirically. `ss_04_25 = smoothstep(0.04, 0.25,
zone_std)` — at zone_std=0.04 (flat/uniform scene), weight=0. At zone_std=0.25 (high
variance), weight=0.75. At zone_std=0.15 (moderate), weight ≈ 0.42.

Research: sample zone_std distribution from Arc Raiders gameplay. Confirm the 0.04–0.25
range covers the real zone_std range. Check that weight=0 at low variance is correct
(flat scenes shouldn't be Retinex-normalised — already illumination-invariant).

## R77C — R60 temporal context exponent

`context_lift = exp2(log2(slow_key / zk_safe) * 0.4)`

The exponent 0.4 determines how aggressively temporal dark-period boost/suppress fires.
At slow_key/zk_safe = 2.0 (slowly brightening scene): context_lift = 2^(1.0 * 0.4) = 1.32.
At slow_key/zk_safe = 0.5 (slowly darkening): context_lift = 2^(-1.0 * 0.4) = 0.76.

Research: derive the correct exponent from temporal adaptation psychophysics (Fairchild
1990 or equivalent). Confirm 0.4 is within the physiologically plausible range.

## Deliverable

Numerical analysis document. Parameter changes only if any value is confirmed wrong
by >20%.
