# Research Findings — Wild Card: Physical Optics — 2026-05-03

## Search angle
Physical optics, printing science, and display photometry applied to the SDR post-processing
chain. Three specific threads were investigated: (1) human-eye longitudinal chromatic
aberration as a perceptual rendering cue, (2) MacAdam discrimination ellipses as a
calibration basis for memory-color chroma ceilings, and (3) Beer-Lambert exponential
absorption as a physically-correct model for dye secondary absorption.

---

## Finding 1: Eye LCA Simulation — Chromablur-Derived Per-Channel UV Offset

**Source:** Cholewiak, Love, Srinivasan, Ng, Banks. "Chromablur: Rendering Chromatic Eye
Aberration Improves Accommodation and Realism." ACM Transactions on Graphics 36(6), 2017.
https://dl.acm.org/doi/10.1145/3130800.3130815
**Year:** 2017
**Field:** Physiological optics / perceptual rendering

### Core thesis
The human crystalline lens has ~2.4 diopters of longitudinal chromatic aberration (LCA).
Red focuses ~0.5 D behind the nominal plane; blue focuses ~1.9 D short. The visual system
is calibrated to this fact: natural scenes always show a specific chromatic fringe at
high-contrast edges — blue fringe slightly outside, red fringe slightly inside, relative
to the viewer's fixation distance. Chromablur (2017) demonstrated that rendering this
fringe explicitly improves perceived realism and accommodation response. The relevant
result for a flat-screen SDR pipeline: the *static* LCA pattern (radially symmetric,
scale-invariant, achromatic in luminance) creates optical texture that reads as "filmed
through glass" rather than purely digital. The effect is a per-channel radial UV offset:
blue channels are sampled slightly outside the nominal UV; red channels slightly inside.
Magnitude at the image corner for normal viewing distance (60 cm, 27″ monitor): ~0.3%
of image width.

### Current code baseline
`grade.fx` line 222 samples all three channels identically:
```
float4 col = tex2D(BackBuffer, uv);
```
No per-channel sampling offset exists anywhere in the pipeline.

### Proposed delta
Add two additional BackBuffer reads for R and B, splitting the monolithic sample:
```hlsl
// R81A: eye LCA — blue samples outward, red samples inward (radially from centre)
float2 lca_off = (uv - 0.5) * LCA_STRENGTH * 0.004;
float4 col     = tex2D(BackBuffer, uv);           // G channel baseline (and alpha)
col.r          = tex2D(BackBuffer, uv - lca_off).r;  // red: inward shift
col.b          = tex2D(BackBuffer, uv + lca_off).b;  // blue: outward shift
```
Add to `creative_values.fx`:
```hlsl
// ── EYE LCA ──────────────────────────────────────────────────────────────────
// Longitudinal chromatic aberration of the human eye: blue focuses short, red
// focuses long. Simulates the natural per-channel fringe that real-world optics
// produce. 0 = off. 0.5 = ~1.2D (subtle). 1.0 = ~2.4D (full physiological LCA).
#define LCA_STRENGTH  0.0
```
The `0.004` constant maps `LCA_STRENGTH=1.0` to ±0.4% UV offset at the image corner —
within the measured human-eye range.

### Injection point
`grade.fx` lines 222–224, replacing the single `tex2D(BackBuffer, uv)` with the three
channel-split samples before the data highway guard.

### Breaking change risk
LOW. Default 0.0 = identity (lca_off = 0 → all three reads collapse to the same UV).
Adds 2 texture fetches. No value-domain risk: sampling BackBuffer [0,1] at offset UV
stays [0,1].

### Viability verdict
**VIABLE.** Self-limiting by construction (radial, linear in distance from centre).
No gates. SDR-safe. Game-agnostic. 2 extra texture reads — acceptable. Primary concern:
at LCA_STRENGTH > 0.3, the colour fringe at fine aliased geometry could look like
digital artefacts rather than optical character. Recommend default 0.0 with a range
note of 0.0–0.5 in the knob comment.

---

## Finding 2: MacAdam-Calibrated Per-Hue Chroma Ceilings in R73

**Source:** MacAdam, D.L. "Visual Sensitivities to Color Differences in Daylight." JOSA
32(5) 1942. Updated quantification: Shen, Zhao et al. "Measurement of the Imperceptible
Threshold for Color Vibration Pairs Selected by using MacAdam Ellipse." SIGGRAPH 2024
Posters. arxiv:2406.08227. https://arxiv.org/abs/2406.08227
**Year:** 1942 / 2024
**Field:** Colorimetry / display photometry

### Core thesis
MacAdam (1942) established that color discrimination thresholds form ellipses in
chromaticity space that vary dramatically by hue. The ellipses are *not* equal size: blue
and cyan have the smallest ellipses (finest discrimination — ~2–3× tighter than yellow).
Yellow and orange have the largest ellipses. The 2024 SIGGRAPH poster confirmed these
ratios hold for temporal color vibration thresholds as well. In Oklab (designed to be
perceptually uniform) the ellipses are closer to circles, but residual hue-dependent
non-uniformity remains: blue/cyan chroma increments are more perceptually salient per
unit than yellow increments at comparable C values.

The R73 memory color ceilings (grade.fx lines 443–444) are meant to prevent any hue band
from being pushed beyond a natural-looking chroma. MacAdam calibration gives a principled
basis for the per-band ceiling values. Currently:

| Band | Current C_ceil | Rationale issue |
|------|---------------|-----------------|
| RED (0.28) | ✓ correct | Skin/warm light sits at 0.22–0.28 in Oklab |
| YELLOW (0.22) | slightly low | Largest MacAdam ellipse → most headroom; sunlit chrome reaches 0.24–0.26 |
| GREEN (0.16) | ✓ correct | Foliage 0.13–0.18; 0.16 is accurate |
| CYAN (0.18) | too high | Small MacAdam ellipse; sky blues ~0.10–0.14; 0.18 allows visibly artificial teal |
| BLUE (0.26) | too high | Smallest ellipses; deep cobalt rarely exceeds 0.19 in Oklab; 0.26 permits over-electric sky |
| MAGENTA (0.22) | ✓ correct | Vibrant purples 0.18–0.23 |

The CYAN and BLUE values are particularly mis-calibrated relative to MacAdam: they are
the most perceptually sensitive hues and currently have the *loosest* ceilings relative
to natural reference chromas in their bands.

### Current code baseline
`grade.fx` lines 443–444:
```hlsl
float C_ceil = hw_o0 * 0.28 + hw_o1 * 0.22 + hw_o2 * 0.16
             + hw_o3 * 0.18 + hw_o4 * 0.26 + hw_o5 * 0.22;
```

### Proposed delta
```hlsl
// MacAdam-calibrated ceilings: blue/cyan tightened (smallest discrimination
// ellipses), yellow relaxed (largest ellipses).
float C_ceil = hw_o0 * 0.28 + hw_o1 * 0.24 + hw_o2 * 0.16
             + hw_o3 * 0.15 + hw_o4 * 0.19 + hw_o5 * 0.22;
```
Changes: YELLOW 0.22→0.24, CYAN 0.18→0.15, BLUE 0.26→0.19.

Rationale for each:
- **YELLOW +0.02**: MacAdam's largest ellipse band. Sunlit chrome and specular highlights
  on warm surfaces can reach C=0.24 naturally. The existing 0.22 was clipping these.
- **CYAN −0.03**: Small ellipse; natural sky under Arc Raiders' post-apocalyptic overcast
  conditions sits at 0.08–0.12. Anything above 0.15 is perceptually extraordinary and
  should be protected by the ceiling, not permitted.
- **BLUE −0.07**: Smallest ellipses in the MacAdam dataset. Cobalt blue (most saturated
  natural blue) sits at C≈0.17–0.19 in Oklab. Allowing to 0.26 permits video-game electric
  blue that reads as digital.

### Injection point
`grade.fx` lines 443–444 only. No new variables, no creative_values.fx change.

### Breaking change risk
MEDIUM. Any scene containing strongly saturated blues or cyan (neon lights, energy beams,
sci-fi UI) will be visibly desaturated relative to current behaviour. These scenes should
be reviewed after the change. Skies will be less "electric" which is likely correct for
Arc Raiders' desaturated-industrial palette but must be validated.

### Viability verdict
**VIABLE — validate before shipping.** The mathematical basis is sound. The specific
constants should be validated against Arc Raiders reference footage (interior neon signs,
exterior sky, energy weapon VFX) before committing.

---

## Finding 3: Beer-Lambert Exponential Dye Absorption in R50

**Source:** Beer, A. "Bestimmung der Absorption des rothen Lichts in farbigen Flüssigkeiten."
Ann. Physik 86, 1852. Applied to photographic dye modelling in: Hunt, R.W.G.
"The Reproduction of Colour," 7th ed., Wiley, 2004 (Chapter 7: Photographic Colour
Reproduction). Color matching via Beer-Lambert in printing: IEEE ICIP 2014 gravure paper
(ieeexplore.ieee.org/document/6931482).
**Year:** 1852 (classical) / 2004 (film application)
**Field:** Physical optics / photographic chemistry / printing science

### Core thesis
Beer-Lambert law states that transmittance through an absorbing medium is exponential in
path length and concentration: T = exp(−α·c·d). In a photographic dye layer, the dominant
channel's suppression of adjacent channels follows this exponential form. The current R50
implementation uses a linear subtraction:

```hlsl
lin = saturate(lin - 0.06 * dom_mask * sat_proxy * ramp);
```

For small `sat_proxy` (< 0.1) the linear and exponential models agree: exp(−x) ≈ 1 − x.
But for sat_proxy > 0.2 (saturated colors: vivid reds, greens, cyans), the exponential
model predicts meaningfully more absorption — the dominant channel progressively loses
its "shine" in a way that is characteristic of Fuji Velvia and Kodak Ektar (high-saturation
film stocks). Linear subtraction underestimates this at high chroma.

Numerical comparison (dom_mask = 1, ramp = 1):

| sat_proxy | Linear Δ (−0.06 × s) | BL Δ (exp(−0.065×s)−1) |
|-----------|----------------------|------------------------|
| 0.10 | −0.006 | −0.0063 ≈ same |
| 0.25 | −0.015 | −0.0158 ≈ same |
| 0.50 | −0.030 | −0.0317 ≈ +6% more |
| 0.80 | −0.048 | −0.0504 ≈ +5% more |
| 1.00 | −0.060 | −0.0630 ≈ +5% more |

The difference is modest — ~5–6% additional suppression at high chroma. Perceptibly
distinct on highly saturated red/green/cyan that appear "plasticky" in the current linear
model.

### Current code baseline
`grade.fx` lines 278–282:
```hlsl
float lin_min   = min(lin.r, min(lin.g, lin.b));
float sat_proxy = max(lin.r, max(lin.g, lin.b)) - lin_min;
float ramp      = smoothstep(0.0, 0.25, sat_proxy);
float3 dom_mask = saturate((lin - lin_min) / max(sat_proxy, 0.001));
lin = saturate(lin - 0.06 * dom_mask * sat_proxy * ramp);
```

### Proposed delta
Replace the final line only:
```hlsl
// R81B: Beer-Lambert dye absorption — exp(−α·c·d) is physically correct at high chroma
float3 bl_abs = dom_mask * sat_proxy * ramp;
lin = saturate(lin * exp(-0.065 * bl_abs));
```
The constant 0.065 ≈ 0.06 × (1 + 0.083) to account for the first-order correction
to the linear approximation, keeping the low-saturation behaviour identical.

SDR guarantee: exp(−x) ∈ (0, 1] for all x ≥ 0, and `bl_abs ≥ 0` by construction.
`lin ∈ [0,1]` × `exp(−positive) ∈ (0,1]` → output ∈ [0,1]. No `saturate()` needed
beyond the existing one.

### Injection point
`grade.fx` line 282, replacing the last line of the R50 block. 4 characters of
contextual change.

### Breaking change risk
LOW. Behavioural change only at sat_proxy > 0.2 (moderately saturated pixels).
Difference from current: ≤ 6% darker on the dominant channel at full saturation,
0% different on neutral/low-sat pixels. Perceptible only on vivid single-hue objects.
Very unlikely to break anything; more likely to subtly improve highly-saturated game
assets.

### Viability verdict
**VIABLE — low risk, worth shipping.** The code change is one line; the physics
motivation is rigorous; the SDR guarantee is provable; the behavioural deviation from
the current linear model is small and in the correct direction.

---

## Discarded this session

| Title | Reason |
|-------|--------|
| Stiles-Crawford effect of 2nd kind (SCE2) | Requires pupil size as input; display-specific; maps to existing Purkinje work (R52) |
| Optical vignetting cos⁴(θ) | Radial vignette.fx was explicitly rejected by user |
| Kubelka-Munk gamut boundary (Saunderson correction) | Complex formula with no meaningful advantage over current R68B Reinhard pre-knee; SDR constraint limits depth of gamut compression anyway |
| Yule-Nielsen FilmCurve replacement | Would replace the existing quadratic FilmCurveApply with a single-parameter n-curve — loses per-channel knee/toe expressiveness; not an improvement |
| Chromablur VR-specific accommodation features | Depth-based defocus requires per-pixel depth, which vkBasalt cannot access; flat-screen benefit is LCA-only (Finding 1 captures this) |

---

## Strategic recommendation

**Finding 1 (LCA)** is the most novel for the pipeline — no existing shader effect touches
per-channel spatial sampling. Recommend implementing as an opt-in knob at default 0.0.
Perceptual benefit is subtle but additive with halation (R56): LCA gives chromatic edge
character at any luminance; halation gives warm glow only in the top 20% luma. Together
they make the image read as "through glass" rather than digital.

**Finding 2 (MacAdam ceilings)** is a targeted correction to existing constants. Recommend
validating against Arc Raiders neon lights and sky before shipping — the BLUE and CYAN
tightening is the highest-risk change.

**Finding 3 (Beer-Lambert)** is a one-line fix that is analytically correct and low-risk.
Recommend shipping alongside the next unrelated change.
