# R58 — Retinex-Aware Shadow Lift

**Date:** 2026-05-02
**Status:** Research complete — safe to implement.

---

## Problem

After R57 (ISL shadow lift), the lift fires aggressively in the low-illum range
where ground foliage micro-contrast lives (luma 0.05–0.15). Leaf-to-leaf shadow
variation — the subtle dark pockets that give foliage its 3D texture — gets lifted
equally alongside uniformly dark inter-patch shadow that genuinely needs recovery.
The result: foliage reads flat.

The lift cannot currently distinguish between:
- A **uniformly dark region** (deep shadow between light pools — should be lifted)
- A **local dark detail within a region** (shadow side of a leaf — should be preserved)

---

## Solution

`log_R = log2(new_luma / illum_s0)` is already computed at line 300, one line above
the lift. It is the log ratio of the pixel's luma to its spatial low-frequency
average — i.e. the Retinex reflectance estimate.

- `log_R ≈ 0`: pixel matches its local average → uniformly dark region → lift
- `log_R < 0`: pixel is darker than its surroundings → local detail shadow → protect

Gate the lift through a smoothstep on `log_R`:

```hlsl
float detail_protect = smoothstep(-0.5, 0.0, log_R);
float shadow_lift    = SHADOW_LIFT * (0.149169 / (illum_s0 * illum_s0 + 0.003))
                     * local_range_att * detail_protect;
```

No new textures, no new passes, no new knobs. `log_R` is in scope and free.

---

## Threshold derivation

`smoothstep(-0.5, 0.0, log_R)` means:

| log_R | pixel vs local avg | detail_protect |
|-------|--------------------|----------------|
| ≤ −0.5 | ≤ 70.7% of avg (≥29% darker) | 0.00 — fully protected |
| −0.25 | 84% of avg | 0.50 — half lift |
| 0.0 | 100% of avg (matches) | 1.00 — full lift |
| > 0.0 | brighter than avg | 1.00 — full lift |

A 29% darker-than-average threshold cleanly separates foliage shadow variation
(leaf dark side / bright side ratio typically 50–70% = 30–50% darker) from
uniformly dark regions (pixel ≈ local average, log_R ≈ 0, detail_protect = 1).

Alternative thresholds considered:

- **−0.3** (18.8% threshold): too tight — starts protecting only at the very darkest
  micro-detail; most foliage shadow at 70–80% of local avg still gets significant lift.
- **−0.7** (38.4% threshold): too loose — starts protecting canopy inter-patch pixels
  that are only slightly darker than their already-dark local average; those still
  need lift.

**−0.5 is correct.**

---

## Numerical validation

Foliage scenario, `illum_s0 = 0.12` (moderately shadowed canopy region):

| new_luma | ratio to avg | log_R  | detail_protect |
|----------|-------------|--------|----------------|
| 0.03 | 0.25 | −2.00 | 0.000 — protected |
| 0.07 | 0.58 | −0.78 | 0.000 — protected |
| 0.09 | 0.75 | −0.42 | 0.077 — mostly protected |
| 0.10 | 0.83 | −0.26 | 0.461 — transitioning |
| 0.12 | 1.00 |  0.00 | 1.000 — full lift |
| 0.15 | 1.25 | +0.32 | 1.000 — full lift |

Uniform deep shadow (pixel = local average, all illum levels):

| illum_s0 | new_luma | log_R | detail_protect |
|----------|---------|-------|----------------|
| 0.02 | 0.02 | 0.000 | 1.000 |
| 0.06 | 0.06 | 0.000 | 1.000 |
| 0.10 | 0.10 | 0.000 | 1.000 |

Uniformly dark regions always get full lift regardless of depth. ✓

Applied lift at `SHADOW_LIFT = 1.5`, `local_range_att = 1.0`:

| Scenario | illum_s0 | new_luma | protect | Applied Δ |
|----------|---------|---------|---------|-----------|
| Deep uniform shadow | 0.04 | 0.04 | 1.000 | +0.01388 |
| Moderate uniform shadow | 0.08 | 0.08 | 1.000 | +0.01178 |
| **Leaf shadow (dark side)** | **0.12** | **0.07** | **0.000** | **+0.00000** |
| Leaf midtone | 0.12 | 0.12 | 1.000 | +0.00750 |
| **Deep foliage pocket** | **0.06** | **0.03** | **0.000** | **+0.00000** |
| Canopy inter-patch | 0.04 | 0.035 | 0.669 | +0.00822 |

The leaf shadow dark side and deep foliage pockets are fully protected. Inter-patch
deep shadows are lifted. Canopy inter-patch pixels that are only slightly darker than
their already-dark local average get ~67% lift — appropriate, as these are transitional
areas, not pure micro-detail.

---

## Implementation

**File:** `general/grade/grade.fx`, lines 303–304.

**Before:**
```hlsl
float local_range_att = 1.0 - smoothstep(0.20, 0.50, zone_iqr);
float shadow_lift     = SHADOW_LIFT * (0.149169 / (illum_s0 * illum_s0 + 0.003)) * local_range_att;
```

**After:**
```hlsl
float local_range_att = 1.0 - smoothstep(0.20, 0.50, zone_iqr);
float detail_protect  = smoothstep(-0.5, 0.0, log_R);
float shadow_lift     = SHADOW_LIFT * (0.149169 / (illum_s0 * illum_s0 + 0.003)) * local_range_att * detail_protect;
```

One line added. `log_R` is already in scope from line 300. No new cost.

---

## Note on log_R timing

`log_R` is computed at line 300 using the **pre-Retinex** `new_luma`. The Retinex
step at line 301 modifies `new_luma` for global scene key normalisation. Using the
pre-Retinex `log_R` for the detail gate is correct — it captures the true local
reflectance contrast structure before global normalisation obscures it.
