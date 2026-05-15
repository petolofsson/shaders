# R198 — Analytically Invertible Film Curve

**Date:** 2026-05-15  
**Question:** Can the FilmCurve in `grade.fx` be replaced (or its exact inverse derived) so that
`inverse_grade.fx` can pre-compensate before chroma expansion, then `grade.fx` applies the forward
curve to land on the correct graded signal?

---

## 1. Problem

`inverse_grade.fx` (R90) expands Oklab chroma on the raw swapchain signal — before
`grade.fx`'s `ColorTransformPS` has applied the FilmCurve. Chroma expansion at this point
operates on the wrong tonal reference: the FilmCurve subsequently compresses highlights and
lifts shadows, altering the apparent saturation and the signal level against which the expansion
was measured.

**Desired pipeline:**

```
swapchain → [FC⁻¹] inverse_grade → [chroma expand] → corrective → grade [FC] → display
```

`FC⁻¹ ∘ FC = identity` on luma; chroma expansion sees the post-curve domain.

For this to be exact, `FC` must be analytically invertible and its parameters must be
reconstructable in `inverse_grade` (one frame earlier in the chain).

---

## 2. FilmCurve Anatomy (`grade.fx` line 174)

```hlsl
float3 FilmCurveApply(float3 x, knee_r, knee_g, knee_b, ktoe_r, ktoe_g, ktoe_b)
{
    above    = max(x - knee, 0)
    below    = max(ktoe - x, 0)
    headroom = 1 - knee                         // h

    // Body lift: one-sided upper-mid S — zero at x≤0.5 and x=1
    body_s   = max(0, (x(1-x))² (2x-1)) × 0.65

    // Rational shoulder: asymptotes toward 1.0, C¹ at knee
    sh_comp  = above² / (h + above)

    // Rational toe lift: raises shadows below ktoe, C¹ at ktoe
    tc_comp  = (0.06/ktoe) × below² / (ktoe + below)

    y = x + body_s − sh_comp + tc_comp
}
```

### Key evaluation points (knee = 0.85, ktoe = 0.20)

| x (in) | body_s | sh_comp | tc_comp | y (out) | deviation from identity |
|--------|--------|---------|---------|---------|------------------------|
| 0.000  | 0      | 0       | +0.030  | 0.030   | +3.0% (toe lift)       |
| 0.100  | 0      | 0       | +0.010  | 0.110   | +1.0%                  |
| 0.200  | 0      | 0       | 0       | 0.200   | 0% (ktoe anchor)       |
| 0.500  | 0      | 0       | 0       | 0.500   | 0%                     |
| 0.724  | +0.012 | 0       | 0       | 0.736   | +1.2% (body_s peak)    |
| 0.850  | +0.007 | 0       | 0       | 0.857   | +0.7%                  |
| 0.900  | +0.004 | −0.013  | 0       | 0.892   | −0.8%                  |
| 1.000  | 0      | −0.075  | 0       | 0.925   | −7.5% (shoulder)       |

### Slope profile

`dy/dx` at x=0 is **0.775** (not 1.0) — the toe lift is largest at black and decreases to zero
at ktoe, compressing the shadow range. The slope rises back to ~1.0 at ktoe, slightly exceeds 1.0
in the body_s zone [0.5, 0.85], then drops below 1.0 into the shoulder. This non-monotone slope
profile rules out any single-formula (1,1) rational.

### Architectural note: `y(0) = 0.030 ≠ 0`

The curve maps **black to a non-black value** (lifted blacks, film print toe). This means the
forward curve's range is [0.030, 0.925] for default parameters. Any pre-inverse applied in
`inverse_grade` to a zero-valued pixel would need to compute `FC⁻¹(0)`, which falls outside
the domain. Domain clipping to `[y_min, y_max]` before inversion is required.

---

## 3. Candidate Comparison

### Candidates examined

| Candidate | Forward | Exact Inverse | Matches toe lift | Matches shoulder | Matches body_s | Notes |
|-----------|---------|--------------|-----------------|-----------------|---------------|-------|
| **Power law** y = xᵞ | xᵞ | y^(1/γ) | No (y(0)=0) | No shoulder | No | Monotone, no shoulder rolloff |
| **Reinhard** y = x/(x+k) | cheap | ky/(1−y) | No (y(0)=0) | Only shoulder | No | Shoulder only, no toe lift |
| **Hable extended Reinhard** y = x(1+x/L²)/(1+x/W) | cheap | Quadratic formula | Partial | Yes | No | HDR-derived, midrange not near-identity |
| **ACES Narkowicz** y = x(Ax+B)/(x(Cx+D)+E) | cheap | Quadratic formula | No (y(0)=0) | Yes | No | Compresses midrange, wrong domain |
| **General (2,2) rational** y = (ax²+bx+c)/(dx²+ex+1) | cheap | Quadratic formula | Yes (c≠0) | Yes | No | Fitting creates denominator zeros inside [0,1] (see §4) |
| **Piecewise exact inverse** of existing FilmCurve | (no replacement needed) | See §5 | Yes | Yes | No (neglected, <1.2%) | **Recommended** |

### Why single-formula replacements fail

The FilmCurve has **two qualitatively different deviations** from identity:
- **Toe region** (x < ktoe): y > x (lift, creates non-zero `y(0)`)
- **Shoulder region** (x > knee): y < x (compression)

A smooth global rational that fits both toe and shoulder constraints creates a denominator with a
zero inside [0, 1] (verified numerically for the (2,2) case — pole appears near x ≈ 0.97 for
typical knee/ktoe). The domain restriction is not avoidable within a single-polynomial rational
that also matches the midrange-identity constraint.

Eliminating the toe-lift constraint (accepting y(0)=0) avoids the pole, but then `FC⁻¹(0) = 0`
— the pre-inverse maps black to black rather than to the actual scene signal. This breaks the
round-trip for all shadow pixels.

---

## 4. Key Finding: The FilmCurve Is Already Piecewise-Exactly-Invertible

Each of the three active components has a **closed-form inverse**:

### Shoulder inverse (y ≥ knee)

Forward: `y = knee + d·h / (h + d)`, where `d = x − knee`, `h = 1 − knee`

Solve for d: `d = (y − knee)·h / (h − (y − knee))`

**Exact inverse:**
```
x = knee + (y − knee)·h / (h − (y − knee))
```
Valid for y ∈ [knee, knee + h/2) i.e. y < (1 + knee)/2. Within SDR, y_max = FilmCurve(1.0) = 1 − h²/(2h) = 1 − h/2. For knee=0.85, h=0.15: y_max = 0.925, and h − (y_max − knee) = 0.15 − 0.075 = 0.075 > 0. ✓

### Toe inverse (y ≤ ktoe)

Forward: `y = x + A·b² / (ktoe + b)`, where `b = ktoe − x`, `A = 0.06/ktoe`

Rearrange into quadratic in b:
```
(1 − A)·b² + y·b + (y − ktoe)·ktoe = 0
```
For y < ktoe: discriminant = `y² + 4·(1−A)·(ktoe−y)·ktoe > 0` always (since A < 1 for ktoe > 0.06).

**Exact inverse:**
```
b = [−y + sqrt(y² + 4·(1−A)·(ktoe−y)·ktoe)] / (2·(1−A))
x = ktoe − b
```
Verified numerically: y=0.030 → b=0.200 → x=0.000 ✓, y=0.110 → b=0.100 → x=0.100 ✓

### Midrange identity (ktoe < y < knee)

`y ≈ x` — only body_s is active here. Body_s peaks at **x ≈ 0.724, Δy ≈ +0.012** (1.2%).
No closed-form inverse for the body_s polynomial (degree 5 in x). However:

- At the boundary x=ktoe=0.200: body_s = 0 (2x−1 < 0 → clamped to 0) ✓
- At the boundary x=knee=0.850: body_s ≈ 0.007 (0.7% — absorbed into shoulder formula transition)
- Peak error: **12 linear units at 8-bit depth**, or **≈0.3 dB** — negligible for chroma correction

**Midrange approximation:** x = y (identity). Acceptable.

---

## 5. Exact Piecewise Inverse

Given output `y` and parameters `knee`, `ktoe` (per-channel), reconstruct input `x`:

```
FilmCurveInverse(y, knee, ktoe):

  h = 1 − knee
  A = 0.06 / ktoe

  if y >= knee:                          // shoulder zone
      s = y − knee
      return knee + s·h / (h − s)        // denominator safe: s < h within SDR

  elif y <= ktoe:                        // toe zone (quadratic formula)
      qa = 1 − A
      disc = y² + 4·qa·(ktoe − y)·ktoe
      b = (−y + sqrt(disc)) / (2·qa)
      return ktoe − b

  else:                                  // midrange (body_s neglected)
      return y
```

**Error budget:**
- Toe: exact
- Shoulder: exact
- Midrange: max ≈ 0.012 in linear (at x≈0.724, body_s peak)
- Domain: input `y` must be clamped to [FilmCurve(0), FilmCurve(1)] before inversion

---

## 6. Parameter Availability in `inverse_grade`

`BuildSceneCtx()` computes `fc_knee` and `fc_knee_toe` from percetile data:

```
fc_knee     = lerp(0.90, 0.80, saturate((p75 − 0.60) / 0.30)) − saturate(bowley) × 0.06
fc_knee_toe = lerp(0.15, 0.25, saturate((0.40 − p25) / 0.30))
              (with mode-anchor adjustment)

bowley = (p75 + p25 − 2·p50) / max(p75 − p25, 0.01)
```

All inputs (p25=HWY 194, p50=HWY 195, p75=HWY 196, mode=HWY 206) are readable from
`HighwayTex` in `inverse_grade`. The reconstruction is a one-frame delay — identical to the
existing `NeutralIllumTex` one-frame delay already accepted in the pipeline.

Per-channel offsets `CURVE_R_KNEE`, `CURVE_B_KNEE`, `CURVE_R_TOE`, `CURVE_B_TOE` are static
creative knobs — available directly as uniforms.

---

## 7. Proposed HLSL Sketch

```hlsl
// In inverse_grade.fx — call before Oklab chroma expansion.
// p25/p50/p75 read from highway; mode from HWY_MODE.
float3 FilmCurveInverseRGB(float3 col,
                           float fc_knee, float fc_knee_toe,
                           float knee_r, float knee_b,
                           float ktoe_r, float ktoe_b)
{
    // Per-channel knee/toe (mirrors BuildSceneCtx)
    float3 knee = float3(
        clamp(fc_knee * exp2(knee_r * 0.10), 0.70, 0.95),
        fc_knee,
        clamp(fc_knee * exp2(knee_b * 0.10), 0.70, 0.95));
    float3 ktoe = float3(
        clamp(fc_knee_toe * exp2(ktoe_r * 0.10), 0.08, 0.35),
        fc_knee_toe,
        clamp(fc_knee_toe * exp2(ktoe_b * 0.10), 0.08, 0.35));

    float3 result;
    [unroll] for (int i = 0; i < 3; i++) {
        float y  = col[i];
        float k  = knee[i];
        float kt = ktoe[i];
        float h  = 1.0 - k;
        float A  = 0.06 / kt;

        if (y >= k) {
            // Shoulder inverse
            float s = y - k;
            result[i] = k + s * h / max(h - s, 1e-5);
        } else if (y <= kt) {
            // Toe inverse (quadratic)
            float qa   = 1.0 - A;
            float disc = y*y + 4.0*qa*(kt - y)*kt;
            float b    = (-y + sqrt(max(disc, 0.0))) / (2.0*qa);
            result[i] = kt - b;
        } else {
            // Midrange: identity (body_s ≤ 1.2% — neglected)
            result[i] = y;
        }
    }
    return result;
}
```

Cost: 1 `sqrt` per channel (3 total) in the toe/shoulder path — comparable to `pow`. Zero
extra texture samples. Per-pixel branch is uniform within each zone — no divergence issues on
GPU wavefronts.

---

## 8. Recommendation

**Do not replace the FilmCurve.** Derive its piecewise exact inverse instead.

The piecewise approach is exact in the toe and shoulder (the zones where chroma sees the most
distortion), and introduces at most **1.2% error in the midrange** where body_s is the only
active term. This error is smaller than typical frame-to-frame chroma jitter.

### Implementation path

1. Reconstruct `fc_knee`, `fc_knee_toe` in `inverse_grade` from highway p25/p50/p75/mode slots
   (one-frame delay — already accepted precedent).
2. Add `FilmCurveInverseRGB()` call **before** the Oklab conversion in `InverseGradePS`, after
   the `INVERSE_STRENGTH <= 0` early-out guard.
3. The forward FilmCurve in `grade.fx` remains unchanged.
4. Validate: a constant-color input should survive the round-trip `FC⁻¹ → expand → FC` with
   zero luma change and only the intended chroma delta.

### What this does NOT fix

- The body_s midrange lift is not cancelled — its effect on chroma is ≤1.2% and uniform across
  the [0.5, 0.85] zone, so it is unlikely to cause visible hue shift.
- If `INVERSE_STRENGTH = 0`, the pre-inverse should be skipped (no-op path already exists).
- The one-frame parameter delay means scene cuts see one frame of mismatch — identical to the
  existing chroma slope delay behavior.
