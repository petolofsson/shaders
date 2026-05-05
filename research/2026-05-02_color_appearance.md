# Research Findings — Color Appearance Models — 2026-05-02

## Search angle

Saturday domain: color appearance models. Queries targeted JzAzBz, ICtCp, CIECAM16, Oklab
hue non-linearity, HELMLAB, ACES Output Transform chroma compression, and Hunt/Stevens
effect models. Five Brave/WebSearch queries and three arxiv attempts (arxiv returned no
results — network partition). Key sources: arxiv 2602.23010 (HELMLAB, Feb 2026),
ACES Output Transform documentation (acescentral.com), Raph Levien Oklab critique (2021),
Oklab original specification (Ottosson 2020).

---

## Finding 1: HELMLAB 4-harmonic Fourier hue correction reveals actionable Oklab hue non-linearity in band-weighted chroma operations

**Source:** https://arxiv.org/abs/2602.23010 — "HELMLAB: An Analytical, Data-Driven Color
Space for Perceptual Distance in UI Design Systems," Görkem Yildiz, February 2026
**Year:** 2026
**Field:** Perceptual color space design / human colour-difference data

### Core thesis

HELMLAB builds a 72-parameter analytical color space fit to 64,000 human observations
(COMBVD dataset). Its forward transform includes a **4-harmonic Fourier hue correction**
of the form:

```
h_corrected = h + Σ_{k=1..4} (a_k·cos(k·θ) + b_k·sin(k·θ))
```

This equalises the perceptual hue circle. An initial fit overshoots in the blue-magenta
band; a blue-band refit with sub-dataset penalties resolves this, reducing **gradient
non-uniformity in blue-cyan by 8.9×** at a cost of only +0.08 STRESS. Aggregate result:
HELMLAB STRESS = 23.30 vs CIEDE2000 STRESS = 29.18, a 20.2% improvement.

The 8.9× non-uniformity figure is the key transfer: it quantifies how much worse the
blue-cyan region is relative to a corrected perceptual baseline. All Oklab-family spaces
(including Oklab itself) share a similar pathology — Raph Levien's 2021 critique
independently identifies the yellow-green equi-chroma crookedness and the blue-purple
(270–330°) hue shift that CILAB always exhibited and Oklab only partially resolves.

### Current code baseline

`grade.fx:317`  
```hlsl
float  h   = OklabHueNorm(lab.y, lab.z);
```
`h` is used raw (without any correction) for:
- `HueBandWeight()` calls at lines 331–336 (R21 hue rotation weights)  
- `HueBandWeight()` calls at lines 363–366 (chroma lift band weights)  
- `h_out` at line 337 (post-rotation hue, used for Abney and H-K)  

If Oklab's reported hue angle does not uniformly track perceptual hue, all six band-weighted
operations operate on a slightly wrong hue axis. The error is worst in blue-cyan
(h ≈ 0.54–0.74, matching BAND_CYAN=0.542 and BAND_BLUE=0.735) — precisely the region
HELMLAB quantifies as 8.9× non-uniform.

### Proposed delta

Inject a 2-harmonic Fourier correction to `h` immediately after line 317, before any band
weight is computed:

```hlsl
// HELMLAB principle: 2-term Fourier correction aligns Oklab hue → perceptual hue.
// Coefficients approximate the known Oklab blue-purple / yellow-green bending:
//   1st harmonic: global warp (blue pulls CCW, yellow pulls CW, net rotation)
//   2nd harmonic: double-frequency correction for the two known problem zones
float theta  = h * 6.28318;
float h_perc = frac(h + (0.008 * sin(theta) + 0.004 * sin(2.0 * theta)) / 6.28318);
```

Use `h_perc` (not raw `h`) for all six `HueBandWeight()` calls and for `h_out` before the
R21 hue-rotation delta. Do **not** use `h_perc` for the fast-atan2 (`OklabHueNorm`) itself
— the correction is applied only in the perceptual band-weight domain.

Coefficient magnitudes (0.008, 0.004) are first-order estimates from Ottosson's 2020
comparison plots; a calibration pass against COMBVD data would sharpen them. The
HELMLAB GitHub implementation (github.com/Grkmyldz148/helmlab) contains the full
72-parameter fit and could supply more accurate values for the 1st and 2nd harmonic
that are specific to the Oklab→perceptual mapping.

### Injection point

`grade.fx:317–318` — immediately after `OklabHueNorm`, before `HueBandWeight(h, BAND_RED)`
at line 331. Replace all downstream uses of `h` in band weights with `h_perc`; keep `h`
only for the Purkinje stage (line 321) where Oklab's own axis is appropriate.

### Breaking change risk

LOW. The correction is a small, smooth, periodic perturbation. Maximum hue shift is ≈0.8°
(0.002 normalised). Band weights remain bounded [0,1] and the Fourier terms sum to zero
over the full circle, so mean saturation is unchanged. The change would slightly re-centre
which pixels respond to BAND_BLUE and BAND_CYAN controls.

### Viability verdict

**ACCEPT — R60 candidate.** Well-sourced, 2-ALU incremental cost, addresses a quantified
perceptual gap in the existing chroma/rotation machinery.

---

## Finding 2: Per-pixel Hunt adaptation luminance — CAM16 local-field specification vs current global scene-mean

**Source:**  
Li, C. et al. (2017) "Comprehensive colour appearance model (CAM16)," *Color Research &
Application* — CAM16 specifies the adaptation field luminance L_A as the per-pixel
viewing condition, not a fixed global mean.  
Hunt, R.W.G. (1995) "The Reproduction of Colour," 5th ed., ch. 8 — original Hunt effect
derivation is per-stimulus.
**Year:** 1995 / 2017
**Field:** Colour appearance modelling

### Core thesis

The Hunt effect (increased colorfulness at higher luminance) is specified per-pixel in
CAM16: the adaptation luminance L_A enters the F_L calculation *for each pixel
independently*. Using a single global scene mean (zone_log_key) applies the correct
average but creates a systematic error: highlight pixels receive too little Hunt boost
(they are brighter than the scene mean, so their actual L_A is higher), and shadow
pixels receive too much (their actual L_A is lower). The error magnitude grows with
scene contrast; in a high-dynamic-range game scene, zone_std can reach 0.20–0.25,
corresponding to a ~1.3× F_L ratio between shadow and highlight pixels.

### Current code baseline

`grade.fx:339–346`
```hlsl
float la         = max(zone_log_key, 0.001);
float k          = 1.0 / (5.0 * la + 1.0);
float k2         = k * k;
float k4         = k2 * k2;
float fla        = 5.0 * la;
float one_mk4    = 1.0 - k4;
float fl         = k4 * la + 0.1 * one_mk4 * one_mk4 * pow(fla, 1.0 / 3.0);
float hunt_scale = sqrt(sqrt(max(fl, 1e-6))) / 0.5912;
```

`zone_log_key` (scene log-mean, from ChromaHistoryTex col 6) is uniform across all pixels.
`new_luma` (post-tonal per-pixel luminance) is already computed at line 303 but not used
in the Hunt block.

### Proposed delta

Replace the single `la = zone_log_key` with a per-pixel blend toward the local luminance:

```hlsl
// CAM16 local-field adaptation: blend global scene mean toward pixel-local luminance.
// HUNT_LOCALITY = 0 → current global behavior; 0.35 → proposed default.
float la = max(lerp(zone_log_key, new_luma, HUNT_LOCALITY), 0.001);
```

Add `HUNT_LOCALITY` to `creative_values.fx` (default 0.35, range 0.0–0.7). The k/fl/
hunt_scale computation that follows remains identical — the change is solely in the
input luminance fed to the adaptation chain.

Effect at default 0.35:
- A highlight at new_luma=0.85 with zone_log_key=0.25: la rises from 0.25 to 0.46 →
  fl increases → hunt_scale increases → chroma_str gets a modest boost.
- A shadow at new_luma=0.04: la falls from 0.25 to 0.16 → chroma_str is reduced,
  preventing shadow colour mud.

### Injection point

`grade.fx:339` — replace `float la = max(zone_log_key, 0.001)` with the lerp.
New knob: `creative_values.fx` — `HUNT_LOCALITY  0.35`.

### Breaking change risk

MEDIUM. Spatially varying chroma boost could produce subtle saturation gradients at
hard luminance boundaries (e.g. a bright sun disc against deep shadow). However:
- The effect is modulated by `HUNT_LOCALITY`; at 0 it is the current behavior.
- `new_luma` is computed from low-freq textures at mip 1 (CreativeLowFreqSamp) via the
  MSR illumination estimate — it is already spatially smoothed, not per-pixel raw luma.
  Actually `new_luma` at line 295-311 uses the zone S-curve result; it's per-pixel but
  varies smoothly in well-lit scenes. Validation needed at `HUNT_LOCALITY ≤ 0.4`.
- Self-limiting: the Hunt boost is bounded by `chroma_str = saturate(...)` and the
  downstream `saturate(chroma_rgb)`.

### Viability verdict

**ACCEPT — R61 candidate.** Closes a documented CAM16 specification gap, adds one lerp
(~2 ALU), new creative knob is on/off-able at 0. Requires A/B test in a scene with
large luminance range.

---

## Finding 3: Chroma-stable tonal scaling — Oklab L-only substitution instead of RGB proportional scaling in the zone S-curve

**Source:**  
ACES Output Transforms 2.0 technical overview (docs.acescentral.com, 2024) — explicitly
separates the tone-mapping path (J-only) from chroma (M preserved).  
Dolby ICtCp design rationale (SMPTE ST 2084, 2016) — opponent-channel processing separates
I from Ct/Cp to prevent chroma contamination during luminance encoding.  
**Year:** 2016 / 2024
**Field:** Colour image tone mapping / opponent channel processing

### Core thesis

Scaling linear-light RGB by a factor k is NOT equivalent to scaling Oklab L by k^(1/3):

```
Linear RGB → Oklab: L(k·rgb) = k^(1/3) · L(rgb)
                    C(k·rgb) = k^(1/3) · C(rgb)   ← chroma changes too
```

Because Oklab uses per-channel cube-roots, proportional RGB scaling changes both L **and**
C simultaneously. The current tonal stage at `grade.fx:311`:

```hlsl
lin = saturate(lin * (new_luma / max(luma, 0.001)));
```

applies a scale of `r = new_luma / luma` to all channels. This changes Oklab chroma by
`r^(1/3)`. For a zone S-curve that moves a highlight pixel from luma=0.40 to luma=0.50
(r=1.25), Oklab chroma rises by 1.25^(1/3) ≈ 1.08 (+8%) as a side effect — a colorfulness
increase that was never requested.

ACES 2.0 Output Transforms solve the equivalent problem by operating only on J (Hellwig
luminance) within the tone-mapping step, leaving M (colorfulness) strictly untouched.
ICtCp encodes I separately from Ct/Cp for the same reason.

For our pipeline: an Oklab round-trip in the TONAL stage can replicate this principle
without any colour-space switch.

### Current code baseline

`grade.fx:285–312` — TONAL block.  
Line 311: `lin = saturate(lin * (new_luma / max(luma, 0.001)));`

This is the only place where a tonal luma change is applied to the RGB signal.

### Proposed delta

Replace line 311 with an Oklab L-substitution:

```hlsl
// Tonal scaling: set Oklab L to new_luma without touching a,b (chroma-stable).
// Prevents zone S-curve from inadvertently changing colorfulness.
float3 lab_t = RGBtoOklab(saturate(lin));
lab_t.x = new_luma;
lin = saturate(OklabToRGB(lab_t));
```

This preserves the (a, b) vector — and therefore Oklab C and h — through the entire tonal
stage, including MSR, shadow_lift, and zone S-curve. Colorfulness changes only where
the pipeline explicitly intends them: Stage 3 (CHROMA).

Edge case: when `new_luma` > max-achievable L at the current (a,b), `OklabToRGB` produces
out-of-gamut values that `saturate()` clips per-channel. This is the correct gamut-aware
behaviour (the RGB clip desaturates at the gamut boundary, which is physically correct
when tone-lifting a saturated shadow toward mid-tone). The current approach also clips at
`saturate()` but does so after scaling all channels, which can clip in a less perceptually
predictable way.

### Cost

Adds one `RGBtoOklab` + one `OklabToRGB` round-trip (~24 ALU: 2 mat-vec muls, 6 cube
roots, 6 cubes). Both functions are already inlined in the shader; the compiler can
share register pressure with the Stage 3 Oklab that follows at line 315.

### Injection point

`grade.fx:311` — replace the one-line proportional scale. `lin` entering line 312 will
have the same luma trajectory but stable Oklab chroma. `TONAL_STRENGTH` lerp at 312
still applies.

### Breaking change risk

MEDIUM. The chroma-contamination artefact being removed is subtle (~8% at r=1.25), but
has been part of the pipeline since the zone S-curve was introduced. Removing it will
slightly reduce colorfulness in brightened zones and slightly increase it in darkened
zones compared to today. The net chroma change integrates to near-zero over a typical
scene (zone median pixels are unchanged; brightened and darkened pixels partially
cancel). Perceptually the change is positive (TONAL stage no longer has chroma side
effects), but A/B comparison in a high-contrast scene is warranted before commit.

`TONAL_STRENGTH = 0` is unchanged (lerp pins to `lin_pre_tonal`).

### Viability verdict

**ACCEPT — R62 candidate.** Closes a principled gap: tonal operations should not affect
chroma. Cost is well-bounded, no new knobs needed, no gates, SDR by construction.
Implementation is 3 lines. Requires visual validation.

---

## Discarded this session

| Title / Source | Reason |
|---|---|
| JzAzBz full color space replacement | Full pipeline rewrite; BT.2100 PQ encoding requires HDR values — violates SDR constraint |
| ICtCp as working space for chroma | ST.2084 EOTF requires >1.0 values internally; SDR violation |
| CIECAM16 hue quadrature H in shader | Full CIECAM16 H requires 4-segment piecewise with 5 unique hue primaries and 4 ternary coefficients — not SPIR-V safe, LUT-equivalent cost |
| Deep Chroma Compression (arxiv 2409.16032) | GAN-based (ML inference) — violates real-time constraint |
| Chromatic adaptation VR (arxiv 2509.23489) | Addresses time-course adaptation for dynamic display power; no SDR shader application |
| ACES cusp-model M compression replacing density_L | Our existing gclip (grade.fx:408-410) already implements a gamut projection; cusp approximation without hue-dependent LUT is too crude to improve on it |
| PCS23-UCS hue band-center shift | The architectural insight (hue-plane preservation) is valid but the specific delta (shift BAND_CYAN/BLUE by 0.007) is too small to merit a standalone finding; absorbed into R60's Fourier correction |
| Oklab achromatic noise gate (HELMLAB neutral correction) | Would require a smoothstep threshold on C — explicit gate, violates no-gates rule |

---

## Strategic recommendation

R60, R61, and R62 are independent and can be implemented in any order. Suggested staging:

1. **R60 first** (lowest risk, 2 ALU) — Fourier `h_perc` correction. Most likely to cause
   no visual surprise; only shifts which pixels respond to blue/cyan knobs slightly.
2. **R62 second** (medium risk, 24 ALU) — Oklab-stable tonal. Cleaner architecture; the
   change will be most visible in high-saturation, high-contrast test scenes.
3. **R61 last** (new knob, needs tuning) — per-pixel Hunt locality. Requires a calibrated
   HUNT_LOCALITY value; start at 0.25 and listen for saturation gradient artifacts in
   hard-edged lighting.

All three have zero dependency on each other and none require any new analysis textures.
