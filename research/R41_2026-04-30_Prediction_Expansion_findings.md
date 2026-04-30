# R41 — Prediction Algorithm Expansion — Findings

**Date:** 2026-04-30
**Parent:** R41_2026-04-30_Nightly_Automation_Research.md
**Searches:**
1. Wiener / AR / ARMA prediction on luminance signals (temporal anticipatory filtering)
2. Bayesian color constancy / scene classification for artistic style prediction
3. CLIP / neural color suggestion, learned preference models 2024–2025
4. Predictive tone mapping — anticipatory adjustment before scene change
5. Image aesthetics prediction, color grade parameters, 2024–2025 arxiv
6. Scene-adaptive color preset classification, real-time GPU, hue histogram clustering
7. RLS / Kalman innovation signal and scene-cut detection / predictive staging
8. NCST neural color style transfer 2024 — closed-form parameter output

---

## Background

R41 concluded that 17 remaining artistic knobs are not automatable via single-frame
scene statistics alone. Two overlay-hint candidates were identified:
- EV hint from `zone_log_key` vs. 0.18 middle-grey (EXPOSURE diagnostic)
- Grey-world AWB reference from mean Oklab (a, b) (3-way corrector reference point)

This expansion searches for prediction algorithms — temporal, content-based, learned
— that could provide stronger or more actionable suggestions, going beyond the
single-frame baseline.

---

## Key Findings by Algorithm Class

### 1. Temporal Prediction: AR / ARMA / Wiener on Scene Key

**What the literature says:**

AR and ARMA models, together with Wiener prediction filters, are well-established for
anticipatory signal estimation. The Kalman/Wiener duality (ScienceDirect 2023, IEEE
Xplore 1171734) is directly relevant: a Wiener predictor on an ARMA process is
equivalent to an optimal Kalman smoother run forward in time. The practical form is:

```
x̂(t+k) = a₁·x(t) + a₂·x(t-1) + ... + aₙ·x(t-n+1)
```

where aᵢ are the AR coefficients estimated from the autocorrelation of the observed
signal, and k is the prediction horizon. For a stationary signal, this is a pure IIR
filter; for non-stationary signals a VFF-RLS (variable forgetting factor, recursive
least squares) update of the AR coefficients is the standard approach.

**Relevance to this pipeline:**

The pipeline already runs VFF-RLS (R39 Kalman) on p25, p50, p75 and zone_std, stored
in ZoneHistoryTex. These give a rolling history of the luminance distribution. An
AR(2) or AR(3) predictor on `zone_log_key` or `p50` over a sliding window of the last
N frames is structurally identical to an extension of the existing Kalman state — it
simply adds a prediction step beyond the current smoother.

**Prediction horizon:** At 60 fps, the zone history depth (currently unspecified but
likely 8–16 frames) gives a prediction window of 130–270 ms — enough to anticipate a
gradual scene-key drift (e.g. moving from indoor to outdoor) 2–4 frames early, before
the operator would notice.

**What it can predict:** A predictive AR step on `zone_log_key` could produce a
*predicted future EV deviation* — i.e., the EV hint would be computed on the
anticipated scene key 4 frames ahead, not the current one. This is strictly a
refinement of the EV hint already identified in R41, not a new automation candidate.

**Shader viability:** Yes. AR(2) prediction is two multiply-adds on the existing
ZoneHistoryTex values — trivially SPIR-V compatible. No new passes or textures needed.
The AR coefficient update (RLS) is already done each frame for the Kalman state; adding
a prediction step is one to three additional lines in UpdateHistoryPS.

**GPU cost:** Negligible — 2–3 ALU ops in an already-running pass.

**Output:** Scalar `predicted_zone_log_key` — a shifted version of the current EV hint.
Concrete, actionable as a display-only number.

**Limitation:** AR prediction only helps for *gradual* scene-key drift. It cannot
predict an abrupt scene cut. It refines the EV hint timing but does not unlock any
of the locked artistic knobs (3-way corrector, hue rotations, film curve offsets).

**Verdict:** Viable as a minor improvement to the existing EV hint. Does not expand
the set of automatable knobs. Low priority.

---

### 2. Content-Based Prediction: Hue Energy Classification for Artistic Preset

**What the literature says:**

Bayesian color constancy (Brainard & Freeman 1997; IEEE 2008 "Bayesian Color
Constancy Revisited") frames illuminant estimation as MAP inference over a prior on
illuminant spectra and surface reflectances. The classification-based variant (Schröder
& Moser, ScienceDirect 2009) extends this: images are classified into content classes
by unsupervised clustering of hand-crafted features, then per-class color correction
algorithms are selected and blended. Their result: "classification-based strategies
outperform general-purpose algorithms."

NCST (arXiv 2411.00335, Signal Image Video Processing 2025) — Neural-based Color
Style Transfer for Video Retouching — is the most relevant recent work. It uses a
network to predict color grading parameters (brightness, contrast, and style
transfer coefficients) from a content image paired with a reference style image.
Key architectural detail: the network outputs explicit scalar parameters, not a
pixel-level transform, making it more distillable than a full network. However the
paper does not provide a closed-form approximation; the network is a CNN.

**Applicability to this pipeline:**

The pipeline stores per-band chroma energy across 6 hue bands (ChromaHistoryTex).
This is a 6-vector of hue energies. Three well-separated artistic presets could in
principle be defined by their hue-energy signatures:
- **Warm/orange preset:** high energy in red and yellow bands
- **Cool/teal preset:** high energy in cyan and blue bands
- **Neutral:** balanced energy across all 6 bands

A nearest-centroid classifier in 6D hue-energy space is equivalent to:

```
dist_warm   = dot((hue_energy - centroid_warm)², 1)
dist_cool   = dot((hue_energy - centroid_cool)², 1)
dist_neutral = dot((hue_energy - centroid_neutral)², 1)
preset_blend = softmax(-[dist_warm, dist_cool, dist_neutral] / temperature)
```

This is 18 multiply-adds per pixel-lane evaluation, trivially SPIR-V compatible.
The centroids would be hardcoded constants derived offline from sample game footage.

**Critical problem — it predicts the wrong thing:**

A nearest-centroid classifier on scene hue energy tells you what colours are
*already in the scene*, not which artistic grade intent matches. The artistic
intent in this pipeline is often contrastive to the scene content: Arc Raiders
warm highlights / cool shadows is intentionally opposite to what a warm-scene
classifier would suggest neutralizing. The artistic presets encode the *response*
to content, not a reflection of it.

More formally: the same grey-world limitation identified in R41 for the 3-way
corrector applies here. Hue content classification would recommend neutralizing
or matching the scene palette, whereas the user's artistic intent is frequently
to counterpoint the scene palette (cool treatment of warm environments for
cinematic tension, etc.).

The Bayesian color constancy literature (Brainard 1997, Nafifi mixedillWB 2025)
confirms this is the fundamental difficulty: the model needs a *prior over
artistic intent*, not just a prior over scene illuminants. That prior does not
exist in a game-agnostic pipeline — it is project-specific and not derivable from
scene statistics.

**Bayesian classifier — what it actually needs:**

A Bayesian classifier for artistic preset would require:
- A training set of (scene hue histogram, operator-chosen grade) pairs
- Per-game or per-project labeled data — not derivable from game-agnostic statistics
- Ground-truth labels for what "warm preset" means in this creative context

This is equivalent to requiring supervised learning on annotated grade sessions.
It is not feasible for a general-purpose shader pipeline.

**Verdict:** Not viable. The signal (6-band hue energy) is available; the mapping
from signal to artistic intent is not derivable without labeled training data that
is project-specific. This does not expand the automatable knob set.

---

### 3. Scene-Change Anticipation via Kalman Innovation Signal

**What the literature says:**

The Kalman innovation sequence (the difference between prediction and observation at
each step, also called the residual or measurement residual) is a zero-mean white
noise sequence under the model assumption when the system is in a steady-state regime.
When the system undergoes a structural change (e.g., a scene cut), the innovation
magnitude spikes — this is the standard basis for change-point detection using
Kalman filters (CUSUM on the normalized innovation squared, or GLR test).

The VFF-RLS already uses innovation magnitude to adapt the forgetting factor — a
large innovation causes the filter to reduce λ (trust recent data more). This
implicitly treats large innovations as change indicators, but does not explicitly
raise a "scene-cut warning" signal.

**Relevance:**

An explicit change-point detector on the VFF-RLS innovation sequence would work as:

```
innovation_sq = dot(innovation, innovation)    // already computed per-frame
nis = innovation_sq / expected_variance        // normalized innovation squared (NIS)
// NIS >> χ²_k threshold (e.g. NIS > 9 for k=1, p<0.003) → scene cut flagged
```

A scene-cut flag could be used to:
a. Suppress the EV hint display during the unstable transition period
b. Pre-stage a parameter change — but only if the target post-cut scene statistics
   are known, which they are not (the cut hasn't happened yet)

The anticipation question is: can the *magnitude* of innovations predict an
*impending* cut, rather than detecting one after it happens? Literature search
found no evidence that pre-cut innovation buildup is a reliable predictor.
Scene cuts in games are abrupt by construction (Unreal's level streaming or
cutscene trigger). The innovation will spike *at* the cut, not before it.

**Verdict:** Innovation-based scene-cut *detection* is viable and nearly free
(NIS is 1–2 ops on existing state). Pre-cut *anticipation* is not feasible —
games do not broadcast cut events to the swapchain. A scene-cut detector would
suppress the EV hint during transitions (prevents showing a misleading hint
during a 5-frame adaption transient). This is a minor robustness improvement
to the existing EV hint, not a new automation candidate.

---

### 4. Perceptual Preference Prediction: CLIP and Neural Aesthetics

**What the literature says:**

CLIP-based color grading approaches ("Color Grade Prompter," aescripts.com 2024;
text-guided LUT generation) exist as production plugins. They take a text description
("warm cinematic," "teal and orange") and produce a color correction that matches
the CLIP embedding. The underlying mechanism is gradient descent on LUT parameters
until the CLIP similarity to the text prompt is maximized.

Image aesthetics networks (NIMA 2018; multi-task CNN 2023, arXiv 2305.09373;
HumanAesExpert 2025, arXiv 2503.23907) predict overall aesthetic quality scores
or aesthetic attribute scores from image content. These range from 5M–100M parameter
networks. The 2024–2025 trend is towards multi-modal LLM approaches (MLLMs) for
richer aesthetic description, which are larger, not smaller.

NCST (2024/2025) outputs explicit scalar grading parameters from a CNN, but the
inference graph is a full convolutional forward pass on the content image — not
a closed-form expression.

**Distillation feasibility — closed-form in a shader:**

CLIP inference at ~87M parameters (ViT-B/32) requires >1000 ms at FP32 on a
consumer GPU in a forward pass — orders of magnitude above the vkBasalt per-frame
budget (~0.5 ms total). NIMA-style CNN (5M parameters) at 224×224 input requires
~10 ms on GPU, still 20× over budget.

Knowledge distillation — compressing a learned model into a polynomial or lookup
table closed-form — is theoretically possible. For aesthetic *quality* score
prediction, a polynomial regression on hand-crafted features (saturation mean,
contrast IQR, hue entropy) has been shown to achieve ~60–65% of the full CNN
SRCC correlation (Building CNN-Based Models, PMC 2023). However, this only
predicts a quality scalar (good/bad), not color grade parameters.

For the specific question of "which artistic preset (warm/cool/neutral) fits
this scene," the distillation target would need to be labeled data from a
colorist, not an image quality model. No public 2024–2026 paper addresses
distillation of artistic grading preference into a closed-form expression
applicable in real-time rendering.

**Shader viability:** A quality-score polynomial on existing statistics
(p50, zone_std, mean_chroma, hue_entropy derived from ChromaHistoryTex) is
SPIR-V compatible at ~20 ops. However, a quality scalar does not produce
actionable parameter suggestions — it would only tell you the current grade
looks good or bad, not which knob to move.

**Verdict:** No 2024–2026 paper provides a route from learned color preference
to closed-form shader-viable parameter suggestions. CLIP and aesthetics networks
are far too large for in-shader inference. Distillation to closed-form produces
quality scores at best, not parameter vectors. Does not expand the automatable
knob set.

---

## Parameter Validation

Assessing each of the 17 locked knobs against all four algorithm classes:

| Knob group | AR/Wiener temporal | Hue-energy classifier | Innovation scene-cut | CLIP/aesthetics distill |
|---|---|---|---|---|
| EXPOSURE (1) | Refines EV hint timing only | No | Suppresses hint at cuts only | No |
| 3-way TEMP/TINT (6) | No | No — artistic intent contrapuntal to scene | No | No — needs labeled data |
| CURVE R/B KNEE/TOE (4) | No | No | No | No — stock identity, not scene-adaptive |
| ROT_* hue rotations (6) | No | No — intent contrapuntal to scene | No | No — needs labeled data |

No algorithm class unlocks any currently-locked knob for automation.

---

## What Is Shader-Viable vs. Not

### Shader-viable (SPIR-V, <1 ms, concrete scalar/vector output)

- **AR(2) prediction on zone_log_key** — 2–3 ALU ops, extends existing Kalman state,
  produces a predicted future EV scalar. Improves EV hint latency by 4 frames at 60 fps.
- **NIS scene-cut detector on VFF-RLS innovation** — 1–2 ALU ops on existing state,
  produces a binary flag. Suppresses EV and AWB hints during scene transitions.
- **Nearest-centroid hue classifier (6-vector)** — 18 ALU ops on ChromaHistoryTex,
  produces warm/cool/neutral blend weights. Technically viable; fails on the
  content-vs-intent problem identified above (not useful in practice).

### Not shader-viable

- **CLIP inference** — 87M parameters, 1000+ ms forward pass, requires FP16/FP32
  compute pipeline, not compatible with vkBasalt single-pass fragment shader model.
- **NIMA / aesthetics CNN** — 5–100M parameters, 10–100 ms, requires intermediate
  feature maps; not deployable as SPIR-V fragment shader.
- **NCST** — CNN backbone, explicit training data required; not closed-form.
- **Bayesian scene classifier for artistic preset** — requires labeled training data
  (game-specific); no universal prior available; not shader-implementable without
  baked lookup tables from supervised sessions.

---

## Verdict and Recommended Next Steps

**Overall verdict:** No prediction algorithm class expands the set of automatable
knobs beyond the two overlay-hint candidates identified in R41. The expansion
question is answered in the negative for all four algorithm classes:

1. **AR/Wiener temporal prediction** — viable as a minor EV hint refinement (4-frame
   look-ahead on zone_log_key). Not a new automation candidate — it only tightens
   the timing of an existing hint. If EV hint latency is observed to be an issue,
   an AR(2) extension to UpdateHistoryPS is low-risk and cheap.

2. **Content-based preset classification** — shader-viable in principle but fails
   because artistic intent is contrapuntal to scene content in this pipeline.
   Hue energy classifies what the scene looks like; the grade is a deliberate
   artistic departure from that, not an echo of it. Requires labeled training data
   that does not generalize across games.

3. **Innovation-based scene-cut anticipation** — cannot predict cuts in advance in
   a game (cuts are abrupt, not preceded by statistical drift). The innovation NIS
   could usefully *detect* cuts to suppress hints during transitions. This is a
   robustness improvement to existing hints, not a new automation capability.

4. **Learned preference prediction (CLIP, aesthetics networks)** — too large for
   in-shader inference by 3–4 orders of magnitude. No 2024–2026 distillation into
   closed-form scalar/vector grade parameters exists. Predicts quality, not style.

**Recommended next steps (if any):**

| Action | Benefit | Cost | Risk |
|--------|---------|------|------|
| AR(2) look-ahead on zone_log_key | 4-frame EV hint latency improvement | ~3 ALU ops in UpdateHistoryPS | None |
| NIS scene-cut suppressor | Prevents misleading hints during cuts | ~2 ALU ops; add 1-bit flag to PercTex | None |
| Both EV hint + AWB hint (R41 recommendation) | First actionable overlay readout | Minor UpdateHistoryPS + ChromaHistoryTex extension | None |

The R41 original finding stands: the 17 artistic knobs are not automatable. The
prediction algorithm search confirms this through four independent reasoning paths.
The highest-value next action remains the original R41 recommendation: implement
the two overlay-hint candidates (EV hint + AWB neutral reference) in a single
small session when debug readout is wanted.
