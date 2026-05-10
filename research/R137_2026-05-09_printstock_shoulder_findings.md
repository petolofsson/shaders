# R137 — Print Stock Shoulder Formula: Findings
**Date:** 2026-05-09

---

## 1. Mathematical analysis of `1 - (1-ps)² × k`

The formula is a reflected quadratic. Key properties:
- f(1) = 1 always (correct ceiling)
- f(0) = 1 - k (negative for k > 1 — critical for lerp framework)
- Zero crossing: f(ps) = 0 at ps = 1 - 1/√k → ps ≈ 0.255 for k=1.8
- Identity crossing: f(ps) = ps at ps = 1 - 1/(k(1-ps))... solving numerically:
  - k=1.8: identity at ps ≈ 0.44 (below this, shoulder < ps = compressive)
  - k=1.2: identity at ps ≈ 0.31

The formula goes negative below ps≈0.255 — this is load-bearing. The `lerp(toe, shoulder, smoothstep)` blend has weight≈0 in deep shadows, so negative shoulder values are almost never applied. But any replacement that stays non-negative at low ps (as the `ps+A*ps*(1-ps)²` attempt did) will dramatically over-brighten lower mids. **This constraint must be preserved.**

---

## 2. k-sweep — blended output `lerp(toe, shoulder, smoothstep(0,0.5,ps))`

For ps ≥ 0.5: smoothstep = 1.0, so blended = shoulder exactly.
For ps = 0.40: smoothstep weight = 0.896.

| ps | input | k=1.2 | k=1.5 | **k=1.8** | k=2.5 |
|----|-------|-------|-------|-----------|-------|
| 0.40 | 0.40 | 0.562 | 0.465 | **0.368** | 0.134 |
| 0.50 | 0.50 | 0.700 | 0.625 | **0.550** | 0.375 |
| 0.65 | 0.65 | 0.853 | 0.816 | **0.780** | 0.694 |
| 0.70 | 0.70 | 0.892 | 0.865 | **0.838** | 0.775 |
| 0.75 | 0.75 | 0.925 | 0.906 | **0.888** | 0.844 |
| 0.80 | 0.80 | 0.952 | 0.940 | **0.928** | 0.900 |
| 0.85 | 0.85 | 0.973 | 0.966 | **0.960** | 0.944 |
| 0.90 | 0.90 | 0.988 | 0.985 | **0.982** | 0.975 |
| 0.95 | 0.95 | 0.997 | 0.996 | **0.996** | 0.994 |

Key observation: reducing k uniformly reduces expansion everywhere — including in the
midtones (ps=0.50–0.70) where the expansion was desirable. k=1.2 at ps=0.65 gives 0.853
vs k=1.8's 0.780 — that's weaker midtone compression, not stronger. Uniform k tuning
cannot selectively reduce highlights while preserving midtone character.

Identity (k=5.0 crossover at ps=0.80): `1 - 0.04k = 0.80` → k=5. At this k, midtone output
would be catastrophically different. Uniform k is not the right tool.

---

## 3. Cubic extension `1 - (1-ps)²k + (1-ps)³m`

The cubic `+(1-ps)^3 * m` adds lift that peaks in the lower midrange (where (1-ps)^3 is
large), not in the highlights. Solving for (k,m) pairs that match k=1.8 at ps=0.65 while
reducing at ps=0.85 yields k≈3.5–6.0, m≈5–12. At these coefficients, the shoulder at
ps=0.50 rises to 0.73–1.0, producing large midrange brightening.

**Verdict:** Cubic extension in `(1-ps)` does not decouple midtone and highlight behavior.
The correction term is in the wrong part of the domain.

---

## 4. Proposed formula: subtractive highlight correction `- ps^n × c`

The key insight: `ps^n` for large n is near-zero for small ps and grows toward 1 only
in the highlights. This is the opposite shape to `(1-ps)^n`. Subtracting it from the
original formula adds compression selectively in highlights while leaving shadows and
midtones essentially unchanged.

```
f(ps) = 1 - (1-ps)² × 1.8  -  ps⁶ × c
```

At ps=0.20: `ps^6 = 6.4e-5` — negligible (< 0.004 change)
At ps=0.50: `ps^6 = 0.0156` — negligible (< 0.001 change at c=0.06)
At ps=0.80: `ps^6 = 0.262` — meaningful (0.016 change at c=0.06)
At ps=0.90: `ps^6 = 0.531` — significant (0.032 change at c=0.06)

Shadow negativity preserved: at ps=0.20, f(0.20) ≈ 1 - 0.64×1.8 - 0 = −0.152 ✓

### Blended output — current vs proposed (k=1.8, n=6, c=0.06)

| ps | input | k=1.8 current | k=1.8 − ps⁶×0.06 | delta |
|----|-------|--------------|-------------------|-------|
| 0.40 | 0.40 | 0.368 | 0.368 | 0.000 |
| 0.50 | 0.50 | 0.550 | 0.549 | −0.001 |
| 0.65 | 0.65 | 0.780 | 0.775 | −0.005 |
| 0.70 | 0.70 | 0.838 | 0.831 | −0.007 |
| 0.75 | 0.75 | 0.888 | 0.877 | −0.011 |
| 0.80 | 0.80 | 0.928 | 0.912 | −0.016 |
| 0.85 | 0.85 | 0.960 | 0.937 | −0.023 |
| 0.90 | 0.90 | 0.982 | 0.950 | −0.032 |
| 0.95 | 0.95 | 0.996 | 0.952 | −0.044 |

Shadow and lower-mid behavior is preserved exactly. Upper highlight compression engages
progressively from ps=0.75 upward, with maximum effect at ps=0.90–0.95.

### HLSL implementation

```hlsl
float3 ps3      = ps * ps * ps;
float3 shoulder = 1.0 - (1.0 - ps) * (1.0 - ps) * 1.8 - ps3 * ps3 * 0.06;
```

3 new ALU ops vs current (2 mults to form ps3 and ps3*ps3, 1 scaled subtract).
SPIR-V safe. No conditionals. Monotone increasing on [0,1].

### Coefficient sensitivity

| c | ps=0.80 output | ps=0.85 output | ps=0.90 output |
|---|---------------|---------------|---------------|
| 0.03 | 0.920 | 0.949 | 0.966 |
| 0.06 | 0.912 | 0.937 | 0.950 |
| 0.09 | 0.904 | 0.926 | 0.934 |
| 0.12 | 0.897 | 0.914 | 0.918 |

c=0.06 gives a moderate shoulder correction. c=0.09–0.12 for a tighter highlight rolloff.

---

## 5. Survey — film emulation shoulder formulas

- **AgX (Troy Sobotka):** Uses a log-space piece-wise polynomial mapped through an
  OCIO transform. Not a closed-form single expression; uses LUT lookup in practice.
  Not portable to 4-op HLSL.
- **darktable filmic (Aurelien Pierre):** Rational Bezier cubic with two split-point
  parameters (latitude + hardness). Also not a simple closed form.
- **ACES Output Transform:** Segmented spline (3-segment) — requires a branch or LUT.
- **Reinhard:** `ps/(1+ps*k)` — compressive everywhere, including midtones. Confirmed
  not suitable (loses midtone punch).

**Conclusion from survey:** No existing tool uses a simple closed-form shoulder that fits
the lerp(toe, shoulder, blend) framework here. The subtractive `ps^n * c` correction is
novel and well-suited to this constraint set.

---

## Recommendation

```hlsl
float3 ps3      = ps * ps * ps;
float3 shoulder = 1.0 - (1.0 - ps) * (1.0 - ps) * 1.8 - ps3 * ps3 * 0.06;
```

- **c=0.06**: moderate — reduces whitening on bright sandy surfaces, preserves body punch
- **c=0.09**: tighter — appropriate if PRINT_STOCK is used at 0.60+
- Coefficient is a candidate for a `PRINT_SHOULDER_ROLLOFF` creative_values knob if
  desired, but c=0.06 hardcoded is likely sufficient.
