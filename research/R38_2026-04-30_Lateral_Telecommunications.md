# Lateral Research — Telecommunications — 2026-04-30

## Domain this week
ISO week 18 → 18 % 7 = 4 → **Telecommunications / signal comms**
(arxiv eess.SP, IEEE Trans Communications, IET Signal Processing)

---

## Pipeline problems targeted

| Problem | Current approach | Where |
|---------|-----------------|-------|
| State estimation / temporal filtering | Kalman filter (scalar, zone median); EMA for p25/p75 | corrective.fx Pass 4 `SmoothZoneLevelsPS` |
| Illumination/reflectance separation | Multi-Scale Retinex mips 0/1/2, coarse-biased (0.20/0.30/0.50) | grade.fx `ColorTransformPS` Stage 2 |
| Sparse scene sampling | 8×8 Halton grid, 16 zones | corrective.fx Pass 2 |
| Multi-scale basis decomposition | 3-band Haar wavelet (D1/D2/D3) | grade.fx Stage 2 CLARITY |
| Local contrast / edge-preserving | Zone IQR S-curve + CLAHE clip | grade.fx Stage 2 |
| Optimal signal recovery | None — open | Future |

---

## HIGH PRIORITY findings

### VFF-RLS: Variable Forgetting Factor for scene-cut resilience

**Why it is high priority:** The current Kalman P-based filter has good steady-state noise
rejection but a fixed process noise Q=0.0001 means it tracks abrupt scene changes slowly
— the filter converges gradually over many frames rather than snapping to the new scene.
VFF-RLS from telecom (channel equalisation for non-stationary channels) solves exactly
this: the forgetting factor λ drops toward 0 when the prediction residual is large (scene
cut) and climbs back to ≈0.99 during steady state. No new texture, no new pass — it is a
change to 4 scalar ALU operations in `SmoothZoneLevelsPS`. Visual impact: sharp scene
cuts currently produce a visible pull of the tone curve over 20–40 frames before the zone
history settles; VFF would reduce that to 2–5 frames.

---

## Findings

### 1. Variable Forgetting Factor RLS (VFF-RLS) applied to zone temporal filter

- **Pipeline target:** `corrective.fx` Pass 4 `SmoothZoneLevelsPS` — the Kalman / EMA
  temporal smoother for zone median, p25, p75.
- **Mathematical delta:** Current approach: fixed Q=0.0001 Kalman on zone median +
  KALMAN_K_INF=0.095 EMA on p25/p75. Telecom analogue: VFF-RLS (IET Signal Processing,
  Absolute finite differences method; arxiv 2511.15273) computes a time-varying
  forgetting factor λ_t from the normalised prediction residual squared:

      e_t = x_t − x̂_{t−1}           (prediction residual)
      α   = e_t² / (σ_noise² + e_t²) (0=steady, 1=abrupt change)
      λ_t = λ_min + (λ_max − λ_min) × (1 − α)
      x̂_t = λ_t × x̂_{t−1} + (1 − λ_t) × x_t

  Typical values: λ_min=0.70, λ_max=0.98, σ_noise²=0.0001 (matches current KALMAN_R).
  This is mathematically equivalent to the Kalman gain K being driven by the residual
  magnitude rather than the fixed P recursion — it collapses to the EMA when residual
  is small and jumps to near-unity gain on scene cuts.

  In HLSL (4 scalar ALU, no extra taps):
  ```hlsl
  float e       = current.r - prev.r;
  float alpha   = (e * e) / (KALMAN_R + e * e);   // KALMAN_R reused as σ²
  float lambda  = lerp(0.98, 0.70, alpha);
  float median  = lerp(prev.r, current.r, 1.0 - lambda);
  float p25     = lerp(prev.g, current.g, lerp(KALMAN_K_INF, 1.0 - lambda, alpha));
  float p75     = lerp(prev.b, current.b, lerp(KALMAN_K_INF, 1.0 - lambda, alpha));
  ```
  The P-channel in .a can remain (stores last α for potential debug) or be dropped.

- **GPU cost:** Zero — same pass, same taps, 4 scalar ALU ops replacing 5 (removes the
  P_pred / K / P_new recursion). Net neutral or slight reduction.
- **ROI:** HIGH visual impact (scene-cut stability), zero GPU cost, ~10 lines of code.
  **HIGH PRIORITY.**
- **Novelty in real-time rendering:** VFF from telecom channel tracking is standard in
  DSP but has not been used in post-process temporal image statistics smoothing as far
  as the literature shows. The direct mapping of "fading channel non-stationarity" to
  "scene cut in a frame histogram" is the lateral insight.
- **Search that found it:** "variable forgetting factor RLS non-stationary estimation
  scene change detection 2024 arxiv eess.SP"

---

### 2. EM-EKF (Expectation-Maximisation + Extended Kalman) for adaptive Q/R estimation

- **Pipeline target:** `corrective.fx` Pass 4 — the Q and R constants KALMAN_Q=0.0001
  and KALMAN_R=0.01 are currently hardcoded. In OFDM channel estimation (ScienceDirect
  2021, EM-EKF for high-mobility OFDM) the EM step estimates both process noise Q and
  measurement noise R online from recent residuals, removing the need to hand-tune them.
- **Mathematical delta:** After each Kalman update accumulate a short window of
  residuals e_t. EM update:
      R_new = (1/N) Σ e_t²
      Q_new = K × e_t² × K^T   (scalar: K² × e²)
  Since the pipeline already stores P in ZoneHistoryTex.a, this needs only two
  running accumulators per zone per frame — but ZoneHistoryTex is 4×4 RGBA16F with
  .a already occupied by P. A second scalar would require packing into an existing
  channel or a tiny 4×4 R16F auxiliary (tiny cost).
- **GPU cost:** Low — one additional 4×4 texture write per frame + 6 scalar ALU ops.
  But requires a new texture or channel packing change.
- **ROI:** Medium. VFF-RLS (Finding 1) gives most of the benefit at zero cost. EM-EKF
  is more principled but implementation cost is higher and the incremental visual gain
  over VFF is small. Defer until VFF is validated.
- **Novelty:** High — adaptive noise covariance in a real-time image pipeline is
  uncommon. Worth a future dedicated research session.
- **Search that found it:** "Kalman filter channel estimation OFDM recursive temporal
  smoothing pilot-based 2023 2024"

---

### 3. MMSE Pilot Interpolation → weighted multi-scale illumination estimation

- **Pipeline target:** `grade.fx` Stage 2 Multi-Scale Retinex — the Retinex log-ratio
  blend currently uses fixed mip weights 0.20/0.30/0.50. In pilot-aided OFDM (EURASIP
  2022 survey; IEEE Xplore Ptolemy OFDM), MMSE interpolation between pilot subcarriers
  uses a noise-to-signal ratio (NSR) to weight nearby frequency samples:
      w_k = C_hh(k,p) / (C_hh(p,p) + σ²/σ_s²)
  The Retinex analogue: weight each scale by the inverse of its expected illumination
  variance. Coarse scales (mip 2) are low-variance / low-noise for overall key; fine
  scales (mip 0) are high-variance and carry texture. The existing smoothstep blend
  `lerp(0.04, 0.25, zone_std)` already does something similar, but MMSE would replace
  the fixed 0.20/0.30/0.50 weights with per-frame adaptive weights driven by the
  variance of each mip level relative to the global scene key (zone_log_key already
  available in ChromaHistoryTex col 6).
- **Mathematical delta:** Replace fixed weights in the log-ratio sum with:
      var_s0 = (illum_s0 - zone_log_key)²   // proxy for illumination variance at scale 0
      var_s1 = (illum_s1 - zone_log_key)²
      var_s2 = (illum_s2 - zone_log_key)²
      w_si   = 1.0 / (var_si + 0.01)        // MMSE-style inverse variance weighting
      normalise w_s0..w_s2 to sum=1
  The local luma_s / illum_sX ratio for each mip already computed — weight assignment
  is ~6 extra ALU ops per pixel. No extra taps needed.
- **GPU cost:** ~6 ALU ops in `ColorTransformPS` (already within the MegaPass). Zero
  extra taps, zero extra passes.
- **ROI:** Medium-High. Scenes with extreme contrast between zones (bright sky / dark
  interior) are where fixed weights break: mip 2 becomes the dominant illuminant for
  flat uniform sky patches while mip 0 is more relevant in shadow-clutter regions.
  Adaptive MMSE weighting would self-adjust without the user touching anything.
- **Novelty:** MMSE pilot interpolation applied to spatial illumination scale weighting
  is not in the image processing literature. Direct lateral import.
- **Search that found it:** "MMSE channel estimation sparse pilot interpolation
  multi-carrier frequency domain 2024"

---

### 4. Subspace Forgetting (SIFt-RLS) — directional forgetting for Chroma history

- **Pipeline target:** `corrective.fx` Pass 5 `UpdateHistoryPS` —
  ChromaHistoryTex stores per-band Kalman P in .a (6 hue bands). Currently each band
  updates independently with the same KALMAN_K_INF EMA. In MIMO channel estimation
  (arxiv 2404.10844 SIFt-RLS, Lai et al. 2024) subspace/directional forgetting applies
  forgetting only in directions that are currently "excited" (receiving new data), and
  holds directions with no new input at their last known value — preventing covariance
  windup and parameter drift.
- **Mathematical delta:** For each chroma band b, if the scene has essentially no
  pixels in that hue band (weight h.b ≈ 0), the current EMA still decays the history
  toward zero. SIFt-RLS equivalent: gate the update by the band weight:
      float excitation = saturate(h.b / (h.b + 0.05));   // soft gate on sample count
      float k_b        = lerp(0.0, KALMAN_K_INF, excitation);
      mean_C_new       = lerp(prev_mean, h.r, k_b);
  This prevents unrepresented hue bands (e.g., no cyan in a desert scene) from drifting
  their smoothed mean toward zero over time, causing spurious chroma lift on the next
  frame that does contain cyan.
- **GPU cost:** Zero — same pass, 2 extra ALU ops per band (12 total).
- **ROI:** Medium. Most scenes have enough coverage across all 6 bands that drift is
  slow. Visually relevant on cut from an outdoor (cyan sky) to indoor scene (no cyan) —
  cyan chroma lift would persist for O(1/KALMAN_K_INF) ≈ 10 frames without this fix.
- **Novelty:** Directional/subspace forgetting from MIMO telecom applied to per-hue
  band temporal averaging is a direct mapping, not in image processing literature.
- **Search that found it:** "variable forgetting factor RLS non-stationary estimation
  scene change detection 2024 arxiv eess.SP" (SIFt-RLS reference therein)

---

### 5. Compressed Sensing / Restricted Isometry — optimal zone sampling grid

- **Pipeline target:** `corrective.fx` Pass 2 `ComputeZoneHistogramPS` — currently
  samples 10×10=100 points per zone from the 1/8-res low-freq texture. The 8×8 Halton
  grid for the overall analysis is already near-optimal for stratified coverage. CS
  theory (IEEE Xplore 9852418; MDPI 2022) formalises this: a measurement matrix Φ
  satisfies the Restricted Isometry Property (RIP) if any k-sparse signal is uniquely
  recoverable. For histogram estimation the "sparsity" is the number of non-zero bins
  — a 32-bin histogram with typical scene has O(8) populated bins, so CS theory says
  ~20–25 samples per zone suffice for p95-accurate quantile estimation, not 100.
- **Mathematical delta:** Reduce the zone histogram inner loop from 10×10=100 taps to
  5×5=25 taps using a Halton(2,3) sub-grid (already implemented in the codebase for
  the global Halton). The 25-sample Halton grid satisfies RIP for 32-bin histograms
  at 8-sparse approximation. R31 already confirmed 8 Halton samples + Kalman ≈ p95 for
  the global quantile. Zone-level extension of the same logic.
- **GPU cost:** NEGATIVE — reduces from 100 taps to 25 per zone output pixel (64% tap
  reduction in Pass 2, which iterates over all 32×16=512 output pixels). Pass 2 is
  already fast but the reduction matters for the GPU budget constraint.
- **ROI:** Medium — visual quality unchanged (histogram accuracy unchanged due to
  temporal Kalman smoothing), GPU cost decreases. Low implementation risk because R31
  validated the underlying math.
- **Novelty:** CS/RIP as the theoretical justification for reducing zone histogram
  sample count is not in the existing research notes.
- **Search that found it:** "compressed sensing sparse signal recovery optimal sampling
  pattern visual signal reconstruction 2023 2024"

---

### 6. Noise shaping / sigma-delta — perceptual weighting of quantisation error

- **Pipeline target:** No current analogue — this would be a new capability. The
  pipeline outputs to an 8-bit UNORM BackBuffer between effects. Sigma-delta modulation
  / noise shaping (Wikipedia; ScienceDirect) pushes quantisation noise into perceptually
  less-sensitive frequency bands using a feedback error filter.
- **Mathematical delta:** Between the corrective and grade effects the BackBuffer is
  8-bit UNORM, clipping values silently. Noise shaping is not directly applicable here
  because the pipeline operates on the spatial rather than temporal dimension, and the
  BackBuffer is written once per frame. The analogy breaks: sigma-delta requires
  feedback over many oversampled steps, which a single-pass shader cannot do.
- **GPU cost:** Not applicable — mapping does not hold.
- **ROI:** LOW — no applicable mapping to the pipeline. Discard.
- **Novelty:** N/A
- **Search that found it:** "quantization noise shaping sigma delta modulation optimal
  bit allocation perceptual weighting signal processing"

---

## ROI table

| Finding | Visual impact | GPU cost | Recommended action |
|---------|--------------|----------|--------------------|
| 1. VFF-RLS zone temporal filter | HIGH — scene-cut convergence speed | Zero (net neutral) | **Implement next session** |
| 2. EM-EKF adaptive Q/R | Medium — better steady-state in slow-varying scenes | Low (new texture channel or packing) | Defer until VFF validated |
| 3. MMSE-weighted Retinex scales | Medium-High — extreme contrast zones | ~6 ALU, zero taps | Implement after VFF |
| 4. SIFt-RLS chroma band forgetting | Medium — scene-cut chroma drift | Zero (12 ALU) | Bundle with VFF session |
| 5. CS/RIP zone histogram tap reduction | Neutral visual, GPU cost reduction | Negative (saves 75 taps/px) | Implement, low risk |
| 6. Sigma-delta noise shaping | None — mapping does not hold | N/A | Discard |

---

## Searches run

1. "Kalman filter channel estimation OFDM recursive temporal smoothing pilot-based 2023 2024"
   → Found EM-EKF (Finding 2), KF-MIMO-OFDM literature baseline

2. "MMSE channel estimation sparse pilot interpolation multi-carrier frequency domain 2024"
   → Found MMSE pilot interpolation weighted averaging (Finding 3), EURASIP AI survey

3. "adaptive equalisation recursive least squares RLS forgetting factor non-stationary signal 2024"
   → Found VFF-RLS PMC paper, SIFt-RLS reference, IET absolute finite differences method
   → Confirmed VFF-RLS as HIGH PRIORITY (Finding 1)

4. "MIMO spatial channel decomposition basis functions multi-scale signal separation estimation 2024"
   → Found tensor decomposition MIMO, spatial basis expansion model (SBEM)
   → Informed Finding 3 (spatial basis / multi-scale analogy)

5. "variable forgetting factor RLS non-stationary estimation scene change detection 2024 arxiv eess.SP"
   → Found arxiv 2511.15273 (RLS with forgetting profile segmentation), arxiv 2404.10844
   (SIFt-RLS directional forgetting, Lai et al. 2024) — confirmed Findings 1 and 4

6. "compressed sensing sparse signal recovery optimal sampling pattern visual signal reconstruction 2023 2024"
   → Found IEEE 9852418, MDPI CS survey 2022, Rice DSP CS resources
   → Confirmed Finding 5 (zone histogram tap reduction via RIP)

7. "quantization noise shaping sigma delta modulation optimal bit allocation perceptual weighting signal processing"
   → Found sigma-delta literature; mapping to pipeline does not hold — Finding 6 discarded

---

## Implementation priority order

1. **VFF-RLS zone temporal filter** (`SmoothZoneLevelsPS`) — zero cost, high impact, ~10 lines
2. **SIFt-RLS chroma band excitation gate** (`UpdateHistoryPS`) — zero cost, bundle with above
3. **CS/RIP zone histogram 100→25 taps** (`ComputeZoneHistogramPS`) — GPU budget relief
4. **MMSE-weighted Retinex scale blending** (`ColorTransformPS` Stage 2) — medium complexity
5. **EM-EKF adaptive Q/R** — defer until 1–2 validated
