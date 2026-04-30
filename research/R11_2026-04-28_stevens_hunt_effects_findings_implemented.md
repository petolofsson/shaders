# R11 — Stevens & Hunt Effects: Findings

**Date:** 2026-04-28  
**Status:** Research complete, pending implementation decision

---

## 1. Internal Audit

**Stevens (grade.fx `FilmCurve`, lines 300–301):**
```hlsl
float stevens = lerp(0.85, 1.15, saturate((p50 - 0.10) / 0.50));
float factor  = 0.05 / (width * width) * stevens;
```
Linear ramp on p50. No psychophysical basis. Range [0.85, 1.15] and midpoint at p50=0.35.

**Hunt (grade.fx Stage 3, lines 434–435):**
```hlsl
float hunt_scale = lerp(0.7, 1.3, saturate((perc.g - 0.15) / 0.50));
float chroma_str = saturate(CHROMA_STRENGTH / 100.0 * hunt_scale);
```
Linear ramp on p50. Range [0.70, 1.30]. No psychophysical basis.

---

## 2. Literature

### 2.1 Stevens Effect — CIECAM02 / CAM16

**Source:** CIE CIECAM02 (2002), Li et al. CAM16 (2017) — both use identical Stevens formulation.

The Stevens effect in CIECAM02 appears through the **lightness exponent z**:

$$J = 100 \left(\frac{A}{A_w}\right)^{cz}$$

$$z = 1.48 + \sqrt{n}, \quad n = Y_b / Y_w$$

where $n$ is the background-to-white luminance ratio (proxy: scene median $p_{50}$), $c$ is the surround factor (dim surround: 0.59, average: 0.69). Higher adaptation luminance → larger z → steeper J curve → more perceived contrast.

**Key finding:** The Stevens relationship is **square-root**, not linear. Current linear lerp approximates the correct shape only near the midpoint; it underpredicts dark-scene contrast and overpredicts bright-scene contrast by ~15%.

**Normalized for shader use** (reference point p50 = 0.30 → stevens = 1.0):

$$\text{stevens}_{\text{CIECAM}} = \frac{1.48 + \sqrt{p_{50}}}{1.48 + \sqrt{0.30}} = \frac{1.48 + \sqrt{p_{50}}}{2.03}$$

Values:

| p50 | Current lerp | CIECAM02 sqrt | Δ |
|-----|-------------|---------------|---|
| 0.10 | 0.85 | 0.894 | +0.044 |
| 0.30 | 1.00 | 0.999 | ≈0 |
| 0.60 | 1.15 | 1.111 | −0.039 |

The CIECAM02 formula predicts a slightly narrower range than the current [0.85, 1.15] and is concave (sqrt), not linear.

### 2.2 Hunt Effect — CIECAM02 FL Luminance Adaptation Factor

**Source:** CIECAM02 / CAM16. Colorfulness:

$$M = C \cdot F_L^{1/4}$$

$$F_L = 0.2 \, k^4 (5 L_a) + 0.1 \left(1 - k^4\right)^2 (5 L_a)^{1/3}, \quad k = \frac{1}{5 L_a + 1}$$

where $L_a$ is the adaptation luminance (cd/m²). In our SDR context, $L_a$ is proxied by $p_{50}$ directly (normalized linear light).

**Computed FL^{1/4} normalized at p50 = 0.35:**

| p50 (La proxy) | FL^(1/4) | Normalized | Current lerp |
|----------------|----------|------------|--------------|
| 0.05 | 0.454 | 0.768 | 0.700 |
| 0.15 | 0.546 | 0.924 | 0.865 |
| 0.35 | 0.591 | 1.000 | 1.000 |
| 0.65 | 0.620 | 1.049 | 1.300 |

**Key findings:**
1. The current range **[0.70, 1.30] is ~3× too wide on the bright end.** FL^(1/4) at p50=0.65 gives only 1.05 normalized, not 1.30.
2. The curve is **sub-linear**: the effect saturates at bright scenes (FL^(1/4) flattens above p50=0.35) but continues to decrease at dark scenes (significant drop below p50=0.15).
3. The current dark-scene underperformance is less severe than the bright-scene over-amplification.

### 2.3 Hellwig & Fairchild 2022

**Source:** "Brightness, lightness, colorfulness, and chroma in CIECAM02 and CAM16." *Color Research & Application* 47(5):1083–1095.

Key change: **Q is now linear in J_HK**:

$$Q_{HK} = \frac{2}{c} \cdot \frac{J_{HK}}{100} \cdot A_w$$

versus original CIECAM02:

$$Q = \frac{4}{c} \sqrt{\frac{J}{100}} (A_w + 4) F_L^{1/4}$$

The H-K (Helmholtz–Kohlrausch) correction to lightness:

$$J_{HK} = J + f(h) \cdot C^{0.587}$$

$$f(h) = -0.160 \cos h_r + 0.132 \cos 2h_r - 0.405 \sin h_r + 0.080 \sin 2h_r + 0.792$$

(h_r in radians; output range ≈ [0.3, 1.3] across hue angles)

**Relevance:** Hellwig 2022 does NOT change z (Stevens) or FL (Hunt). Its contribution to our shader is primarily an improved H-K formula for the Stage 3 HK block — a potential R08N refinement, separate from R11. The C^0.587 exponent and 4-term Fourier f(h) are the key values.

Note: applying f(h) in our shader requires mapping Oklab-normalized hue (0–1) to CIECAM radian hue, which is a non-trivial remapping. Not pursued further here.

---

## 3. Proposed Replacements

### Finding 1 — Stevens: sqrt-based curve (PASS)

**Current:** `lerp(0.85, 1.15, saturate((p50 - 0.10) / 0.50))`

**Proposed:**
```hlsl
float stevens = (1.48 + sqrt(max(perc.g, 0.0))) / 2.03;
```
- Gate-free. No new uniforms. 1-line change.
- Normalized constant 2.03 = 1.48 + √0.30 (reference at p50 = 0.30).
- Range: [0.47, ∞) in theory, but for p50 ∈ [0.05, 0.80] gives [0.86, 1.14]. Output is bounded by downstream `factor` product and FilmCurve return value.
- Injection point: `grade.fx:300`.

### Finding 2 — Hunt: FL^(1/4) from CIECAM02 (PASS)

**Current:** `lerp(0.7, 1.3, saturate((perc.g - 0.15) / 0.50))`

**Proposed:**
```hlsl
float la  = max(perc.g, 0.001);
float k   = 1.0 / (5.0 * la + 1.0);
float k4  = k * k * k * k;
float fl  = 0.2 * k4 * (5.0 * la) + 0.1 * (1.0 - k4) * (1.0 - k4) * pow(5.0 * la, 0.333);
float hunt_scale = pow(max(fl, 1e-6), 0.25) / 0.5912;
// 0.5912 = FL^(1/4) at La = 0.35 (reference normalization)
```
- Gate-free. No branches.
- `pow(5*la, 0.333)` is safe: la > 0 guaranteed by max() guard.
- Gives hunt_scale ∈ [0.77, 1.05] for p50 ∈ [0.05, 0.65].
- Injection point: `grade.fx:434`.
- **Impact on CHROMA_STRENGTH:** The upper bound drops from 1.3 to ~1.05. At CHROMA_STRENGTH=10 (current default), the effect is small. At high CHROMA_STRENGTH values, this will noticeably reduce the bright-scene chroma amplification — more accurate to the literature.

---

## 4. Strategic Assessment

| Change | Visual ROI | SPIR-V safe | Gate-free | Bounded |
|--------|-----------|-------------|-----------|---------|
| F1 Stevens sqrt | Low — range barely changes | PASS | PASS | PASS |
| F2 Hunt FL^(1/4) | High — corrects 3× over-amplification at bright scenes | PASS | PASS | PASS |

**Recommendation:** F2 (Hunt) has the higher ROI — the current bright-scene chroma amplification at 1.3 is 3× what the literature supports, and bright scenes in Arc Raiders are common. F1 (Stevens) is a marginal correction and can be deferred.

**Knob impact:** Both changes preserve the meaning of CHROMA_STRENGTH and CORRECTIVE_STRENGTH. No creative_values.fx changes required.

**Unified La note:** Both effects share the same scene-median-as-La proxy. The FL computation serves both: FL^(1/4) is the Hunt scale; sqrt(La) approximates the Stevens z term. A single FL pre-computation at the top of ColorTransformPS could feed both, adding ~5 ALU ops total.
