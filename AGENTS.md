# Shader Pipeline

vkBasalt HLSL post-process chain for SDR game output. BackBuffer uses UNORM
views; shaders explicitly decode/encode sRGB at processing boundaries. Internal
work is linear-light. HDR must be off in-game.

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
- `FRAME_TIMER` is retained only for compatibility; active output uses spatial dither and no temporal grain.

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
- Retinex reconstructs against pre-Retinex luma; chroma reconstructs against input C.
- Local max-channel protection supplements the global near-clip history.
- Film, shadow, print, and gamut hysteresis uses elapsed time, with no forced
  maximum-strength target on scene cuts; other analysis Kalman filters remain separate.
- Dither uses the sRGB code domain and preserves exact black/white endpoints.
- Local Retinex and zone contrast use a confidence-weighted blend toward the global path.
- Diffusion and grain are removed; the 2x2 activity marker remains in `ColorTransformPS`.
- Golden-image regression testing has been removed; use matched captures and effect attribution instead.
- The configured four-effect chain leaves grade's cross-effect highway and zone
  reads at zero in vkBasalt. `gzw_stronger_trial.conf` tests a combined technique;
  the active GZW config has not been switched.

## Validation

```text
python3 -B -m unittest discover -s tests -p 'test_diagnostics.py'
python3 -B tools/compare_frame.py gamespecific/gzw/analysis/reference/autof_20260515_133058.png --all-effects --game gzw --only FILM_CURVE RETINEX BLACKS_WHITES --delay 5 --settle 5
```

Capture runs print a unique `/tmp/shader-runtime-*/` directory containing mpv
and vkBasalt logs. All-effects uses a fresh process per image. Five seconds of
warmup is a reproducible protocol, not proof of full temporal convergence.
Screenshot captures contain no highway telemetry; `capture --dump` is unsupported.
