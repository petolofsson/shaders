# Lateral Research — Climate Science / Data Assimilation — 2026-05-10

## Domain this week

**Climate science / data assimilation** — ISO week 19, 19 % 7 = 5.

Data assimilation is the discipline of fusing sparse, noisy real-time observations with
a prior model state to produce an optimal analysis. It is the mathematical backbone of
numerical weather prediction and has driven 40+ years of rigorous work on Kalman variants,
covariance localization, ensemble methods, and optimal sampling — all problems the pipeline
faces in its analysis passes.

Search databases: arxiv physics.ao-ph, Tellus A, Monthly Weather Review, Quarterly Journal
of the Royal Meteorological Society.

---

## Pipeline problems targeted

1. **State estimation / temporal filtering** — `corrective.fx` SmoothZoneLevelsPS and
   UpdateHistoryPS. Current: VFF Kalman (R39) + scene-cut spike (R53). The open question is
   whether P is inflated correctly when a hue band receives no real observations.

2. **Sparse scene sampling** — UpdateHistoryPS samples 8 Halton points per frame shared
   across 6 chroma bands. A band absent from the frame still runs a full Kalman update
   against a noise-contaminated mean. Climate science's "covariance localization" principle
   directly addresses this.

3. **Multi-scale basis decomposition** — CreativeLowFreqTex 3-mip Laplacian residual and
   pro_mist mip blending. Climate science's scale-dependent background-error covariance
   (MGBF/SDL) literature addresses how different spatial scales should carry different
   process noise.

---

## HIGH PRIORITY findings

### Observation-weight-gated Kalman P inflation ("covariance localization" for hue bands)

**Why HIGH PRIORITY:** Eliminates a silent error in the existing VFF Kalman implementation
with zero extra passes and three lines of changed math. Medium-High visual benefit.

The pipeline accumulates 8 Halton samples per frame and distributes them to 6 hue bands via
`HueBandWeight(h, center) + MIN_WEIGHT`. `MIN_WEIGHT = 1.0` guarantees every sample
contributes at least 1.0 weight to every band regardless of its actual hue. When a hue is
absent from the frame (e.g., no cyan content), band 4 still receives `sum_w = 8 × MIN_WEIGHT
= 8.0`, and the Kalman mean `new_mean` is a hue-agnostic average of all sampled chromas.

The VFF then computes `|e_chroma| = |bogus_mean - prev.r|` which is nonzero, inflates
`Q_vff_c` toward `KALMAN_Q_MAX`, and raises `K` — pulling the band's state toward a noisy,
hue-incorrect value. Over successive frames this produces slow, incorrect chroma drift for
bands absent from the scene.

**Climate science analogue:** covariance localization in ensemble Kalman filters. When an
observation is spatially remote from a state variable, its update weight on that variable is
talpered to zero. Here "distance" is hue distance rather than spatial distance.

**Fix (pure math in UpdateHistoryPS):**
```hlsl
// confidence: how much excess weight above the MIN_WEIGHT floor?
float obs_confidence = saturate(
    (sum_w - float(8) * MIN_WEIGHT) / (float(8) * 0.5)
);
// gate P inflation: don't inflate when no real hue-matching samples
float Q_vff_c = lerp(KALMAN_Q_MIN,
                     lerp(KALMAN_Q_MIN, KALMAN_Q_MAX,
                          smoothstep(0.0, VFF_E_SIGMA_CHROMA, abs(e_chroma))),
                     obs_confidence);
```

When `obs_confidence → 0` (band absent), `Q_vff_c → KALMAN_Q_MIN` (tiny process noise),
`P_pred` stays low, `K` stays low, and the state freezes instead of drifting. When the hue
reappears, the full VFF range is restored.

**ROI:** Visual High / Implementation Low

---

## Findings

### [High-dimensional EnKF with adaptive covariance inflation — Sun et al. 2024]
- **Source:** Quarterly Journal of the Royal Meteorological Society, 2024
- **Pipeline target:** SmoothZoneLevelsPS — per-zone Kalman P update
- **Mathematical delta:** The paper combines statistically consistent covariance estimators
  with adaptive inflation in a single pass. Rather than choosing Q_MAX empirically, the
  inflation factor is solved as a Bayesian posterior from the running innovation sequence.
  Concretely: `Q_opt = max(0, (e² − R) / (H P_pred Hᵀ + R))` where the numerator is the
  innovation minus measurement noise — a per-step optimal inflation derived from data rather
  than the scalar KALMAN_Q_MAX constant. In steady-state this converges to the same value,
  but during transients it adapts faster with no user-tunable Q_MAX needed.
- **GPU cost:** Pure math. Replace the `smoothstep(0.0, VFF_E_SIGMA, abs(e))` Q lookup with
  the innovation-based formula. One extra divide per zone per frame.
- **ROI:** Medium visual / Low implementation
- **Novelty:** Innovation-based Q tuning has not appeared in real-time rendering. The VFF
  analog (`Q_vff = lerp(Q_MIN, Q_MAX, smoothstep(...))`) is already in the pipeline (R39),
  but the adaptive Q_MAX derivation from innovation statistics is new.
- **Conflict:** None with pipeline constraints.
- **Search:** `Ensemble Kalman filter non-stationary adaptive covariance inflation real-time
  2023 2024 2025`

---

### [Variable forgetting factor with directional/subspace forgetting — VDF-RLS]
- **Source:** IEEE Signal Processing literature (IET Signal Processing, multiple 2024 results)
- **Pipeline target:** UpdateHistoryPS EMA for std and wsum secondary channels
- **Mathematical delta:** Standard VFF (already in pipeline as R39) applies a scalar forgetting
  factor to all state dimensions equally. Directional/subspace forgetting (VDF-RLS, SIFt-RLS)
  applies forgetting only in directions excited by new data — dimensions orthogonal to the
  observation subspace are frozen. In the pipeline: `new_std` and `new_wsum` use fixed
  `KALMAN_K_INF = 0.095` EMA regardless of whether new chroma data arrived. With subspace
  forgetting, their gain would be tied to `obs_confidence` above — only update std/wsum when
  the band actually has new observations.
- **GPU cost:** Zero extra passes. Two extra multiplies in UpdateHistoryPS.
- **ROI:** Low-Medium visual / Low implementation
- **Novelty:** Subspace forgetting has not appeared in real-time rendering. The pipeline's
  existing VFF (R39) is scalar; this adds per-dimension confidence weighting.
- **Conflict:** None. Complements the HIGH PRIORITY finding above — apply `obs_confidence`
  to the EMA gain as well: `k_ema = lerp(0.0, lerp(KALMAN_K_INF, 1.0, scene_cut), obs_confidence)`.
- **Search:** `recursive Bayesian estimation adaptive forgetting factor non-stationary signal
  convergence 2024 2025`

---

### [Spatially varying decorrelation length in optimal interpolation — NWP literature]
- **Source:** Geoscientific Model Development 2025; Tellus A (scale-dependent localization)
- **Pipeline target:** ZoneHistoryTex → grade.fx zone normalization (Stage 2 Retinex + zone S-curve)
- **Mathematical delta:** The 4×4 zone grid uses bilinear interpolation between zone centers
  (LINEAR sampler). Optimal interpolation (OI) from NWP uses a spatially varying Gaussian
  structure function: `C(d) = exp(−d² / 2L²)` where the decorrelation length `L` adapts to
  local scene complexity. In practice, zones with high zone_std (high contrast) should have
  a short L (sharp zone boundaries reflect real structure); zones with low zone_std should
  have a long L (smooth illumination → blend liberally with neighbors). This would reduce
  seaming at zone boundaries in high-contrast scenes while keeping the smoothing in flat scenes.
  The multigrid beta filter (MGBF) literature applies this at multiple spatial scales
  simultaneously.
- **GPU cost:** One extra texture read per pixel (precompute per-zone L into a 4×4 texture
  written in UpdateHistoryPS from zone_std). Then the bilinear interpolation in grade.fx
  remains but is informed by a data-driven L. Alternatively, approximate with a single
  zone_std-weighted blend: already partially done via `lerp(10, 30, smoothstep(..., zone_std))`
  in the spatial normalization strength.
- **ROI:** Medium visual / Medium implementation
- **Novelty:** OI-style spatially varying localization radius has not appeared in real-time
  post-processing. The pipeline's fixed bilinear interpolation is the naive baseline.
- **Conflict:** Adds a pass or complicates UpdateHistoryPS. Given GPU budget constraints for
  Arc Raiders (VK_ERROR_DEVICE_LOST history), must be verified cost-neutral.
- **Search:** `optimal interpolation covariance localization decorrelation length scale
  spatially varying 2023 2024 2025`

---

### [Sparse Gaussian Process with nonstationary composite kernels — Springer 2025]
- **Source:** Mathematical Geosciences 2025 — sparse spectrum representation for nonstationary
  geo-data
- **Pipeline target:** CreativeLowFreqTex mip structure / pro_mist IQR-driven radius
- **Mathematical delta:** Composite kernel = stationary global component (like the current
  fixed mip blur) + nonstationary local component (like the IQR-driven radius). The 2025 paper
  shows that the composite outperforms either alone by adapting to local signal variance while
  retaining global smoothness. In pro_mist: the mip 0+1 blend is currently weighted by a
  fixed 0.5/0.5 split with IQR-driven scatter radius. A locally adaptive blend weight
  (heavier mip1 in flat regions, heavier mip0 in structured regions) would better separate
  fine detail from coarse mist.
- **GPU cost:** One extra texture read (zone_std lookup from ChromaHistoryTex col 6) to
  compute the local blend weight. Zero extra passes.
- **ROI:** Low-Medium visual / Low implementation
- **Novelty:** Composite stationary+nonstationary kernel blending has not appeared in
  real-time mist/bloom effects.
- **Conflict:** None.
- **Search:** `optimal interpolation covariance localization decorrelation length scale
  spatially varying 2023 2024 2025`

---

### [Entropy-initialized sensor placement for field reconstruction — DeepAI / JCP 2024]
- **Source:** Journal of Computational Physics 2024; DeepAI information entropy concrete autoencoder
- **Pipeline target:** UpdateHistoryPS Halton sampling strategy
- **Mathematical delta:** Current Halton sequence is purely geometric (maximizes spatial
  coverage uniformly). Entropy-based placement concentrates sensors where conditional entropy
  is highest — regions of highest uncertainty. In the pipeline, `P` from ZoneHistoryTex
  identifies which screen zones are most uncertain. Biasing Halton sample UVs toward
  high-P zones would make each frame's 8 samples more informative.
  Practical implementation: after computing Halton UV, add a small jitter proportional
  to (zone_P − global_mean_P) × jitter_scale, clamped to CLAMP address mode.
- **GPU cost:** One extra texture read (ZoneHistoryTex P channel) per Halton iteration = 8
  reads in UpdateHistoryPS. Pure UV perturbation, no extra passes.
- **ROI:** Low visual / Medium implementation (zone UV mapping for the bias is non-trivial)
- **Novelty:** Information-entropy-driven sample placement has not appeared in real-time
  analysis pass design.
- **Conflict:** The chicken-and-egg issue: P from ZoneHistoryTex is computed before
  UpdateHistoryPS (pass 4 writes ZoneHistoryTex, pass 5 reads it) — so the ordering is
  already correct. No ordering conflict.
- **Search:** `ensemble data assimilation sparse observation optimal placement information
  content 2024 2025`

---

## ROI table

| Finding | Visual impact | GPU cost | Recommended action |
|---------|--------------|----------|--------------------|
| Obs-weight-gated Kalman P inflation (HIGH PRIORITY) | High | Zero passes, 3 lines | Implement — R91 candidate |
| Directional EMA freeze for absent hue bands | Medium | Zero passes, 2 lines | Bundle with above into R91 |
| Innovation-derived adaptive Q_MAX (EnKF-N analogue) | Medium | Zero passes, 1 divide | Implement after R91, verify convergence |
| Spatially varying zone decorrelation length (OI) | Medium | +1 tex read/pixel | Hold — verify GPU cost first |
| Composite kernel mip blend in pro_mist | Low-Medium | +1 tex read/pass | Low priority |
| Entropy-biased Halton UV placement | Low | +8 tex reads/frame | Low priority, complex to validate |

---

## Searches run

1. `Ensemble Kalman filter non-stationary adaptive covariance inflation real-time 2023 2024 2025`
2. `recursive Bayesian estimation adaptive forgetting factor non-stationary signal convergence 2024 2025`
3. `ensemble data assimilation sparse observation optimal placement information content 2024 2025`
4. `adaptive sampling optimal sensor placement spatial coverage information entropy minimization 2024 2025`
5. `background field covariance localization spatial decomposition heterogeneous illumination estimation 2024 2025`
6. `optimal interpolation covariance localization decorrelation length scale spatially varying 2023 2024 2025`
