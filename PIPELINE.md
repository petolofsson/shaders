# Olofssonian Render Pipeline

Game-agnostic vkBasalt/ReShade pipeline for photojournalistic game capture.  
Linear sRGB input (vkBasalt auto-linearizes). RGBA16F internal bus. 8-bit UNORM between effects.

---

## Effect Chain

```
analysis_frame_analysis → analysis_scope_pre → corrective_render_chain → creative_render_chain → analysis_scope
```

---

## Shaders

### analysis_frame_analysis
Builds two shared histograms per frame:
- **SatHistTex** (64×6 R32F) — per-hue-band saturation distribution, 6 bands (R/Y/G/C/B/M)
- **LumHistTex** — scene luma distribution

SatHistTex is shared by identifier with corrective and creative chains (identical declaration = same GPU resource).

### analysis_scope_pre
Captures pre-correction luma histogram into BackBuffer row y=0 (the data highway).  
Highway layout: bins 0–127 = 128-bin luma histogram, bin 128 = scene mean luma.

### corrective_render_chain
14-pass technical correction. All passes share CorrectiveBuf (RGBA16F) — no clamping between stages.

| Pass | Name | Input → Output | Role |
|------|------|----------------|------|
| 1 | WhiteBalance | BackBuffer → CorrectiveBuf | WB_R/G/B multipliers only |
| 2 | ComputeLowFreq | CorrectiveBuf → LowFreqTex | 1/8 res 4-tap downsample |
| 3 | IlluminantEstimate | LowFreqTex → IlluminantTex | Grey Pixel estimator, 4×4 zones, EMA |
| 4 | ComputeZoneHistogram | LowFreqTex → ZoneHistTex | 32-bin luma histogram per zone |
| 5 | BuildZoneLevels | ZoneHistTex → ZoneLevelsTex | CDF walk → p25/p50/p75 per zone |
| 6 | CopyBufToSrc | CorrectiveBuf → CorrectiveSrcTex | snapshot |
| 7 | ApplyAdaptation | CorrectiveSrc → CorrectiveBuf | CAT16 chromatic adaptation |
| 8 | CopyBufToSrc | CorrectiveBuf → CorrectiveSrcTex | snapshot |
| 9 | ApplyContrast | CorrectiveSrc → CorrectiveBuf | IQR-adaptive S-curve, zone median anchor |
| 10 | BuildSatLevels | SatHistTex → SatLevelsTex | CDF walk → p25/p50/p75 per hue band |
| 11 | CopyBufToSrc | CorrectiveBuf → CorrectiveSrcTex | snapshot |
| 12 | ApplyChroma | CorrectiveSrc → CorrectiveBuf | IQR-adaptive per-hue saturation S-curve |
| 13 | CopyBufToSrc | CorrectiveBuf → CorrectiveSrcTex | snapshot |
| 14 | OutputTransform | CorrectiveSrc → BackBuffer | Luma-based sigmoid, scene-adaptive grey |

**Invariants:**
- Every pass that writes to BackBuffer or CorrectiveBuf guards `if (pos.y < 1.0) return col` to preserve the data highway.
- True blacks (0.0) and true whites (1.0) pass unclamped through all corrective stages.
- All tonal compression lives exclusively in OutputTransform.

### creative_render_chain
6-pass creative look, applied after corrective. Reads ZONE_STRENGTH and CHROMA_STRENGTH from creative_values.fx.

ComputeLowFreq → ComputeZoneHistogram → BuildZoneLevels → ApplyContrast → BuildSatLevels → ApplyChroma

### analysis_scope
Dual-panel 512×164px luma histogram overlay, bottom-left.
- Top 80px (white): post-correction luma, live from BackBuffer
- Bottom 80px (red): pre-correction luma, from highway row y=0
- Yellow needle: scene mean luma. Grey line: 0.90 reference.

---

## Tuning Surface

**One file:** `gamespecific/arc_raiders/shaders/creative_values.fx`

```hlsl
#define YOUVAN_STRENGTH    // 0–100  CAT16 color constancy (0 = off)
#define OPENDRT_STRENGTH   // 0–100  display tone curve (0 = passthrough)
#define ZONE_STRENGTH      // 0–100  tonal contrast S-curve
#define CHROMA_STRENGTH    // 0–100  per-hue saturation S-curve
```

All other values are hardcoded constants inside the shaders.

---

## Key Algorithms

### Grey Pixel Illuminant Estimation (Pass 3)
For each of 16 spatial zones (4×4 grid), sample 100 pixels from the low-frequency image.  
A pixel is considered neutral if `max(|R−G|, |R−B|) / (R+G+B) < threshold`.  
Average neutral pixels → zone illuminant. If none qualify, fall back to zone mean.  
Temporal EMA smoothing normalized by frametime.

### CAT16 Chromatic Adaptation (Pass 7)
Convert pixel and zone illuminant to LMS cone space via M_CAT16.  
Scale each cone channel by `grey / illuminant_lms` to neutralize the cast.  
Convert back via M_CAT16_inv. Preserves saturation and brightness by construction (diagonal scaling in cone space = Von Kries principle).

### IQR-Adaptive S-Curve (Passes 9, 12)
The CDF walk (Passes 5, 10) captures p25, p50, p75 for each zone/band.  
IQR = p75 − p25 measures inherent contrast/saturation spread.  
Adaptive strength: `strength = base × tonal_weight × (1 − IQR)`  
Flat scenes (low IQR) receive full correction; already-contrasty scenes auto-tame.  
Chroma additionally guards near-neutrals: `sat_w = smoothstep(0, 0.15, saturation)`.

### Scene-Adaptive Output Transform (Pass 14)
Grey point reads scene mean luma from highway (row y=0, pixel 128), clamped [0.05, 0.40].  
Tone curve applied to luminance only — RGB scaled proportionally. No hue shift.  
`luma_out = sigmoid(luma_in, grey)` → `result = rgb × (luma_out / luma_in)`

---

## References & Credits

**Erik Reinhard, Michael Stark, Peter Shirley, James Ferwerda**  
*Photographic Tone Reproduction for Digital Images* (SIGGRAPH 2002)  
Scene-adaptive grey point (key value) used in OutputTransform.

**C. Li, Z. Li, Z. Wang et al.**  
*Comprehensive colour appearance model (CIECAM16)* — CIE 248:2022  
CAT16 chromatic adaptation matrices (M_CAT16, M_CAT16_inv) used in ApplyAdaptation.

**Joost van de Weijer, Theo Gevers, Arjan Gijsenij**  
*Edge-Based Color Constancy* (IEEE Trans. Image Processing, 2007)  
Grey Pixel color constancy assumption used in IlluminantEstimate.

**Jed Smith**  
*OpenDRT* — open display rendering transform  
Sigmoid curve structure used as the basis for OutputTransform.

**Björn Ottosson**  
*OKLab: A perceptual color space* (2020) — bottosson.github.io  
OKLab used for highlight chroma compression in OutputTransform.

**Ansel Adams**  
*The Zone System* — photographic tonal framework  
4×4 spatial zone grid and zone-median contrast approach conceptually rooted here.
