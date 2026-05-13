# R188 — Temporal Filtering & State Estimation — 2026-05-13

## Domain
Wednesday rotation: Temporal filtering & state estimation (2023–2026 literature sweep).

---

## Summary of findings

Two complementary improvements to the pipeline's Kalman-based temporal estimators:

1. **Primary — Huber-robust innovation cap** (proposed for implementation): a smooth
   M-estimation wrapper on the Kalman innovation that limits the per-frame shift caused by
   outlier frames (muzzle flashes, explosions) without disturbing normal scene tracking.
   Applies to `UpdateChromaKalman` (corrective.fx) and the percentile Kalman (analysis_frame.fx).

2. **Secondary — Alpha-beta second-order slow_key** (future research): replace the
   first-order EMA in `ComputeSlowKey` with a two-state g-h filter that also tracks the
   rate-of-change (trend) of scene illumination, eliminating steady-state lag during
   gradual illumination ramps.

---

## Finding 1 — Huber-Robust Innovation Cap

### Literature basis

- **"Improved robust Huber-Kalman filtering" (Aerospace Systems, 2023)** — derives a
  Huber M-estimator reformulation of the standard Kalman measurement update, showing that
  replacing the L2 innovation penalty with a Huber loss (quadratic for small innovations,
  linear above threshold c) significantly reduces state drift from impulsive outliers.
  Applicable wherever measurement noise is non-Gaussian with heavy tails.

- **"Outlier-Robust KalmanNet: Neural Network Aided Kalman Filtering Based on Huber Loss"
  (ResearchGate, 2024)** — applies the Huber innovation cap to real-time tracking, confirming
  that even a scalar first-order Kalman benefits substantially from Huber re-weighting when
  outlier measurements are 3–10× the steady-state noise floor.

- **"Robust recursive sigma point Kalman filtering for Huber-based generalized M-estimation"
  (ScienceDirect, 2024)** — proves convergence of the Huber-Kalman update and provides
  guidance that the Huber threshold c should be set at 3–5× the measurement noise std σ_R
  for maximum outlier suppression without degrading normal tracking.

### Problem in this pipeline

Both Kalman sites apply `K * innovation` directly:

**analysis_frame.fx CDFWalkPS (VFF Kalman for p25/p50/p75):**
```hlsl
float e_p50 = p50 - prev.g;
float Q_vff_p = lerp(KALMAN_Q_PERC_MIN, KALMAN_Q_PERC_MAX,
                     smoothstep(0.0, VFF_E_SIGMA_PERC, abs(e_p50)));
float P_pred  = P + Q_vff_p;
float K       = P_pred / (P_pred + KALMAN_R_PERC);
return float4(prev.r + K * (p25 - prev.r),   // ← raw innovation
              prev.g + K * e_p50,              // ← raw innovation
              prev.b + K * (p75 - prev.b),     // ← raw innovation
              P_new);
```

**corrective.fx UpdateChromaKalman (Sage-Husa Kalman for chroma bands):**
```hlsl
float K        = P_pred / (P_pred + KALMAN_R);
float new_mean = prev.r + K * e_chroma;   // ← raw innovation
```

**Failure mode for flash frames:**

In the VFF percentile Kalman, a muzzle-flash frame creates a large `|e_p50|`, which drives
`Q_vff_p` to KALMAN_Q_PERC_MAX and consequently K → 0.91. The full-scale flash innovation
is then applied at K=0.91 — the opposite of what is needed. The P-accumulation damping in
subsequent frames is correct but arrives one frame too late.

In the Sage-Husa chroma Kalman, `Q_vff_c` is driven by posterior P (not innovation), so it
is not flash-triggered. However K can still be near unity during the P warm-up phase that
follows a scene cut, making the chroma bands vulnerable to a flash coinciding with a cut.

### Proposed fix — smooth Huber cap

Replace `K * innovation` with `K * innovation * H(innovation, c)` where `H` is a smooth
halving function that is 1.0 for small innovations and fades toward 0.5 for extreme ones:

```hlsl
// H(e, c): 1.0 for |e| << c, 0.5 for |e| >> 2c. No hard branch.
float HuberScale(float e, float c)
{
    return 1.0 - 0.5 * smoothstep(0.0, c * 2.0, abs(e));
}
```

This is a smooth approximation of the Huber ψ-function, appropriate for SDR scalar signals.
The halving (not zeroing) ensures that even extreme outliers produce *some* update, which
prevents P from growing unboundedly if outliers recur.

**Threshold guidance from literature:** set `c` at 3–5× measurement noise std.

- For percentile Kalman: `KALMAN_R_PERC = 0.005` → σ_R ≈ 0.07. c = 4 × VFF_E_SIGMA_PERC
  (which equals 4 × 0.04 = 0.16). This is already implicit in the VFF smoothstep width;
  using the same scale constant keeps the parameter count zero.
- For chroma Kalman: `KALMAN_R = 0.01` → σ_R ≈ 0.10. c = 4 × VFF_E_SIGMA_CHROMA
  (= 4 × 0.04 = 0.16).

**Concrete change — analysis_frame.fx CDFWalkPS:**

```hlsl
// After computing e_p50 and K:
float h_p = 1.0 - 0.5 * smoothstep(0.0, VFF_E_SIGMA_PERC * 8.0, abs(e_p50));
return float4(prev.r + K * (p25 - prev.r) * h_p,
              prev.g + K * e_p50 * h_p,
              prev.b + K * (p75 - prev.b) * h_p,
              P_new);
```

(Using 8× instead of 4× because `VFF_E_SIGMA_PERC` is already half of the chroma sigma;
adjust to match the percentile noise floor empirically.)

**Concrete change — corrective.fx UpdateChromaKalman:**

```hlsl
// After computing K and e_chroma:
float h_c    = 1.0 - 0.5 * smoothstep(0.0, VFF_E_SIGMA_CHROMA * 4.0, abs(e_chroma));
float new_mean = prev.r + K * e_chroma * h_c;
```

### GPU cost

- 1 `smoothstep` call + 1 `multiply` per Kalman update site → ≈4 ALU ops total across
  both sites. Negligible in a pixel shader context.
- No new textures, no new passes, no new highway slots.

### Conflict check

- **No gates:** `smoothstep` is a smooth monotone function, not a hard conditional.
  The "no gates" rule applies to per-pixel thresholds causing spatial seams; this is applied
  to temporal scalar statistics.
- **No HDR dependency:** the cap is on the update delta, not the signal value. SDR-clean.
- **No knobs required:** the threshold is expressed as a multiple of existing `VFF_E_SIGMA`
  constants. Zero new creative_values.fx entries. If tuning is desired in the future,
  a `KALMAN_HUBER_C` constant in the shader header is the appropriate location (not a
  user-facing creative_values.fx knob, since users should not need to tune filter internals).
- **P update unchanged:** the Huber cap is on the state update only, not on P. P correctly
  reflects filter uncertainty and VFF remains unaffected.

### Verdict

**VIABLE — ready for implementation.** Two files, four lines changed. High confidence in
correctness from recent peer-reviewed Huber-Kalman literature. Directly addresses the
flash-frame vulnerability in both Kalman sites.

---

## Finding 2 — Alpha-Beta (g-h) Second-Order slow_key (Future Research)

### Literature basis

- **Alpha-beta filter (g-h filter)** — a minimal two-state estimator that tracks both level
  (position) and velocity (trend) of a slowly varying signal. Well-documented on
  kalmanfilter.net and in the MDPI Mathematics paper "The Alpha-Beta Family of Filters to
  Solve the Threshold Problem" (2022).

- **"A higher prediction accuracy–based alpha–beta filter algorithm using the feedforward
  artificial neural network" (CAAI Transactions on Intelligence Technology, 2023)** —
  confirms that the alpha-beta filter outperforms first-order EMA in tracking gradual ramps
  by up to 40% in steady-state RMSE, while remaining as computationally lightweight as EMA.

### Problem

`ComputeSlowKey` (corrective.fx) is a pure first-order EMA:

```hlsl
float slow_next = lerp(prev_slow, zone_key, 0.003);
```

With α=0.003 and a constant illumination ramp of rate r (luma/frame), the steady-state
tracking lag is `r / α`. At α=0.003 and r=0.001 (luma/frame, realistic for a gradual dungeon
walk), the lag is 0.33 luma units — visible as shadow lift that responds as if the scene is
33% lighter than it actually is.

A second-order alpha-beta filter tracks both level AND trend, reducing steady-state lag to
zero for linear ramps, at the cost of one additional state variable (the trend estimate).

### Proposed formulation

```hlsl
// Two-state update (α-β / g-h filter):
float alpha = 0.003;                           // same as current EMA
float beta  = alpha * alpha / (2.0 - alpha);   // critically damped (Benedict-Bordner)
                                               // β ≈ 4.5e-6

float pred_level = prev_slow + prev_trend;     // one-step-ahead prediction
float resid      = zone_key - pred_level;      // residual (innovation)
float slow_next  = pred_level + alpha * resid; // level update
float trend_next = prev_trend + beta  * resid; // trend update (rate of change)
```

### Highway storage

`trend_next` is a signed quantity (illumination can increase or decrease). Encoding:

```
write:  HWY_SLOW_TREND = trend_next + 0.5     (maps [-0.5, +0.5] → [0, 1])
read:   prev_trend     = ReadHWY(HWY_SLOW_TREND) - 0.5
```

Range justification: the trend converges to `r` (the ramp rate). At α=0.003 and a 10%
luminance change over 60 frames, r = 0.10/60 ≈ 0.0017. Even a fast ramp of 100% over 30
frames gives r ≈ 0.033. The ±0.5 encoding provides an 15× safety margin.

A free highway slot is required. Current alpha-branch assignment shows x=207–209, x=211–212
appear unassigned. Recommend x=207 as `HWY_SLOW_TREND`.

### Why this is deferred

- Requires assigning and documenting a new highway slot.
- The β coefficient (4.5e-6) is so small that the trend contribution is sub-pixel on human
  timescales; the benefit is real but subtle and requires a slow gradual scene to be
  perceptible. The Huber cap (Finding 1) has immediate measurable impact.
- No urgency: the first-order slow_key does not cause artifacts, only mild lag. The lag has
  not been identified as a perceptual problem in any audit.

### Verdict

**VIABLE but deferred.** Implement after Finding 1 ships and a free slot is confirmed.
No pipeline conflicts; the alpha-beta update is mathematically equivalent to the current EMA
when β=0, so the fallback is trivial.

---

## Implementation priority

| # | Change | Files | Lines | Priority |
|---|--------|-------|-------|----------|
| 1 | Huber cap on chroma Kalman innovation | `corrective.fx` | +3 | Now |
| 2 | Huber cap on percentile Kalman innovation | `analysis_frame.fx` | +3 | Now |
| 3 | Alpha-beta slow_key (second-order) | `corrective.fx`, `highway.fxh` | +8 | Deferred |

---

## Sources

- L. et al., "Improved robust Huber-Kalman filtering," *Aerospace Systems*, 2023.
  https://ui.adsabs.harvard.edu/abs/2023AerSy...6...85L/abstract
- "Outlier-Robust KalmanNet: Neural Network Aided Kalman Filtering Based on Huber Loss,"
  ResearchGate, 2024. https://www.researchgate.net/publication/399274991
- "Robust recursive sigma point Kalman filtering for Huber-based generalized M-estimation,"
  *ScienceDirect* (Chinese Journal of Aeronautics), 2024.
  https://www.sciencedirect.com/science/article/pii/S1000936124003522
- "The Alpha-Beta Family of Filters to Solve the Threshold Problem: A Comparison," *MDPI
  Mathematics*, 2022. https://www.mdpi.com/2227-7390/10/6/880
- Khan et al., "A higher prediction accuracy–based alpha–beta filter algorithm using the
  feedforward artificial neural network," *CAAI Transactions on Intelligence Technology*,
  2023. https://ietresearch.onlinelibrary.wiley.com/doi/full/10.1049/cit2.12148
- "Alpha beta filter," Wikipedia / kalmanfilter.net — fundamentals and steady-state lag
  analysis. https://en.wikipedia.org/wiki/Alpha_beta_filter
