# R44 — Signal-Dependent Gain — Findings
**Date:** 2026-04-30
**Searches:**
1. Signal-dependent gain / noise-dependent sharpening — two-sided suppression in image enhancement
2. Decision Feedback Equalizer nonlinear gain — sqrt magnitude signal detection
3. Perona-Malik edge-stopping functions — sqrt(|x|) and anisotropic diffusion comparators
4. Unsharp mask threshold / noise-floor suppression — clarity and sharpening literature
5. Wavelet shrinkage / soft threshold — Donoho-Johnstone, sqrt gain, denoising
6. 8-bit linear quantisation noise floor — LSB step size, SDR thresholding

---

## Key Findings

### 1. Signal-dependent gain in image enhancement

Literature uses "signal-dependent noise" (SDN) extensively (Schuler et al., Fourier analysis
of SDN images, *Scientific Reports* 2024; Canadian J. Physics 1983) but the dominant framing
is *noise estimation*, not gain shaping. The proposal inverts this: instead of estimating noise
to subtract it, it shapes the gain so that noise-level inputs receive near-zero amplification.
This is equivalent to a signal-dependent *multiplicative shrinkage* applied before the
enhancement operator.

No paper was found that uses the exact term "two-sided signal-dependent gain" in the context
of sharpening. However, the concept is strongly implicit in the Perona-Malik literature (see §3)
and in threshold-based unsharp masking (see §4). The proposal is novel in combining both effects
in a single rational function rather than a separate threshold gate.

### 2. Decision Feedback Equalizer analogue

DFE nonlinear feedback (ScienceDirect overview; MDPI *Photonics* 2025 — MA-DFE for PAM4) uses
signal amplitude information to weight the error function. The MDPI paper explicitly states:
"utilizes signal amplitude information to construct the error function, which is robust to carrier
phase noise." The Stanford Cioffi DFE textbook chapter notes that intermediate results involve
`1/sqrt()` computations in matrix square-root factorisation of the optimum filter.

The DFE analogy is *architecturally* sound: in DFE, decisions near the noise floor are
de-weighted; decisions near the expected signal level are trusted. The proposed `g = sd/(sd+c)`
maps cleanly onto this concept with `sd = sqrt(|detail|)` acting as a signal magnitude proxy.
The analogy is heuristic, not a formal derivation — which is appropriate for a real-time shader.

### 3. Perona-Malik and sqrt(|x|) edge-stopping functions

Perona and Malik (1990) defined the canonical edge-stopping function as:

```
c(x) = 1 / (1 + (|∇I|/K)²)       [PM1 — Cauchy bell in gradient space]
c(x) = exp(-(|∇I|/K)²)           [PM2 — Gaussian bell]
```

Both are *one-sided* (large gradient → stop diffusion; small gradient → diffuse freely).
This is precisely the bell's failure mode: PM1 = the existing `bell = 1/(1+d²/0.0144)`.
The PM model is the image-processing formalisation of the current implementation.

Multiple PM extension papers (ScienceDirect 2015; Hindawi 2020; Wiley 2020; Semantic Scholar
"Generalised PM") propose replacing the Cauchy/Gaussian with functions that also suppress
at very small gradients to reduce noise amplification in flat regions. The Hindawi 2020 paper
on Caputo-Fabrizio fractional PM explicitly redefines the energy functional as "an increasing
function of the absolute value of the image intensity fractional derivative" to suppress noise
while preserving edges — exactly the zero-at-floor behaviour of `g`.

The proposed `g = sqrt(|d|)/(sqrt(|d|)+c)` is a rational approximation to a *monotonically
increasing* edge-stopping surrogate. It does not stop diffusion at large gradients; instead it
relies on clarity_mask and auto_clarity for hard-edge containment. This departs from the PM
philosophy but is valid in a composed pipeline where those upstream limiters exist.

**Key comparison — PM1 vs. proposed g:**

| |detail| | PM1 bell (K²=0.0144) | proposed g (c=0.04) |
|---------|---------------------|---------------------|
| 0.000   | 1.000 (no suppress) | 0.000 (floor killed)|
| 0.005   | 0.998               | 0.527               |
| 0.040   | 0.900               | 0.833               |
| 0.120   | 0.500               | 0.933               |
| 0.400   | 0.083               | 0.980               |

At `|detail|=0.005` (noise floor), PM1 applies 99.8% strength; g applies 53% — a factor ×1.9
suppression. At `|detail|=0.04` (real texture), PM1 and g are within 7.6% of each other.
At `|detail|=0.12` (hard edge), g applies 87% more strength than PM1 — this is the regime
where clarity_mask must do the work PM1 previously did.

### 4. Unsharp mask noise suppression — threshold literature

Wikipedia, Adobe, and Cambridge In Colour documentation all confirm that the **Threshold**
parameter in unsharp masking is the canonical way to suppress noise-floor sharpening:
"controls the minimal brightness change that will be sharpened... to prevent smooth areas from
becoming speckled." The recommended threshold for photographic work is 3–10 (on a 0–255 scale),
corresponding to 0.012–0.039 in linear [0,1] space.

The proposed constant `c = 0.04` places the g=0.5 knee at `|detail| = c² = 0.0016`, and g
reaches 0.83 at `|detail| = 0.04` — numerically consistent with the USM threshold literature's
"3–10" range. This is not coincidence: the USM threshold and the g constant both parametrise
the same underlying noise floor.

The key difference between USM threshold and `g`: USM threshold is a *hard gate* (below
threshold → zero gain; above → full gain) with a visible seam. `g` is a *soft gate*, rising
continuously from zero — consistent with the project's no-gates rule.

### 5. Wavelet shrinkage / soft threshold — relationship to g

Donoho and Johnstone (1994, 1995) define:
- **Hard threshold:** `η_H(x) = x · 𝟙(|x| > λ)` — hard gate
- **Soft threshold:** `η_S(x) = sign(x)·max(|x|−λ, 0)` — shifts coefficients toward zero

Neither is the same as `g`. Soft threshold is a *subtractive* shrinkage; g is a *multiplicative*
gain. However, the multiplicative form `x · g(|x|)` applied here is known in the literature as
a **"non-negative garrote"** or **firm threshold** (Gao 1998, Bruce & Gao 1996). The garrote
estimator is:

```
η_G(x) = x · max(1 - λ²/x², 0)
```

The proposed g does not match the garrote exactly, but shares its key properties:
- Multiplicative (output is d · g, not d − λ)
- Continuous at zero
- Monotonically increasing toward identity for large |d|

The closest named function in signal processing is a **half-wave soft-knee compressor** or
**Michaelis-Menten saturation function** (from enzyme kinetics / pharmacology), which has the
form `x/(x+K)` — exactly `sd/(sd+c)` in sqrt-domain. In signal processing this is also called
a **Hill function** with exponent 1 (Hill 1910). In image processing, the Michaelis-Menten form
appears in retinal adaptation and tone-mapping models (Naka-Rushton equation).

**Therefore:** `g = sqrt(|d|)/(sqrt(|d|)+c)` is equivalent to a **Naka-Rushton / Michaelis-
Menten gain function applied in the sqrt(|detail|) domain.** It is not a standard shrinkage
function but belongs to a well-studied family of saturating gain functions used in visual
science and tone-mapping.

### 6. Quantisation noise floor — 8-bit linear SDR

From quantisation theory (Wikipedia; DSP Guide ch.3):
- 8-bit linear [0,1]: step size = 1/255 ≈ **0.00392**
- RMS quantisation noise = (1/255)/sqrt(12) ≈ **0.00113** per channel
- Peak-to-peak quantisation error = ±0.00196 (±0.5 LSB)

For a Laplacian high-pass `detail = luma − blur(luma)`, the noise in `detail` is the
difference of two quantised values, so the effective noise floor doubles:
- RMS detail noise ≈ 2 × 0.00113 = **0.00226**
- Peak detail noise ≈ 2 × 0.00196 = **0.00392** (≈ 1 LSB)

The proposed g at `|detail| = 0.004` (1 LSB):
```
sd = sqrt(0.004) ≈ 0.0632
g  = 0.0632 / (0.0632 + 0.04) ≈ 0.613
```

**This means 1-LSB quantisation noise receives 61% gain — not full suppression.** The knee
at g=0.5 falls at `|detail| = 0.04² = 0.0016`, i.e., ~0.4 LSB — below the peak quant error.
In practice, real texture detail in Arc Raiders is typically |detail| ≈ 0.03–0.10 (measured
from nightly histogram data), so the gain at 0.04 (g≈0.83) is appropriate for texture.

However, quantisation noise at 1 LSB receives g≈0.61 vs. PM1's g≈0.998 — a 39% reduction in
noise amplification. This is meaningful but not full suppression.

**To push noise suppression lower:** reduce `c` from 0.04 toward 0.02:
- At c=0.02: g(0.004) = sqrt(0.004)/(sqrt(0.004)+0.02) = 0.0632/0.0832 ≈ **0.76** — less suppression
- At c=0.02: g(0.04) = 0.2/0.22 ≈ **0.91** — higher texture gain

Counterintuitively, reducing `c` moves the knee *lower* (toward noise floor) and *raises* gain
everywhere above it. The most noise-suppressive setting is not the smallest `c` — it is the
largest `c` that still passes real texture at acceptable strength. `c=0.04` is in the right
range given the quantisation analysis.

---

## Literature Support

| Claim | Support level | Source |
|-------|--------------|--------|
| PM1 bell is identical to existing bell — one-sided by design | **Strong** | PM (1990); Wikipedia Anisotropic diffusion |
| Zero-at-floor gain suppresses noise in flat regions | **Strong** | Multiple PM extension papers; USM threshold docs |
| g = x/(x+c) is a Michaelis-Menten / Naka-Rushton gain | **Strong** | Signal processing / visual science literature |
| sqrt-domain application of Michaelis-Menten is novel | **Moderate** | No direct precedent found; sqrt(|x|) appears in PM fractional derivative extensions |
| DFE amplitude-weighting as conceptual analogue | **Moderate** | MDPI Photonics 2025; Cioffi DFE textbook |
| g is a non-negative garrote analogue | **Moderate** | Gao 1998; Bruce & Gao 1996 garrote estimator concept |
| USM threshold 3–10 maps to |detail| ≈ 0.012–0.039 | **Strong** | Adobe; Peachpit; Cambridge In Colour |
| 1-LSB quantisation noise at 0.004 receives g≈0.61 | **Strong** | Quantisation theory (Wikipedia; DSP Guide) |

---

## Parameter Validation

### c = 0.04 — what it actually means

- g=0.5 knee: `|detail| = c² = 0.0016` ≈ 0.41 LSB (below typical quantisation noise peak)
- g=0.83 at `|detail| = 0.04` — real texture peak region
- g=0.93 at `|detail| = 0.12` — hard-edge region (clarity_mask territory)
- Quantisation noise (1 LSB ≈ 0.004) receives g ≈ 0.61 — 39% less than PM1's near-unity gain
- The constant is perceptually well-placed but does not fully gate quantisation noise

### SPIR-V safety of sqrt(abs(x)) at x=0

`abs(x)` is defined for all real inputs including x=0; result is 0.0 exactly.
`sqrt(0.0)` returns 0.0 in IEEE 754 (no NaN, no infinity).
`g = 0.0 / (0.0 + 0.04) = 0.0` — arithmetically clean, no divide-by-zero.
No `out`-keyword or static-const-array issues. **SPIR-V safe.**

### Degradation with R43 energy-normalised detail_wp

`detail_wp` (R43) is a weighted sum of D1–D4 with energy normalisation, dimensionally
equivalent to `detail`. Its range is the same [−1, +1] real-valued. The g function depends
only on `|detail|` magnitude — composing cleanly with any monotonic rescaling of the
detail signal. The energy normalisation in R43 does not change the sign or domain; g is
scale-agnostic within the relevant magnitude range. **No degradation expected.**

---

## Risks and Concerns

### 1. Hard-edge clarity boost stronger than PM1
At `|detail| > 0.12`, g > 0.93 vs. PM1's < 0.50. In the absence of R43, clarity_mask must
carry the entire burden of hard-edge suppression. The current clarity_mask rolls off linearly
toward zero above luma 0.6 and is fully zero above 0.9. For bright hard edges (specular
highlights, white lettering) this is sufficient. For dark edges in mid-luma (e.g., metal
rivet vs. concrete — luma ≈ 0.4, |detail| ≈ 0.15) clarity_mask may be non-zero and g ≈ 0.93,
giving ~10% stronger clarity than PM1 at these locations. Monitor for haloing artifacts in
dark-field hard edges.

### 2. Noise floor suppression not complete at 1 LSB
g(0.004) ≈ 0.61 — reduces noise-floor amplification by 39% vs. PM1. This is improvement,
not elimination. Observers expecting full noise gating (like USM hard threshold) will perceive
a subtle difference rather than a dramatic one in very flat areas.

### 3. Perceptual character change
PM1 gave "soft clarity" — midtones boosted, extremes symmetrically limited, a gentle quality.
g gives "texture-selective" clarity — noise floor reduced, texture passed at ~83% of PM1's
peak, hard edges passed more freely. The literature prediction (USM sources; PM extension
papers) is that this reads as **cleaner** rather than **softer**. Skin tones and smooth gradients
will show less sharpening noise; textured surfaces will appear similarly sharpened. The loss
of the PM1 bell's "softening" at hard edges is the main risk — mitigated by clarity_mask.

### 4. g is monotonically increasing — no built-in two-sided suppression
The proposal brief describes g as "suppresses BOTH extremes of the wrong kind." This is only
partially accurate. g suppresses noise at `|detail| ≈ 0` (correct). It does NOT suppress
haloing at large `|detail|` — it passes near-unity. The "two-sided" character relies on
clarity_mask for the upper side. If the proposal is evaluated in isolation (without
clarity_mask), hard-edge haloing will be stronger than with PM1. The composed system is
two-sided; the g function alone is one-sided (but in the opposite direction from PM1).

---

## Verdict

**Proceed with implementation — with monitoring conditions.**

The proposal is theoretically grounded:
- The Michaelis-Menten / Naka-Rushton gain family is well-established in visual science
  and tone-mapping; applying it in sqrt(|detail|) domain is an incremental, defensible extension
- The noise-floor suppression improvement is real (39% reduction at 1-LSB level) and
  directionally correct relative to PM1
- SPIR-V safe, no new passes, no new knobs, composes cleanly with R43
- The USM threshold literature validates `c ≈ 0.04` as numerically appropriate for the
  SDR pipeline's noise regime

**Conditions for approval:**
1. Test standalone (without R43) first — confirm no haloing on dark-field hard edges
2. Specifically observe metal/concrete boundaries in mid-luma (luma ≈ 0.3–0.5, |detail| ≈ 0.1–0.2)
3. Compare flat wall / sky regions for noise-floor character — expect "cleaner" not "softer"
4. If haloing appears in standalone test, reduce `auto_clarity` by 10% or add small
   Bell coefficient `0.1 * PM1 + 0.9 * g` as a blended transition — do not change c

**Best deployment:** R43 first, then R44 composed. Valid standalone with monitoring.
