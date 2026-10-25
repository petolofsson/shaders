# Shader Pipeline

vkBasalt HLSL post-process chain for SDR game output. BackBuffer uses UNORM
views; shaders explicitly decode/encode sRGB at processing boundaries. Internal
work is linear-light. HDR must be off in-game.

## Product Direction and Startup

Read [GOAL.md](GOAL.md) for the agreed game-agnostic visual direction:
fuller SDR color relationships, deep nuanced shadows and convincing light,
with unobtrusive automatic restraint. Preserve the game's palette and lighting.
Richness is not a saturation, darkness or hue-coverage target. Existing profiles
remain intact during assessment; no auto-exposure or HDR output is introduced.
Use [PLAN.md](PLAN.md) for current priorities, [HANDOFF.md](HANDOFF.md) for state,
and [startup-prompt-latest](startup-prompt-latest) as the sole startup prompt.
All runtime testing must remain private and headless; no desktop fallback.

## Active Chain

Configured in `gamespecific/arc_raiders/arc_raiders.conf` and
`gamespecific/gzw/gzw.conf`:

```text
analysis_frame : inverse_grade : corrective : grade
```

`grade.fx` is an 8-pass technique:

```text
LFDownscale1 -> LFDownscale2 -> NeutralIllum -> GuidedCoeff -> GuidedBase
-> ColorTransform -> AdaptiveHistory -> TexHwyWrite
```

Diffusion has been removed from `grade.fx`.

## Hard Rules

- `creative_values.fx` is the only user-facing tuning surface.
- SDR by construction: output stays in `[0,1]`; `saturate()` is the ceiling.
- No auto-exposure. `EXPOSURE` is deliberate user tuning.
- No dynamic branches on pixel properties; prefer smooth arithmetic.
- Do not modify shader header comments unless explicitly asked.
- Do not edit `gzw.conf` unless explicitly asked.
- Explicit-render-target-only effects must end with BackBuffer passthrough.

## vkBasalt / SPIR-V Gotchas

- No `static const float[]` or `static const float3`: can compile with wrong output.
- No variable named `out`: reserved by HLSL/SPIR-V.
- No `tex2Dlod(BackBuffer, ...)`: it returns zero; use `tex2D(BackBuffer, uv)`.
- Explicit render targets in separate `.fx` effects do not share data, even at
  mip0. Build and read required surfaces inside one effect technique.
- Inter-effect BackBuffer is UNORM; overrange values clip between effects.
- SDR games commonly use 8-bit; mpv validation used a 10-bit UNORM swapchain.
- Keep BackBuffer `SRGBTexture`/`SRGBWriteEnable` false with explicit sRGB math;
  10-bit UNORM has no corresponding sRGB image-view format.
- Active output uses spatial dither and no temporal grain; analysis sampling retains `FRAME_TIMER`.

## Key Files

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
3. `grade` corrective: `INVERSE_LUMA` on source signal, then `EXPOSURE`, DIR
   couplers, and 3-way CC.
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
```

## Current State

- Diffusion is removed from the active grade; no diffusion setting is exposed.
- The 2x2 red activity marker is intentional; mask it in strict image tests.
- Exact-white histogram samples are clamped into the final bin before counting.
- Percentile and entropy reads normalize the temporally smoothed histogram;
  its total mass can be below one during startup.
- Scene cuts use p50 delta plus raw histogram entropy delta.
- Guided-filter epsilon is local-variance adaptive.
- Zone statistics use 64 squared-edge bins decoded to linear light for near-black precision.
- Local contrast's negative arm uses a luminance-relative smooth bound to preserve shadows.
- Arc Raiders and GZW share shader code; current profiles still need visual
  recalibration after the color-space and reconstruction fixes.
- `RETINEX_STRENGTH`, `ZONE_CONTRAST_STRENGTH`, and `SHADOW_LIFT_STRENGTH` are
  independent diagnostic gates; each zero value is a visual bypass.
- Shadow lift uses the histogram p10 shadow floor as an adaptive black-level guard.
- Film-curve strength adapts to highlight-tail separation, highlight presence, and entropy;
  `FILM_CURVE` remains the manual ceiling.
- Print stock, soft gamut compression, and chroma protection adapt to scene statistics;
  scene-cut confidence temporarily damps those adaptations.
- Internal grade Oklab conversions preserve signed RGB and positive overrange;
  final gamut projection checks negative and over-one channels before `saturate()`.
- Inverse-luma reconstruction applies its weighted linear-light gain in RGB;
  scaling Oklab coordinates directly cubed that gain and over-darkened midtones.
- Retinex reconstructs against pre-Retinex luma; chroma reconstructs against input C.
- Local max-channel protection supplements the global near-clip history.
- Film, shadow, print, and gamut hysteresis uses elapsed time, with no forced
  maximum-strength target on scene cuts; other analysis Kalman filters remain separate.
- Dither uses the sRGB code domain and preserves exact black/white endpoints.
- Retinex retains bounded gain and global confidence without coarse-edge strength
  fading, which produced halos. Zone contrast uses its existing conservative
  0.65 confidence floor uniformly; its coarse-edge fade also produced false rims.
- Retinex reconstructs its illuminant guide at native input luma from averaged
  coefficients stored alongside the existing base in `BilateralLogTex` RGBA16F.
  This reduces flat-face rims; smaller coarse-zone interior gradients remain.
- Matched headless Babylon motion is validated with sparse frame identities;
  15 source poses/sec duplicated at 30 fps does not prove dense continuity.
- Explicit diagnostic GPU readback isolates the measured dark-return tail to slow
  key rather than local-zone lag. Its intentional adaptation rate is unchanged.
- Diffusion and grain are removed; the 2x2 activity marker remains in `ColorTransformPS`.
- Golden-image regression testing has been removed; use matched captures and effect attribution instead.
- The configured four-effect chain leaves grade's cross-effect highway and zone
  reads at zero in vkBasalt. `gzw_stronger_trial.conf` tests a combined technique;
  the active GZW config has not been switched.

## Validation

```text
python3 -B -m unittest discover -s tests -p 'test_diagnostics.py'
python3 -B tools/compare_frame.py gamespecific/gzw/analysis/reference/autof_20260515_133058.png --all-effects --game gzw --config gamespecific/gzw/gzw_stronger_trial.conf --only FILM_CURVE RETINEX BLACKS_WHITES --delay 5 --settle 20
```

Capture runs print a unique `/tmp/shader-runtime-*/` directory containing mpv
and vkBasalt logs. All-effects uses a fresh process per image. Use 20 seconds of
settling for small effects and an unchanged repeat; elapsed warmup alone does
not prove full temporal convergence. Private GPU/localhost tests require sandbox
escalation. Diagnostic techniques may explicitly render offscreen history for
readback; ordinary screenshot captures contain no such telemetry.
Screenshot captures contain no highway telemetry; `capture --dump` is unsupported.
