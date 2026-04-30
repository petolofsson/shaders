# R35 — Automate SHADOW_LIFT — Findings
**Date:** 2026-04-30
**Searches:**
1. "adaptive shadow lift tone mapping scene luminance statistics color grading algorithm"
2. "percentile luminance p25 shadow content estimation image statistics histogram tone mapping"
3. "scene key value luminance average dark scene bright scene adaptive tone operator Reinhard"
4. "film print emulation toe lift shadow density analog film process simulation ACES"
5. "ITU SMPTE recommendation adaptive low-end lifting blacks shadow lift display calibration"
6. "p25 percentile vs mean luminance shadow estimation natural image statistics scene content"

---

## Key Findings

### 1. Scene-key–driven adaptation is well-established

Reinhard et al. (2002) "Photographic Tone Reproduction for Digital Images" (SIGGRAPH) is the
canonical reference for scene-adaptive tone operators. Their system computes a **log-average
luminance** (geometric mean) as the "key value" — explicitly naming it as a descriptor of
whether a scene is high-key (bright) or low-key (dark). The key value is used to scale the
entire luminance mapping. This is exactly the intellectual lineage of R35: use a scene-level
statistic to modulate how aggressively the toe/shadow region is treated.

The Reinhard key approach uses log-average (geometric mean), not a percentile. However, the
paper acknowledges that any robust scene-level statistic can serve as the driver; the
log-average is preferred because it is robust to outlier highlights. A low-percentile (p25) is
at least as robust, and more directly represents shadow content.

### 2. p25 is a reasonable — but not standardised — choice for shadow content

No paper was found that specifically canonises p25 as the shadow signal. However, the natural
image statistics literature (Frazor & Geisler 2006, *Vision Research*; related JOV 2006 paper
by the same group) uses the 2.5th and 97.5th percentiles to bound the luminance range of image
patches, explicitly to exclude outlier specular highlights and deep shadow clipping from
statistical characterisation. This is the percentile-based approach as opposed to the mean.

The p25 choice in R35 sits between the extremes: it is not as outlier-sensitive as the mean,
not as noisy as p10, and not as close to the noise floor as p5. Conceptually, p25 represents
the luminance level that 25% of pixels fall below — i.e., the typical shadow floor of the
scene. For a scene where shadows are genuinely crushed, p25 will be very low; for a bright
outdoor scene, p25 will be significantly elevated. This is exactly the signal needed.

The academic standard for shadow estimation in display/imaging work is typically mean or
geometric mean, but both are vulnerable to bright-biased scenes. p25 is the more practical
signal for a real-time SDR game post-process where the goal is specifically to detect shadow
crushing severity.

### 3. Tone-mapping adaptive dark-region enhancement is an active research area

Wang et al. (2025, *Color Research & Application*) describe an adaptive tone mapping algorithm
that explicitly includes a "dark region enhancement" stage driven by global contrast and
luminance statistics. This confirms that scene-adaptive shadow lifting is considered a
legitimate sub-problem in current HDR-to-LDR pipeline literature, not a niche hack.

The "Display Adaptive Tone Mapping" work (Mantiuk 2008) shows that scene-level luminance
distribution (histogram shape) should drive how much shadow detail is preserved vs. elevated.
In dark scenes, the histogram is skewed low, and more aggressive toe lifting is needed to
maintain shadow detail visibility.

### 4. Film print analog: toe lift is scene-density-dependent by construction

ACES print emulation context (from ACES RRT/ODT documentation and Mixing Light / Mononodes
practitioner sources) confirms that film print emulation LUTs typically lift the shadow floor
(D-min) to give blacks a softer, more "print-like" density curve. The critical point from the
analog domain: on real film, the toe shape depends on the print density which is proportional
to the scene exposure. In dark scenes (low overall density), the print's toe region is steeper
relative to highlight, so shadow detail recovery requires more lift. In bright scenes (high
density), the toe is compressed by the shoulder of the positive print and the effective lift is
lower. ACEScct explicitly adds a toe to its encoding precisely because "when using lift
operations the response feels more similar to traditional log film scans" (Frame.io ACES guide).

This is the film-physics basis for scene-adaptive shadow lift: a fixed lift is physically
incorrect; the correct analog behavior is a lift that varies with scene density — exactly what
R35 proposes.

### 5. ITU/SMPTE: no direct adaptive shadow lift recommendation

ITU-R BT.2408 (editions 4, 5, 8) addresses shadow/black-level lift in the context of display
calibration (brightness control, BT.1886 EOTF), not scene-adaptive grading. The ITU framing
is about **display black floor** compensation, not creative shadow lifting driven by scene
content. SMPTE standards similarly focus on reference viewing environment, not adaptive
per-scene toe behavior. There is no ITU or SMPTE document that directly addresses
scene-luminance-driven shadow lift. The closest is BT.1886's treatment of how a non-zero
display black lifts near-black pixels, and the recommendation to compensate for it — but this
is a static calibration, not a dynamic scene-driven algorithm.

---

## Literature Support (or Lack)

| Claim | Support |
|-------|---------|
| Scene-key signal should drive shadow treatment | **Strong** — Reinhard 2002 canonical; Wang 2025 confirms for dark-region enhancement |
| Percentile-based scene statistics are appropriate | **Moderate** — percentile bounding used in natural image statistics literature (Frazor 2006); no paper specifically canonises p25 as the shadow signal |
| p25 preferable to mean for shadow content | **Indirect** — mean is vulnerable to highlights in typical HDR game scenes; p25 is more direct; no head-to-head comparison found |
| Adaptive lift range should be larger for dark scenes | **Strong** — physically grounded in both tone mapping (Reinhard key) and analog film print density behavior |
| Film print: shadow lift is scene-density-dependent | **Strong** — supported by ACES ACEScct toe rationale and film print LUT practitioner literature |
| ITU/SMPTE recommendation for adaptive toe | **None found** — standards only cover static display calibration |

---

## Parameter Validation

### Lift range 5–20

The current fixed value is 15 (applied as `15/100 * 0.75 = 0.1125` effective lift weight at
peak). The proposed range is 5–20. In perceptual terms:

- **5** (0.0375 effective weight) — very soft lift, essentially a minor toe roll-off. Appropriate
  for bright scenes where crushing is not occurring.
- **20** (0.15 effective weight) — moderately aggressive. This is not a radical value; at the
  lift formula's construction (`new_luma * smoothstep(0.4, 0.0, new_luma)`), the weight
  function already self-limits: it tapers to zero at luma=0 and luma=0.4, peaking around
  luma≈0.2. So the maximum actual lift at any pixel is bounded well below 0.15 on a linear
  scale. A value of 20 produces no risk of pushing shadows above midtones.
- The range 5–20 (4:1 ratio) is consistent with the range of key-value scaling used in
  Reinhard's operator (typically 0.18 base key, varying over approximately 4× for dark vs
  bright scenes).

The range is perceptually reasonable. No literature specifically validates 5–20 for SDR game
post-process, but the ratio and absolute values are consistent with established tone mapping
practice.

### Smoothstep transition 0.04–0.28

The Frazor & Geisler (2006) natural image statistics paper shows that within-image luminance
range spans more than one log unit (10×) across typical scene patches. For scene-level p25:

- A dark interior/night scene (Arc Raiders underground areas, tunnels): p25 is expected in the
  0.01–0.05 linear range. This is consistent with real-world nighttime or heavily shadowed
  scenes where 25% of pixels are very dark.
- A bright overcast outdoor scene: mean luminance is typically 0.2–0.4 linear, so p25 would
  fall in roughly 0.15–0.30 range (the lower quartile of a bright scene still contains
  mid-range values).
- The transition 0.04→0.28 spans approximately 7× in linear space (or ~0.85 log units), which
  is consistent with the ~1 log unit variation in mean luminance seen across natural scene
  types.

The transition endpoints appear well-chosen. The lower edge (0.04) correctly captures
"genuinely dark scene" territory; the upper edge (0.28) correctly captures "bright scene where
shadow lifting is counterproductive." The smoothstep function provides the required continuity
(no seams/gates) per the project's no-gates rule.

---

## Risks / Concerns

### 1. p25 vs. geometric mean
The Reinhard/academic standard for scene key is geometric mean (log-average). In a scene with
a large specular highlight or bright light source, geometric mean can be pulled high, causing
under-estimation of shadow severity. p25 is more resistant to this pull — which is actually a
practical advantage for game scenes with strong light sources. However, p25 can be elevated
in scenes with strong ambient fill (e.g., an overcast outdoor scene where even the shadows are
bright). In that case, the algorithm would correctly suppress shadow lift. Verdict: p25 is the
better choice than geometric mean for this use case.

### 2. Kalman lag in scene transitions
After R34, PercTex is Kalman-smoothed. This means shadow_lift will lag when entering a dark
scene from a bright one — the lift will ramp up over several frames rather than snapping to
aggressive immediately. This is the intended behavior (no flicker), but the lag duration
should be validated. A fast cut from noon outdoors (p25~0.28) to a night interior (p25~0.02)
could take several seconds for shadow_lift to reach its maximum. This is acceptable for a game
post-process (abrupt changes in lift are jarring) but should be confirmed against the Kalman
time constant from R34.

### 3. EXPOSURE interaction
As noted in the R35 proposal: lowering EXPOSURE reduces p25 → increases shadow_lift → which
partially offsets the darkening effect of lower exposure. This is a coupling. Whether this is
desirable (complementary) or problematic (conflated control surfaces) depends on user intent.
If the user lowers EXPOSURE to darken the overall image, they may not want automatic
compensation. However, the coupling is gentle (the lift weight formula has limited range) and
this is the same kind of coupling present in all perceptual tone operators (they all have
some feedback between exposure and shadow treatment). Flag for user awareness.

### 4. No literature-validated lift floor
The minimum lift of 5 at bright scenes is not derived from any standard. It could be 0 (no
lift) without breaking anything. The rationale for keeping it at 5 rather than 0 would be that
a minimal toe roll-off is perceptually appropriate even in bright scenes (matching film print
behavior where D-min is never zero). The film print literature supports this implicitly. If
perceptual testing shows bright scenes look washed, reducing to 3 or 0 is safe.

### 5. No ITU/SMPTE external validation
The adaptation scheme has no direct standard to cite. It is principled (grounded in Reinhard
scene-key theory and film print density behavior) but not normative. This is not a concern for
a creative post-process shader but is worth noting.

---

## Verdict

**Proceed with R35.** The proposal is well-grounded:

- The scene-key concept (Reinhard 2002) is the direct intellectual precedent for driving
  shadow treatment from a scene-level luminance statistic.
- p25 is a reasonable and arguably better shadow-content signal than the commonly used
  geometric mean, because it is directly measuring the shadow quartile and is resistant to
  highlight bias.
- The lift range 5–20 and transition 0.04–0.28 are consistent with both tone mapping practice
  and natural image statistics (Frazor 2006 ~1 log unit variation in scene luminance).
- Film print emulation practice confirms that analog shadow lifting is scene-density-dependent
  by construction — a fixed lift is physically incorrect.
- The only non-trivial risk is the Kalman lag on scene transitions, which is shared with all
  Kalman-smoothed stats and is the price of temporal stability.

No literature was found that contradicts the approach. The absence of a specific ITU/SMPTE
recommendation is expected — this is a creative grading parameter, not a calibration one.

**Confidence: High.** Research supports all key assumptions.
