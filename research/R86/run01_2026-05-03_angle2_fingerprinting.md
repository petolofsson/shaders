# R86 Scene Reconstruction Research — Tone Mapper Identification / Fingerprinting — 2026-05-03 15:00

## Run angle

**Angle 2 — Tone mapper identification / fingerprinting**

`(15 // 6) % 3 = 2 % 3 = 2`

The question: given only the display-referred SDR output of Arc Raiders, can we infer
that the Hill/ACES rational function was applied, and estimate its parameters, from
statistics already available in the pipeline (PercTex p25/p50/p75, zone histograms)?
This run surveys the state of the art in blind ITM parameter estimation and asks
whether any published method maps cleanly onto what PercTex already exposes.

---

## HIGH PRIORITY findings

None this run. No paper found that provides a **closed-form per-pixel** method for
identifying the Hill/ACES rational-function parameters from display-referred histogram
percentiles. The closest work (Banterle 2006; Aydinetal 2020 Cambridge Core) estimates
a scalar gamma, not the coefficients of a rational function. However, the gamma-from-
statistics model *is* actionable for confidence-scoring the inverse: see Prototype
sketch section.

---

## Findings

### [Banterle et al. — Inverse Tone Mapping (Graphite 2006)]
- **R86 sub-problem:** fingerprinting / parameter estimation for blind inverse
- **Approach:** analytical / statistical
- **GPU feasibility:** yes — parameter estimation is a scalar reduce; inverse curve is per-pixel. Single pass feasible.
- **Error bounds:** not characterised rigorously; gamma estimate degrades when scene has
  extreme highlights (>10% overexposed pixels); luminance error up to ~0.15 stops reported.
- **Novelty gap:** designed for offline VFX LDR→HDR expansion; the gamma model is too
  coarse to recover a rational function but gives a correctness signal.
- **Directly usable:** with modifications — the key-value / geometric-mean / overexposure
  triple already maps to p50 / PercTex.g and zone histogram overflow counts. Could drive
  a confidence weight on the analytic ACES inverse.
- **Search that found it:** `"blind inverse tone mapping" "parameter estimation from luminance distribution"`

### [Aydin et al. — Fully-Automatic Inverse Tone Mapping via Dynamic Mid-Level Mapping (APSIPA 2020)]
- **R86 sub-problem:** fingerprinting / parameter estimation
- **Approach:** statistical — multi-linear model: `γ = f(key_value, overexposed_fraction, geometric_mean_luma)`
- **GPU feasibility:** parameter estimation is a 1×1 texture reduce (same pattern as
  PercTex); curve application is per-pixel. Single pass at negligible cost.
- **Error bounds:** average ΔE ≈ 4–6 (CIELAB) vs. ground-truth HDR for standard test
  images; performs better than fixed-gamma but worse than neural methods.
- **Novelty gap:** targets generic consumer LDR, not game-engine ACES. The multi-linear
  gamma model implicitly fits a power curve — cannot recover the asymmetric shoulder of
  the Hill rational function. Useful as a sanity / confidence check rather than the
  primary inverse method.
- **Directly usable:** with modifications — PercTex already holds p25/p50/p75/iqr.
  `key_value ≈ exp(mean_log_luma)` can be approximated from zone_log_key (ChromaHistoryTex
  col 6). Overexposed fraction is derivable from CreativeZoneHistTex top bins.
- **Search that found it:** `"blind inverse tone mapping" "parameter estimation from luminance distribution"`

### [ITU-R BT.2446-1 (2021) — SDR-to-HDR Conversion Methods]
- **R86 sub-problem:** fingerprinting — deducing knee/compression from display-referred luminance distribution
- **Approach:** statistical / analytical — analyses distribution of SDR code values across
  75 broadcast programs; typical "knee" at SDR ~0.72–0.78 and compression factor ~2.4 inferred
  from histogram shape (excess density in 0.7–0.9 range = shoulder compression signature).
- **GPU feasibility:** per-frame histogram already available (CreativeZoneHistTex); reading
  the overflow fraction from top 4 bins is 4 texture fetches. Zero per-pixel cost.
- **Error bounds:** not specified; the method targets HLG/PQ broadcast, not ACES. Transfer
  to game ACES output is conceptually valid but untested.
- **Directly usable:** with modifications — the "histogram shoulder excess" heuristic is
  directly implementable using CreativeZoneHistTex. Bins 28–32 (top ~12.5% of display range)
  holding disproportionate mass = ACES-style compression detected. Threshold TBD via
  calibration against known ACES output.
- **Search that found it:** `"blind inverse tone mapping" "parameter estimation from luminance distribution"`

### [TGTM — TinyML-based Global Tone Mapping for HDR Sensors (arXiv:2405.05016, 2024)]
- **R86 sub-problem:** fingerprinting — demonstrates that a 256-bin luminance histogram
  carries enough information to drive a complete tone mapping decision.
- **Approach:** neural (tiny MLP, 1k parameters, 9 kFLOPS input = 256-bin histogram)
- **GPU feasibility:** inference at 9 kFLOPS is negligible; but requires a trained model,
  not a closed-form derivation.
- **Error bounds:** PSNR competitive with full-image methods; histogram input alone
  sufficient for global curve decisions.
- **Novelty gap:** forward tone mapping, not inverse. The key contribution for R86 is
  the proof-of-concept that the per-frame histogram shape is a sufficient statistic for
  curve characterisation — supporting the hypothesis that PercTex percentiles are
  sufficient to fingerprint ACES vs. non-ACES tone mapping.
- **Directly usable:** no (requires trained model). The insight is useful: the ratio
  p75/p50 and p99 (derivable from zone histogram overflow) are likely discriminative
  features for ACES identification.
- **Search that found it:** `"tone curve identification from display-referred statistics histogram shape classifier game engine 2023 2024"`

### [AIM 2025 Challenge on Inverse Tone Mapping — ITMFlow (arXiv:2508.13479, 2025)]
- **R86 sub-problem:** inverse derivation — state-of-the-art SDR→HDR benchmark
- **Approach:** neural — dual-branch conditional flow matching; best result PU21-PSNR
  34.49 dB, 69 participants.
- **GPU feasibility:** no — conditional flow matching requires multiple diffusion steps;
  incompatible with real-time per-pixel single-pass constraints.
- **Error bounds:** PU21-PSNR 34.49 dB / SSIM 0.95 on benchmark; represents ceiling
  for the task when full neural budget is available.
- **Novelty gap:** offline / post-process only. Establishes that ~34 dB PU21-PSNR is
  achievable; sets the target quality bar for R86's analytical inverse.
- **Directly usable:** no. The error ceiling is useful context: the analytical ACES
  inverse (angle 0) is expected to reach higher PSNR than a generic neural method on
  ACES-specific input, because the operator is known.
- **Search that found it:** `site:arxiv.org "inverse tone mapping" 2024 2025`

### [Semantic Aware Diffusion Inverse Tone Mapping (arXiv:2405.15468, May 2024)]
- **R86 sub-problem:** inverse derivation — hallucinate clipped highlights via diffusion
- **Approach:** neural — diffusion-based inpainting for saturated regions
- **GPU feasibility:** no — multi-step diffusion; not real-time.
- **Error bounds:** not stated numerically in the abstract; subjectively outperforms
  non-diffusion baselines in clipped regions.
- **Novelty gap:** addresses the highlight hallucination problem, which is less critical
  for R86 (ACES compresses highlights but rarely clips them in well-exposed SDR frames).
- **Directly usable:** no. Relevant only if R86 later needs to handle clipped sky/specular.
- **Search that found it:** `site:arxiv.org "inverse tone mapping operator unknown recovery"`

### [Blind Quality Evaluation for Tone-Mapped Images (Springer Multimedia Systems, 2024)]
- **R86 sub-problem:** fingerprinting / TMO classification — exploits statistical features
  and deep perceptual features to distinguish well-tone-mapped from poorly-tone-mapped images.
- **Approach:** hybrid — handcrafted statistics (kurtosis, skewness of luminance histogram)
  + learned features.
- **GPU feasibility:** kurtosis/skewness computation is 3 texture passes over CreativeZoneHistTex;
  trivially feasible.
- **Error bounds:** classification accuracy not directly applicable; the statistical
  features (kurtosis, skewness, histogram spread) are the relevant output.
- **Novelty gap:** quality assessment, not operator identification. However, the statistical
  features it relies on (histogram kurtosis and skewness) are the same features that
  distinguish the heavy-shouldered ACES curve from a linear or power-law mapping.
- **Directly usable:** with modifications — histogram kurtosis and p75/p50 spread ratio
  are computable from existing PercTex + CreativeZoneHistTex. A high kurtosis + narrow
  IQR relative to the full range is consistent with ACES compression.
- **Search that found it:** `"tone mapping operator identification scene statistics signature 2022 2023 2024"`

---

## Prototype sketch

*No HLSL code for angle 2, per spec. Conceptual fingerprinting logic only.*

### ACES fingerprint via PercTex statistics

The Hill ACES rational function produces a characteristic histogram shape that distinguishes
it from a power law (gamma) or linear mapping:

1. **Shoulder compression signature:** ACES pushes display-referred p75 toward ~0.68–0.72
   even when scene p75 is around 0.8–0.85. If `perc.b / perc.g` (p75/p50 ratio) falls
   in [1.25, 1.55] and `iqr` is narrower than expected for a linear distribution
   (expected IQR ≈ `p50 * 0.6` for typical outdoor scenes), ACES compression is indicated.

2. **Toe lift signature:** ACES has a mild linear toe; the p25/p50 ratio for ACES output
   tends to be ≥ 0.40 even for dark scenes (pure gamma 2.2 would give ≈ 0.30 for the
   same scene). A test: `perc.r / perc.g > 0.38` is consistent with ACES.

3. **Combined confidence score (pseudocode):**
   ```
   float p25 = perc.r, p50 = perc.g, p75 = perc.b, iqr = perc.a;
   float shoulder_ratio = p75 / max(p50, 0.001);
   float toe_ratio      = p25 / max(p50, 0.001);
   // ACES expected range for shoulder_ratio: [1.25, 1.60]
   // ACES expected range for toe_ratio:      [0.38, 0.60]
   float aces_conf = saturate(smoothstep(1.20, 1.30, shoulder_ratio))
                   * saturate(smoothstep(0.55, 0.65, 1.0 - shoulder_ratio + 1.6))
                   * saturate(smoothstep(0.35, 0.42, toe_ratio));
   ```
   `aces_conf` in [0,1] can gate the analytic inverse: apply full R86 inverse when
   `aces_conf > 0.7`, blend to identity when below 0.3.

4. **Zone overflow proxy:** bins 28–32 of CreativeZoneHistTex row 0 (global zone) holding
   ≥ 8% of pixels in aggregate indicates either ACES shoulder compression or HDR mode
   leaking through — the latter is ruled out by the HDR-OFF prerequisite in CLAUDE.md.

### Calibration plan

To validate the thresholds above, take three frames:
- A bright outdoor scene (expected high ACES confidence)
- A dark interior (medium confidence — toe is diagnostic)
- A neutral mid-grey test card (baseline: both ratios near 0.5, low confidence)

Read PercTex after each and compute shoulder_ratio and toe_ratio. Adjust smoothstep
bounds accordingly. This costs no shader time — the data is already being written by
corrective.fx.

---

## Implementation gaps remaining

1. **No validated ACES-specific histogram signature.** The p75/p50 and p25/p50 heuristics
   above are derived analytically from the Hill rational function, not calibrated against
   live Arc Raiders frames. A single calibration session with known good ACES output
   (HDR OFF confirmed) is needed to tighten the smoothstep bounds.

2. **No method for distinguishing Hill ACES from Reinhard or ACES 2.0.** The shoulder and
   toe ratios may not be discriminative enough if UE5 switches tone mappers between versions.
   A third feature — the inflection-point location (where d²f/dx² = 0) — is derivable
   from p25/p75 asymmetry and would help. Not computed yet.

3. **Overexposed-fraction counter not in pipeline.** BT.2446 and Banterle both use the
   fraction of pixels above 0.95 as a key fingerprinting input. CreativeZoneHistTex has
   this data (top 1–2 bins) but no scalar pass currently reads it into a 1×1 texture.
   Adding a single 1×1 "clipping stats" pass to corrective.fx would unlock this feature
   for both fingerprinting and the inverse confidence weight.

4. **Angle 0 analytic inverse not yet derived.** This run confirmed the inverse is
   solvable via the quadratic formula (Banterle approach) but does not contain the HLSL
   sketch — that is angle 0's output. The fingerprinting score from this run should gate
   that inverse pass once implemented.

5. **Hue distortion characterisation absent.** ACES red→orange push and cyan→blue push
   magnitudes are not quantified against Oklab ground truth. Needed before the angle 1
   ROT_* correction table can be filled in.

---

## Searches run

1. `"tone mapping operator identification" scene statistics signature 2022 2023 2024`
2. `"blind inverse tone mapping" "parameter estimation from luminance distribution"`
3. `"HDR image reconstruction" "single image" tone curve fitting 2024 2025`
4. `"display referred" luminance histogram fingerprint tone operator classification`
5. `site:arxiv.org "inverse problem" tone mapping operator unknown recovery`
6. `site:arxiv.org "inverse tone mapping" 2024 2025`
7. `ACES tone mapping identification fingerprint luminance statistics SDR image analysis real-time`
8. `tone curve identification from display-referred statistics histogram shape classifier game engine 2023 2024`
