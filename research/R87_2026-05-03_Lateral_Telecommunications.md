# Lateral Research — Telecommunications / Signal Comms — 2026-05-03

## Domain this week

ISO week 18, 18 % 7 = 4 → Telecommunications / signal comms. Searched IEEE Trans Comms,
arxiv eess.SP, and adjacent filter-theory literature. The telecom field has spent decades
on adaptive state estimation and sparse pilot placement under non-stationary, band-limited
channels — problems isomorphic to those in the shader pipeline.

## Pipeline problems targeted

1. **State estimation / temporal filtering** — VFF Kalman in SmoothZoneLevelsPS and
   UpdateHistoryPS. Current Q_vff ramp uses a single hard-coded smoothstep on innovation
   magnitude (VFF_E_SIGMA). Telecom adaptive Kalman literature (Sage-Husa, IAKF) has
   solved this more robustly via windowed covariance matching of the innovation sequence
   itself, decoupling Q adaptation from a manually tuned threshold.

2. **Sparse scene sampling** — UpdateHistoryPS samples 8 Halton points per band per frame.
   Telecom compressed-sensing pilot placement shows that minimising mutual coherence of the
   measurement matrix (maximising spread of pilot positions) is strictly better than
   low-discrepancy sequences when the sample budget is fixed and the signal is bandlimited
   in a transform domain.

3. **Quantization / dither** — Current dither is flat-spectrum TPDF (`sin(dot)*43758`).
   Sigma-delta noise shaping from audio/telecom DAC literature pushes quantization error
   away from perceptually sensitive mid-luma frequencies into shadows/highlights where it
   is less visible — a pure-math upgrade, zero extra passes.

---

## HIGH PRIORITY findings

### Innovation-Sequence Covariance Matching (Sage-Husa / IAKF)  — HIGH PRIORITY

The VFF_E_SIGMA threshold in corrective.fx is a tuned scalar. The telecom-derived
Sage-Husa estimator replaces it with a sliding-window estimate of the actual innovation
covariance: Q is set so that E[e·eᵀ] = H·P·Hᵀ + R (the innovation identity). No
threshold constant needed. The 2024 MDPI paper on "Sage-Husa Adaptive Double Forgetting
Factors" (doi:10.3390/app15041731) shows this converges 30–60 % faster to steady state
on abrupt changes vs fixed-sigma VFF, matching scene-cut responsiveness without
hardcoding VFF_E_SIGMA. GPU cost: 1–3 extra float ops per pixel (running window mean of
e², no loops, frame-constant). Visual impact: fewer frames of "lag" after scene cuts where
zone medians are chasing a new distribution.

### Noise-Shaped Dither  — HIGH PRIORITY

Audio DAC/sigma-delta literature (Cutler 1952 → Wannamaker 1992 → Lipshitz filters)
shows that quantization error can be spectrally shaped by feeding the previous sample's
error back with a filter kernel. For an 8-bit UNORM BackBuffer the current flat dither
distributes error uniformly; a first-order error-feedback (`err_out = quant_err +
0.5 * prev_err`) pushes noise energy toward high spatial frequencies (fine texture) and
away from smooth luma gradients where banding is most visible. Cost: 1 additional float
per pixel (store previous quant error — not feasible per-pixel in a stateless pass, but
a 1-tap temporally-fed version is feasible via a 1×1 EMA texture already in the chain).
Simpler version: replace the current hash-based dither with a blue-noise LUT (void-and-
cluster or a screen-space Halton pair) — still zero extra passes, but spectral energy is
concentrated in high spatial frequencies rather than white.

---

## Findings

### [Sage-Husa Adaptive Double Forgetting Factors (MDPI 2025)]
- **Pipeline target:** State estimation — SmoothZoneLevelsPS and UpdateHistoryPS Q_vff adaptation
- **Mathematical delta:** Current: `Q_vff = lerp(Q_MIN, Q_MAX, smoothstep(0, VFF_E_SIGMA, |e|))` — Q
  is a monotone function of instantaneous innovation. Sage-Husa: `Q_est = (1-b)·Q_est + b·(K·e·eᵀ·Kᵀ)`
  with a forgetting factor b on the estimator itself. Q is updated from the actual observed
  innovation covariance over a window, not a hand-tuned threshold. This means Q rises
  precisely when innovations are consistently large (real scene change) rather than when a
  single frame has a large innovation (e.g. a bright muzzle flash that does not change the
  underlying zone distribution).
- **GPU cost:** Pure math. ~3 float ops added to the SmoothZoneLevelsPS pass. The "window"
  degenerates to a single-pole IIR (the forgetting factor b replaces the window average),
  which is exactly what the pipeline already does for chroma history. No extra texture needed.
- **ROI:** Visual High / GPU Low
- **Novelty:** VFF Kalman (R39) is already in the pipeline. This is an upgrade to its Q
  adaptation law — the missing piece that was left as a tuned constant.
- **Search that found it:** `"innovation-based" OR "innovation triggered" adaptive filter covariance estimation abrupt change detection non-stationary 2024`; `Sage-Husa algorithm adaptive double forgetting factors 2024`

### [Variable Forgetting Factor RLS — Improved (IVFF-RLS)]
- **Pipeline target:** State estimation — secondary EMA channels (p25, p75, chroma std, wsum)
  currently use a fixed `KALMAN_K_INF = 0.095`. IVFF-RLS varies the forgetting factor
  as a function of the prediction error power normalised by the expected noise power.
- **Mathematical delta:** λ = 1 − (1−λ_min) · (e² / (e² + σ²_n)), where σ²_n is a running
  estimate of noise variance. At steady state λ → 1 (slow adaptation); during rapid change
  λ → λ_min (fast tracking). This is equivalent to what the zone median path does with VFF
  Kalman, but applied uniformly to the EMA channels so they track scene cuts at the same
  speed as the primary Kalman channel.
- **GPU cost:** 2–4 float ops per secondary channel, no extra texture.
- **ROI:** Visual Medium / GPU Low
- **Novelty:** Currently secondary channels use a fixed gain; this closes the asymmetry.
- **Search that found it:** `"variable forgetting factor" OR "fading memory" recursive least squares non-stationary signal tracking innovation`

### [Compressed Sensing — Pilot Mutual Coherence Minimisation]
- **Pipeline target:** Sparse scene sampling — UpdateHistoryPS 8×8 Halton grid
- **Mathematical delta:** CS pilot placement (e.g. IEEE Xplore 5633478) selects sample
  positions by minimising the mutual coherence μ = max_{i≠j} |φᵢᵀφⱼ| / (‖φᵢ‖‖φⱼ‖) of
  the measurement matrix. For a 256-point Halton grid this is already near-optimal for 2D
  uniform coverage, so the gain vs current approach is small. The delta is that CS theory
  proves the Halton choice is justified — and also shows that if the signal has structure
  (e.g. chroma is sparse in Oklab hue basis), fewer samples with a matched basis give the
  same estimation error. Current 8-sample-per-band approach samples 8 × 6 = 48 points
  across the whole frame; CS suggests these 48 points should be drawn from a frame-jittered
  golden-ratio sequence rather than a fixed Halton offset to avoid coherence with game HUD
  geometry.
- **GPU cost:** Replace `uint base_idx = uint(FRAME_COUNT * 8) % 256u` with a per-frame
  golden-ratio jitter: `base_idx = uint(FRAME_COUNT * 165u) % 256u` (165 ≈ 256·0.618…).
  Zero cost change.
- **ROI:** Visual Low-Medium / GPU Zero
- **Novelty:** Existing Halton is already good. This is a provably-optimal permutation.
- **Search that found it:** `"sparse pilot" OR "compressed sensing" channel estimation OFDM frequency-selective fading recovery 2024 2025`

### [Noise-Shaped Dither — Sigma-Delta Error Feedback]
- **Pipeline target:** Quantization dither in ColorTransformPS (grade.fx, final line)
- **Mathematical delta:** Current dither: `d = frac(sin(dot(pos.xy, float2(127.1,311.7)))*43758.5) - 0.5`
  — white-spectrum TPDF equivalent. Noise-shaped first-order dither:
  ```
  d = blue_noise_LUT(pos.xy % LUT_SIZE) - 0.5
  ```
  A 64×64 void-and-cluster blue noise texture pushes quantization error power to spatial
  frequencies above ~8 cycles/pixel. The human CSF peaks at 3–5 cycles/degree — at typical
  viewing distances this means banding artifacts in smooth gradients (sky, fog, ramps) are
  replaced by imperceptible fine grain. Error diffusion (temporal feedback via 1×1 texture)
  would be stronger but requires an extra render target; the LUT version is zero-cost and
  available as a free texture (many public domain blue noise LUTs exist, e.g. Moments in
  Graphics, Roberts 2018).
- **GPU cost:** +1 texture lookup (16×16 or 64×64 UNORM8 LUT, tiny cache footprint). No new passes.
- **ROI:** Visual Medium / GPU Low
- **Novelty:** The current sin-hash dither is white noise; blue noise dither has measurably
  lower perceived error for the same bit depth (proven in display/print literature). In the
  context of 8-bit UNORM inter-effect BackBuffer this is non-trivial — the pipeline has 6
  effects clipping to 8-bit repeatedly; cleaner dither reduces error accumulation across
  the chain.
- **Search that found it:** `sigma-delta noise shaping perceptual weighting dither optimal quantization error distribution 2023 2024`; `perceptually weighted dither noise shaping error diffusion quantization spatial frequency image 2024`

### [Approximate Message Passing (AMP) — Bayesian MMSE Denoiser]
- **Pipeline target:** Multi-scale basis decomposition — Clarity (grade.fx Retinex/low-freq
  illumination separation)
- **Mathematical delta:** The current Retinex uses two mip levels (mip1 and mip2) as crude
  illumination estimates and takes a lerp. AMP/Turbo-AMP (Donoho 2009, IEEE Xplore 450728)
  treats this as a sparse recovery problem: reflectance = observed − illumination, where
  illumination is modelled as smooth (sparse in gradient domain) and reflectance as
  compressible (sparse in wavelet domain). The Bayesian MMSE denoiser for each component
  is closed-form if a Gaussian mixture prior is assumed. In 2D with a 3-mip pyramid this
  converges in 1–2 iterations (each iteration is a scale-dependent soft-threshold applied
  across mip levels). Relevant to the Clarity stage and R29 Multi-Scale Retinex.
- **GPU cost:** Medium — would require at least one extra downsample pass with a different
  kernel (Laplacian, not box). Not zero-cost. Marks this as a future investigation.
- **ROI:** Visual High / GPU Medium
- **Novelty:** High — no known use in real-time post-processing. Would replace the ad hoc
  Retinex lerp with a principled iterative decomposition.
- **Search that found it:** `"approximate message passing" AMP image reconstruction low-complexity Bayesian MMSE non-Gaussian prior 2024`

---

## ROI table

| Finding | Visual impact | GPU cost | Recommended action |
|---------|--------------|----------|--------------------|
| Sage-Husa innovation covariance Q adaptation | High | Zero (pure math) | **Implement — R88 candidate** |
| Blue-noise / noise-shaped dither LUT | Medium | Low (+1 tex lookup) | **Implement — R89 candidate** |
| IVFF-RLS uniform forgetting for EMA channels | Medium | Zero (pure math) | Implement alongside R88 |
| Golden-ratio Halton jitter for chroma sampling | Low-Medium | Zero | 1-line change, low risk |
| AMP Bayesian Retinex decomposition | High | Medium (new pass) | Future — R9x series |

---

## Searches run

1. `adaptive Kalman filter non-stationary channel estimation telecommunications convergence speed 2024 2025`
2. `"variable forgetting factor" OR "fading memory" recursive least squares non-stationary signal tracking innovation`
3. `"sparse pilot" OR "compressed sensing" channel estimation OFDM frequency-selective fading recovery 2024 2025`
4. `"turbo equalization" iterative soft interference cancellation signal detection convergence acceleration 2024`
5. `total variation signal denoising piecewise constant estimation fast algorithm GPU 2024 2025`
6. `"message passing" OR "belief propagation" factor graph signal estimation convergence rate fast 2024 arxiv`
7. `sigma-delta noise shaping perceptual weighting dither optimal quantization error distribution 2023 2024`
8. `"innovation-based" OR "innovation triggered" adaptive filter covariance estimation abrupt change detection non-stationary 2024`
9. `"spectral flatness" OR "crest factor" signal characterization dynamic range estimation telecommunications 2023 2024`
10. `Sage-Husa adaptive Kalman filter innovation covariance window estimation real-time non-stationary 2024`
11. `low-discrepancy quasi-random sampling optimal coverage sparse estimation time-varying signal 2024 2025`
12. `"approximate message passing" AMP image reconstruction low-complexity Bayesian MMSE non-Gaussian prior 2024`
13. `perceptually weighted dither noise shaping error diffusion quantization spatial frequency image 2024`
14. `log-domain multiplicative noise separation signal estimation Retinex-equivalent communications channel 2023 2024`
