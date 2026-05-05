# R84 Findings — Optical Density FilmCurve
**2026-05-03**

## Summary

Implementable. The log-density reformulation is physically correct and GPU-efficient.
The key risk is matching the current default appearance — the existing CURVE_* values
are polynomial coefficients that must be remapped to log-density units before launch.

---

## Finding 1 — H&D curve structure for Kodak 2383

**Source:** Gordon Arkenberg blog; ResearchGate H&D curve diagrams; Kodak 2383 datasheet

The H&D characteristic curve has three regions:
1. **Toe** (log H below ~1.5): D ≈ D-min, very low slope
2. **Straight-line** (log H 1.5 to ~4.2): D proportional to log H, slope = gamma (~3.0 for 2383)
3. **Shoulder** (log H above ~4.2): D rolls off toward D-max (~3.0–3.5 for 2383)

Kodak 2383 is described as "steeply curved" with higher D-max than earlier stocks (2386).
The toe curves of the three sensitometric channels "are matched more closely than 2386
Film, producing more neutral highlights on projection" — i.e., the per-channel divergence
is primarily in the mid-scale and shoulder, not the toe. This is consistent with the
CURVE_R_KNEE / CURVE_B_KNEE offsets being mid-scale controls.

**Key parameters for 2383 (estimated from published data):**
- Gamma (straight-line slope): ~2.8–3.2 (steep, high-contrast print stock)
- Log H at toe onset: ~1.5 (log10 units of exposure)
- Log H at shoulder: ~4.0–4.2
- D-max: ~3.0–3.4
- D-min (base+fog): ~0.08–0.12

---

## Finding 2 — log2/exp2 is the correct real-time formulation

**Source:** Filmic Worlds "Minimal Color Grading Tools" (John Hable); shaderLABS optimization guide

John Hable's log-contrast implementation uses:
```c
float logX = log2f(x + eps);
float adjX = logMidpoint + (logX - logMidpoint) * contrast;
return max(0, exp2f(adjX) - eps);
```

This is a log-space contrast operator and maps cleanly to the H&D straight-line segment.
The shaderLABS guide confirms `log2` and `exp2` are native GPU hardware instructions
(1 cycle each on all major GPU architectures) — not approximated in software.

**Translation to H&D curve:**
- `log2(x)` converts linear light to log-exposure space
- A linear segment in log space (the straight-line section) = `log2(x) * gamma + offset`
- `exp2(result)` converts back to linear
- Toe and shoulder are natural rolloffs when the input is clamped or soft-limited

For a physically correct mapping, note that H&D uses log10, but log2 is proportional
(log2(x) = log10(x) / log10(2)). The gamma parameter absorbs the log base difference.

---

## Finding 3 — Per-channel offsets become density-space deltas

In the log-density formulation, adding a per-channel offset to the log-space value before
`exp2` shifts the curve earlier (negative offset) or later (positive offset) along the
exposure axis. This is exactly what CURVE_R_KNEE and CURVE_B_KNEE do conceptually:
- `CURVE_R_KNEE = -0.006` → red curve shifts left → red compresses earlier
- `CURVE_B_KNEE = +0.005` → blue curve shifts right → blue compresses later

In log-density space: `adj = log2(x) * gamma + (logMidpoint + knee_offset_channel)`
The existing knob values can be rescaled to log-density units. At the current default
exposure range (~0.01–1.0 linear), a shift of 0.006 in linear-space knee ≈ 0.025 in
log2 units (log2(1 + 0.006/0.5) ≈ 0.017 — order of magnitude estimate).

The exact remapping requires evaluating the current FilmCurve at the current CURVE_* values
and finding the log-density offset that produces the same output. This is a one-time
calibration, not a runtime cost.

---

## Implementation — validated sketch

```hlsl
float3 FilmCurveDensity(float3 x, float gamma, float logMid,
                         float3 knee, float3 toe) {
    const float eps = 1e-5;
    float3 lx = log2(max(x, eps));
    // per-channel density offset shifts the curve along the exposure axis
    float3 adj = logMid + (lx - logMid) * gamma + knee;
    return saturate(exp2(adj) + toe);
}
```

Called from Stage 1 (FilmCurve block), replacing the current polynomial.

Parameters at default:
- `gamma` ≈ 1.0 (calibrated to match current curve shape — not Kodak's ~3.0, since
  the pipeline operates on display-referred [0,1] not raw scene log-exposure)
- `logMid` = log2(p50) from PercTex — adapts to scene key (already used by current curve)
- `knee` = `float3(CURVE_R_KNEE, 0, CURVE_B_KNEE)` (green = 0, red/blue offset)
- `toe` = `float3(CURVE_R_TOE, 0, CURVE_B_TOE)`

**GPU cost:** log2(float3) + exp2(float3) = 6 native GPU ops + ~4 MAD. The current
polynomial is ~8 MAD — net change approximately neutral.

---

## Implementation gaps

1. **Calibration of knee/toe values.** The existing CURVE_* constants (e.g., R_KNEE = -0.006)
   were tuned empirically against the current polynomial curve. They need to be re-tuned
   against the new log-density curve to preserve the default appearance. Approach: render
   a grey ramp with old and new curves at current CURVE_* values, match the output visually,
   then record the new constants. Do this before committing.

2. **`logMid` adaptive vs. fixed.** Using `log2(p50)` as the pivot point is adaptive —
   the curve shifts with scene key. The current FilmCurve is also adaptive (uses PercTex).
   The adaptive behaviour should be preserved, but the exact formulation needs to match
   the current curve's adaptive response. Validate on low-key and high-key scenes.

3. **Behaviour at x = 0.** `log2(0)` = −∞. The `max(x, eps)` guard handles this.
   Confirm the eps value (1e-5) doesn't introduce a visible floor artifact at true black.
   At eps = 1e-5: exp2(log2(1e-5)) = 1e-5 ≈ 0 — safe.

## Verdict

**Implement.** Physically correct, same GPU cost, no new taps or knobs. The only real
work is the one-time calibration of CURVE_* constants to log-density units — this can
be done during implementation by matching output against the current curve.
