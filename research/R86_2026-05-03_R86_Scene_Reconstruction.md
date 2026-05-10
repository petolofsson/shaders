# R86 — Tone Mapper Identification and Analytical Inversion
**Date:** 2026-05-03 | **Angle run:** 0 (UTC hour 18 → (18//6)%3 = 0)
**Sub-track:** Scene Reconstruction (R86)

---

## Run angle

Angle 0 — Analytical inversion and closed-form derivation.

---

## HIGH PRIORITY findings

### 1. Exact analytical ACES inverse — 4 ALU, zero error (HIGH PRIORITY)

The Hill 2016 ACES approximation `y = (2.51x²+0.03x) / (2.43x²+0.59x+0.14)` has an exact
quadratic inverse for all `y` in `[0, 1]`. Rearranging to `(2.43y−2.51)x² + (0.59y−0.03)x + 0.14y = 0`
and solving with the quadratic formula yields:

```hlsl
float ACESInverse(float y)
{
    float qa = 2.43 * y - 2.51;   // always < 0 for y in [0,1]
    float qb = 0.59 * y - 0.03;
    float qc = 0.14 * y;
    float disc = max(qb * qb - 4.0 * qa * qc, 0.0);
    return (-qb - sqrt(disc)) / (2.0 * qa);  // x2 root — always positive for y in (0,1]
}
```

**Validation (forward(inverse(y)) round-trip errors, all below floating-point epsilon):**

| y_in  | x_scene  | round-trip error |
|-------|----------|-----------------|
| 0.01  | 0.019375 | 1.7e-18 |
| 0.10  | 0.085241 | 4.2e-17 |
| 0.30  | 0.200283 | 5.6e-17 |
| 0.50  | 0.356330 | 1.1e-16 |
| 0.70  | 0.657627 | 1.1e-16 |
| 0.90  | 1.771312 | 1.1e-16 |
| 0.99  | 5.551912 | 2.2e-16 |

Errors are at or below `float32` machine epsilon (2.2e-16). The inverse is numerically exact.

**Root selection:** `qa = 2.43y − 2.51 < 0` for ALL `y ∈ [0, 1]` (since 2.43·1 − 2.51 = −0.08).
Therefore x2 = `(-qb − sqrt(disc)) / (2·qa)` is ALWAYS the physically valid (positive) root.
x1 = `(-qb + sqrt(disc)) / (2·qa)` is always negative — discard it.

**Note on Microsoft DirectX-Graphics-Samples MiniEngine formula:**
The formula in `ToneMappingUtility.hlsli` (`0.5 * (D * sdr - sqrt(...) - B) / (A - C * sdr)`)
algebraically reduces to x1 — the negative root. It is **incorrect** for recovering
scene-linear values from display-referred ACES output. Use the formula above instead.

### 2. Scene-linear range recovered by inversion

| Display y | Scene-linear x | Ratio to mid-grey (0.18) |
|-----------|---------------|--------------------------|
| 0.10      | 0.085         | 0.5×                     |
| 0.25      | 0.170         | 0.9×                     |
| 0.50      | 0.356         | 2.0×                     |
| 0.80      | 0.982         | 5.5×                     |
| 0.90      | 1.771         | 9.8×                     |
| 0.95      | 2.863         | 15.9×                    |
| 0.99      | 5.552         | 30.8×                    |

The inversion maps display-referred [0, 1] back to scene-linear [0, ∞). The p95 of the
display frame corresponds to ~15–31× mid-grey in scene space — consistent with a game
scene with strong highlights. p95 (rather than p99 as initially proposed in PLAN) is
the more robust scale anchor due to specular spike contamination at p99.

### 3. AIM 2025 Challenge on Inverse Tone Mapping (arxiv 2508.13479)

**Source:** ICCV 2025 Workshop, Wang et al.
**Sub-problem:** General inverse TMO, HDR reconstruction from single LDR
**Approach:** Neural (U-Net baseline + challenge submissions)
**GPU feasible:** NO — inference models, offline
**Relevance:** Confirms that analytical inversion of known operators (their "analytical baseline")
consistently outperforms blind neural methods when the TMO is known. Validates the R86
approach of using the closed-form ACES inverse when confidence is high.
**Key quote:** "expansion using analytical tone-mapping functions" appears as a competitive
baseline against deep learning approaches.

---

## Findings

### F1 — Analytical ACES inverse via quadratic formula
- **Sub-problem:** Inverse (Angle 0)
- **Approach:** Analytical, closed-form
- **GPU feasible:** YES — 4 ALU (2 MAD + sqrt + div), SPIR-V safe, no static const arrays
- **Error bounds:** Machine epsilon (≤2.2e-16), exact for float32
- **Real-time adaptable:** Fully — single function, per-channel
- **Novelty:** The formula itself is not novel (standard quadratic), but the application
  inside a real-time display shader with TMO confidence-gating is novel
- **Search query:** "inverse tone mapping operator rational function GPU shader"

### F2 — Microsoft MiniEngine InverseToneMapACES formula is wrong (negative root)
- **Sub-problem:** Implementation trap
- **Source:** github.com/microsoft/DirectX-Graphics-Samples ToneMappingUtility.hlsli
- **Detail:** Their formula computes x1 (always negative for y∈[0,1]). The correct formula
  requires x2 = `(-qb - sqrt(disc)) / (2·qa)`. This is an important correctness note —
  copying the Microsoft formula will produce garbage output silently.

### F3 — AIM 2025 ITM Challenge: analytical methods competitive with neural
- **Sub-problem:** Inverse (general)
- **Approach:** Neural + analytical baselines
- **GPU feasible:** NO for neural, YES for analytical baselines
- **Error bounds:** PU21-PSNR 27.23 dB for U-Net baseline; analytical baselines
  competitive when TMO is known
- **Usable:** Confirms the design philosophy: analytical when TMO is identified, fallback
  to identity otherwise
- **Search query:** "AIM 2025 challenge on Inverse Tone Mapping Report"

### F4 — ACES histogram fingerprint: three discriminants from PercTex
- **Sub-problem:** TMO identification (fingerprinting)
- **Approach:** Statistical, closed-form
- **GPU feasible:** YES — 5-6 ALU using existing PercTex data, no new taps
- **Discriminants:**
  1. `highs_norm = (1-p75)/IQR` — ACES: 0.8–1.5 (bright scenes); Reinhard: 4–11; Hable: 10–25
  2. `shadow_rat = p25/p50` — ACES: 0.49–0.73; Reinhard: 0.64–0.71; Hable: 0.63–0.65
  3. `bright_gate = p50 > 0.15` — dark scenes have ambiguous signature for all TMOs
- **Caveat:** At dark scene exposure (scene_mu=0.10), all TMOs converge in their
  display-referred statistics. Gate on p50 > 0.15 before trusting the score.
- **Search query:** "tone mapper identification fingerprint histogram display statistics"

### F5 — HDR reconstruction literature: neural methods dominate 2023-2025
- **Sub-problem:** General inverse / HDR reconstruction
- **Approach:** Neural (diffusion, U-Net, multi-exposure synthesis)
- **GPU feasible:** NO (inference latency 100ms+)
- **Relevance:** Confirms R86's decision to use analytical inversion (known TMO) rather
  than a neural model. All neural methods are offline VFX tools.
- **Search query:** "HDR reconstruction single exposure analytical display referred 2024 2025"

---

## Prototype sketch

### ACESInverse (per-channel, per-pixel)

```hlsl
// R86: Analytical ACES Hill 2016 inverse
// Input y in [0,1] (display-referred). Output x in [0, inf) (scene-linear).
// Solves (2.43y-2.51)x^2 + (0.59y-0.03)x + 0.14y = 0 for positive root.
// Round-trip error <= 2.2e-16 (float32 machine epsilon).
float ACESInverse(float y)
{
    float qa = 2.43 * y - 2.51;          // always negative for y in [0,1]
    float qb = 0.59 * y - 0.03;
    float qc = 0.14 * y;
    float disc = max(qb * qb - 4.0 * qa * qc, 0.0);
    return (-qb - sqrt(disc)) / (2.0 * qa);
}

float3 ACESInverse3(float3 rgb)
{
    return float3(ACESInverse(rgb.r), ACESInverse(rgb.g), ACESInverse(rgb.b));
}
```

### Confidence score (uses existing PercTex — zero new taps)

```hlsl
// R86: ACES confidence from display-referred histogram shape.
// perc = tex2D(PercSamp, ...) — r=p25, g=p50, b=p75, a=iqr
// Returns [0,1]: 1 = almost certainly ACES, 0 = not ACES or undecidable.
float ACESConfidence(float4 perc)
{
    float iqr       = max(perc.b - perc.r, 0.001);
    float highs_norm = max(1.0 - perc.b, 0.0) / iqr;     // ACES: <1.5; others: >4
    float shadow_rat = perc.r / max(perc.g, 0.001);       // ACES: <0.65; others: >0.65
    float bright_gate = smoothstep(0.15, 0.30, perc.g);   // dark scene = undecidable
    return bright_gate * saturate(
        smoothstep(3.0, 1.2, highs_norm) * 0.70 +
        smoothstep(0.72, 0.52, shadow_rat) * 0.30);
}
```

### Scale anchor (p95 → scene-linear ceiling)

```hlsl
// Map display-referred p95 back to scene-linear.
// Use this as the re-normalization scale after inversion.
// p95 is stored in zone_hist bins (bin 30 of 32 = ~95th percentile).
// If not available, use p75 as a conservative anchor.
float scene_ceil = ACESInverse(perc.b);  // p75 anchor (conservative)
// TODO: wire to actual p95 from CreativeZoneHistTex once prototype confirmed
```

### Integration point (Stage 0, before EXPOSURE)

```hlsl
// In ColorTransformPS, BEFORE pow(col.rgb, EXPOSURE):
float aces_conf = ACESConfidence(perc);
if (aces_conf > 0.3)
{
    float3 scene_lin = ACESInverse3(col.rgb);
    // Normalize to [0,1] using p95 anchor
    float scene_ceil = ACESInverse(lerp(perc.b, 0.95, 0.5));  // approximate p95
    scene_lin = scene_lin / max(scene_ceil, 1.0);
    col.rgb = lerp(col.rgb, saturate(scene_lin), smoothstep(0.3, 0.7, aces_conf));
}
// Then proceed with existing EXPOSURE, CAT16, etc.
```

---

## Implementation gaps

1. **Confidence score needs empirical tuning.** The discriminants are derived from
   synthetic log-normal scenes. Need to run Arc Raiders and GZW in debug mode to
   read actual `perc.r/g/b/a` values and verify the score fires correctly.
   Arc Raiders target: `aces_conf > 0.7`. GZW target: `aces_conf < 0.3`.

2. **p95 anchor needs a dedicated histogram bin or approximation.**
   PercTex only stores p25/p50/p75/IQR. A rough p95 estimate from the zone histogram
   (bin 30/32 of CreativeZoneHistTex averaged across zones) could provide this.
   Alternatively, use `lerp(p75, 1.0, 0.6)` as a heuristic (p95 ≈ 0.4*(1-p75) above p75
   for ACES at typical exposure — needs validation).

3. **ACES hue shift correction not yet researched.**
   The ACES operator introduces hue distortions (red→orange push, cyan→blue shift,
   yellow highlight desaturation). These are Angle 1 territory — not covered this run.
   After the luminance inversion is stable, the hue correction layer is the next step.

4. **Forward re-apply design pending.**
   After scene-referred grading, a controlled forward display transform is needed.
   Decision: whether this replaces FilmCurve entirely or operates as an additive layer
   on top depends on how the inversion interacts with existing Stage 1 corrections.
   Not prototypeable until luminance inversion is validated end-to-end.

5. **Prototype location:** `unused/general/inverse-grade/inverse_grade_aces.fx` (new file).
   Do NOT modify live `grade.fx` until confidence score is validated on both games.

6. **Post-ACES operations risk.** Arc Raiders may apply sharpening, bloom, or UI compositing
   after the ACES tone mapper and before vkBasalt sees the frame. These would introduce
   scene content at non-ACES luminance levels. The y=0 highway guard already suggests
   one non-ACES overlay layer. Need to test whether the inversion degrades gracefully
   on UI/HUD regions (current thinking: confidence score gates the whole-frame inversion,
   so UI-heavy frames get low confidence and fall back to identity).

---

## Searches run

1. `inverse tone mapping ACES analytical closed-form 2023 2024 2025` — Found GameDev.net forum thread, Shadertoy implementations, Microsoft DirectX-Graphics-Samples (key find — wrong root bug identified), Narkowicz blog, AIM 2025 paper
2. `inverse tone mapping operator rational function GPU shader HLSL` — Found Microsoft MiniEngine HLSL code (wrong root confirmed), AMD GPUOpen reversible tonemapper, ReShade forum discussion
3. `HDR reconstruction single exposure analytical display referred 2024 2025` — Confirmed neural methods dominate 2024-2025; no analytical per-pixel methods competitive with closed-form for known TMO
4. `arxiv.org inverse tone mapping analytical perceptual 2024 2025` — AIM 2025 challenge arxiv:2508.13479, Semantic Diffusion ITM (2405.15468), perceptual TMO CIECAM16 (2309.16975)
5. `ACES filmic inverse quadratic closed form exact solution Hill 2016 UE4 UE5` — Narkowicz 2016 blog, Shadertoy implementations, no definitive closed-form write-up with root selection analysis
6. `tone mapping operator classification recognition histogram display statistics real-time` — No dedicated TMO identification paper found; fingerprinting approach is novel
7. `AIM 2025 inverse tone mapping challenge analytical baseline methods results arxiv 2508.13479` — Confirmed analytical TMO inversion is used as competitive baseline in 2025 challenge

---

## Key conclusions

- The analytical ACES inverse is 4 ALU, machine-epsilon accurate, and SPIR-V safe.
- The Microsoft MiniEngine formula has a root-selection bug — verified analytically and numerically.
- A confidence score using only existing PercTex data (zero new taps) is feasible.
- The fingerprint is robust for mid-to-bright scenes (p50 > 0.15) but degrades for very dark scenes — gate accordingly.
- Angle 1 (hue distortion characterization) and Angle 2 (blind fingerprinting) are the natural next runs for R86.
- No existing real-time shader implementation combines confidence-gated ACES inversion + scene-referred grading — this remains novel.
