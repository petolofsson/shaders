# R200 — Temporal Chromatic Adaptation: Psychophysically-Grounded EMA Time Constants

**Date:** 2026-05-17  
**Domain:** Wild card (Sunday) — adjacent to chromatic adaptation (CAT16/R83/R90)  
**Focus:** Temporal dynamics of the visual system's chromatic adaptation; calibrating the
pipeline's `slow_key` (HWY_SLOW_KEY, x=205) and scene-cut EMA logic against measured
psychophysical time constants.

---

## Literature

**Primary:** Sawyer, M. et al., "Modeling and Exploiting the Time Course of Chromatic
Adaptation for Display Power Optimizations in Virtual Reality," *ACM Transactions on
Graphics* (SIGGRAPH Asia 2025), arXiv:2509.23489.  
Proposes a real-time per-frame illuminant-tracking model that follows the psychophysical
adaptation curve. Applies it to OLED power reduction (31% saving with no perceptible
loss). The model is a first-order exponential — directly analogous to an EMA filter.

**Secondary (confirmation):** Ji et al. (2023), "The time course of chromatic adaptation
in human early visual cortex revealed by SSVEPs," *Journal of Vision*, PMC10214868.  
Neurophysiological measurement: SSVEP amplitude decays as a single exponential with
**T_half ≈ 20 s**, consistent with earlier psychophysical reports (Rinner & Gegenfurtner
2000; Fairchild & Reniff 1995).

**Classic reference:** Rinner & Gegenfurtner (2000), *JOSAA*: two-component model —  
- Fast component: T_half ≈ 40–70 ms (photoreceptor bleaching)  
- Slow component: T_half ≈ 20 s (cortical / neural re-calibration)

Both are exponential decays toward the current illuminant. The slow component dominates
steady-state scene appearance; the fast component handles abrupt cuts.

---

## Pipeline Relevance

### What `slow_key` currently does

`corrective.fx`, SmoothZoneLevels pass (≈ line 252-253):

```hlsl
prev_slow = lerp(zone_log_key, prev_slow, step(0.001, prev_slow)); // cold-start init
return float4(lerp(prev_slow, zone_log_key, 0.003), 0, 0, 0);
```

Fixed α = 0.003 per frame.  
- At 60 fps (Δt = 16.67 ms): T_half = log₂(2) / −log₂(0.997) ≈ **231 frames = 3.85 s**  
- At 30 fps (Δt = 33.3 ms): same α → **231 frames = 7.7 s**

**Two problems:**
1. The time constant is **5× too fast** compared to the psychophysical 20 s slow
   component. This makes the pipeline's ambient key estimate over-respond to transient
   lighting events (explosions, flashes) in steady scenes.
2. The alpha is **not framerate-independent** — no `frametime` scaling. At 30 fps the
   effective time constant doubles relative to 60 fps.

### Scene-cut fast-path — missing for slow_key

`slow_key` has no scene-cut reset. The Kalman / EMA paths in `analysis_frame.fx` do
react to HWY_SCENE_CUT (x=199): `alpha = lerp(alpha_nominal, 1.0, scene_cut)`. The
slow_key skips this, so after a hard cut the ambient key drifts for seconds rather than
snapping to the new illuminant within ~3 frames (fast photoreceptor component).

---

## Mathematics

### Frametime-scaled EMA

For a first-order exponential with half-life T_half (ms):

```
τ        = T_half / ln 2
α(Δt)   ≈ 1 − exp(−Δt / τ)   ≈  Δt / τ   (for Δt ≪ τ)
```

| Component | T_half | τ | α at 16.67 ms | α at 33.3 ms |
|-----------|--------|---|---------------|--------------|
| Slow (cortical, steady scene) | 20 000 ms | 28 868 ms | 0.000578 | 0.001154 |
| Fast (photoreceptor, scene cut) | 67 ms | 96.7 ms | 0.172 | 0.294 |

In the pipeline's `saturate(frametime * K)` convention:

```
K_slow = 1 / 28868  ≈  0.0000346
K_fast = 1 / 96.7   ≈  0.01034
```

### Dual-rate EMA update

```hlsl
float scene_cut  = ReadHWY(HWY_SCENE_CUT);          // [0,1] smooth
float alpha_slow = saturate(frametime * 0.0000346);  // T_half = 20 s
float alpha_fast = saturate(frametime * 0.01034);    // T_half = 67 ms
float alpha      = lerp(alpha_slow, alpha_fast, scene_cut);
new_slow_key     = lerp(prev_slow, zone_log_key, alpha);
```

HWY_SCENE_CUT is already smooth (smoothstep output from analysis_frame.fx), so the
`lerp` between fast and slow α is continuous — no gate.

---

## Conflict Check

| Rule | Status |
|------|--------|
| No gates | ✓ — lerp on smooth scene_cut, no hard if/threshold |
| No auto-exposure | ✓ — slow_key feeds Hunt/shadow-lift, not EXPOSURE |
| SDR by construction | ✓ — slow_key is log-key [0,1], unchanged |
| creative_values.fx only tuning surface | ✓ — no new user knob needed; time constants are psychophysical constants, not creative choices |
| No OPT-2/3 cold-start regression | ✓ — cold-start init (`step(0.001, prev_slow)`) is unchanged |

**`frametime` uniform not in corrective.fx** — currently only `FRAME_TIMER` (elapsed
ms since app start). Adding `uniform float frametime < source = "frametime"; >;` to
corrective.fx is the only required declaration change.

---

## Implementation Sketch

**File:** `general/corrective/corrective.fx`

1. Add uniform at top (with other uniforms):
```hlsl
uniform float frametime < source = "frametime"; >;   // ms since last frame
```

2. In SmoothZoneLevels pass, replace the slow_key write (≈ line 253):
```hlsl
// Before:
return float4(lerp(prev_slow, zone_log_key, 0.003), 0, 0, 0);

// After: dual-rate EMA, psychophysically grounded (Rinner & Gegenfurtner 2000)
// Slow component T_half=20s; fast component T_half=67ms on scene cut.
float scene_cut  = ReadHWY(HWY_SCENE_CUT);
float alpha_slow = saturate(frametime * 0.0000346f);
float alpha_fast = saturate(frametime * 0.01034f);
return float4(lerp(prev_slow, zone_log_key, lerp(alpha_slow, alpha_fast, scene_cut)), 0, 0, 0);
```

No highway slot changes. No new textures. No touch to `creative_values.fx`.

---

## Downstream Effects

`slow_key` feeds `HWY_SLOW_KEY` (x=205). Consumers in grade.fx should be checked:
- **R66 ambient shadow tint** reads HWY_SLOW_KEY to gate the tint by ambient luminance.
  A longer time constant means the tint shifts more slowly after lighting changes — more
  cinematically stable, less twitchy.
- If any consumer uses slow_key as a frame-to-frame delta (finite difference), the much
  smaller per-frame step will reduce derivative magnitude ~8× at 60 fps. Verify no
  consumer divides by or differentiates slow_key.

---

## GPU Cost

- 2 × `saturate(frametime * K)`: 2 ALU ops
- 1 × `lerp(alpha_slow, alpha_fast, scene_cut)`: 1 ALU op
- 1 × `lerp(prev, target, alpha)`: 1 ALU op (already present)
- 1 × `ReadHWY(HWY_SCENE_CUT)`: 1 texture tap (already read by other passes)

**Net new cost: ~3 ALU, 0 new taps.** Negligible.

---

## Summary

The pipeline's `slow_key` EMA uses a fixed α=0.003 — 5× too fast for the cortical
adaptation component (T_half≈20 s) and framerate-dependent. The 2025 ACM TOG paper and
2023 SSVEP neurophysiology jointly confirm the 20 s half-life; the Rinner & Gegenfurtner
two-component model motivates a fast-path (~67 ms) on scene cuts. Replacing the fixed
constant with a frametime-scaled dual-rate lerp is a 4-line change, zero GPU cost, and
brings the pipeline's temporal adaptation behaviour into psychophysical calibration.

**Viability: High.** Recommend implementing in the next corrective.fx session.

---

## Sources

- arXiv:2509.23489 — Sawyer et al. 2025 ACM TOG (SIGGRAPH Asia)
- PMC10214868 — Ji et al. 2023 *Journal of Vision* SSVEP study
- Rinner & Gegenfurtner (2000), *JOSAA* — two-component time course
- Fairchild & Reniff (1995), *JOSAA* — slow component T_half distribution
