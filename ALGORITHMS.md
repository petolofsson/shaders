# Pipeline Algorithms

All algorithms currently active in the shader chain, in firing order.
Last updated: 2026-05-14

---

## Chain order

```
analysis_frame → inverse_grade → corrective → grade
                                               ├── ApplyCorrective
                                               ├── ApplyTonal
                                               ├── ApplyChroma
                                               ├── ApplyLook
                                               └── DiffusionPS (output)
```

---

## analysis_frame.fx

Per-frame scene statistics. Runs before everything else. All outputs written
to HighwayTex (256×1 R16F) for downstream consumption via `ReadHWY(slot)`.

| Algorithm | Slot | Purpose |
|-----------|------|---------|
| 32×18 downsample | — | Cheap scene sample source for all stat passes |
| 64-bin luma histogram | — | Per-frame luminance distribution |
| EMA histogram smoothing | — | Temporal stability (~4 frame time constant) |
| VFF Kalman on p25/p50/p75 | 194–196 | Stable percentile estimates, scene-cut aware |
| R53 scene-cut detection | 199 | p50 delta spike → hard Kalman reset |
| p90 luma tracker | 200 | Specular floor — isolated bright source measure |
| Chroma slope (median_C → slope) | 197 | Drives inverse_grade expansion magnitude |
| Oklab median chroma (median_C) | 198 | Scene chroma character; drives R176 vibrance adapt |
| Oklab ab centroid (mean hue angle) | 201 | Scene dominant hue direction |
| Achromatic fraction | 202 | Fraction of pixels with Oklab C < 0.05 |
| R147 histogram mode | 206 | Dominant luminance level (argmax bin), EMA-smoothed |
| R195 H_norm entropy | 207 | Global tonal spread — 0=all mass one bin, 1=uniform |
| R195 IQR | 208 | p75 − p25 scene contrast width |

---

## corrective.fx

Per-zone histogram analysis. Outputs zone statistics to HighwayTex and
ChromaHistoryTex for grade.fx consumption.

| Algorithm | Slot/Tex | Purpose |
|-----------|----------|---------|
| 1/8-res downsample | CreativeLowFreqTex | Source for all zone analysis |
| 8-zone 32-bin luma histograms | ZoneHistoryTex | Per-region luminance distribution |
| CDF walk → zone medians | ZoneHistoryTex | Per-zone key values |
| R116 histogram moments | ZoneHistoryTex | Per-zone intra_std (local variance) |
| R39 VFF Kalman — zone stats | 203–204 | zone_key, zone_std; scene-cut aware |
| R39 VFF Kalman — per-hue chroma | ChromaHistoryTex | Per-band chroma means (12 hues) |
| R88 Sage-Husa Q | — | Adaptive Kalman process noise from posterior P |
| R171 observation confidence gate | — | Only updates Kalman when hue band is present |
| R53 scene-cut Kalman override | — | Spikes gain to 1.0 on hard cuts |
| Slow key EMA | 205 | Ambient luma tracker for temporal lift context |

---

## inverse_grade.fx

Adaptive inverse tone mapping. Runs post-analysis, pre-corrective. Expands
Oklab chroma compressed by the game's tonemapper.

| Algorithm | Purpose |
|-----------|---------|
| R90 Oklab chroma expansion | IQR-derived slope drives chroma expansion toward natural gamut |
| R156 per-hue slope bias | Warm hues (ACES compresses more) get stronger expansion |
| R157 achromatic scene gate | Lowers chroma threshold when scene is mostly neutral |
| R163 dominant-hue directional scale | Complementary hues expand more than scene-aligned hues |
| R165 warm-scene bias suppression | Backs off warm-hue expansion in warm-lit illuminant |
| R193 ACES 2.0 toe_inv ceiling | Rational asymptotic ceiling — expansion never clips gamut |
| HueCeil natural gamut ceiling | Per-hue hard ceiling shared with grade.fx |

---

## grade.fx — ApplyCorrective

Runs on post-inverse_grade signal. Builds the film-negative analogue.

| Algorithm | Purpose |
|-----------|---------|
| EXPOSURE | Per-pixel luma-gated gain — rolls off above L=0.55 to protect highlights |
| R104 DIR couplers | Log-space cross-channel developer-inhibitor-release masking |
| R168 halation | Pre-curve DoG PSF — orange/amber fringe around specular sources; two-scale (1/16-res + 1/32-res); AH-layer rem-jet attenuation |
| R194 ACES luma inverse | Undoes ACES midtone boost below fixed point (L≈0.728); darkening only — no highlight expansion |
| FilmCurve | Rational shoulder+toe; p25/p75 adaptive knee; per-channel R/B knee+toe offsets (CURVE_R_KNEE etc.) |
| R83 chromatic floor | LMS-space warm shadow floor from NeutralIllumTex scene illuminant |
| R84 log-density offsets | Per-channel density shifts in log space |
| R85 dye masking | Cross-channel dye layer interactions |
| R19 3-way CC | Shadow/mid/highlight temperature + tint grade (SHADOW_TEMP/TINT etc.) |

---

## grade.fx — ApplyTonal

Spatial and global tonal shaping. Runs after corrective.

| Algorithm | Purpose |
|-----------|---------|
| R190 guided filter | Self-guided log-luma base layer; adaptive ε (Hu 2023); r=3 at 1/8-res → 49 taps; replaces bilateral |
| LOCAL_TONE | Lifts areas darker than scene key; lift-only gate on max(log_base, log_pixel) — never lifts bright pixels in dark areas |
| CLARITY_STRENGTH | Scales guided filter detail layer for micro-contrast punch (Lightroom Clarity equivalent) |
| R29 multi-scale Retinex | Spatial illuminant normalisation using 1/16-res (illum_s0) and 1/32-res (illum_s2) |
| R33 CLAHE clip limit | Bounds zone S-curve slope; tightens when Retinex is engaged |
| Zone S-curve | Adaptive contrast redistribution driven by zone_std and zone_key |
| R195 H_norm attenuation | Reduces zone_str up to 25% when entropy > 0.55 — avoids over-processing naturally rich scenes |
| R119 fine-texture gate | 3×3 neighbourhood average suppresses S-curve in already-textured regions |
| Shadow lift | Auto lift scaled by zone_std, slow_key, and shadow_lift_str |
| R60 temporal context | Slow ambient key EMA boosts lift during dark transitions; suppresses on re-entry |
| R162 specular contrast gate | Suppresses shadow lift when isolated bright sources dominate (p90−p50 gap) |
| R62 Oklab-stable tonal | L-substitution — luma ratio applied in Oklab L to preserve chroma under tonal shifts |
| R65 Hunt coupling | Colorfulness ∝ L^0.25 (CAM16, Hunt 2004, CIECAM02 eq.14-16) |
| R66 ambient shadow tint | Injects scene-ambient hue from LowFreqMip2 into lifted achromatic shadows |

---

## grade.fx — ApplyChroma

All hue and saturation work. Runs after tonal.

| Algorithm | Purpose |
|-----------|---------|
| R183 shadow cast | Warm amber Oklab additive in deep shadows (L < 0.25); Deakins pre-flash model |
| R52 Purkinje shift | Rod-vision blue-green bias + scotopic desaturation in mesopic range (L < 0.30) |
| R150 scotopic gate | Dark-dominant scenes: lower histogram mode → wider Purkinje weight |
| R22 sat-by-luma | Shadow desaturation ~20%; shadow arm only (highlight arm removed) |
| R133 Munsell per-hue highlight rolloff | Per-hue chroma ceiling as highlights approach white |
| R21 per-band hue rotation | 6-hue rotation in Oklab LCh (ROT_RED/YELLOW etc.) |
| R125/R126 Bezold-Brücke | Luminance-driven hue shift; anchored at Oklab invariant hues (yellow h=0.25, blue h=0.75) |
| R176 median_C chroma adapt | Scales vibrance base +25% in low-chroma scenes, −15% in vivid scenes |
| R68A spatial chroma attenuation | Backs off chroma lift in textured regions (local_var gate) |
| R179 per-band chroma lift (12-hue) | Lift-only vibrance per hue band; zero effect on already-saturated pixels |
| R117D memory color attraction | Gentle chroma boost in each hue band's canonical luminance range |
| R73 memory color ceilings | Per-band hard chroma ceiling — sky, foliage, skin; full 12-hue wheel |
| R71 vibrance self-mask | Attenuates lift delta on already-saturated pixels |
| R117C chromatic induction | Broad surround hue nudges near-achromatic pixels toward complement |
| R15 Helmholtz-Kohlrausch | Perceived brightness contribution from chroma (HK effect) |
| R69/R12 Abney correction | Hue shift compensation for desaturation (Abney effect) |
| Density | Log-space per-band chroma density from chroma history |
| R68B gamut pre-knee | Reinhard soft chroma rolloff in last 12% before gamut boundary |
| R78 gclip | Constant-hue gamut projection in Oklab ab space |
| R105 halation DoG PSF | Chromatic scatter from specular; 1/16-res inner ring + 1/32-res outer ring |
| R106 Lorentzian tail | Long-range Lorentzian scatter tail on halation |

---

## grade.fx — ApplyLook

Post-grade print emulation. ACES LMT position — fires after all tonal and
chroma work, before optical output.

| Algorithm | Purpose |
|-----------|---------|
| R51 print stock (2383) | Two-piece S-curve: power toe 1.15 compresses shadows (dye-layer density); Reinhard K=1.5 shoulder rolls off highlights |
| R110 masking coupler | Cross-channel density inhibition (film masking layer model) |
| R130 dye matrix | Film dye layer cross-talk (colour channel crosstalk) |
| Bleach bypass | Retains silver alongside dye — shadow desat + midtone contrast steepening |
| R192 printer lights | Per-channel RGB exposure post-emulsion; printer points (25=neutral, 1pt=1/12 stop) |

---

## grade.fx — DiffusionPS (output)

Optical finishing. Runs last before final output.

| Algorithm | Purpose |
|-----------|---------|
| R131 HBM additive shimmer | Highlight bloom into dark areas only; micro-lenslet scatter model |
| R132 polydisperse scatter | Per-channel diffusion width — red ×1.15, green ×1.00, blue ×0.85 |
| HBM midtone overlay | Soft bell-gated smoothing; zero at blacks and whites |
| Radial oval shape | Full clarity centre, diffusion increases toward left/right edges |
| R136 film grain | Selwyn 2383 granularity; 3 decorrelated dye layers (R:G:B = 1.00:0.80:1.50); Selwyn envelope sqrt(1−L_gamma); framerate-independent 24fps slot snap |
| R167/R174 pcg3d noise | RGB-decorrelated hash for grain; no static arrays (SPIR-V safe) |
| R89 IGN dither | Blue-noise dither (Jimenez 2016) to break 8-bit BackBuffer quantization |

---

## Supporting infrastructure

| Component | File | Purpose |
|-----------|------|---------|
| HighwayTex (256×1 R16F) | highway.fxh | Shared data bus between effects |
| LowFreqMip1Tex (1/16-res) | grade.fx | Retinex illum_s0, shadow lift denominator |
| LowFreqMip2Tex (1/32-res) | grade.fx | Retinex illum_s2, halation outer ring, ambient tint |
| NeutralIllumTex (1×1) | grade.fx | Neutral-pixel-weighted scene illuminant (CAT16) |
| DiffusionTex / DiffusionHorizTex (1/4-res) | grade.fx | Gaussian-blurred source for HBM diffusion |
| CreativeLowFreqTex (1/8-res) | corrective.fx | Zone histogram source; mip0 only (cross-technique mips zero) |
| hue_bands.fxh | general/ | 12-hue band centers, HueBandWeight(), HueCeil() — shared by inverse_grade and grade |
