# Research Findings — Sage-Husa Q Adaptation (Kalman Filter) — 2026-05-03

## Status: Implemented — `corrective.fx`

---

## Problem

The Kalman filters in `SmoothZoneLevelsPS` and `UpdateHistoryPS` used
instantaneous innovation `(y - ŷ)²` to drive the process noise Q. A single
bright flash (e.g. explosion, muzzle flash) produced a very large innovation,
which spiked Q and drove the filter gain K toward 1.0 for several frames after
the flash. The filter "forgot" its accumulated history and tracked the flash
transient rather than the steady-state scene.

---

## Physical / mathematical basis

Sage-Husa (1969) adaptive Kalman filter: instead of deriving Q from the current
innovation, derive it from the posterior covariance P — the accumulated estimate
of how uncertain the state estimate is. P grows slowly when the state is stable
and shrinks when measurements confirm the model. It does not spike on single
outlier measurements, making the gain K robust to transient disturbances.

The update rule changes from:

```
Q = alpha * (y - ŷ)²          // innovation-driven — spikes on flash
```

to:

```
Q = beta * P_posterior          // posterior-P-driven — smooth, transient-resistant
```

where `beta` is a small mixing coefficient (typically 0.01–0.05).

---

## Implementation

`corrective.fx` — `SmoothZoneLevelsPS` and `UpdateHistoryPS`:

```hlsl
// Before (innovation-driven):
float innov  = y - y_hat;
float Q_new  = KALMAN_BETA * innov * innov;

// After (posterior-P-driven):
float Q_new  = KALMAN_BETA * P_posterior;
```

2 lines changed across both passes.

---

## Effect

- Single-frame flashes no longer cause multi-frame gain spikes.
- Kalman gain K remains smooth between cuts and transients.
- Scene-key (zone_log_key) and chroma history converge faster after cuts
  because the filter is not spending frames recovering from a flash-induced
  gain excursion.

---

## GPU cost

Zero — same ALU path, constant substitution.

---

## References

- Sage, A.P., Husa, G.W. (1969). "Adaptive filtering with unknown prior
  statistics." *Proceedings of the Joint Automatic Control Conference*, 760–769.
- R87 (2026-05-03): Lateral telecommunications research — Sage-Husa identified
  as high-ROI candidate for Kalman stabilization.
- R28 (2026-04-30): Original Kalman temporal history implementation.
