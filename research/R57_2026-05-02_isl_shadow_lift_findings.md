# R57 — ISL Shadow Lift — Findings

**Date:** 2026-05-02
**Status:** Research complete — safe to implement.

---

## Task 1 — Shadow lift block in grade.fx

**Lines 299–306** of `ColorTransformPS`:

```hlsl
float illum_s0 = max(tex2Dlod(CreativeLowFreqSamp, float4(uv, 0, 1)).a, 0.001);
float log_R    = log2(max(new_luma, 0.001) / illum_s0);
new_luma = lerp(new_luma, saturate(exp2(log_R + log2(max(zone_log_key, 0.001)))), 0.75 * smoothstep(0.04, 0.25, zone_std));

float local_range_att = 1.0 - smoothstep(0.20, 0.50, zone_iqr);
float shadow_lift     = SHADOW_LIFT * 25.19 * exp(-5.776 * illum_s0) * local_range_att;
float lift_w      = new_luma * smoothstep(0.30, 0.0, new_luma);
new_luma          = saturate(new_luma + (shadow_lift / 100.0) * 0.75 * lift_w);
```

**`illum_s0`** — `.a` channel of `CreativeLowFreqTex` sampled at mip 1. This is
the spatially low-frequency luminance at 1/8 resolution, blurred further by mip 1.
It represents local average scene illumination, not per-pixel luma.

**`local_range_att`** — attenuates lift in high-IQR zones (smoothstep 0.20→0.50).
In flat/uniform zones (IQR < 0.20) it is 1.0; in high-contrast zones (IQR > 0.50)
it is 0.0. This prevents lift from flattening scenes with wide tonal range.

**`lift_w`** — `new_luma * smoothstep(0.30, 0.0, new_luma)`. Peaks around
new_luma ≈ 0.14, is zero at new_luma = 0 and new_luma ≥ 0.30. This gate is what
limits clipping — it prevents lift from firing on near-black pixels (luma=0 → lift_w=0)
and suppresses it entirely in midtones (luma≥0.30 → lift_w=0).

**Insert point for ISL swap:** line 304. Replace `exp(-5.776 * illum_s0)` with
`K / (illum_s0 * illum_s0 + EPS)`, matching the surrounding formula structure.

---

## Task 2 — Curve comparison: exponential vs ISL

Calibration: ISL matched to exponential at `illum_s0 = 0.08` (typical p25).
`K = 0.149169`, `EPS = 0.003`.

| illum_s0 | EXP   | ISL   | ISL/EXP | Applied Δ EXP | Applied Δ ISL |
|----------|-------|-------|---------|---------------|---------------|
| 0.001    | 25.05 | 49.71 | 1.98×   | 0.01391       | 0.02761       |
| 0.005    | 24.47 | 49.31 | 2.02×   | 0.01360       | 0.02740       |
| 0.010    | 23.78 | 48.12 | 2.02×   | 0.01321       | 0.02673       |
| 0.030    | 21.18 | 38.25 | 1.81×   | 0.01177       | 0.02125       |
| 0.050    | 18.87 | 27.12 | 1.44×   | 0.01048       | 0.01507       |
| **0.080**| **15.87**|**15.87**|**1.00×**|**0.00882**|**0.00882**|
| 0.120    | 12.60 |  8.57 | 0.68×   | 0.00700       | 0.00476       |
| 0.180    |  8.91 |  4.21 | 0.47×   | 0.00495       | 0.00234       |
| 0.300    |  4.45 |  1.60 | 0.36×   | 0.00247       | 0.00089       |
| 0.500    |  1.40 |  0.59 | 0.42×   | 0.00078       | 0.00033       |

Applied Δ values computed at `new_luma = 0.10`, `SHADOW_LIFT = 1.0`,
`local_range_att = 1.0` to isolate the curve shape.

**The shapes differ meaningfully — this is not a rescale.** Below the crossover
(illum < 0.08), ISL fires up to 2× harder. Above it, ISL drops 32% faster at
illum=0.12, 53% faster at 0.18, and 64% faster at 0.30. The curve is steeper on
both sides of the calibration point: deeper shadows get more, soft shadows get less.

This is the key distinction from exponential: exponential decays monotonically from
a high value at zero toward zero at high illum, but its decay rate is constant
(a fixed half-life). ISL decays quadratically — slowly in deep shadow, then
increasingly fast through the mid-shadow zone. The result is a more distinct boundary
between "dark enough to need lift" and "lit enough to leave alone."

---

## Task 3 — Calibration constants

```
K   = 0.149169
EPS = 0.003
```

**EPS derivation:** Must prevent divergence at the effective black floor.
`FILM_FLOOR = 0.005` → `illum_s0²` at floor = 0.000025. `EPS = 0.003` is 120×
larger, ensuring the denominator never approaches zero in practice. At
`illum_s0 = FILM_FLOOR = 0.005`: ISL = 0.149169 / (0.000025 + 0.003) ≈ 49.3 —
large but bounded.

**K derivation:** Match EXP at illum = 0.08.
```
EXP_ref = 25.19 * exp(-5.776 * 0.08) = 15.869
K = EXP_ref * (0.08² + 0.003) = 15.869 * 0.009400 = 0.149169
```

Both baked as shader constants — not exposed in `creative_values.fx`.
`SHADOW_LIFT` retains the same user-facing semantic and the same calibrated scale.

---

## Task 4 — Step artefact risk

**Risk: none.** Two independent smoothing mechanisms prevent discontinuities:

1. `illum_s0` is sampled from `CreativeLowFreqTex` at mip 1 — a 1/8-res texture
   sampled through linear mipmapping. Spatially it changes only very slowly across
   the frame. No hard edge in `illum_s0` is possible.

2. `lift_w = new_luma * smoothstep(0.30, 0.0, new_luma)` is itself a smoothstep —
   it tapers the lift to zero before the midtone range, independently of the
   `illum_s0` curve. Even if ISL dropped to zero sharply (which it cannot, being a
   rational function), `lift_w` would suppress the artefact.

The steeper ISL slope at illum=0.12–0.18 could theoretically produce softer-than-
expected midtone lift in those pixels, but since `illum_s0` is blurred, that
gradient is spread spatially over many pixels and will not read as a step.

---

## Task 5 — Field test recommendation

Cannot execute from research. Recommend testing two scenes after implementation:

- **GZW jungle** (primary motivation): look for improved separation between
  dappled lit patches and deep inter-patch shadow under canopy. The 2× boost in
  very dark areas (illum < 0.05) should lift shadow detail without graying out
  the lit patches (those are above the crossover and see less lift than before).

- **Arc Raiders indoor** (regression check): indoor scenes tend to have more
  uniform illumination (illum_s0 sits in the 0.10–0.25 range). In that range ISL
  applies 30–55% less lift than exponential — this will slightly deepen indoor
  shadows. Check whether this feels natural or needs `SHADOW_LIFT` bumped from
  1.7 to compensate (1.9–2.0 suggested starting point).

---

## Recommendation

**Implement.** The curve shape change is meaningful and physically well-motivated.
The 2× deeper-shadow boost directly targets dappled canopy inter-patch shadows;
the steeper midtone rolloff preserves contrast where the scene is already lit.
No clipping risk (see task below). No artefact risk (task 4). Constants are stable.

---

## Clipping at toe (from proposal risk section)

**Not a concern.** Worst case: `illum_s0 = FILM_FLOOR = 0.005`, `SHADOW_LIFT = 2.0`,
`new_luma = 0.15` (lift_w peak).

```
shadow_lift  = 2.0 * 49.31 = 98.62
lift_w       = 0.15 * smoothstep(0.30, 0.0, 0.15) = 0.15 * 0.500 = 0.075
applied Δ    = (98.62 / 100.0) * 0.75 * 0.075 = +0.0555
new_luma     = 0.15 + 0.0555 = 0.2055  ← well within [0, 1]
```

The `lift_w` gate, not `saturate()`, is the operative limiter. `saturate()` on
`new_luma` at line 306 is redundant protection.

---

## Implementation diff

**File:** `general/grade/grade.fx`, line 304.

**Before:**
```hlsl
float shadow_lift     = SHADOW_LIFT * 25.19 * exp(-5.776 * illum_s0) * local_range_att;
```

**After:**
```hlsl
float shadow_lift     = SHADOW_LIFT * (0.149169 / (illum_s0 * illum_s0 + 0.003)) * local_range_att;
```

One line. No new textures, no new passes, no knobs added.
