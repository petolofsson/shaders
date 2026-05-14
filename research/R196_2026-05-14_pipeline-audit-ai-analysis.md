# R196 — Pipeline Audit: AI Analysis Review

**Date:** 2026-05-14
**Source:** realtime_shader_pipeline_research_notes.md (external AI analysis)

---

## Context

External AI analysis of the pipeline identified 10 areas for improvement.
This document records the evaluation of each against the actual pipeline state,
constraints (SDR, vkBasalt HLSL/SPIR-V, game GPU budget), and known issues.

---

## Actionable — implement or investigate

### A. Asymmetric temporal hysteresis on scene state signals (from point 2)

**The claim:** The pipeline is fundamentally frame-reactive. Halation strength,
Purkinje gating, shadow lift, and chroma adaptation react too quickly to
transient highlights and temporary dark frames, causing grade pumping and flicker.

**Assessment: Valid.**

Currently:
- `slow_key` (slot 205) is the only signal with an asymmetric time constant —
  it is a slow EMA on zone_key used specifically for shadow lift temporal context.
- Halation effective strength is driven by `specular_contrast` (p90−p50), which
  updates every frame via the Kalman-smoothed p90. No hysteresis.
- Purkinje weight is driven by `new_luma` (per-pixel, instantaneous). No
  temporal smoothing on the scene-level gate.
- Scene cuts are handled (hard Kalman reset via HWY_SCENE_CUT) but gradual
  transitions between lighting states have no asymmetric handling.

**Proposed direction:**

Introduce asymmetric rise/fall EMAs for the two most affected signals:

1. **Halation `eff_hal_str`** — currently `HAL_STRENGTH * lerp(1.0, 1.4, specular_contrast)`.
   Specular contrast rising fast (bright source enters frame): slow rise (τ ≈ 0.5s).
   Specular contrast falling (source leaves): fast fall (τ ≈ 0.1s).
   Avoids the halation "bloom pulse" when a bright source briefly enters frame.

2. **Shadow lift `shadow_lift_str`** — currently driven by `_sls_t` (linear from
   perc.r + scene_mode). Dark transition: allow fast lift increase. Bright
   re-entry: slower falloff (currently τ ≈ slow_key which is already 1s EMA).
   The slow_key mechanism partially handles this — audit before adding more.

**Highway slot needed:** 1 new slot for smoothed specular_contrast (or write
asymmetric EMA inside analysis_frame or corrective HighwayWritePS).

**GPU cost:** Near-zero — one EMA per affected signal in existing passes.

---

### B. Highlight classification for inverse_grade (from point 4)

**The claim:** Non-semantic inverse tone mappers occasionally invent colour in
clipped whites, over-warm practical lights, and oversaturate emissive FX.

**Assessment: Valid and documented.** testbed known issues include
yellow/orange over-saturation and mid-shadow off-color.

**Most viable signal: temporal persistence of near-clip pixels.**

Clipped or near-clipped highlights (luma > 0.90) are structurally static between
frames — they cannot change because the game's tonemapper has already crushed them.
A pixel that remains near-clip for N consecutive frames is almost certainly a
genuine specular/emissive, not compressed colour that benefits from expansion.
Temporal persistence is detectable cheaply via the existing scene-cut signal and
a per-frame near-clip fraction count.

**Secondary signal: local chroma gradient.**

Genuine compressed colour has neighbours with consistent chroma direction
(a colour light source surrounded by its own reflected light). Emissive FX and
specular spikes have near-zero surrounding chroma (white bloom over dark background).
Local Oklab C variance in a small neighbourhood around each near-clip pixel
distinguishes these two cases. Expensive per-pixel but cheap at 1/8-res.

**Proposed direction:**

- Add a near-clip fraction signal to analysis_frame (pixels with luma > 0.90,
  as a fraction of total — similar to achrom_frac structure).
- Write to a new highway slot. In inverse_grade, gate chroma expansion strength
  by `(1 − near_clip_weight)` — pixels in scenes with high near-clip fraction
  are likely in emissive/specular-dominated regions and get less expansion.
- Temporal persistence: compare near-clip fraction against slow EMA of itself.
  If fraction is stable across frames (persistent clip), reduce expansion further.

**Note:** Per-pixel local chroma gradient at 1/8-res is a stretch target —
research whether the scene-level near-clip fraction is sufficient first.

---

## Audit only — investigate before deciding

### C. Operator doubling in dark areas (from point 1)

**The claim:** LOCAL_TONE + shadow lift may be compounding on the same dark pixels,
Retinex + zone S-curve may be stacking local contrast amplification.

**Assessment: Plausible, needs measurement.**

LOCAL_TONE gate: `max(log_key - max(log_base, log_pixel), 0.0)` — lifts pixels
darker than scene key, gated by both local base and pixel luma.

Shadow lift: `shadow_lift_str` applied in L-space after Retinex, gated by
`_sls_t` (driven by p25 + scene_mode).

These touch different things: LOCAL_TONE is spatially aware (guided filter base),
shadow lift is global (percentile-driven). But for a uniformly dark scene, both
fire in full strength on the same pixels.

**Proposed direction:** Measure both in isolation on a dark interior testbed
frame. If shadow lift is already covering what LOCAL_TONE does in dark scenes,
LOCAL_TONE could be attenuated when shadow_lift_str is high. Not a rewrite —
a one-line cross-term attenuation.

**Do not act on until measured.** Prematurely coupling these would break the
current calibration.

---

## Rejected — skip

| Point | Reason |
|-------|--------|
| #3 — Move to JzAzBz/ICtCp | SDR [0,1] range; JzAzBz designed for HDR (0.001–10,000 nits). Oklab differences negligible in SDR. Not worth conversion cost. |
| #5 — Rational spline tone fields | FilmCurve already uses rational shoulder+toe. Already done. |
| #6 — Spectral diffusion energy conservation | Polydisperse R/G/B widths (1.15/1.00/0.85) already capture key effect. SDR difference would be subtle. |
| #7 — Replace gates with continuous confidence | Already the design principle (CLAUDE.md: no hard gates, smoothstep everywhere). Nothing to do. |
| #8 — Foveated perceptual importance maps | Requires spatial subject detection. ML territory for game content. Not actionable. |

---

## What to keep exactly as-is (confirmed by external analysis)

- Oklab workflow
- Constant-hue gamut projection (R78 gclip)
- Histogram percentile modeling
- Kalman stabilization (R39/R88)
- Hunt coupling (R65)
- Purkinje modeling (R52)
- Memory color attraction (R117D)
- Density-space masking (R84/R85)
- Chroma self-mask vibrance (R71)
- Asymptotic gamut ceilings (R73)
- Film-density style couplers (R110/R130)

---

## Priority order

1. **R196-A** — Asymmetric temporal hysteresis on specular_contrast / halation.
   Targeted, low cost, directly addresses observable grade pumping.

2. **R196-B** — Near-clip fraction signal for inverse_grade highlight classification.
   Requires new analysis pass but highway slot infrastructure already exists.

3. **R196-C** — Operator doubling audit (LOCAL_TONE vs shadow lift).
   Measure first, act only if compounding is confirmed.

---

## Addendum — Algorithm upgrade recommendations (second AI analysis)

**Source:** shader_pipeline_algorithm_upgrade_recommendations.md

Second analysis focused on concrete algorithm replacements rather than
architectural patterns. Most Tier 1 suggestions are HDR-specific or already
implemented. Six items survive the SDR/SPIR-V filter.

---

### D. AgX-inspired highlight desaturation (from Tier 1 #1)

**The claim:** AgX solves ACES problems — less cyan clipping, better perceptual
saturation preservation, smoother highlight desaturation.

**Assessment: Research-worthy, not a replacement.**

The SDR argument for AgX is narrower than the HDR one, but real: AgX's
highlight desaturation rolloff is more perceptually smooth than ACES-fit
curves, and smoother than a Reinhard shoulder alone. Our FilmCurve already
uses a rational shoulder (not ACES), so cyan clipping and orange skew are not
our problem. What AgX does better: the natural transition from saturated
highlights into luminous white, which ACES compresses chromatically.

Munsell per-hue highlight rolloff (R133) partially covers this for the 12
canonical hue bands. The gap is cross-hue: the global rolloff into white is
driven solely by the FilmCurve shoulder shape, not by hue-aware desaturation.

**Proposed direction:** Research AgX's per-hue highlight desaturation curve
independently of the tone scale. A low-cost approximation: `chroma *= 1 −
smoothstep(L_threshold, 1.0, L)` with L_threshold per hue band. This is
R133-style but driven by hue-specific luminance headroom rather than a global
curve. No tone scale replacement needed.

**Action:** Deferred — research before R133 expansion pass.

---

### E. ACES 2 cusp-aware gamut compression (from Tier 1 #3)

**The claim:** Spectral gamut compression (ACES 2 style) better preserves hue
purity and emissive color structure than Oklab-space projection.

**Assessment: Valid gap in R78 gclip.**

R78 gclip is constant-hue projection — it preserves hue angle but desaturates
linearly to the gamut boundary. This is correct for most pixels. The failure
mode is cusp proximity: highly saturated colours near the gamut cusp (deep
red, cyan, yellow-green) get compressed toward neutral faster than they should
perceptually, because the cusp is not equidistant from the Oklab boundary in
all hue directions.

ACES 2's compression uses the cusp luminance and chroma as reference geometry.
In Oklab: the cusp is the point of maximum C for a given hue — find it once
per hue band, use it to normalize the compression distance. This is a
within-shader lookup using HueCeil() (already computed), not a new pass.

**Proposed direction:** Augment R78 gclip with cusp-relative distance
normalisation. Before projection, compute `d_norm = C / HueCeil(hue)`. Apply
a compression function on d_norm rather than on raw C. This gives hue-aware
smooth compression with no structural change to R78.

**Action:** R197 candidate — can be prototyped inside gclip in one pass.

---

### F. Grain spatial correlation (from Tier 2 #9)

**The claim:** Real film grain is spatially correlated; independent per-pixel
noise looks synthetic.

**Assessment: Valid, and cheap to approximate.**

Current R136 grain is per-pixel pcg3d hash — zero spatial correlation. Real
grain clusters in silver halide aggregates; at typical screen viewing distances
the apparent grain texture has structure at 2–4 pixel scale.

The cheapest approximation: at 1/2-res, generate grain normally, then
bilinear-upsample to full res. Bilinear blending at half-res automatically
introduces 2×2 pixel correlation. Zero extra passes — the grain generation
texture just operates at half-res before being composited.

**GPU cost:** Negligible — same pcg3d hash, same Selwyn envelope, half the
invocations. Upsampling is one tex2D fetch.

**Action:** Quick win — implement next grain pass.

---

### G. CAM16 unified appearance adaptation (from Tier 2 #8)

**The claim:** We already implement fragments of CAM16 (Hunt, Purkinje, HK,
Bezold-Brücke, Abney). Unifying under CAM16 would improve coherence.

**Assessment: Partially valid; unification carries risk.**

The fragments are correct individually. The coupling between them is
empirically calibrated rather than derived from a unified adaptation model.
CAM16 full implementation would require luminance adaptation state (absolute
cd/m² values) which we do not have in SDR — the model presupposes a reference
white luminance.

What is salvageable: CAM16's chromatic adaptation transform (CAT16) is already
used in NeutralIllumTex for R83. Expanding CAT16 to drive Hunt coupling
coefficient and HK weight (instead of the current L^0.25 / perceptual
heuristics) would tighten the appearance model internally without requiring
absolute luminance.

**Action:** Note for future unified appearance pass — not blocking anything now.

---

### H. Anamorphic PSF approximation (from Tier 1 #4, measured PSF subset)

**The claim:** Real lens PSFs are asymmetric and field-angle dependent.
Measured PSF kernels would hugely increase realism.

**Assessment: Full measured PSF is out of scope; anamorphic is achievable.**

Storing and applying a measured PSF requires a separable decomposition or FFT
— neither fits SPIR-V without significant complexity. However, the most
visible anamorphic characteristic (horizontal stretch of highlight bokeh) is
achievable with a modified DoG pass: apply the existing inner/outer ring blur
at anisotropic radii (rx > ry by 1.5–2×). This gives the horizontal flare
character of anamorphic without storing a PSF.

**Action:** Low priority — current DoG+Lorentzian produces organic result.
Could add ANAMORPHIC_RATIO control to halation if desired aesthetically.

---

### I. Fast Global Smoother / WLS decomposition (from Tier 1 #2)

**The claim:** Guided filter leaks across strong gradients; WLS/FGS provides
better edge isolation for local tone.

**Assessment: Addressed by R190 adaptive ε; monitor for residual halo evidence.**

R190 already introduced adaptive ε (Hu 2023 method) which tightens guidance
in high-gradient regions — this is precisely the WLS advantage. FGS is
conceptually the iterative limit of adaptive-ε guided filter. The key
difference (FGS uses Laplacian smoothness penalty; GF uses local box variance)
matters most in thin-structure scenes (hair, foliage). If halo artifacts on
depth edges appear in testbed, revisit then.

**Action:** Deferred — R190 adaptive ε covers the main weakness. No evidence
of residual halos in current testbed.

---

### Rejected from second analysis

| Suggestion | Reason |
|------------|--------|
| KLL quantile sketch | Kalman already stabilises percentiles; GPU SPIR-V implementation non-trivial |
| BOCPD scene-cut detection | Kalman damping handles gradual transitions; no observed pumping artifacts |
| JzAzBz / ICtCp | SDR context — already rejected in first analysis |
| HDR-VDP tone allocation | SDR context |
| Wave-optics bloom | FFT-expensive; HDR benefit only |
| Spectral film simulation | Long-term research direction; not actionable in HLSL |
| Neural memory color priors | Requires offline training pipeline |
| Temporal reservoirs (ReSTIR) | Wrong domain — sample-based rendering technique, not grading |
| Laplacian pyramid LTM | Already covered by guided filter + zone S-curve combination |
| Full measured PSF | Separable decomposition / FFT required; out of scope for SPIR-V chain |

---

## Updated priority order (including addendum)

1. **R196-A** — Asymmetric temporal hysteresis on specular_contrast / halation.
2. **R196-B** — Near-clip fraction signal for inverse_grade highlight classification.
3. **R196-E** — Cusp-aware gamut compression augment to R78 gclip. (R197 candidate)
4. **R196-F** — Grain spatial correlation via half-res generation. (quick win)
5. **R196-C** — Operator doubling audit (LOCAL_TONE vs shadow lift). (measure first)
6. **R196-D** — AgX-style per-hue highlight desaturation research. (deferred)
7. **R196-G** — CAM16 unified adaptation note. (future, not blocking)
8. **R196-H** — Anamorphic PSF approximation. (aesthetic, low priority)

---

## Addendum — Perceptual scene reconstruction (third AI analysis)

**Source:** algo.md

Third analysis frames the pipeline's next step as "perceptual scene
reconstruction from SDR constraints" rather than more inverse tone mapping.
Seven points evaluated; three are new and actionable.

---

### J. Illumination/reflectance separation in inverse_grade (from point 3)

**The claim:** SDR tonemappers compress illumination and reflectance differently.
Inverse grade should act on them separately — expansion on reflectance, not on
the full pixel appearance signal.

**Assessment: Valid and directly addresses the testbed yellow/orange issue.**

The decomposition model:

```text
log(pixel) = log(reflectance) + log(illumination)
```

We already have the illumination estimate: `LowFreqMip1Tex` (1/16-res) is the
Retinex illuminant `illum_s0`. The reflectance residual is:

```text
log_reflectance = log(pixel) - log(illum_s0)
```

Currently `inverse_grade.fx` operates on the full pixel signal — it expands
chroma uniformly across pixel appearance, with only scene-level gates
(achromatic fraction, dominant-hue suppression, warm-scene bias). It has no
mechanism to distinguish:

- A warm practical light (illumination-dominated, high illum_s0, low
  reflectance variation) — should NOT expand chroma
- Skin under warm light (reflectance-dominated, moderate illum_s0, meaningful
  reflectance) — should expand chroma
- Emissive FX (extreme illumination, near-zero reflectance signal) — must not
  expand

**Proposed direction:**

Compute `illum_weight = smoothstep(0.30, 0.70, illum_s0)` at each pixel (read
from `LowFreqMip1Samp`). This is 1 at illumination-dominated regions,
0 at dark/reflectance-dominated regions. Gate the chroma expansion strength by
`(1 − illum_weight * ILLUM_GATE)` where ILLUM_GATE is a new knob in
creative_values.

LowFreqMip1 is already passed into `grade.fx` but not into `inverse_grade.fx`.
`inverse_grade.fx` would need to declare and read `CreativeLowFreqSamp` (1/8-res,
already in `corrective.fx` scope) or access `LowFreqMip1` via a new sampler
declaration — the texture is available since it is a cross-technique read
target. Alternatively, encode a scene-level illum_fraction to a highway slot
and use that as a global gate (cheaper, less spatially precise).

**Priority: High** — directly addresses the most persistent testbed artifact
(warm practical over-saturation). Connects to R196-B: near-clip pixels in
illumination-dominated regions should have zero expansion.

---

### K. Unified scene_confidence signal (from point 5)

**The claim:** Multiple independent observation gates (hue gating, scene-cut
override, entropy attenuation) should be unified into a single `scene_confidence`
scalar that gates all temporal adaptation.

**Assessment: Valid, extends R196-A.**

We already have the pieces:
- Hue observation confidence: `R171` gate (only updates Kalman when band present)
- Scene cut override: hard reset to gain=1.0 on p50 spike
- Entropy attenuation: `R195` reduces zone_str when H_norm > 0.55

A unified `scene_confidence` highway signal would be:

```text
confidence = 1.0
confidence *= (1 − scene_cut_strength)       // from slot 199
confidence *= lerp(1.0, 0.5, entropy_excess) // H_norm overshoot
confidence *= lerp(1.0, 0.6, specular_gap)   // p90−p50 burst
```

This single float could then gate:
- Kalman process noise Q (boost Q on low confidence → faster adaptation)
- Asymmetric hysteresis rise speed (from R196-A — slow down rise on low confidence)
- Halation eff_str (existing R162 gate already does part of this)
- inverse_grade chroma expansion strength

**Key observation:** The sources the analysis mentions as confidence-reducing
(particles, muzzle flashes, bloom spikes) all manifest as sudden specular_gap
increases — already in slot 200/p90. The information exists; it just isn't
unified.

**GPU cost:** One additional highway slot write (combine existing signals). No
new analysis passes needed.

**Action:** Implement as extension to R196-A. Write to a new highway slot in
`corrective.fx` HighwayWritePS. Priority after R196-A.

---

### L. Highlight shape priors for inverse_grade classification (from point 6)

**The claim:** Semantic highlight classes, bloom morphology, and local frequency
analysis let a realtime pipeline approximate what diffusion-based inverse tone
mapping does via learned priors.

**Assessment: Valid extension of R196-B.**

R196-B proposes near-clip fraction as the primary classification signal.
This analysis adds two spatial signals that would sharpen the classification:

1. **Highlight compactness:** A compact, high-frequency near-clip region
   (small area, sharp edges) = specular spike — should not expand. A large,
   soft near-clip region (window, sky) = compressed scene luminance — could
   expand. This is measurable at 1/8-res: `near_clip_area / near_clip_perimeter`
   ratio (approximated with 3×3 neighbourhood dilate/erode) is a compactness
   proxy.

2. **Local frequency content at clip boundary:** High local gradient at the
   edge of a near-clip region = structural boundary (specular on dark bg).
   Low local gradient = gradual falloff (wide illumination source). This is
   the Laplacian energy in a neighbourhood around near-clip pixels — expensive
   per-pixel but cheap at 1/8-res on the near-clip mask.

Both signals could be derived from `CreativeLowFreqTex` mip0 (1/8-res,
already in corrective.fx scope) using the near-clip mask defined in R196-B.

**Practical implementation order:**
1. Implement R196-B's near-clip fraction first (scene-level gate)
2. Add compactness signal as second highway slot if fraction alone is
   insufficient
3. Local frequency analysis at clip boundary as stretch target

**Action:** Folds into R196-B implementation — record the spatial extensions
as stretch targets.

---

### Rejected from third analysis

| Point | Reason |
|-------|--------|
| #1 — Learned parametric scene embeddings | HighwayTex already IS the compact scene state vector; the "learned" part requires ML offline training not available in SPIR-V chain |
| #2 — Domain transform / recursive bilateral | Already covered by R196-I — R190 adaptive ε addresses the main guided filter weakness; no perf concern at 1/8-res |
| #4 — Learned hue manifold LUT | Psychovisual parameters are adaptive by design (Purkinje gate, R176 chroma adapt); baking them into a LUT loses scene-responsiveness |
| #7 — Unified appearance-domain processing | Oklab already collapses luma/chroma; full simultaneous processing would require pipeline stage reorder — major rewrite for uncertain gain |

---

## Final priority order (all analyses)

1. **R196-A** — Asymmetric temporal hysteresis on specular_contrast / halation.
2. **R196-J** — Illumination/reflectance separation gate in inverse_grade. (testbed issue)
3. **R196-B+L** — Near-clip fraction + highlight shape priors for inverse_grade.
4. **R196-K** — Unified scene_confidence highway signal. (extends A)
5. **R196-E** — Cusp-aware gamut compression augment to R78 gclip. (R197 candidate)
6. **R196-F** — Grain spatial correlation via half-res generation. (quick win)
7. **R196-C** — Operator doubling audit (LOCAL_TONE vs shadow lift). (measure first)
8. **R196-D** — AgX-style per-hue highlight desaturation research. (deferred)
9. **R196-G** — CAM16 unified adaptation note. (future)
10. **R196-H** — Anamorphic PSF approximation. (aesthetic)

---

## Web search findings — literature strength/weakness assessment per case

**Searches conducted 2026-05-14.** Each case assessed against published
research to confirm, weaken, or reframe the original proposal. Sources listed
inline.

---

### R196-A — Asymmetric temporal hysteresis
**Verdict: STRENGTHENED**

Tariq et al. 2023 "Perceptually Adaptive Real-Time Tone Mapping" (SIGGRAPH
Asia 2023) directly validates asymmetric temporal adaptation as an open
problem in realtime grading. The paper proposes a perceptual contrast-matching
framework with real-time adaptive tone curve estimation, confirming that
frame-reactive pipelines produce appearance inconsistencies.

"Adaptive Temporal Tone Mapping" (Johnson, Utah) addresses asymmetric temporal
adaptation specifically in the tone mapping context — confirming this is a
documented problem class with known solutions.

**New implementation constraint from confidence Kalman literature:** Research
on confidence-weighted Kalman filters (2022–2024) notes that "adaptive
observation noise mutation causes abrupt changes in the Kalman gain, which
reduces stability." The asymmetric EMA for specular_contrast must itself be
EMA-smoothed before being fed into the Kalman confidence path — a raw spike
signal would introduce exactly the instability described. This informs the
implementation: smooth the rise/fall signal before use, not just the output.

---

### R196-B+L — Near-clip highlight classification + shape priors
**Verdict: DIRECTION STRENGTHENED, optical proxies partially weakened**

"Semantic Aware Diffusion Inverse Tone Mapping" (arXiv 2405.15468, 2024)
confirms that highlight classification is the correct approach for SDR→HDR
chroma expansion quality. The paper's method uses FastFCN semantic segmentation
(ADE20K: sky, ground, vegetation, water, human subjects) combined with a
directed acyclic graph of scene luminance relationships to determine what is
clipped and how to handle it.

**Key finding for R196-B:** The paper does NOT classify highlights by optical
properties (specular vs. emissive). Distinction comes from semantic class
identity — what the pixel IS, not how bright it is. This means our near-clip
fraction + compactness proxy is a heuristic approximation of semantic class,
not a direct equivalent. The R196-L compactness/frequency approach is the
closest realtime analogue: compact high-frequency clips → specular (skip
expansion); large soft clips → sky/window (allow expansion).

**Practical conclusion:** Direction is sound and well-validated. Optical
proxies will misclassify edge cases (e.g., a neon sign is compact but should
not have chroma suppressed; a fogged-out window is large and soft but may not
have recoverable chroma). Implement R196-B first as a scene-level guard; treat
R196-L as a refinement pass if scene-level gating proves insufficient.

---

### R196-C — Operator doubling audit (LOCAL_TONE vs shadow lift)
**Verdict: STRENGTHENED as a concern**

Wronski 2022 "Exposure Fusion – local tonemapping for real-time rendering"
confirms: "haloing artifacts can result from both relatively strong settings
as well as some optimizations and limitations of the algorithm." More
specifically, search results confirm that stacked local tone mapping operators
"result in blinking, dark and light halo and other unpleasant artifacts when
the camera moves in dynamic pictures." A separate measurement result: "both
types of artifact become perceptible from 1% onwards when spatial extent is
adjusted."

Literature confirms this is a real risk class. The guidance stands: measure
on a dark interior frame with each operator isolated before coupling them.

---

### R196-D — AgX per-hue highlight desaturation
**Verdict: WEAKENED in extractability, concept confirmed**

AgX research confirms the "path to white" — graceful desaturation as colours
approach highlight — corrects the "Notorious 6" hue shifts that ACES produces.
The darktable AgX module and reshade.me AgX DRT shader document this behaviour.

**Key finding that weakens the case:** AgX's highlight desaturation is NOT a
separate operator — it is intrinsic to the tone scale transform, achieved by
adjusting input primaries before the curve is applied. The "path to white" is
tone-scale-integrated. Extracting just the per-hue desaturation rolloff into
our existing FilmCurve without adopting the full AgX tone scale would require
reverse-engineering the implicit desaturation curves, which vary by hue in a
way that is not publicly specified as standalone curves.

**Revised proposal:** Research the darktable AgX source code for the per-hue
rolloff curves as a reference, then implement as an additional smoothstep-gated
chroma attenuation on top of the FilmCurve shoulder — similar to R133 Munsell
rolloff but driven by highlight proximity rather than hue-band-specific ceilings.
This is viable but requires a separate research pass before implementation.

---

### R196-E — Cusp-aware gamut compression
**Verdict: STRONGLY STRENGTHENED — HueCeil() is already the cusp**

ACES2 documentation confirms the cusp-based compression approach in
production at scale. The ACES2 DRT uses JMh space (Hellwig 2022 CAM), where
the cusp is the point of maximum chroma (M) for each hue. Normalization:
`M_norm = M / cusp_M(hue)`. A power-law compression function is applied on
M_norm rather than raw M.

**ACESCentral forum finding:** The AP1 cusp can be approximated with a
trigonometric function (6 cosine/sine coefficients) achieving average pixel
error of ~0.000607 — "imperceptible to pixel-peeping." No LUT needed.

**Critical alignment with our pipeline:** `HueCeil()` already stores the
maximum chroma ceiling per hue band — this IS the Oklab equivalent of the
ACES2 cusp. Our proposed `d_norm = C / HueCeil(hue)` matches the ACES2
normalization principle exactly. We just need to replace the current hard
projection with a smooth power-law or Reinhard-style compression on d_norm.

ACES2 production validation + alignment with existing `HueCeil()` infrastructure
makes this a **fast, high-confidence implementation.** Elevate from "R197
candidate" to immediate next implementation target.

---

### R196-F — Grain spatial correlation
**Verdict: STRONGLY STRENGTHENED**

Multiple independent sources confirm the perceptual gap:
- "Real crystals don't distribute randomly — they cluster based on emulsion
  chemistry. Fine-grain films like T-Max use Poisson clustering; Tri-X and
  HP5 show fractal patterns." (grain simulator research)
- "Procedural approach will ensure the grain will never tile, but the result
  is actually a noise and does not resemble the granularity of film grain at
  all. It does look more like a digital sensor noise." (realtime shader
  survey)

The half-res bilinear approach is directly supported: Wronski's bilinear
upsampling article confirms that bilinear sampling at half-res introduces
2-texel correlation naturally, with known pixel grid alignment considerations
(half-pixel offset must be handled correctly to avoid systematic bias).

**Confirmed quick win.** Trivially differentiates film grain from digital
noise — the perceptual difference is immediate on visible grain strengths.

---

### R196-G — CAM16 unified adaptation
**Verdict: WEAKENED — absolute luminance requirement confirmed as blocker**

Search confirms CAM16 is validated for SDR ("CAM16 obtains the best marks for
SDR images," 2024 color appearance model comparison). Active research
continues (CAM16-UCS for HDR viewing conditions, 2025).

**Key constraint confirmed:** CIECAM02/16 "takes into account the environment
of each color" by requiring absolute luminance (cd/m²) for the adaptation
state. SDR [0,1] values do not encode absolute luminance. Our CAT16 usage for
NeutralIllumTex is already the most tractable part of CAM16 that works without
absolute luminance — it computes chromatic adaptation in relative terms.

Remain a future note. No change to assessment.

---

### R196-H — Anamorphic PSF approximation
**Verdict: WEAKENED — aesthetic only, no technical obligation**

Anamorphic halation in realtime is a well-explored aesthetic choice (Wronski
2015, KinoStreak Unity shader, Blender anamorphic bokeh). The Blender
developers note: "with simple Gaussian blurs using a real stretch ratio of
2:1 it is impossible to achieve the extreme effect of anamorphic flares seen
in movies."

Our DoG + Lorentzian halation already produces organic film-like scatter. The
case for anamorphic would be an explicit aesthetic goal (emulating anamorphic
lens character), not a quality improvement. Our testbed does not use anamorphic
game content. Drop this from the priority list entirely unless the user
requests it as an aesthetic feature.

---

### R196-J — Illumination/reflectance separation in inverse_grade
**Verdict: STRONGLY STRENGTHENED**

2023–2024 Retinex research overwhelmingly validates this decomposition as the
standard foundation for low-light enhancement and SDR→HDR expansion:

- "The primary assumption of Retinex theory is that an image can be decomposed
  into illumination and reflectance components" — foundational, confirmed
- "Reti-Diff extracts reflectance and illumination priors to facilitate
  detailed reconstruction" (ICCV 2023) — state of the art uses exactly this
- "A variational framework based on synergy between illumination and
  reflectance for Retinex decomposition" (ScienceDirect 2025) — active area
- "A depth iterative illumination estimation network for Retinex-based
  low-light enhancement" (Scientific Reports 2023) — iterative refinement
  of illumination estimate improves reconstruction quality

**All papers use the same decomposition we proposed:** illumination estimate
from a low-frequency luminance field (equivalent to our LowFreqMip1Tex
illum_s0), reflectance = pixel / illumination, chroma reconstruction on
reflectance component.

Our infrastructure is already the standard approach. The implementation is
a one-sampler-declaration change in inverse_grade.fx plus a gate expression.

---

### R196-K — Unified scene_confidence signal
**Verdict: STRENGTHENED IN CONCEPT, implementation complexity elevated**

Confidence-weighted Kalman filter research (2022–2024) confirms the mechanism
is valid but flags a specific instability risk: "The NSA Kalman filter
introduces confidence deviation as the observation noise scale variable, but
the adaptive observation noise mutation causes abrupt changes in the Kalman
gain, which reduces stability." Specifically: "strong fluctuations in the
adaptive observation noise introduced through detection confidence will cause
mutation noise of the Kalman gain to weaken prediction stability."

**Mitigation from literature:** "The Smoothing Gain Kalman filter combines
the Gaussian function with the adaptive observation coefficient matrix to
stabilize the mutation noise." This translates directly: the `scene_confidence`
highway signal must be EMA-smoothed before use as a Kalman process noise
modifier. Using the raw specular_gap or scene_cut signal directly would
introduce exactly the instability described.

**Revised implementation note:** The confidence highway value must have its
own temporal EMA (τ ≈ 0.2s to damp transient spikes) before it gates Kalman
noise. This adds one EMA state variable but removes the instability risk.
The gating of non-Kalman systems (halation, inverse_grade) can use the raw
signal; only Kalman Q modulation needs the smoothed version.

---

## Web-search-revised final priority order

Changes from pre-search order in brackets.

1. **R196-J** — Illumination/reflectance separation in inverse_grade.
   **[UP from 2]** STRONGLY STRENGTHENED. Infrastructure exists. One-pass change.
   Directly addresses testbed warm-practical over-saturation.

2. **R196-E** — Cusp-aware gamut compression to R78 gclip.
   **[UP from 5]** STRONGLY STRENGTHENED. HueCeil() IS the cusp. ACES2
   production-validated. Replace hard projection with smooth power-law on
   d_norm = C / HueCeil(hue). Fastest high-confidence win in the list.

3. **R196-F** — Grain spatial correlation via half-res generation.
   **[UP from 6]** STRONGLY STRENGTHENED. Perceptual gap confirmed by multiple
   independent sources. Cheapest implementation in the list. Do this next
   grain pass.

4. **R196-A** — Asymmetric temporal hysteresis on specular_contrast / halation.
   **[DOWN from 1]** Still strengthened, but implementation constraint added:
   EMA-smooth the derived confidence signal before feeding Kalman Q. Slightly
   more complex than originally scoped.

5. **R196-B+L** — Near-clip fraction + highlight shape priors.
   **[HELD at 3]** Direction confirmed. Optical proxies are the correct realtime
   substitute for semantic segmentation. Implement scene-level fraction first.

6. **R196-K** — Unified scene_confidence signal.
   **[HELD at 4]** Concept strengthened; implementation elevated in complexity
   (needs own EMA to avoid Kalman instability). Implement after R196-A.

7. **R196-C** — Operator doubling audit.
   **[HELD at 7]** Concern confirmed by literature. Measure before acting.

8. **R196-D** — AgX per-hue highlight desaturation.
   **[DOWN from 8]** Weakened in extractability. Requires research into darktable
   AgX source for per-hue rolloff curves before implementation is possible.

9. **R196-G** — CAM16 unified adaptation.
   **[HELD at 9]** Absolute luminance blocker confirmed. Future note only.

10. **R196-H** — Anamorphic PSF.
    **[HELD at 10, demoted to aesthetic-only]** No technical obligation.
    Remove from active pipeline development list.
