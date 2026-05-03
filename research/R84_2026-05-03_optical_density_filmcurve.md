# R84 — Optical Density FilmCurve
**2026-05-03 | Stage 1 novel +5%**

## Problem

The current `FilmCurve` fits a sigmoid polynomial to the H&D curve shape in linear light.
Real film H&D curves are defined in optical density units (D = −log₁₀(T)), where the
characteristic curve is a near-linear segment in log-exposure space with natural toe and
shoulder rolloffs.

Working in linear light forces a higher-order polynomial to approximate what is a simpler
function in log-density space. Per-channel offsets (CURVE_R_KNEE, CURVE_B_KNEE, etc.) are
currently empirical polynomial coefficients rather than physically motivated density deviations.

Reformulating in log-density space gives a more accurate shoulder/toe at lower ALU cost,
and the per-channel offsets become proper H&D curve deviations matchable to Kodak 2383
datasheet values.

## Targets

Stage 1 novel: 65% → 70%

## Research questions

1. What are the characteristic H&D curve parameters (gamma/contrast, toe LogH, shoulder LogH)
   for Kodak 2383? Specifically: where does the toe start, where does the shoulder roll off?
2. What log-density sigmoid shape best matches 2383 — logistic, tanh, or the filmic
   `log2/exp2` contrast formulation?
3. How do the current CURVE_R/B KNEE/TOE values map to equivalent log-density offsets?
4. Are there SPIR-V issues with log2/exp2 in this context? (Already used in grade.fx — expected OK.)

## Proposed implementation

Replace FilmCurve sigmoid in Stage 1:

```hlsl
// optical density sigmoid — D = -log10(T), operating in log2 space
float3 FilmCurveLog(float3 x, float gamma, float3 knee, float3 toe) {
    float3 lx = log2(max(x, 1e-5));
    float3 adj = lx * gamma + knee;    // per-channel density offset
    return exp2(adj) + toe;            // back to linear, per-channel toe lift
}
```

CURVE_R_KNEE, CURVE_B_KNEE become density-space offsets (negative = red compresses
earlier in log space). CURVE_R_TOE, CURVE_B_TOE become density-space toe lifts.

GPU cost: log2(float3) + exp2(float3) = 6 native GPU ops. Replaces current polynomial
at approximately the same or lower cost.

## Constraints

- SPIR-V: log2/exp2 on float3 already used in grade.fx (safe)
- No new user knobs — existing CURVE_* names kept, units reinterpreted
- Output range must remain [0,1] — saturate at output
- Must not change default appearance at current CURVE_* = 0 values
