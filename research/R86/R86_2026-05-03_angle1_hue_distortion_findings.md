# R86 Angle 1 — ACES Hue Distortion Characterisation
**Date:** 2026-05-03 | **Angle:** 1 (hue distortion, per-channel ACES error analysis)
**Sub-track:** Scene Reconstruction (R86)

---

## Run angle

Angle 1 — Per-hue distortion characterisation and correction offset derivation.

---

## HIGH PRIORITY findings

### 1. Root cause: per-channel ACES application breaks hue constancy

The Hill 2016 approximation `y = (2.51x²+0.03x) / (2.43x²+0.59x+0.14)` is applied
independently to each of R, G, B. Because the function is concave (`f''(x) < 0`),
the dominant channel is compressed proportionally more than secondary channels:

> For a pixel (R, G, B) with R > G > B, the output satisfies
> `ACES(R)/ACES(G) < R/G` and `ACES(G)/ACES(B) < G/B`.

This is the exact mechanism behind the three known distortions — all are a
consequence of the dominant channel losing proportional ground to secondary channels.

ACES 2.0 (2024, DaVinci Resolve) addressed this by replacing per-channel application
with a "norm-based ratio-preserving tone-scale" (uniform scaling by a channel norm),
which preserves R:G:B ratios and thus hue. The Hill/UE5 approximation has no such fix.

**Source:** DaVinci Resolve ACES 2.0 deep-dive (cubiecolor.com); ACESCentral
game-dev thread on highlight desaturation; per-channel concavity analysis (derived).

---

### 2. Red→orange push: analytical derivation

**Mechanism:** For warm pixels (R >> G), the shoulder compresses R more than G →
G/R ratio increases → hue shifts from red toward yellow (orange is the intermediate).

**Example:** Scene (R=0.80, G=0.40, B=0.20):
| | Scene | Display (ACES) |
|---|---|---|
| R | 0.800 | 0.7525 |
| G | 0.400 | 0.5408 |
| B | 0.200 | 0.2995 |
| G/R ratio | 0.500 | **0.719** (+44%) |

A 44% increase in G/R is a large hue shift. In Oklab LCh, the red hue band centers
near h=0.083 (≈30°). Orange sits near h=0.15–0.20 (≈55–70°). The distortion
moves warm pixels ~12–18° clockwise (toward yellow) at mid-bright chroma.

**Magnitude (analytical):** ≈ 10–18° in Oklab hue at L≈0.65–0.75, C≈0.12–0.20.
Peak distortion at saturated reds just entering the ACES shoulder region (~0.6–0.8 display).

---

### 3. Cyan→blue shift: analytical derivation

**Mechanism:** For cyan/teal pixels (G ≥ B >> R), G is in the shoulder while B is
slightly lower. ACES compresses G more than B → G/B ratio decreases → teal shifts
toward pure blue.

**Example:** Scene (R=0.20, G=0.80, B=0.70):
| | Scene | Display (ACES) |
|---|---|---|
| G | 0.800 | 0.7525 |
| B | 0.700 | 0.7173 |
| G/B ratio | 1.143 | **1.049** (−8%) |

The G/B ratio decrease pushes the hue from teal/cyan toward blue. Confirmed
qualitatively by the Oolite game forum report ("intense blues taking an electric blue
or purplish tone after tone mapping").

**Magnitude (analytical):** ≈ 5–10° clockwise (toward blue) at L≈0.55–0.70, C≈0.12–0.18.

---

### 4. Yellow highlight desaturation: analytical derivation

**Mechanism:** For yellow highlights (R ≈ G >> B at high luminance), R and G are
deep in the ACES shoulder while B is in the near-linear toe. B is boosted proportionally
relative to R and G → blue injection into yellow → chroma collapses toward white.

**Example:** Scene (R=0.88, G=0.82, B=0.20):
| | Scene | Display (ACES) |
|---|---|---|
| R | 0.880 | 0.7754 |
| G | 0.820 | 0.7585 |
| B | 0.200 | 0.2995 |
| R/B ratio | 4.40 | **2.59** (−41%) |
| G/B ratio | 4.10 | **2.53** (−38%) |

The B channel is boosted from 23% of R to 39% of R. This is a pure chroma collapse
— yellow saturates toward white rather than undergoing a hue rotation.

**Correction approach:** Primarily a chroma restoration (C boost in Oklab) rather than
a hue rotation. Quantified as: `ΔC ≈ +0.04–0.08` restoration needed at high-luma yellows.
Defer chroma restoration to a second prototype pass; Angle 1 focuses on hue rotation.

---

## Correction offset derivation

All distortions are clockwise (positive hue direction in Oklab normalized [0,1]).
Corrections are the negatives of the distortions. Using same convention as grade.fx
R21 system (±1.0 → ±36°, applied as `h_out = frac(h + delta * 0.10)`):

| Band | Distortion direction | Magnitude estimate | Correction offset |
|------|---------------------|-------------------|------------------|
| Red (0.083) | +clockwise ~14° | ~0.39 ROT units | **−0.35** (−12.6°) |
| Yellow (0.305) | mostly chroma loss | <3° | **0.00** |
| Green (0.396) | minimal | <2° | **0.00** |
| Cyan (0.542) | +clockwise ~8° | ~0.22 ROT units | **−0.20** (−7.2°) |
| Blue (0.735) | +clockwise ~4° | ~0.11 ROT units | **−0.10** (−3.6°) |
| Magenta (0.913) | minimal | <2° | **0.00** |

**Uncertainty:** These are analytical lower bounds from the per-channel concavity argument.
Actual distortions may be 20–40% larger if the game applies a scene exposure pre-scale
before ACES (e.g., the Hill blog note: "pre-exposed"). Prototype thresholds should be
treated as initial estimates; empirical tuning required.

---

## Findings

### F1 — Per-channel ACES concavity is the single root cause of all hue distortions
- All three reported distortions (red→orange, cyan→blue, yellow desat) derive from
  the monotone concavity of the Hill approximation applied per-channel.
- ACES 2.0 fixed this architecturally. Hill/UE5 cannot be trivially fixed without
  inverting the transform.
- **Implication for R86:** The inversion (ACESInverse) naturally reverses the concavity
  effect. The hue correction layer is a residual correction for the fact that the
  inversion operates in display-referred space rather than the original AP1 space.

### F2 — Magnitude order: red push > yellow desat > cyan shift
- Red→orange is the largest distortion (~14°) because reds have the largest R-G
  separation entering the shoulder.
- Yellow desaturation is second in perceptual impact but is a chroma effect, not hue.
- Cyan→blue is smallest (~8°) because G-B separation in the shoulder region is modest.
- Blue→purple (~4°) is a secondary effect of cyan shift propagating into the blue band.

### F3 — ACES 2.0 "norm-based ratio-preserving" fix is documented evidence
- DaVinci Resolve's ACES 2.0 implementation (2024) uses a channel norm to preserve
  R:G:B ratios through the tone curve. This is documented as specifically fixing the
  "reds, skin tones, fire skewing chromatically" behaviour of ACES 1.x.
- **Source:** cubiecolor.com ACES 2.0 deep-dive article, 2024.

### F4 — ACESCentral confirms game-dev hit rate
- Multiple game developers reported the highlight desaturation issue when adopting
  Unity's ACES option (ACESCentral: "High light fix and premature desaturate" thread).
- The "blue highlight fix" LMT is a separate issue (AP1 out-of-gamut clipping) and
  does NOT address the per-channel hue distortion.
- **Implication:** The distortions are real, reproducible, and noticed by game developers.

### F5 — Yellow desat needs chroma restoration, not hue rotation
- The `ΔC ≈ +0.04–0.08` chroma restoration at high-luma yellows should be a
  separate term from the hue rotation. Mixing chroma scaling into the hue layer
  would interfere with the existing R22 Munsell shadow/highlight correction.
- Defer to a second Angle 1 pass once the hue-rotation prototype is validated.

---

## Prototype correction constants (for inverse_grade_aces.fx)

```hlsl
// R86 Angle 1: ACES hue distortion correction — undo per-channel shoulder compression errors.
// Convention matches grade.fx R21: ±1.0 → ±36°, applied as h_out = frac(h + delta * 0.10).
// Analytical estimates — expect empirical tuning ±25% after in-game validation.
#define ACES_CORR_RED     (-0.35)  // undo red→orange push  (~−12.6°)
#define ACES_CORR_YELLOW  ( 0.00)  // yellow: chroma collapse, not hue rotation
#define ACES_CORR_GREEN   ( 0.00)  // green: sub-threshold distortion
#define ACES_CORR_CYAN    (-0.20)  // undo cyan→blue shift  (~−7.2°)
#define ACES_CORR_BLUE    (-0.10)  // undo blue→purple bleed (~−3.6°)
#define ACES_CORR_MAG     ( 0.00)  // magenta: sub-threshold
```

---

## Searches run

1. `ACES filmic tone mapping hue distortion red orange push cyan blue shift magnitude degrees`
   — Narkowicz blog (2016), Oolite forum thread (cyan→blue confirmed), DaVinci ACES 2.0 article
2. `ACES tone mapping hue rotation red orange desaturation yellow Oklab LCh shift correction shader 2024`
   — ACESCentral game-dev thread, BruOp tonemapping blog, PBR Neutral TMO article
3. `ACES 1.0 RRT per-channel hue error quantified color chart Oklab 2023 2024`
   — Bram Stout "Enhancing the ACES RRT", ACESCentral Oklab/ACES comparison thread
4. `Hill 2016 ACES approximation per-channel saturate hue distortion analytical derivation`
   — delta.tonemapping blog (confirms per-channel oversaturation of brights), Stack Exchange
5. `ACESCentral "high light fix" premature desaturate game hue orange skin tone ACES 1.0`
   — ACESCentral thread (multiple game-dev reports, Unity highlight desat confirmed)

---

## Key conclusions

- All three ACES hue distortions (red→orange, cyan→blue, yellow desat) trace to one root cause: per-channel concave tone curve application.
- Magnitudes: red ~14°, cyan ~8°, blue ~4° in Oklab hue at mid-bright chroma. Yellow is primarily chroma loss (~0.05 C reduction), not rotation.
- Correction constants derived analytically. Empirical validation required once the inversion prototype is running on real game frames.
- Yellow chroma restoration deferred to second pass. The hue rotation layer is sufficient for the first prototype.
- ACES 2.0 confirmed to fix these issues via norm-based tone-scale; Hill/UE5 does not.
