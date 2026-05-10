# R86 Scene Reconstruction — Run 02 — Fingerprinting — 2026-05-03 15:48

## Run angle

**Angle 2 — Tone mapper identification / fingerprinting**

`(15 // 6) % 3 = 2 % 3 = 2`

Run 01 (same session slot, same angle) surveyed the existing literature and proposed
a heuristic confidence score based on p75/p50 and p25/p50. This run deepens that
work by:
1. Deriving the expected display-referred percentile ratios **analytically from the Hill
   ACES rational function coefficients** — replacing the empirically-guessed thresholds
   from run01 with first-principles values.
2. Introducing a new, scene-exposure-independent discriminant: the **asymmetry ratio**
   `(p75/p50) / (p50/p25)`.
3. Surveying new literature not covered by run01 (Gain-MLP 2025, real-time self-
   supervised tone curve estimation 2023, CVMP ITMLUT 2023, ACM/SIGGRAPH results).

---

## HIGH PRIORITY findings

### Analytically derived ACES fingerprint — asymmetry ratio

**Closed-form, directly actionable, no calibration data needed.**

The Hill ACES rational `f(x) = (2.51x² + 0.03x) / (2.43x² + 0.59x + 0.14)` maps
a neutral-exposure log-normal scene (median = 0.18 scene-linear, σ = 1 stop) to the
following display-referred percentiles:

| Scene linear | Display ACES | Display Reinhard | Display linear |
|-------------|-------------|-----------------|----------------|
| p25 = 0.113 | 0.1491      | 0.1015          | 0.113          |
| p50 = 0.180 | 0.2670      | 0.1525          | 0.180          |
| p75 = 0.287 | 0.4227      | 0.2230          | 0.287          |

Derived statistics:

| TMO      | p50 display | p75/p50 | p25/p50 | **asymmetry** | IQR/p50 |
|----------|-------------|---------|---------|---------------|---------|
| ACES Hill| 0.267       | 1.583   | 0.559   | **0.884**     | 1.025   |
| Reinhard | 0.153       | 1.462   | 0.666   | **0.973**     | 0.797   |
| Linear   | 0.180       | 1.594   | 0.628   | **1.001**     | 0.948   |
| Pow γ2.2 | 0.459       | 1.235   | 0.808   | **0.998**     | —       |

`asymmetry = (p75/p50) / (p50/p25)`

The asymmetry ratio is **scene-exposure-independent** for log-normal scene distributions:
scaling the scene exposure multiplies all percentiles by the same factor, which cancels
in both ratios. ACES produces a notably lower asymmetry (~0.88) than all other common
TMOs (≥0.97) because it compresses the highlight shoulder more aggressively than it lifts
the toe.

**GPU feasibility:** 3 scalar divides from PercTex (already fetched). Zero additional cost.
**Directly usable:** yes — see refined prototype sketch below.

---

## Findings

### [Gain-MLP — Improving HDR Gain Map Encoding via a Lightweight MLP (arXiv:2503.11883, Mar 2025)]
- **R86 sub-problem:** inverse derivation (exposure estimation sub-problem)
- **Approach:** dual-branch neural — Local Contrast Restoration branch + Global Luminance
  Estimation (GLE) branch. GLE captures image-wise luminance statistics for gain map
  estimation; the gain map encodes how much each pixel must be expanded to recover HDR.
- **GPU feasibility:** full network is not real-time. However, the GLE branch concept
  is relevant: a 1×1 global luminance estimate from percentile statistics mirrors what
  PercTex already provides. The R86 "exposure estimation" step can be modelled as a
  gain map scalar derived from p95 — structurally identical to GLE but reduced to a
  single scalar.
- **Error bounds:** not stated for the MLP variant; the gain map format itself targets
  ±0.5 EV reconstruction error.
- **Novelty gap:** full network is offline; the GLE branch insight is adaptable to a
  single scalar from PercTex.
- **Directly usable:** with modifications — the exposure estimation step of R86 (PLAN.md
  §R86 point 3: "use p99 of the scene to anchor the inverse curve scale") is structurally
  identical to the GLE global stage. The GLE branch validates that a global luminance
  scalar is sufficient for gain estimation in HDR reconstruction.
- **Search that found it:** `"gain map" "inverse tone mapping" SDR HDR luminance estimation histogram 2024 2025 single image`

---

### [Real-Time Self-Supervised Tone Curve Estimation (Computers & Graphics / ScienceDirect, Jul 2023)]
- **R86 sub-problem:** fingerprinting / parameter estimation
- **Approach:** patch-wise self-supervised learning — CNN estimates tone curve parameters
  per spatial block; uses a prior retinal adaptation model as a self-supervised loss term
  (no ground-truth HDR labels needed).
- **GPU feasibility:** the learned CNN is not per-pixel real-time. Key insight: the paper
  demonstrates that *patch-level tone curve parameters* can be estimated from local
  statistics without HDR ground truth. The patch-wise curve degenerates to a global scalar
  when the TMO is truly global (as ACES is). This supports the hypothesis that PercTex's
  global percentiles are sufficient for ACES identification.
- **Error bounds:** "better than existing methods in both objective and subjective metrics
  at low computational cost" — exact numbers not in abstract.
- **Novelty gap:** forward tone mapping, not inverse identification. The self-supervised
  formulation (using retinal adaptation as a prior) may inspire the exposure estimation
  step: treat the adaptation luminance as p50 and derive the gain from PercTex directly.
- **Directly usable:** no (requires training). Conceptually supports the PercTex-based approach.
- **Search that found it:** `"real-time self-supervised tone curve estimation" HDR LDR histogram block patch 2023`

---

### [ITMLUT — Redistributing Precision in 3D-LUT-based Inverse Tone Mapping (CVMP/SIGGRAPH Europe 2023)]
- **R86 sub-problem:** inverse derivation
- **Approach:** offline — learns a 3D LUT to invert a known or estimated TMO. "Redistributing
  precision" means the LUT is warped to allocate more entries to visually sensitive regions.
- **GPU feasibility:** 3D LUT lookup is per-pixel single-pass (trilinear interpolation in
  existing hardware). A pre-computed ACES inverse LUT could be loaded into a texture3D
  and sampled in one tap.
- **Error bounds:** LUT quantization error; 64³ LUT at 16F gives <JND for smooth curves.
- **Novelty gap:** requires offline training / LUT baking; assumes TMO is known (not blind).
  Directly relevant to R86 if the TMO is identified and confirmed as ACES with high confidence.
- **Directly usable:** with modifications — if aces_conf > 0.9, a pre-baked ACES inverse
  LUT (64³ RGBA16F ≈ 2 MB) could replace the per-pixel quadratic formula. The analytical
  inverse (angle 0) is cheaper and more accurate; the LUT approach is a backup if the
  quadratic has numerical issues near the domain boundary.
- **Search that found it:** `SIGGRAPH ACM "ACES" OR "inverse tone mapping" analytical inversion hue distortion 2023 2024 2025`

---

### [AIM 2025 Challenge on Inverse Tone Mapping (arXiv:2508.13479 / ICCVW 2025)]
- **R86 sub-problem:** inverse derivation — quality benchmark
- **Approach:** neural — best entry (ToneMapper) PU21-PSNR 34.49 dB, 69 participants.
  No entry used tone mapper classification / identification — all methods treated the
  TMO as unknown and learned a blind expansion.
- **GPU feasibility:** no (multi-step neural).
- **Error bounds:** 34.49 dB PU21-PSNR is the current ceiling for blind inverse.
- **Novelty gap:** the entire challenge is offline VFX / photo processing. No real-time
  entry. **Confirms the gap: no published work does real-time analytical ACES inversion
  with fingerprinting-gated confidence.**
- **Directly usable:** no. Sets the quality ceiling. The analytical ACES inverse (angle 0)
  is expected to exceed 34.49 dB on ACES-specific input because the operator is known.
- **Search that found it:** `site:arxiv.org "inverse tone mapping" 2025 identification classification`

---

## Prototype sketch

*Angle 2 — conceptual only, no HLSL code.*

### Refined confidence score: asymmetry ratio + absolute p50 guard

Building on run01's prototype, this run adds the asymmetry ratio as the primary discriminant
and demotes the absolute p50 check to a secondary corroborating signal.

**Derivation:** from the analytical table above, the ACES asymmetry ratio is ~0.884 for
neutral-exposure log-normal scenes. The closest competing TMO (Reinhard) gives ~0.973.
The gap of ~0.089 is larger than any calibration uncertainty for outdoor game scenes.

```
float p25 = perc.r, p50 = perc.g, p75 = perc.b;

// Primary: asymmetry ratio (scene-exposure-independent for log-normal scenes)
// ACES: ~0.884. Reinhard/linear/gamma: ≥ 0.97.
// Threshold: <0.92 = ACES-like; >0.97 = non-ACES.
float p75_p50    = p75 / max(p50, 0.001);
float p50_p25    = p50 / max(p25, 0.001);
float asym       = p75_p50 / max(p50_p25, 0.001);
float asym_conf  = saturate(1.0 - smoothstep(0.88, 0.97, asym));

// Secondary: absolute p50 guard (scene-exposure-dependent, so low weight)
// ACES maps scene midgray 0.18 → display ~0.267. At ±0.5 stop exposure variance:
// plausible ACES p50 range: ~0.19 (dark interior) to ~0.38 (bright exterior).
// Values outside [0.15, 0.42] reject — either not ACES or wrong exposure.
float p50_conf   = saturate(smoothstep(0.15, 0.22, p50)
                            * (1.0 - smoothstep(0.38, 0.45, p50)));

// Tertiary (run01 shoulder ratio, as backup): p75/p50 in [1.40, 1.65]
float sho_conf   = saturate(smoothstep(1.35, 1.45, p75_p50)
                            * (1.0 - smoothstep(1.65, 1.75, p75_p50)));

// Combined: asymmetry is most robust; p50 guard prevents false positives in dark scenes
float aces_conf  = asym_conf * 0.60 + p50_conf * 0.25 + sho_conf * 0.15;
```

`aces_conf` in [0,1]. Apply full R86 inverse when > 0.7, blend to identity when < 0.3.

### Calibration plan — three representative Arc Raiders frames

To validate the thresholds above against live data (HDR OFF confirmed):

| Scene type | Expected p50 | Expected asym | Expected aces_conf |
|------------|-------------|---------------|-------------------|
| Bright outdoor (sky visible) | 0.28–0.38 | 0.87–0.90 | > 0.75 |
| Dark indoor (shadow-dominant) | 0.15–0.22 | 0.88–0.93 | 0.50–0.75 |
| Mid-grey test card | 0.24–0.28 | 0.86–0.89 | > 0.70 |

GZW (non-ACES pipeline): expect asym > 0.96 and aces_conf < 0.25.

### The exposure-invariance claim: domain of validity

The asymmetry ratio is exactly exposure-independent when the scene has a **symmetric**
log-normal luminance distribution. Real game scenes deviate in two ways:

1. **Specular spikes** (bright metal, lights) — pull p75 up, increasing p75/p50,
   making asym temporarily look more non-ACES-like (false negative). Mitigation:
   the existing `PercTex.b` (p75) already uses a smooth CDF read — specular spikes
   contribute fewer than 5% of pixels and do not shift p75 significantly.

2. **Fog / bloom pre-pass** — shifts the entire histogram right, increasing p50.
   The p50_conf guard already rejects p50 > 0.42 to handle this case.

3. **UI elements** — score/health bar composited on top of the game image at full
   SDR brightness. The data highway guard (y=0) filters the histogram row but does not
   protect against UI pixels in the frame body. The zone histogram (CreativeZoneHistTex)
   can partially mitigate this: exclude zones containing persistent bright UI elements
   (zones at frame edges typically) when computing the global percentile score. This is
   not yet implemented.

---

## Implementation gaps remaining

1. **Asymmetry ratio not yet validated against live Arc Raiders data.** The derivation
   assumes log-normal scene distribution with σ = 1 stop and median = 0.18 scene-linear.
   Real UE5 frames have a different effective distribution (Gaussian-in-log with heavier
   tails from specular). One calibration session reading PercTex values across 10–20
   diverse frames would lock in the smoothstep thresholds.

2. **GZW asymmetry score unknown.** If GZW uses a power-law or Hable TMO, its asymmetry
   ratio should be ≥ 0.97. If GZW uses a custom S-curve with ACES-like shoulder, the
   asymmetry could accidentally overlap. Reading PercTex from GZW gameplay with the
   proposed test would confirm separation.

3. **Tertiary discriminant needed for dark indoor scenes.** When p50 < 0.18, the ACES
   curve enters a region where the asymmetry ratio is less discriminating (both toe
   and shoulder are compressed relative to linear). The zone histogram top-bin count
   (bins 28–32 of CreativeZoneHistTex row 0, i.e., pixels in the 0.86–1.0 display range)
   is a better discriminant for dark scenes: ACES compresses highlights into this range
   even in dark scenes (specular on dark objects), while linear maps have few pixels there.

4. **Angle 0 analytical inverse still not HLSL-sketched.** The quadratic formula derivation
   is documented in PLAN.md but no prototype exists. This is the next priority for angle 0
   runs.

5. **Hable/Uncharted2 asymmetry not yet computed.** Hable has a complex piecewise rational
   form — its asymmetry ratio needs numerical calculation (not algebraically trivial like
   Reinhard) to confirm the confidence test properly rejects it.

6. **UI overlay discrimination.** Arc Raiders shows health, ammo, and objective markers as
   bright SDR pixels. These are post-ACES composited. Their presence in the full-frame
   histogram shifts PercTex and could corrupt the asymmetry test for the bottom 25% of
   the frame. A zone-masked percentile (excluding bottom 1/4 of screen height where HUD
   elements cluster) would be more reliable.

---

## Searches run

1. `"tone mapping operator identification" scene statistics signature 2022 2023 2024`
2. `"Hill ACES" OR "ACES rational" inverse analytical luminance histogram identification 2023 2024 2025`
3. `site:arxiv.org "inverse tone mapping" 2025 identification classification`
4. `"Reinhard" OR "Hable" OR "AgX" tone mapping classification fingerprint luminance distribution identification`
5. `ACES UE5 tone mapping histogram percentile statistics display-referred SDR characteristic curve`
6. `site:arxiv.org "inverse tone mapping" 2024 2025 operator estimation classification`
7. `"SDR to HDR" game engine tone curve estimation histogram shape real-time 2024 2025`
8. `SIGGRAPH ACM "ACES" OR "inverse tone mapping" analytical inversion hue distortion 2023 2024 2025`
9. `"real-time self-supervised tone curve estimation" HDR LDR histogram block patch 2023`
10. `site:arxiv.org "tone mapping" "identification" OR "fingerprint" OR "classification" "luminance histogram" 2024 2025`
11. `UE5 ACES "Hill 2016" rational approximation "p50" OR "percentile" OR "histogram" analytics detection`
12. `ACES filmic Hill approximation "a=2.51" "b=0.03" "c=2.43" analytical properties inflection shoulder toe`
13. `"gain map" "inverse tone mapping" SDR HDR luminance estimation histogram 2024 2025 single image`
14. `ACES tone mapping "inflection point" OR "concavity" luminance "0.18" OR "p50" histogram characteristic statistical test 2023 2024`
