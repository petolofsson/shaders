# R134 — Print Stock Shoulder Correction: Research Proposal
**Date:** 2026-05-08
**Stage:** Stage 1 (Film Stock) — correctness fix, not novelty work

---

## Problem statement

The R51 print stock emulsion in `ColorTransformPS` uses this shoulder formula:

```hlsl
float3 shoulder = 1.0 - (1.0 - ps) * (1.0 - ps) * 1.8;
ps = lerp(toe, shoulder, smoothstep(0.0, 0.5, ps));
```

The coefficient 1.8 makes the shoulder **expand** highlights rather than compress them.
At `lin=0.80`, the pixel exits R51 at ~0.932 (after curve) and ~0.866 (after lerp at
PRINT_STOCK=0.50). A warm sandy building at L≈0.80 gets pushed to L≈0.87 — deeper
into R133's active zone — and subsequently desaturated toward white. The formula would
need a coefficient ≥ 5 before it even begins to compress highlights below the input.

The toe is correct: `ps² × 3.2` darkens shadows as film does. Only the shoulder is wrong.

Real Kodak 2383 print stock has a characteristic D-logE curve with:
- A linear latitude section (constant slope = gamma)
- A **compressive shoulder** where log-exposure in bright zones maps to less density
  increase — highlights roll off rather than clip

The current implementation produces a contrast-expansion S-curve (darks darker, brights
brighter) rather than a film characteristic curve (darks darker, midtones boosted,
highlights compressed).

---

## Research goals

1. **Kodak 2383 actual H-D curve shape** — what does the density-vs-log-exposure
   curve look like for 2383 print stock? Where is the shoulder onset? How steep is
   the linear section? What is the approximate gamma (slope)?

2. **Correct shoulder formula** — what mathematical form best approximates the 2383
   compressive shoulder in HLSL? Candidates:
   - Reinhard: `ps / (1.0 + ps * k)` — asymptote at 1/k
   - Power: `1.0 - (1.0 - ps)^(1/n)` — compresses for n > 1
   - Cubic Bezier approximation of measured H-D curve
   - Smooth exponential approach: `1.0 - exp(-k * ps) * (1.0 - ps)`
   - Piece-wise: linear section + compressed shoulder above a knee point

3. **Where should the shoulder onset be?** — at what exposure (relative to the scene
   median) does the 2383 shoulder begin? In Oklab L terms, what is the equivalent
   threshold? The current knee `fc_knee` (~0.80–0.90) is the right order of magnitude
   but may not match 2383 data.

4. **Black lift and toe interaction** — R51 applies a 0.025 black lift before the curve.
   Does the shoulder correction interact with this? Should the toe remain as `ps² × 3.2`
   or does the real 2383 toe have a different shape?

5. **Existing implementations** — how do established open-source film emulation tools
   (AgX, darktable filmic, OpenColorIO ACES transforms) model the 2383 shoulder? What
   formulas do they use? Any HLSL-suitable closed forms?

6. **Constraint: no gates** — the new shoulder must be a smooth function with no
   hard thresholds on pixel properties. The existing `smoothstep(0.0, 0.5, ps)` blend
   between toe and shoulder is acceptable (it's luminance-gated, not pixel-property-gated).

---

## Hypotheses to validate or refute

- **H1:** The 2383 shoulder onset is around log-exposure 0.5–1.0 stops above the
  mid-exposure point, placing it in the L=0.70–0.85 range in Oklab. The current
  `fc_knee` (~0.80–0.90) is approximately correct.

- **H2:** A Reinhard-style shoulder `min(ps, ps / (1.0 + (ps - knee) * k))` above
  the knee point cleanly replaces the current formula with correct compressive behavior
  and costs no extra GPU ops.

- **H3:** The toe formula `ps² × 3.2` is a reasonable approximation for 2383 shadow
  behavior and does not need replacement.

- **H4:** The existing `desat_w` midband desaturation in R51 is physically correct and
  should be retained unchanged.

---

## Constraints

- Drop-in replacement for the shoulder formula inside the existing R51 block.
- No new passes, textures, or per-pixel branches.
- SPIR-V safe — no `static const float[]`, no `out` variable names.
- Result must be a smooth monotone function mapping [0,1] → [0,1].
- Must compress highlights (output ≤ input for ps above knee), not lift them.
- `PRINT_STOCK` lerp (line 367) remains the strength control — formula change only.

---

## Deliverable

`R134_2026-05-08_printstock_shoulder_findings.md` covering:
- 2383 H-D curve data (numeric if available)
- Recommended shoulder formula + coefficient values
- Comparison table: old formula vs. new at ps = 0.70, 0.75, 0.80, 0.85, 0.90, 0.95
- Verdict on toe (keep or replace)
- Stage 1 novelty impact (fix only — score should not change)
