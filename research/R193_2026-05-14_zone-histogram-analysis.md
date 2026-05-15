# R193 — Zone / Histogram Analysis — 2026-05-14

## Domain
Thursday rotation: Zone/histogram analysis (2023–2026 literature sweep).

---

## Summary

Three complementary histogram shape descriptors that fill gaps in the current
zone/analysis pipeline. Primary finding is normalized histogram entropy (H_norm) as
a scene tonal complexity signal; secondary findings are explicit IQR on the highway
and mode–median distance as a lightweight bimodality proxy.

---

## Finding 1 — Normalized Histogram Entropy (H_norm) as tonal complexity signal

### Literature basis

**"Perceptual Complexity as Normalized Shannon Entropy"**  
Grzywacz NM, MDPI *Entropy* 27(2):166, published 2025-02-05. PMC11854106.  
Shows that normalized Shannon entropy H_norm = H/H_max = −Σ pᵢ log₂(pᵢ) / log₂(N)
predicts perceived scene complexity better than variance or standard deviation alone.
Demonstrates that H_norm is robust to resolution changes and correlates with human
aesthetic judgements about image richness.

**"Perceptually Adaptive Real-Time Tone Mapping"**  
Tariq et al., SIGGRAPH Asia 2023, DOI:10.1145/3610548.3618222.  
Argues that matching the scene's luminance *distribution shape* (not just its mean or
median) to display capabilities is the key to perceptual fidelity. Uses global
histogram-derived statistics to adaptively scale the tone curve slope. Runs < 1ms on
Quest 2 — demonstrates that full histogram statistics are cost-viable for real-time.

### Gap addressed

Current pipeline has:
- `zone_std` — mean intra-zone pixel variance (per-zone local heterogeneity)
- `zone_log_key` — luminance centroid across zones
- Bowley skewness — distributional tilt (p75 + p25 − 2·p50)
- `specular_contrast` — (p90 − p50) / 0.40 (highlight headroom)
- histogram mode — argmax bin centre (R147)

**What is missing:** A global measure of how *spread out* the luminance mass is across
all 64 bins. A scene with 60 of its 64 bins empty (peaked, concentrated distribution)
has very different processing requirements than a scene where all 64 bins have equal
mass, even if their means and variances are identical. `zone_std` captures local
within-zone variance but not whether the *inter-zone* distribution is flat or spiked.
H_norm captures exactly this: maximum entropy (1.0) = perfectly uniform distribution
across all bins; minimum entropy (0.0) = all mass in one bin.

### Formula

```
H_norm = −[ Σ_{i=0}^{63} h_i · log2(max(h_i, 1e-6)) ] / log2(64)
```

where `h_i` is the normalized histogram bin (already computed by LumHistGatherPS,
sums to 1.0). Division by log₂(64) = 6.0 rescales to [0, 1].

H_norm ∈ [0, 1]:
- 0.0 = all pixels at a single luminance (fog, overexposure)
- 1.0 = perfectly uniform distribution (test chart)
- Typical outdoor scene: ~0.70–0.85
- Typical dark interior: ~0.35–0.55
- Typical night exterior: ~0.25–0.45

### Concrete use cases in the pipeline

**A. Zone S-curve strength modulation**

`zone_str` currently interpolates `lerp(0.26, 0.16, ss_08_25)` driven by `zone_std`.
`zone_std` measures local per-zone heterogeneity, not global tonal distribution.
H_norm could supplement or replace the `zone_std` driver for the inter-zone strength:

```hlsl
// In BuildSceneCtx — supplement zone_str with global entropy
float h_norm = ReadHWY(HWY_H_NORM);          // new slot 207
// High entropy: rich tonal content, attenuate S-curve to preserve gradations
// Low entropy: compressed distribution, safe to stretch harder
float h_att  = lerp(1.0, 0.75, saturate((h_norm - 0.55) / 0.30));
ctx.zone_str *= h_att;
```

This is a non-gate modulation (continuous) that naturally reduces zone stretch when
the scene already has a rich tonal spread that doesn't need redistribution.

**B. fc_stevens adaptation**

`fc_stevens` currently comes from the highway encoded by `analysis_scope_pre`.
H_norm could provide a secondary modulation: very low entropy (≤ 0.35) indicates a
"collapsed" tonal distribution (fog, severe underexposure) where Stevens brightening
is already acting on little tonal material — the slope can safely be raised.

**C. Diffusion adapt_str gating**

`DiffusionPS` currently scales `adapt_str` by `diff_key_scale` and `diff_bowley`.
H_norm ≥ 0.80 (extremely wide distribution) suggests a complex HDR-like scene where
diffusion shimmer is already embedded in highlight spread — modest attenuation avoids
over-diffusing already naturally rich scenes.

### Implementation sketch

New 1×1 texture + new pass in `analysis_frame.fx`, inserted after LumHistSmoothPS:

```hlsl
// ─── Pass N — Histogram Normalized Entropy ────────────────────────────────────
// H_norm = -sum(h * log2(h)) / log2(64). Source: LumHist (EMA-smoothed histogram).

texture2D EntropyTex { Width = 1; Height = 1; Format = R16F; MipLevels = 1; };
sampler2D EntropySamp { Texture = EntropyTex; AddressU = CLAMP; AddressV = CLAMP;
                        MinFilter = POINT; MagFilter = POINT; };

float4 HistEntropyPS(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float H = 0.0;
    [loop] for (int b = 0; b < 64; b++)
    {
        float h = tex2Dlod(LumHist, float4((float(b) + 0.5) / 64.0, 0.5, 0, 0)).r;
        H      -= h * log2(max(h, 1e-6));
    }
    // Normalize to [0,1]: H_max = log2(64) = 6.0
    float h_norm = saturate(H / 6.0);

    // Light EMA smoothing — entropy changes slowly between frames
    float prev  = tex2Dlod(EntropySamp, float4(0.5, 0.5, 0, 0)).r;
    float alpha = saturate(frametime * 0.002);
    return float4(lerp(prev, h_norm, alpha), 0, 0, 1);
}
```

Highway write in `HighwayWritePS`:

```hlsl
#define HWY_H_NORM  207   // histogram normalized entropy [0,1]

if (xi == HWY_H_NORM)
    return float4(tex2Dlod(EntropySamp, float4(0.5, 0.5, 0, 0)).r, 0, 0, 1);
```

### GPU cost estimate

- Texture ops: 64 × tex2Dlod on 64×1 LumHist (L1 resident, effectively free)
- ALU: 64 × log2 + 64 × multiply-add + 1 divide = ~192 ALU instructions
- One additional 1×1 RenderTarget write
- **Estimated cost: < 0.01ms at 4K; negligible.**

### Conflict check

- No static const arrays — scalar loop ✓
- No `out` variable name ✓
- LumHist is a within-technique texture (EMA-smoothed) read via tex2Dlod ✓
- Result fits in [0,1] unencoded — no highway encoding needed ✓
- No gates; continuous modulation only ✓
- No HDR or auto-exposure involvement ✓

---

## Finding 2 — Explicit IQR on the highway (structural fill)

### Gap addressed

IQR = p75 − p25 is currently computed *inline* at several pipeline sites:
- Bowley denominator in BuildSceneCtx: `max(perc.b - perc.r, 0.01)`
- diffusion `diff_ap_scale` in DiffusionPS: `(perc.b + perc.r - 2.0 * perc.g)` uses both
- grade.fx CLAHE scale: `max(ctx.zone_str, 0.001)` via IQR-scaled delta

These inline computations re-derive IQR from the same PercSamp, but they introduce
slight per-pass temporal skew and no single "scene contrast width" is available as a
clean highway signal for future effects.

### Literature basis

Tariq 2023 and the JNR-based histogram literature (Ploumis et al. 2016,
IEEE; multi-scale histogram synthesis, arXiv:2102.00408) consistently treat
IQR as the primary per-frame "scene contrast width" statistic used to scale
tone mapping operators. Making it an explicit highway slot establishes this as a
canonical per-frame scalar available to all downstream effects.

### Implementation

Zero additional passes — computed in `HighwayWritePS` in `analysis_frame.fx`:

```hlsl
#define HWY_IQR  208   // IQR = p75 - p25 [0, 1]

if (xi == HWY_IQR) {
    float4 p = tex2Dlod(PercSamp, float4(0.5, 0.5, 0, 0));
    return float4(p.b - p.r, 0, 0, 1);
}
```

**GPU cost: ~2 tex2Dlod (shared with other slots) + 1 subtract. Effectively 0.**

### Notes on range

IQR ∈ [0, 1] naturally. Typical values:
- 0.02–0.05: low-key interior, flat lighting
- 0.10–0.20: typical outdoor game scene
- 0.25–0.45: high-contrast scene (interior + bright window)
- IQR does not need encoding; fits highway unmodified.

---

## Finding 3 — Mode–Median Distance as bimodality proxy

### Gap addressed

The pipeline tracks:
- Bowley skewness: direction and magnitude of asymmetry around the median
- Histogram mode (R147): single dominant luminance level

What is not tracked: whether the histogram's dominant peak (mode) sits far from the
median. A large |mode − p50| gap signals that the distribution is heavily asymmetric
— the "typical" pixel (mode) is far from the "average" pixel (median). This is a
lightweight proxy for bimodal or heavy-tailed scenes (e.g., dark corridor with a
bright doorway).

Note: this is related to but distinct from Bowley skewness. Bowley captures the
quartile-based asymmetry; mode–median distance captures where the tallest peak
sits relative to the luminance centroid. A bimodal histogram (two peaks of equal
height) would show Bowley ≈ 0 but large mode–median distance.

### Literature basis

The Ashman bimodality coefficient (Ashman, Bird & Zepf 1994) and Hartigan's dip
test are the canonical bimodality detectors, but both require sorted data and are
not GPU-viable. Mode–median distance is a practical real-time surrogate described
informally in histogram-based exposure metering literature (Narkowicz 2016) and used
implicitly in several auto-exposure implementations where mode-hunting and median
estimation are done separately but compared.

### Implementation

No new pass — computable inline in `HighwayWritePS` from existing ModeSamp + PercSamp:

```hlsl
#define HWY_MODE_MEDIAN_D  209  // |mode - p50| as bimodality proxy [0, 1]

if (xi == HWY_MODE_MEDIAN_D) {
    float mode = tex2Dlod(ModeSamp, float4(0.5, 0.5, 0, 0)).r;
    float p50  = tex2Dlod(PercSamp, float4(0.5, 0.5, 0, 0)).g;
    return float4(abs(mode - p50), 0, 0, 1);
}
```

**GPU cost: ~3 tex2Dlod (shared with adjacent slots) + 2 ops. Effectively 0.**

### Use case

In grade.fx, can be read as `ReadHWY(HWY_MODE_MEDIAN_D)` to detect strongly
asymmetric scenes. Example application: when mode_median_d > 0.15, the distribution
has a dominant peak that is not representative of the median — in this regime,
zone_std-based CLAHE slope may be over-estimating heterogeneity. A light attenuation
of zone_str when mode_median_d is large would prevent the S-curve from artificially
redistributing a legitimately asymmetric tonal structure.

---

## Priority

| Finding | Novelty | Cost | Readiness |
|---------|---------|------|-----------|
| F1 — H_norm entropy | High (2025 lit) | ~0.01ms, 1 new pass + texture | Implement-ready |
| F2 — IQR on highway | Structural | ~0 (inline) | Trivial, implement anytime |
| F3 — Mode–median distance | Moderate | ~0 (inline) | Low priority until use case confirmed |

F1 is the recommended primary implementation. F2 can accompany it at negligible cost.
F3 should wait until a concrete consuming expression in grade.fx is identified.

---

## Sources

- Grzywacz NM. "Perceptual Complexity as Normalized Shannon Entropy." *Entropy* 27(2):166, 2025. https://www.mdpi.com/1099-4300/27/2/166
- Tariq T et al. "Perceptually Adaptive Real-Time Tone Mapping." SIGGRAPH Asia 2023. https://dl.acm.org/doi/abs/10.1145/3610548.3618222
- Ploumis et al. "Perception-Based Histogram Equalization for Tone Mapping Applications." IEEE 2016. https://ieeexplore.ieee.org/document/7574892
- arXiv:2102.00408 — "Tone Mapping Based on Multi-scale Histogram Synthesis"
- Narkowicz K. "Automatic Exposure" (2016). https://knarkowicz.wordpress.com/2016/01/09/automatic-exposure/
