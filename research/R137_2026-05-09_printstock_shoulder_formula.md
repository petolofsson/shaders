# R137 — Print Stock Shoulder Formula: Research Proposal
**Date:** 2026-05-09
**Stage:** Stage 1 (Film Stock) — correctness + feel

---

## Context

The R51 print stock block uses this shoulder formula inside a `lerp(toe, shoulder, blend)` construct:

```hlsl
float3 ps       = lin * (1.0 - 0.025) + 0.025;
float3 toe      = ps * ps * 3.2;
float3 shoulder = 1.0 - (1.0 - ps) * (1.0 - ps) * 1.8;
ps = lerp(toe, shoulder, smoothstep(0.0, 0.5, ps));
```

The shoulder formula `f(ps) = 1 - (1-ps)² × k` with k=1.8 has two important properties
that must be preserved by any replacement:

1. **Goes negative at low ps** — below ps≈0.255 (where `(1-ps)² > 1/k`), f(ps) < 0.
   This is not a bug. The lerp blend weight is near-zero in deep shadows
   (smoothstep(0,0.5,ps)≈0 for ps<0.2), so the negative shoulder is almost never reached.
   But any replacement formula must behave similarly — staying low or negative at low ps
   — so the lerp produces correct shadow darkening from the toe side.

2. **Always reaches exactly 1.0 at ps=1.0** — f(1) = 1 by construction.

The problem with k=1.8: in the 0.75–0.95 range, the formula expands too aggressively.
At ps=0.80, output=0.928 (+16%). This was contributing to highlight whitening.

A Reinhard partial shoulder (`ps - d + d/(1 + d*k)`, knee=0.55) was tried and reverted
because it produced less brightening in the 0.50–0.70 range than the original, losing
the "body" character. A `ps + A*ps*(1-ps)²` form was tried and also reverted because
it was always non-negative — breaking assumption 1 — causing more midrange brightening
than the original.

---

## Research goals

### 1. Mathematical analysis of `1 - (1-ps)² × k`

- What is the shape of this curve? Where does it cross ps (identity)? Where does it
  cross zero?
- How does it behave as a shoulder within the lerp(toe, shoulder, smoothstep) framework?
  What does the *blended output* `lerp(toe, shoulder, smoothstep(0,0.5,ps))` look like
  at key ps values for k=1.8?
- Is there a standard name for this functional form in curve design literature?

### 2. What adjusting k does

- Compute the blended output (not just shoulder alone) for k = 0.9, 1.2, 1.5, 1.8, 2.5
  at ps = 0.50, 0.65, 0.75, 0.80, 0.85, 0.90, 0.95.
- At what k value does the shoulder output at ps=0.80 match the input (identity)?
- At what k value does it give moderate expansion (~+5% at ps=0.80) vs aggressive (~+15%)?

### 3. Generalised family — adding a higher-degree term

The current formula is quadratic. A cubic extension:
`f(ps) = 1 - (1-ps)² × k + (1-ps)³ × m`

- How does adding the cubic term change the shape? Where does the extra degree of freedom
  sit in the output?
- Can m be tuned to compress the 0.80-0.95 range while leaving the 0.50-0.75 range
  identical to k=1.8?
- What constraint on m ensures f(ps) < ps (compressive, not expansive) above a given threshold?

### 4. Quadratic Bezier / Hermite shoulder

- Is there a quadratic Bezier curve passing through (0,0), (1,1) with a control point
  at (p_knee, y_knee) that:
  a) Goes negative for ps < p_cross (preserving assumption 1)?
  b) Has less expansion than k=1.8 in the 0.80-0.95 range?
  c) Is evaluable in ~3 HLSL ops (like the current formula)?

### 5. Survey: how do other film emulation tools handle the shoulder in display-referred SDR?

- AgX (Troy Sobotka): what formula does the shoulder use?
- darktable filmic: what is the shoulder equation?
- DaVinci Resolve FilmCurve node: is the shoulder documented?
- Any HLSL/GLSL print emulation implementations with a tunable shoulder that fits
  within ~4 ALU ops?

---

## Constraints

- Formula must be evaluable as `float3 shoulder = f(ps)` in HLSL — no conditionals,
  no tex lookups, no iterative solvers.
- Must go negative (or at least ≤ 0) for ps near 0 so the lerp framework is preserved.
- Must hit exactly f(1) = 1.
- Must be monotone increasing on [0,1].
- Target: expansion at ps=0.75 similar to current k=1.8, but ~50% less expansion
  at ps=0.85-0.90.
- SPIR-V safe — no `static const float[]`, no `out` variable name.

---

## Deliverable

`R137_2026-05-09_printstock_shoulder_findings.md` with:
- Full blended output table for the k-sweep (goal 2)
- Cubic extension analysis (goal 3) — recommended (k, m) pair if viable
- Bezier option (goal 4) — viable or not, with reasoning
- Survey results (goal 5)
- Recommended formula + coefficients
- Comparison table: current vs proposed at ps = 0.50, 0.65, 0.75, 0.80, 0.85, 0.90, 0.95
  showing BLENDED output (not shoulder alone)
