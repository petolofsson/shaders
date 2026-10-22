# Shader Pipeline

vkBasalt HLSL post-process chain for SDR game output. Work is linear-light after
vkBasalt's sRGB swapchain read. HDR must be off in-game.

## Active Chain

Configured in `gamespecific/arc_raiders/arc_raiders.conf` and
`gamespecific/gzw/gzw.conf`:

```text
analysis_frame : inverse_grade : corrective : grade
```

`grade.fx` is a 7-pass technique:

```text
LFDownscale1 -> LFDownscale2 -> NeutralIllum -> GuidedCoeff -> GuidedBase
-> ColorTransform -> TexHwyWrite
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
- Cross-technique RT mips are not populated beyond mip0. Build required lower-res
  surfaces inside the reading technique.
- Inter-effect BackBuffer is 8-bit UNORM; overrange values clip between effects.
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
206 luma mode, 207 entropy, 208 IQR, 209 p10
```

## Current State

- Diffusion is removed from the active grade; no diffusion setting is exposed.
- The 2x2 red activity marker is intentional; mask it in strict image tests.
- Exact-white histogram samples are clamped into the final bin before counting.
- Scene cuts use p50 delta plus raw histogram entropy delta.
- Guided-filter epsilon is local-variance adaptive.
- Arc Raiders and GZW share the new stable profile baseline; creative hue-band
  controls remain omitted from both game profiles.
- `RETINEX_STRENGTH`, `ZONE_CONTRAST_STRENGTH`, and `SHADOW_LIFT_STRENGTH` are
  independent diagnostic gates; each zero value is a visual bypass.
- Shadow lift uses the histogram p10 shadow floor as an adaptive black-level guard.
- Film-curve strength adapts to highlight-tail separation, highlight presence, and entropy;
  `FILM_CURVE` remains the manual ceiling.
- Print stock, soft gamut compression, and chroma protection adapt to scene statistics;
  scene-cut confidence temporarily damps those adaptations.
- Diffusion and grain are removed; the 2x2 activity marker remains in `ColorTransformPS`.
- Old `dcc712f` goldens fail against current Arc Raiders output; review before reblessing.

## Validation

```text
python3 -m py_compile tools/*.py
python3 tools/compare_frame.py --all-effects --game arc_raiders --max-frames 1 --only FILM_CURVE --delay 5
python3 tools/bless_all.py --check --game arc_raiders --delay 5
```

If logging is configured, inspect `/tmp/vkbasalt.log`; recent successful runtime
passes did not create that file.
