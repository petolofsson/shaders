# R36 — Automate DENSITY_STRENGTH + CHROMA_STRENGTH — Findings
**Date:** 2026-04-30
**Searches:**
1. Hunt effect / perceived colorfulness / luminance / chroma scaling / color appearance model
2. CIECAM02 / CAM16 / chromatic adaptation / chroma scaling / colorfulness / ICC
3. Saturation adaptation / human visual system / over-saturation / perceptual colorfulness / scene statistics
4. Film color negative / saturation compression / density curve / analog dye coupler / high-saturation scene
5. Automatic adaptive saturation / video grading / mean scene chroma / colorfulness metric
6. "Mean chroma" / "average saturation" / scene descriptor / adaptive color grading
7. ACES chroma compression / gamut mapping / colorfulness / scene-adaptive output transform
8. Helson-Judd effect / chromatic adaptation / saturation / scene illuminant

---

## Key Findings

### 1. Hunt Effect — Colorfulness Scales with Luminance (confirmed, well-established)

The Hunt effect is one of the foundational phenomena in color appearance modeling (Hunt 1994,
CIECAM02, CAM16). Formally: perceived colorfulness M = C × FL^(1/4), where FL is the
luminance-level adaptation factor derived from the adapting luminance LA. In practical terms:

- At low luminance, colors look desaturated (muted night scene looks greyer than it is)
- At high luminance, colors look more saturated than their physical chroma implies
- The visual system expects this scaling — any rendering engine that ignores it produces
  either under-vivid darks or over-vivid brights

R36's chroma_strength being higher for low-chroma/dark scenes and lower for high-chroma
scenes is directionally consistent with Hunt: the pipeline is compensating for the visual
system's reduced sensitivity to chroma at low luminance by giving it a larger boost, and
restraining the boost when luminance (and physical chroma) is already high.

**Caveat:** The Hunt effect is a luminance-to-colorfulness mapping, not a chroma-to-chroma
mapping. R36 uses mean scene chroma as a proxy for scene luminance state (low-chroma scenes
tend to also be darker in Arc Raiders). The proxy is reasonable but not exact.

### 2. CIECAM02 / CAM16 — Degree-of-Adaptation and the D Factor

CIECAM02's chromatic adaptation transform computes degree of adaptation D as:

    D = F(1 - (1/3.6) × exp(-(LA + 42)/92))

This is scene-state-dependent: higher adapting luminance → stronger adaptation → the
visual system "normalises away" the illuminant more completely. The consequence for chroma
is that colors in highly-adapted (bright, colorful) scenes are perceived as less
extraordinary — the visual system compresses the perceived colorfulness of familiar hues.

The CIECAM02 chroma correlate C = t^0.9 × √(J/100) × (1.64 − 0.29^n)^0.73 includes a
background-relative lightness factor (n from Yb) that modulates how much chroma is
perceived relative to the field. A more chromatic scene field (higher Yb equivalent for
chroma) compresses perceived individual chroma — analogous to contrast masking.

**Relevance to R36:** The inverse relationship (higher scene chroma → less chroma boost)
has theoretical grounding in CIECAM02's background-field chromatic induction. Boosting
chroma on an already-chromatic scene would compound a perceptual quantity the visual system
is already compressing — producing a plasticky, unnatural appearance. R36 avoids this by
pulling chroma_strength back on high-mean-chroma scenes.

### 3. Color Contrast Adaptation — The Scene Statistics Argument

Psychophysical work (Krauskopf, Williams, Mandler & Brown 1986; Webster & Mollon 1991;
Webster 1996) establishes color contrast adaptation: prolonged exposure to a chromatically
rich scene reduces the perceived saturation of subsequent stimuli along the same color axes.
The adaptation magnitude is proportional to the contrast energy of the adapting stimulus.

A high-mean-chroma scene is one in which contrast adaptation is strongest. The visual
system has already "turned down" its own chromatic gain. Applying a fixed, high chroma
lift on top of that suppressed baseline produces a paradoxically garish result. This is
the direct perceptual mechanism behind over-saturation — the gain applied in the pipeline
does not account for the gain the visual system has already removed.

Conversely, a low-chroma scene produces weak contrast adaptation, leaving the visual
system's chromatic channels at full gain. A larger pipeline chroma boost here correctly
exploits that available perceptual range.

**Relevance to R36:** This is the strongest perceptual backing for the inverse relationship
chroma_strength = lerp(55.0, 30.0, chroma_adapt). The direction, the mechanism, and the
smoothstep transition are all well-motivated.

### 4. Film Density — Saturation Compression in Analog Processes

Color.io's documentation for their film density emulation tool explicitly models "the
non-linear saturation response of film density." The chrominance axis of the density
curve spans from near-grey to fully saturated, and the algorithm captures how silver
density responds differently across that range. In real color negative film:

- Dye couplers follow the Beer-Lambert law: optical density is proportional to dye
  concentration, which is proportional to exposure, which is logarithmic
- Each dye layer (CMY) has its own log-exposure / density (D-logE) curve
- At high scene chroma, color negative dye formation becomes non-linear: the layers
  that are most exposed approach the shoulder of the D-logE curve, compressing their
  density contribution. This is what gives film its characteristic "saturation roll-off"
  on very vivid subjects

This means: in film, high scene chroma → the dye layers clip toward their saturation
limit → perceived film density increases (the image "thickens") while individual
chroma channels compress. The net effect is exactly what R36 describes for density_strength:
lerp(35.0, 52.0, chroma_adapt) — higher scene chroma → higher density compression.

**Confidence:** The dye-layer shoulder roll-off is well-established analog physics. The
specific shape of the R36 curve is a reasonable digital approximation, not a transcription
of any particular emulsion's characteristic curve.

### 5. ACES 2.0 Chroma Compression — Independent Industry Validation

The ACES 2.0 output transform applies chroma compression as a distinct stage operating
purely on the M (colorfulness) component in JMh space. Key properties of the ACES
compression:

- It is hue-preserving and invertible
- It responds differentially to input colorfulness: less saturated colors are compressed
  more aggressively than highly saturated ones (toe function)
- Compression strength scales with peak luminance, not mean scene chroma — but the
  net effect is that scenes mapped to lower luminance states receive less compression

The ACES approach is not directly equivalent to R36, but it confirms the industry norm:
chroma compression is scene-state-adaptive, it is applied as a function of the existing
colorfulness of each pixel and/or the scene's luminance envelope, and it is not a fixed
scalar multiply.

The ACES "toe" — "compresses less saturated colors more" — is the inverse of R36's
chroma_strength logic, and that is intentional: ACES is doing gamut compression for
display headroom, R36 is doing chroma lift for perceptual richness. They are
complementary operations that should not be conflated.

### 6. Mean Chroma as a Scene Descriptor — Partial Validation

No academic literature was found that uses "weighted mean chroma across hue bands" as a
named descriptor in precisely the R36 formulation. The closest analog in the color science
literature is:

- **Gray-world assumption** (chromatic adaptation): mean scene chromaticity is used as a
  proxy for illuminant estimation. This validates the concept of treating mean chroma as
  a scene-level signal. The limitation noted in the literature is that it fails under
  strongly chromatic illuminants — which is exactly the high-mean-chroma case R36 guards
  against.
- **CIECAM02 background luminance (Yb)**: the relative luminance of the visual field
  modulates chromatic induction. R36's mean_chroma is a chroma-space analog of this
  background-relative scaling idea.
- **Colorfulness statistics in image quality assessment**: several papers (Hasler & Suesstrunk
  2003 "Measuring Colorfulness in Natural Images" is the canonical reference, though not
  directly found in these searches) use mean chroma / chroma standard deviation as
  image-level colorfulness descriptors. The 0.03–0.25 range cited in R36's proposal
  matches expected Oklab C ranges for real scenes.

**Verdict on descriptor validity:** The mean chroma signal is well-motivated by analogy
to established descriptors (gray-world chromaticity, CIECAM02 Yb). The specific 6-band
luminance-weighted formulation is custom to this pipeline but coherent — it is a
chromaticity-domain analog of the zone system's weighted luminance mean.

---

## Literature Support (or Lack)

| Claim | Support | Confidence |
|-------|---------|------------|
| Colorfulness increases with luminance (Hunt effect) | Well-established — Hunt 1994, CIECAM02, CAM16 | High |
| Inverse chroma boost on high-chroma scenes is perceptually motivated | Color contrast adaptation literature (Webster 1996) | High |
| High scene chroma → more density compression (film physics) | D-logE shoulder, Beer-Lambert, dye coupler saturation | Medium-High |
| Mean chroma across hue bands is a valid scene descriptor | Analogous to gray-world assumption; no exact paper | Medium |
| smoothstep(0.05, 0.20) as transition range | No direct literature; range consistent with observed Oklab C values | Low (engineering judgment) |
| lerp(55→30) and lerp(35→52) specific parameter values | No literature — these are empirically tuned | Low (engineering judgment) |

---

## Parameter Validation

**smoothstep(0.05, 0.20, mean_chroma):**
The Oklab C coordinate for typical natural scenes spans roughly 0.0 (neutral grey) to
0.35 (saturated primary). The 0.05–0.20 window covers the range from near-neutral to
vividly colorful without clipping on either end. This is reasonable. No psychophysical
study validates these exact breakpoints — they are calibrated to the observed range from
Arc Raiders ChromaHistoryTex data.

**chroma_strength lerp(55.0, 30.0):**
The hardcoded baseline is 40. The lerp produces values from 30 (vivid) to 55 (flat),
with 40 reproduced at mean_chroma ≈ 0.12. The ±10–15 point swing is moderate — not
enough to cause a perceptual discontinuity on slow scene transitions. Color contrast
adaptation psychophysics would support a larger swing, but the conservative range reduces
risk of grading artifacts on scene cuts.

**density_strength lerp(35.0, 52.0):**
The hardcoded baseline is 45. The lerp produces 35 (flat scene, ease off compression)
to 52 (vivid scene, add more film body). This mirrors the dye-layer saturation roll-off
direction. The absolute range is narrow, which is conservative.

**Correlation between the two lerps:**
chroma_strength and density_strength move in opposite directions as chroma_adapt increases:
chroma_strength falls while density_strength rises. This mirrors the film physics reality:
heavy scenes carry their own saturation in the density structure, so the chroma lift
should retreat and let density do the work. Perceptually, this is also correct: density
compression (darkness in the dye structure) reads as "richness" without the "plasticky"
quality of raw chroma saturation boost.

---

## Risks and Concerns

**1. Hunt effect proxy mismatch.**
R36 uses mean scene chroma as the driving signal, but the Hunt effect is driven by
luminance. In Arc Raiders, high-chroma scenes tend to also be bright (warm industrial,
vivid outdoor), so the proxy holds. In a hypothetical game with vivid neon in deep
darkness (high chroma, low luminance), R36 would pull back chroma_strength when it
should increase it. This is not a problem for the stated test platform but would need
revisiting for a game with that lighting profile.

**2. ChromaHistoryTex Kalman lag on cuts.**
Already noted in the proposal: 3–5 frame lag. Under psychophysical chromatic adaptation
research (Webster 1996), the human visual system adapts to scene chroma within seconds —
3–5 frames at 60 fps is ~50–80 ms, well within adaptation time. The lag is unlikely to
be perceptually visible.

**3. Mean chroma conflates hue variety and individual saturation.**
A scene with six moderately-saturated hues will have the same mean_chroma as a scene with
one vivid red and five neutral areas. The hue-band weighting partially mitigates this
(each band's mean is weighted by that band's pixel count), but the scalar mean_chroma
discards spatial hue distribution information. This is a known limitation of all
global colorfulness descriptors.

**4. No independent validation of parameter values.**
The lerp endpoints (30, 55, 35, 52) are empirically tuned to Arc Raiders. There is no
psychophysical or film-physics formula to derive them from first principles. They should
be considered engineering estimates requiring perceptual validation.

**5. Interaction with the Abney effect correction in CHROMA stage.**
The CHROMA stage already applies Abney correction and HK scaling. Those operations are
applied per-pixel before R36's mean_chroma scaling would take effect. There is no
theoretical conflict, but the interaction (chroma_str_eff feeding into the HK computation)
should be confirmed in the implementation to ensure the scaling chain is ordered correctly.

---

## Verdict

**Proceed with implementation.** The perceptual foundations for R36 are solid:

1. The inverse relationship (higher mean chroma → lower chroma boost) is well-grounded
   in color contrast adaptation theory and CIECAM02's chromatic induction framework.
2. The density-chroma correlation (higher mean chroma → more density compression)
   matches the analog film physics of dye-layer saturation on the D-logE shoulder.
3. Mean chroma as a scene descriptor is reasonable by analogy with established color
   science (gray-world assumption, CIECAM02 background luminance).
4. ACES 2.0 independently validates the principle of scene-adaptive chroma compression.

The specific parameter values (lerp endpoints, smoothstep range) are engineering
judgments with no direct literature backing — they require perceptual testing rather
than literature validation. This is expected for pipeline-specific tuning.

The Hunt effect provides directional support but is a luminance-driven phenomenon;
R36's use of mean chroma as a proxy is justified for Arc Raiders' lighting profile
but is not a first-principles derivation.

**Risk level: Low.** The proposal is conservative (narrow lerp ranges), reversible
(restoring two #define constants undoes it), and zero-cost at runtime.
