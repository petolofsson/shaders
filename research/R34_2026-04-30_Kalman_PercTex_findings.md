# R34 — Kalman PercTex — Findings
**Date:** 2026-04-30
**Method:** Brave search × 6 queries

---

## Q1 — Q/R values for percentile tracking

**Finding:** No published Q/R priors for percentile tracking in display/ISP pipelines were found; theory
points to Q/R ratio being the primary lever for steady-state gain, and percentiles warrant a lower Q than
zone medians.

The scalar Kalman steady-state gain K_inf ≈ sqrt(Q/R) (for R >> Q), so K_inf scales with sqrt(Q/R). With
Q=0.0001 and R=0.01 (zone-median values), Q/R = 0.01 and K_inf ≈ 0.095. Percentiles aggregate the full
frame (16× more signal than a single zone), so measurement noise R is effectively lower — meaning the
filter already trusts measurements more. To achieve equivalent or greater temporal stability, Q should be
reduced (slower process noise assumption) while R can remain at 0.01 or be reduced modestly. A Q of
0.00003–0.00005 (Q/R ≈ 0.003–0.005) would yield K_inf ≈ 0.055–0.070, meaningfully smoother than zone
medians without losing scene-cut responsiveness.

---

## Q2 — Prior art: Kalman on scene percentiles

**Finding:** No direct prior art for scalar Kalman on image/video scene percentiles was found; adjacent work
uses Kalman on histogram noise (audio), quantile regression + Kalman for price series, and EKF/UKF for
non-Gaussian state spaces.

IEEE Xplore (query 1) surfaced a paper applying Kalman with quantile-based noise estimation to audio
restoration — structurally similar but in 1-D signal, not 2-D scene statistics. ScienceDirect surfaced
Quantile Regression + Kalman for electricity price forecasting, where temporal quantile state is tracked
with small Q (process assumed slow). Neither paper gives explicit Q/R values for visual statistics. The
closest ISP work (query 3) returned no results, confirming this application is novel with no established
industry baseline. The absence of prior art means the R28 zone-median values (Q=0.0001, R=0.01) are the
best available empirical starting point; percentile-specific values must be derived from first principles
or empirical tuning.

---

## Q3 — Cold-start and scene-cut behavior

**Finding:** Standard Kalman practice initialises P_0 to a large value (high uncertainty) so the filter
converges quickly; for display statistics this means the first-frame estimate should be set to the raw
histogram percentile with P_0 = R (or higher), letting K drop toward K_inf over ~10–20 frames.

The DSP Stack Exchange thread (query 4) confirms a scalar Kalman is equivalent to a first-order IIR whose
bandwidth is set by Q/R at steady state. At cold-start, P_0 >> Q causes K ≈ 1 (full trust in the
measurement), which is correct — the filter adopts the first histogram read immediately, then smooths from
frame 2 onward. For scene cuts the same property applies: a sudden luminance shift drives a large
innovation, P temporarily rises, K rises toward 1, and the filter re-acquires quickly. No explicit
scene-cut reset mechanism is needed. MATLAB/Simulink documentation (query 4) recommends setting P_0 = R
as a safe default for slow-varying signals; that means P_0 = 0.01 for this application. The
"Implementing a Kalman Filter" Losant article notes that adaptive-R variants (adjusting R based on
residuals) improve both cold-start and scene-change response — a candidate future enhancement (R35).

---

## Recommended constants

```hlsl
#define KALMAN_Q_PERC  0.00003  // ~1/3 of zone-median Q; percentiles integrate full frame → slower true drift
#define KALMAN_R_PERC  0.01     // same as zone medians; CDF-walk output has comparable read noise
// K_inf = sqrt(Q/R) ≈ sqrt(0.003) ≈ 0.055
// Compare zone medians: Q=0.0001, R=0.01, K_inf≈0.095
// P_0 = 0.01  (= R, gives K≈1 on frame 0 → cold-start equals raw histogram)
```

Rationale for Q reduction: percentiles are whole-frame aggregates over a temporally smoothed histogram
(EMA alpha≈0.072 already pre-smooths). The true drift rate of p25/p50/p75 between frames is lower than
zone medians because spatial averaging suppresses local transients. Q/R ≈ 0.003 keeps K_inf well below
the EMA alpha (0.072), ensuring the Kalman is strictly smoother than the status quo. If empirical testing
shows over-lag on fast cuts, raising Q to 0.00005 (K_inf ≈ 0.070) is the next step.

---

## Summary

| Question | Answer |
|----------|--------|
| Q/R for percentiles | Lower Q than zone medians: Q≈0.00003, R=0.01, K_inf≈0.055. Percentiles are slower-varying due to full-frame spatial integration. |
| Prior art | No direct prior art for Kalman on image/video scene percentiles. Adjacent: audio Kalman + quantile noise (IEEE), quantile-regression + Kalman for price series (ScienceDirect). Application is novel. |
| Cold-start | Set P_0 = R = 0.01; this forces K≈1 on frame 0 so filter immediately adopts the first histogram read. Scene cuts self-correct via innovation growth — no explicit reset needed. |

**Implementation ready / blockers:** No blockers — recommended constants are derivable from first principles
and consistent with R28 zone-median empirical baseline; verify K_inf≈0.055 against captured footage for
acceptable scene-cut re-acquisition speed before committing.
