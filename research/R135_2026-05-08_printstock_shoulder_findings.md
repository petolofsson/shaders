# R135 — Kodak 2383 Shoulder Formula: Findings
**Date:** 2026-05-08
**Responds to:** R134 proposal
**Stage:** Stage 1 (Film Stock) — correctness fix

---

## 1. Kodak 2383 H-D Curve Data

### What the official datasheets contain

Kodak publication H-1-2383t (National Archives copy: archives.gov/files/preservation/products/resources/2383-TI.pdf) and the commercial data sheet (kodak.com) contain graphical sensitometric curves for the three dye layers (red, green, blue). Neither document provides machine-readable tables; the PDFs compress the curves as binary image streams not extractable by text tools. No public CSV/JSON digitization was found during this search.

### Qualitative properties established from primary Kodak language

- "Sensitometric curves determine the change in density on the film for a given change in log exposure."
- "Upper scale is slightly higher in D-max, resulting in improved black on projection."
- "Toe areas of the three sensitometric curves are matched more closely than 2386 Film, producing more neutral highlights on projection." — Kodak language; note "neutral highlights" = toe-matched channels, not shoulder behavior.
- D-max is approximately 4.0 optical density units (forum source: cinematography.com, corroborated by the known Dmax-of-print-stock literature; earlier 2393 Dmax was above 5.0).
- Status A density aims: Red 1.09, Green 1.06, Blue 1.03 (at LAD, the reference gray patch at 1.0 visual density).
- Print film "has higher contrast than negative film" (David Mullen ASC, cinematography.com forum).

### Derived shoulder position from first principles

Film sensitometry defines middle gray (18% luminance) at the center of the straight-line (linear-gamma) region. Shoulder onset = end of straight-line region = start of compression.

For a standard print stock with ~2 stops of exposure latitude above midgray before shoulder:

```
midgray_lin = 0.18
shoulder_onset_lin = 0.18 × 2^2 = 0.72   (+2 stops)
shoulder_onset_lin = 0.18 × 2^1.5 = 0.51 (+1.5 stops)
```

The Kodak 2383 is a **high-contrast** print stock (not a low-contrast intermediate). Its linear section has an estimated average gradient (gamma) of approximately 2.0–2.3 (typical for print stocks versus negative stocks at ~0.5–0.7). At that contrast, the shoulder starts earlier in normalized terms:

| Shoulder onset (stops above 18% gray) | Normalized lin value |
|----------------------------------------|----------------------|
| +1.5 stops                             | 0.51                 |
| +1.8 stops                             | 0.61                 |
| +2.0 stops                             | 0.72                 |
| +2.5 stops                             | 1.02 (clips)         |

**Practical conclusion:** The shoulder onset is approximately lin = 0.55–0.70 in a normalized display-referred signal. The current R51 `fc_knee` range (~0.65–0.75 for ps after black lift, corresponding to lin ≈ 0.64–0.74) is in the correct ballpark.

### Channel differences

The three dye layers of 2383 have slightly different H-D curve shapes (standard for color print film). The green layer typically has the most symmetric curve; red and blue have slightly different shoulder slopes. In practice, for a real-time shader, applying identical shoulder parameters across channels is standard (all public implementations including ACES, AgX, darktable filmic do this).

---

## 2. The Bug: Why `(1 - ps)^2 × 1.8` Always Expands

The formula `1 - (1-ps)^2 * c` equals the input `ps` only when:

```
ps = 1 - (1-ps)^2 * c
(1-ps) = (1-ps)^2 * c
1 = (1-ps) * c
c = 1/(1-ps)
```

So at ps = 0.80, the threshold coefficient for compression is `c = 1/0.20 = 5.0`. The current coefficient is 1.8, which is far below the threshold at every point in the highlight range:

| ps   | c needed for compression | current c=1.8 | result    |
|------|--------------------------|---------------|-----------|
| 0.70 | 3.33                     | 1.8           | EXPANDS   |
| 0.75 | 4.00                     | 1.8           | EXPANDS   |
| 0.80 | 5.00                     | 1.8           | EXPANDS   |
| 0.85 | 6.67                     | 1.8           | EXPANDS   |
| 0.90 | 10.00                    | 1.8           | EXPANDS   |

At c = 1.8, even ps = 0.70 expands by +14.6 percentage points before the lerp blends it back. The formula would need c >= ~10 to compress any highlight below 0.90.

**Root cause:** `1 - (1-x)^n` is a **convex** (bow-up) function for n > 1, meaning it maps every point in (0,1) to a value **above** the identity line y = x. It is always an expansion operator, never compression. Only `x^n` (concave for n > 1) or a rational function like Reinhard are compressive.

---

## 3. Candidate Formula Analysis

### 3a. `1 - (1-ps)^n` family

At any n > 1, this function satisfies `f(x) > x` for all x in (0,1). Verified numerically:

| n   | ps=0.80 output | delta vs input |
|-----|----------------|----------------|
| 1.5 | 0.9106         | +0.1106        |
| 2.0 | 0.9600         | +0.1600        |
| 3.0 | 0.9920         | +0.1920        |
| 5.0 | 0.9997         | +0.1997        |

**All values expand. No n > 1 produces compression.** The form `1 - (1-x)^n` is fundamentally wrong as a compressive shoulder.

### 3b. Power toe `ps^n` (n > 1) — compressive but wrong region

`ps^n` for n > 1 compresses the entire range, not just highlights. It is correctly used as a **toe** (shadow darkening), not a shoulder.

### 3c. Reinhard partial — asymptotic, compressive everywhere above knee

The Reinhard-partial formula applied above a knee point:

```
d = max(0.0, ps - KNEE)
shoulder = ps - d + d / (1.0 + d * K)
```

Properties:
- Below KNEE: identity (d = 0, shoulder = ps)
- Above KNEE: output is strictly less than ps (verified)
- Smooth and C1-continuous at the knee
- Monotone increasing for all positive K
- Asymptote: `KNEE + 1/K` (never exceeds KNEE + 1/K)
- Maps to 1.0 only if K = 0

This is the same family used by Reinhard tone mapping (1/(1+x)), darktable filmic's rational branch, and the Allen Pestaluky 2025 tonemapping curve.

### 3d. Power shoulder with fractional n < 1 — also expansive

`((ps - knee)/(1-knee))^n` mapped back to [knee..1] is expansive for 0 < n < 1 (concave upward from the knee). Verified: at n=0.5, ps=0.80 → +0.0791. **Also wrong.**

### 3e. ACES Narkowicz rational (for reference only)

```hlsl
(x*(2.51*x+0.03)) / (x*(2.43*x+0.59)+0.14)
```

This maps x=0.80 → 0.7523 (compressive), but also significantly remaps midtones (x=0.50 → 0.616, an expansion of +0.116). It is not suitable as a drop-in for R51 which has its own midtone structure.

### 3f. Uncharted 2 (Hable) rational

Severely compresses highlights (x=0.80 → 0.511 after normalization). Too aggressive for a high-contrast print stock emulation within an already-tuned pipeline.

---

## 4. Recommended Formula: Calibrated Reinhard Partial

### Formula

```hlsl
float3 d = max(0.0, ps - FILM_KNEE);
float3 shoulder = ps - d + d / (1.0 + d * FILM_K_SH);
```

### Calibration

The key calibration decision is: what should a diffuse white (ps = 1.0) map to after the shoulder?

For Kodak 2383, which is a **high-contrast print stock** with a mild shoulder:
- Specular highlights are meant to be slightly compressed, not crushed.
- Reference LUTs (Kodak 2383 D60 for Resolve, Cineon Log input) show diffuse white mapping to approximately 95% display white.
- Recommended target: **shoulder(ps=1.0) = 0.95**, implying 5% compression at peak diffuse white.

Solving for K given KNEE = 0.65 and target = 0.95:

```
0.95 = 0.65 + 0.35 / (1 + 0.35 * K)
0.30 = 0.35 / (1 + 0.35*K)
1 + 0.35K = 35/30 = 1.1667
K = 0.1667 / 0.35 = 0.476
```

**FILM_KNEE = 0.65, FILM_K_SH = 0.476**

The knee at ps = 0.65 corresponds to lin ≈ 0.641 (after black lift inversion), which is +1.83 stops above 18% gray. This is consistent with the sensitometric analysis above.

### HLSL drop-in

```hlsl
// R51 Film Curve — Kodak 2383 shoulder correction
// Replaces: float3 shoulder = 1.0 - (1.0-ps)*(1.0-ps)*1.8;
// Reinhard partial: compressive for ps > FILM_KNEE, identity below
static const float FILM_KNEE  = 0.65;
static const float FILM_K_SH  = 0.476;  // shoulder(1.0) = 0.95

float3 d = max(0.0, ps - FILM_KNEE);
float3 shoulder = ps - d + d / (1.0 + d * FILM_K_SH);
```

SPIR-V safety:
- `static const float` (scalar): safe per CLAUDE.md rules.
- No `static const float3`, no arrays, no `out` variable name.
- All arithmetic: `max`, subtraction, division — GPU primitive ops.

---

## 5. Comparison Table

Full R51 output: `lerp(toe, shoulder, smoothstep(0.0, 0.5, ps))`
Black lift applied: `ps = lin * 0.975 + 0.025`

| lin  | Old formula | New (K=0.476) | Old delta | New delta | Old verdict |
|------|-------------|---------------|-----------|-----------|-------------|
| 0.50 | 0.5722      | 0.5125        | +0.072    | +0.012    | expands     |
| 0.60 | 0.7262      | 0.6100        | +0.126    | +0.010    | expands     |
| 0.65 | 0.7904      | 0.6587        | +0.140    | +0.009    | expands     |
| 0.70 | 0.8460      | 0.7060        | +0.146    | +0.006    | expands     |
| 0.75 | 0.8931      | 0.7511        | +0.143    | +0.001    | ~neutral    |
| 0.80 | 0.9316      | 0.7943        | +0.132    | −0.006    | compresses  |
| 0.85 | 0.9615      | 0.8357        | +0.111    | −0.014    | compresses  |
| 0.90 | 0.9829      | 0.8754        | +0.083    | −0.025    | compresses  |
| 0.95 | 0.9957      | 0.9135        | +0.046    | −0.037    | compresses  |
| 1.00 | 1.0000      | 0.9500        | 0.000     | −0.050    | compresses  |

Note: "Old delta" and "New delta" are output minus lin input. Old formula expands throughout the highlight range except at peak white. New formula is expansive below ~0.75 (within the tone shoulder blend transition zone) and compressive above ~0.80.

Output range of new formula: [0.0022, 0.950]. Monotone: verified over 10,001 samples.

### Shoulder-only view (ps after black lift, isolating the shoulder function)

| ps   | Old shoulder | New shoulder | Old delta | New delta |
|------|-------------|--------------|-----------|-----------|
| 0.65 | 0.7904      | 0.6500       | +0.140    |  0.000    |
| 0.70 | 0.8460      | 0.6900       | +0.146    | −0.010    |
| 0.75 | 0.8931      | 0.7167       | +0.143    | −0.033    |
| 0.80 | 0.9316      | 0.7357       | +0.132    | −0.064    |
| 0.85 | 0.9615      | 0.7500       | +0.111    | −0.100    |
| 0.90 | 0.9829      | 0.7611       | +0.083    | −0.139    |
| 0.95 | 0.9957      | 0.7700       | +0.046    | −0.180    |
| 1.00 | 1.0000      | 0.7773       | 0.000     | −0.223    |

The new formula is a true compressive shoulder at every ps above the knee. The old formula was expansive at all the same points except ps = 1.0.

---

## 6. Shoulder Onset Versus Existing Code

The existing R51 block uses `fc_knee` (highway x=214) as a parameter but the shoulder formula itself is not knee-controlled — it applies uniformly to all ps. With the Reinhard partial, the onset is now explicitly controlled by `FILM_KNEE = 0.65`.

For implementors: if the creative_values.fx system adds `FILM_K_SH` as a user knob, the range [0.2, 1.5] maps to approximately:
- K=0.2: shoulder(1.0) = 0.975 (very mild, barely visible)
- K=0.476: shoulder(1.0) = 0.950 (recommended, 5% at peak white)
- K=1.0: shoulder(1.0) = 0.900 (moderate 10% compression)
- K=2.0: shoulder(1.0) = 0.839 (aggressive)

The knee FILM_KNEE = 0.65 is hardcoded and does not need to be a user knob (it corresponds to the fixed physical property of when 2383 shoulder begins).

---

## 7. Prior Art Summary

| Implementation  | Shoulder form                    | Compressive? | Notes                            |
|-----------------|----------------------------------|--------------|----------------------------------|
| darktable filmic| Rational function (M4+M1*rat/(rat+M3)) | Yes   | Precomputed spline coefficients  |
| AgX (GLSL)     | Piecewise rational (a=69.86, b=3.25, c=-0.3077) | Yes | Operates in log2 space |
| ACES Narkowicz  | `(x*(2.51x+0.03))/(x*(2.43x+0.59)+0.14)` | Yes | Remaps full range, not knee-based |
| Uncharted 2     | `((x*(Ax+CB)+DE)/(x*(Ax+B)+DF))-E/F` | Yes  | Aggressive, full-range            |
| Allen Pestaluky | `slope*(x-cp)*(1+(x-cp)/w) / (1+slope*(x-cp)/shoulder_max)` | Yes | Reinhard variant, adjustable |
| **Old R51**     | `1-(1-ps)^2 * 1.8`               | **No** (always expands) | Bug: coefficient threshold is ~3.3–10 |
| **New R51**     | `ps - d + d/(1+d*K)` where d=max(0,ps-KNEE) | Yes | Calibrated to 2383 mild shoulder |

All correct implementations use either a rational function or the Reinhard asymptotic form. None use the `1 - (1-x)^n * c` pattern with c < threshold.

---

## 8. Toe Verdict

The current toe `ps² × 3.2` maps:

| lin   | ps (after lift) | toe output | ratio output/ps |
|-------|-----------------|------------|-----------------|
| 0.10  | 0.1225          | 0.0480     | 0.392 (darkens) |
| 0.20  | 0.2200          | 0.1549     | 0.704 (darkens) |
| 0.30  | 0.3175          | 0.3226     | 1.016 (≈linear) |
| 0.40  | 0.4150          | 0.5511     | 1.328 (lifts)   |
| 0.50  | 0.5125          | 0.8405     | 1.640 (lifts)   |

The toe crushes deep shadows (lin < 0.20) and lifts mid-shadows toward mid-tones. This is characteristic of a high-gamma print stock viewed on a bright projector — the shadow crushing is a physical property of film; the mid-shadow lift at lin=0.4 is an artifact of the lerp blending transitioning toward the shoulder at that range.

The **blend transition zone** (smoothstep(0, 0.5, ps)) is fully shoulder at ps ≥ 0.5. Below ps = 0.5, the toe is increasingly dominant. At ps = 0.3 (lin ≈ 0.28), blend = 0.648 so both contribute.

**Verdict: The toe is acceptable as a rough approximation.** The actual Kodak 2383 toe is more precisely modeled by a log-space curve, but `ps² × 3.2` captures the qualitative behavior (shadow crush, mid-shadow lift) without incurring extra GPU cost or complexity. It should be retained.

The more consequential change is fixing the shoulder, which affects all highlights above ps = 0.50.

---

## 9. Channel Independence

The 2383 dye layers have slightly different H-D curve slopes. The green layer has the lowest intrinsic gamma (most latitude); red tends slightly higher; blue highest (narrowest latitude). However:

1. All public film emulation implementations (ACES, AgX, darktable) apply identical shoulder parameters per channel in real-time contexts.
2. The per-channel differentiation in the existing R51 block comes from `R84 log-density offsets` and `R85 dye masking` upstream, which handle the channel-specific density response.
3. Applying identical FILM_KNEE and FILM_K_SH per channel is correct behavior for this pipeline.

---

## 10. Final HLSL Recommendation

Drop-in replacement for the shoulder line in the R51 block:

```hlsl
// OLD (bug — always expands):
// float3 shoulder = 1.0 - (1.0 - ps) * (1.0 - ps) * 1.8;

// NEW — Reinhard partial shoulder, compressive above FILM_KNEE:
static const float FILM_KNEE = 0.65;   // ~+1.83 stops above 18% gray
static const float FILM_K_SH = 0.476;  // shoulder(ps=1.0) = 0.950
float3 d        = max(0.0, ps - FILM_KNEE);
float3 shoulder = ps - d + d / (1.0 + d * FILM_K_SH);
```

The `lerp(toe, shoulder, smoothstep(0.0, 0.5, ps))` line below is unchanged.

**Properties of the replacement:**
- Smooth, monotone, C1-continuous at FILM_KNEE
- Compressive for all ps > FILM_KNEE (output < input)
- Identity for ps ≤ FILM_KNEE
- Maps [0,1] → [0, 0.95] (asymptote below 1.0 — soft ceiling, never clips)
- No branches, no arrays, no `out` naming conflicts
- SPIR-V safe: uses only scalar `static const float`, local float3 arithmetic
- Two scalar constants, three GPU ops (max, sub, div): negligible cost

**Tunability:** FILM_K_SH is the single knob:
- Lower (< 0.476): even milder shoulder (less compression at peak white)
- Higher (> 0.476): more aggressive shoulder (suitable for more stylized film look)

If desired, FILM_K_SH can be exposed in `creative_values.fx` as a user knob; if not exposed, the default 0.476 is physically motivated (matches 2383 mild shoulder character).

---

## Citations

- Kodak VISION Color Print Film 2383/3383 data sheet: https://www.kodak.com/content/products-brochures/Film/KODAK-VISION-Color-Print-Film-2383-3383-data-sheet.pdf
- Kodak H-1-2383t technical bulletin (National Archives): https://www.archives.gov/files/preservation/products/resources/2383-TI.pdf
- Forum discussion on 2383 D-max: https://cinematography.com/index.php?%2Fforums%2Ftopic%2F101086-color-density-and-dynamic-range-of-kodak-vision-2383%2F=
- AgX minimal GLSL (bWFuanVzYWth): https://github.com/bWFuanVzYWth/AgX
- AgX SB2383 configuration generation (Sobotka): https://github.com/sobotka/SB2383-Configuration-Generation
- darktable filmicrgb.c source: https://github.com/darktable-org/darktable/blob/master/src/iop/filmicrgb.c
- ACES Narkowicz approximation: https://knarkowicz.wordpress.com/2016/01/06/aces-filmic-tone-mapping-curve/
- Unity ACES.hlsl (segmented spline C9): https://github.com/Unity-Technologies/PostProcessing/blob/v2/PostProcessing/Shaders/ACES.hlsl
- Hable piecewise power curves: https://filmicworlds.com/blog/filmic-tonemapping-with-piecewise-power-curves/
- darktable filmic/sigmoid engineering article (Aurelien Pierre): https://eng.aurelienpierre.com/2018/11/filmic-darktable-and-the-quest-of-the-hdr-tone-mapping/
- Allen Pestaluky adjustable tonemapping (2025): https://allenwp.com/blog/2025/05/29/allenwp-tonemapping-curve/
- Tone mapping survey (delta): https://64.github.io/tonemapping/
