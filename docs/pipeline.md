# Pipeline reference

Current architecture and contracts. Read [CODE_RULES](../CODE_RULES.md) before
edits and [TOOLS](../TOOLS.md) for validation. Profiles/identities belong in
[HANDOFF](../HANDOFF.md); dated evidence belongs in `research/`.

## Active chain

Configured in `gamespecific/arc_raiders/arc_raiders.conf` and
`gamespecific/gzw/gzw.conf`:

```text
pipeline (one ShaderPipeline effect containing analysis_frame -> inverse_grade -> corrective -> grade)
```

`grade.fx` is a 13-pass technique:

```text
LFDownscale1 -> LFDownscale2 -> NeutralIllum -> GuidedCoeff -> GuidedBase
-> TintGatherA -> TintGatherB -> TintEnvA -> TintEnvB -> TintRegion
-> ColorTransform -> AdaptiveHistory -> TexHwyWrite
```

Diffusion has been removed from `grade.fx`.

## Key files

| Path | Role |
|------|------|
| `gamespecific/*/shaders/creative_values.fx` | Tuning profile |
| `general/analysis-frame/analysis_frame.fx` | Histogram, percentiles, scene cut, highway write |
| `general/inverse-grade/inverse_grade.fx` | Pre-corrective inverse tone/chroma reconstruction |
| `general/corrective/corrective.fx` | Zone/chroma history, slow key, passthrough |
| `general/grade/grade.fx` | Corrective, tonal, chroma, look, adaptive automation |
| `general/highway.fxh` | Scalar highway slots and `ReadHWY()` |
| `general/hue_bands.fxh` | Hue weights, rolloff, chroma ceilings |
| `tools/compare_frame.py` | Runtime before/after and effect attribution |
| `tools/noise_floor.py` | EXR high-frequency noise measurement |

## Stage Order

1. `inverse_grade`: source reconstruction plus Oklab chroma expansion, bounded
   by `HueCeil()`; FilmCurve is not inverted here.
2. `corrective`: zone/chroma/slow-key analysis; preserves BackBuffer.
3. `grade` shadow surround tint on BLACKS/WHITES-mapped input, then corrective:
   `INVERSE_LUMA` on source signal, then `EXPOSURE`, DIR couplers, and 3-way CC.
4. `grade` tonal: guided-filter detail, Retinex/zone shaping, signed adaptive
   contrast, shadow lift, Hunt coupling, ambient tint, highlights, then the
   luminance-preserving FilmCurve shoulder.
5. `grade` chroma: sat-by-luma, Munsell rolloff, hue rotation, vibrance,
   saturation, compression, and gamut projection.
6. `grade` look: Kodak 2383 print stock, masking/dye couplers, printer lights;
   gated by `LOOK_STRENGTH`.
7. Output: dither and 2x2 red activity marker.

## Highway Slots

`HighwayTex` is `256x1 R16F`; values are normalized to `[0,1]` by convention.
Encode/decode out-of-range quantities at the slot boundary.

```text
194 p25, 195 p50, 196 p75, 197 chroma slope, 198 median C, 199 scene cut
200 p90, 201 mean chroma angle, 202 achromatic fraction
203 zone key, 204 zone std, 205 slow key
206 luma mode, 207 entropy, 208 IQR, 209 p10, 210 near-clip fraction
212 current lift p25, 213 p50, 214 p90, 215 mode, 216 p10, 217 source-valid flag
218 current source p75 for inverse-luma restraint (also uses slots 212/217)
```

## Analysis and histories

- Global/zone raw histograms recover exact 576/100 counts before statistics.
  Smoothed global fractions remain continuous and normalized for percentile/
  entropy reads, including startup mass below one. Exact white lands in the last bin.
- Zone statistics use 64 squared-edge bins decoded to linear light, integer-count
  CDF walks and weighted Welford population variance. Scene cuts use p50 delta
  plus raw-histogram entropy delta.
- Median chroma includes all 576 samples; hue-centroid filtering uses colored
  samples. Percentile covariance initializes only from nonpositive state.
- Authoritative histogram, percentile, near-clip, high-percentile, mode, entropy,
  zone, adaptive, `ChromaHistoryTex` and `MeanChromaTex` accumulators use 32-bit
  storage. Publications/raw observations remain half-float; bounded one-frame
  scene-cut storage remains RGBA16F. Preserve formulas, rates and initialization.
- Slow key reads authoritative chroma history directly; its 20-second/67-ms
  half-lives remain. Mean chroma uses direct feedback. ChromaHistory columns 0–5
  (former per-hue Kalman) stay allocated and are written as zero; zone/slow-key
  records remain live. Spatial-lane reads use `ReadSpatialLane`/`SpatialLaneUV`
  (common.fxh), which clamp to lane texel centers.
- `PercHighTex` has three RGBA32F records: p90/p10 history at 0.5/3;
  current p25/p50/p90/mode at 1.5/3; p10/mass/p75/validity at 2.5/3.
  Highways 212–218 publish current observations; original recurrence remains.

## Tonal model

- A guarded native-source base is shared by Retinex, zone and lift. Carry original
  corrected-pixel detail through their combined gain. Source-range rejection
  protects narrow bright features; continuous overlapping windows estimate the base.
- Downscale/guided taps use allocated integer dimensions, including non-divisible
  sizes. Guided epsilon adapts to local variance. Native guide is R32F and observed
  before inverse corrections; required observations stay inside the combined effect.
- Inverse luma applies its weighted linear gain in RGB. Its guarded shadow
  reference is in the affine input domain, clamped to .06–.12 linear Y;
  .001–.005 near-black/.08–.20 upper fades and `min(original, reference)` retain
  the outer ranges and prevent gain relaxation. Current p25/p75 spans of two to
  four stops restrain strength to half its manual ceiling.
- Retinex evaluates averaged `BilateralLogTex` coefficients in the original-source
  domain using `NativeGuideLogTex`. Condition unresolved residual by `(1-a)`;
  combine bounded .35 log-slope native response with the original guided/native
  `2*key/(key+illuminant)` gain ratio, retaining ±.35 stops. Reconstruct against
  pre-Retinex luma. Coarse-edge strength fading produced halos and remains rejected.
- Zone contrast uses the scene-wide mean zone median/global percentile span,
  shadow debt divided by luma plus pivot, a finite-gain linear black tail and a
  uniform .65 confidence floor. Its coarse-edge fade also produced false rims.
- Local contrast's negative arm is bounded relative to luma. Shadow lift uses
  p10 for its black-level guard. RETINEX/ZONE_CONTRAST/SHADOW_LIFT strength zero
  values are independent visual bypasses.
- The current-source complete lift product uses existing adaptive rates. In adaptive
  record two, RG are gate recovery, B=1 validates gates, B=2 also validates the
  source product, and A stores that product. Zero products remain initialized;
  explicit flags handle source loss/recovery. The R60 context factor bounds
  log2(slow key/zone key) to ±log2 3 (×0.64–1.55 at weight .4). Without a valid
  source observation lift is zero; the original fallback lift was removed and
  adaptive record one's G channel is written as zero.
- FilmCurve adapts to tail separation, highlight presence and entropy; the manual
  value remains its ceiling. Local max-channel protection supplements near-clip
  history. Film/shadow/print/gamut hysteresis uses elapsed time and does not force
  maximum strength at cuts; analysis Kalman filters remain separate.

## Shadow surround tint

- **Fields.** All fields come from the 1/8 spatial lane (linear source).
  - Surface weight: Oklab L .02–.10 in, .80–.95 out.
  - 1/16 gather: 2×2 lane texels, (a·ws, b·ws, L·ws, ws) and (luma·ws, luma·emitter).
  - Normalized Gaussian blur: σ 3.46 texels; the emitter field uses σ 4.90.
  - 1/8 region: lane (luma, a, b, L), σ 1. All are bilinear-read per pixel.
- **Shadow weight.** log2(surface-only wide luma ÷ regional luma), mapped over
  0–1.5 stops; then not-bright region (.10–.35), not-near-black pixel
  (.0003–.002), and a lit-spot fade 1–2 stops above the region.
- **Step.** One Oklch+ step (L^.73; C^.87/(C^.87+.34^.87); arXiv 2606.05255) of
  `SHADOW_SURROUND_TINT`·.0442·weight·hue confidence, toward the surroundings'
  hue. It is evaluated on the regional colour and added per pixel as an Oklab a,b
  offset; saturation is capped at max(original, .45·L).
- **Darkening.** A Fairchild–Pirrotta lightness-preserving RGB gain from the
  regional colour (clamped .5–1), faded out where nearby emitter light dominates.
  Evaluating on the regional colour keeps pixel chroma noise at production level.
- **Known limit.** Dark background behind bright foreground objects can be tinted
  (halo); no depth is used.

## Color, print and output

- Shared-component CC scales three-way a/b offsets by `min(RGB)/Y`, retaining
  gray-axis correction while reducing steering of colored materials.
- Inverse chroma uses `max(.85*HueCeil(hue), C)` and a 14-step fixed-lightness SDR
  budget for added chroma. It preserves incoming C and abstains above its budget.
  Reconstruct chroma against input C; FilmCurve is not inverted.
- Print preserves its helper luminance curve and blends toward incoming RGB
  ratios over linear Y=.01–.10. Lower-tone weak-color protection uses input
  C/L=.03–.12 and fades out over Y=.10–.25. FilmCurve loss relieves secondary
  print-shoulder overlap; secondary shoulder is .75 and the original toe remains.
- Print stock, gamut compression and chroma protection adapt to scene statistics;
  cut confidence temporarily damps adaptation.
- Internal Oklab conversions preserve signed/overrange RGB. Final SDR projection
  checks both negative and over-one channels. Initial face tolerance is only 1e-6
  matrix roundoff; search bounds remain strict and final output is saturated.
- Blue-cusp projection preserves lightness with localized hue adjustment outside
  gamut, retaining valid-input identity. Extreme-blue hue/separation and quantized
  gradient costs remain documented in the [decision](../research/2026-10-27_gamut_continuity_repair.md).
- Output uses sRGB-code-domain spatial dither with exact black/white endpoints,
  followed by the intentional 2×2 red activity marker. No diffusion or temporal grain.

## Decision references

[Shared tonal base](../research/2026-11-02_tonal_architecture.md),
[shared-component CC](../research/2026-11-03_neutral_component_cc_adoption.md),
[lift/activation](../research/2026-10-27_lift_transition_repair.md),
[Retinex](../research/2026-10-27_retinex_material_preservation.md),
[inverse restraint](../research/2026-10-27_tonal_selectivity.md) and
[precision/statistics](../research/2026-10-25_signal_contracts.md) explain the
contracts and retained costs. The [historical root ledger](../research/2026-11-06_root_document_history.md)
preserves the former full evidence table and detailed chronology.
