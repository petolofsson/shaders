# Shader Pipeline

vkBasalt HLSL post-process chain, game-agnostic. Active testbed configured in
`gamespecific/`. SDR. Linear light throughout —
vkBasalt auto-linearizes the sRGB swapchain. HDR must be OFF in-game.

## Active chain (`arc_raiders.conf`)
```
analysis_frame : inverse_grade : analysis_scope_pre : corrective : grade : analysis_scope
```
`grade` is an 8-pass technique (LFDownscale1 → LFDownscale2 → NeutralIllum → ColorTransform → DiffusionDownsample → DiffusionBlurH → DiffusionBlurV → Diffusion).
Diffusion is merged inside grade.fx — it is NOT a separate effect in the chain.

## Silent-failure gotchas — verify before every shader edit

**SPIR-V:**
- No `static const float[]` or `static const float3` — compiles silently, wrong output
- No `out` as a variable name — reserved keyword in HLSL/SPIR-V

**vkBasalt mip generation (R113):**
- `tex2Dlod(BackBuffer, ...)` always returns zero — use `tex2D(BackBuffer, uv)` only
- Cross-technique render targets: only mip0 is populated. `MipLevels > 1` on a texture
  written by one technique and read by another silently zeroes mip1+. Use explicit
  downscale passes within the reading technique instead (see LFDownscale1/2 in grade.fx).
- Within-technique render targets: vkBasalt auto-generates mips correctly (confirmed on DiffusionTex).

**BackBuffer chain rule:**
- Inter-effect BackBuffer is 8-bit UNORM. Values >1.0 clip silently between effects.
- Row y=0 is the data highway: `analysis_scope_pre` writes histogram there; every
  BackBuffer-writing pass must guard `if (pos.y < 1.0) return col;`
- Any effect where all passes use explicit RenderTargets must add a Passthrough pass
  that writes BackBuffer, or vkBasalt clears it for the next effect.
- `corrective.fx` is one effect with 7 passes — the final Passthrough keeps BB alive
  for `grade.fx`. No inter-effect clears between corrective passes.

## How I work

- **90% clarity required before starting.** If the request is less than 90% clear, ask —
  don't guess and implement the wrong thing.
- **Plan before coding.** For any non-trivial edit: state which lines/approach will change
  and wait for a nod before writing code.
- **Strict scope.** Only change what was asked. No opportunistic cleanup of surrounding code.
- **Research naming:** `R{next}_{YYYY-MM-DD}_title.md` (+ `_findings.md`). No N suffix — applies
  to CLI sessions and nightly jobs alike. Next number: `ls research/R*.md | grep -oP 'R\K[0-9]+' | sort -n | tail -1`.

## Non-negotiable rules

- **`creative_values.fx` is the only tuning surface.** All user-facing knobs live there.
  Nothing user-adjustable hardcoded elsewhere.
- **SDR by construction.** All outputs [0,1]. `saturate()` is the intentional SDR ceiling —
  not a soft clamp. No gates or asymptotic fallbacks as workarounds.
- **No gates.** Hard conditionals and smoothstep thresholds on pixel properties cause visible
  seams. Effects must be self-limiting by construction.
- **No auto-exposure.** `EXPOSURE` is a deliberate knob set by the user.
- **Never modify shader header comments** without explicit approval.
- **Never touch `gzw.conf`** without explicit request.

## Key paths

| Path | Role |
|------|------|
| `gamespecific/arc_raiders/shaders/creative_values.fx` | Only tuning surface |
| `general/corrective/corrective.fx` | Analysis passes — zone hist, chroma stats, Passthrough |
| `general/grade/grade.fx` | All color work — `ColorTransformPS` (MegaPass) |
| `general/inverse-grade/inverse_grade.fx` | R90 adaptive inverse tone mapping (pre-corrective) |
| `general/analysis-frame/analysis_frame.fx` | Histogram, PercTex, data highway encoding |
| `general/highway.fxh` | Data highway slot constants + `ReadHWY()` macro |
| `general/hue_bands.fxh` | 12-hue band centers, `HueBandWeight()`, `HueCeil()` — natural chroma ceilings shared by inverse_grade.fx and grade.fx |
| `gamespecific/arc_raiders/shaders/debug_text.fxh` | 3×5 debug font, included by all effects |
| `gamespecific/arc_raiders/arc_raiders.conf` | Chain config — never touch without ask |

**grade.fx internal textures (within-technique, always populated):**
| Texture | Size | Role |
|---------|------|------|
| `LowFreqMip1Tex` / `LowFreqMip1Samp` | 1/16-res | Retinex illum_s0, shadow lift denominator |
| `LowFreqMip2Tex` / `LowFreqMip2Samp` | 1/32-res | Retinex illum_s2, R66 ambient tint, halation outer ring |
| `NeutralIllumTex` / `NeutralIllumSamp` | 1×1 | Neutral-pixel-weighted illuminant estimate for R83 + R66 |
| `DiffusionTex` / `DiffusionSamp` | 1/4-res, 1 mip | Diffusion Gaussian-blurred source (written by BlurV, read by DiffusionPS) |
| `DiffusionHorizTex` / `DiffusionHorizSamp` | 1/4-res, 1 mip | Diffusion H-blur intermediate (written by BlurH, read by BlurV) |

## `ColorTransformPS` stage order (`grade.fx`)

Reads from BackBuffer (post-inverse_grade, post-corrective). Analysis textures
(ZoneHistoryTex, ChromaHistoryTex, PercTex, CreativeLowFreqTex) written by corrective.fx.
inverse_grade.fx runs before corrective — R90 chroma expansion on pre-corrective signal.

**Pre-grade:** inverse_grade.fx — Oklab chroma expansion (slope from highway x=197, INVERSE_STRENGTH) + per-hue chroma ceiling (`HueCeil()` from hue_bands.fxh — blocks expansion overshoot past natural gamut)

**LFDownscale1 + LFDownscale2 passes (pre-ColorTransform):** Build `LowFreqMip1Tex` (1/16-res)
and `LowFreqMip2Tex` (1/32-res) from `CreativeLowFreqTex` mip0 via 4-tap box filter. Must run
before ColorTransform. Cross-technique mips are zero — these passes are the fix (R113).

**NeutralIllum pass (pre-ColorTransform):** 144-sample (16×9) grid over `CreativeLowFreqSamp` mip0, neutral-pixel-weighted (weight = `1−smoothstep(0.04,0.10,C)`). Outputs scene illuminant estimate to 1×1 `NeutralIllumTex`. Used by R83 (chromatic floor) and R66 (ambient shadow tint). CAT16 pixel correction removed R127 — game content is display-referred (sRGB→D65); warm lighting is art direction, not a calibration error.

1. **CORRECTIVE** — `pow(rgb, EXPOSURE)` + R104 DIR couplers (log2-space cross-channel inhibition, default off) + FilmCurve (pure global p25/p75, fc_stevens from highway x=213; upper-mid one-sided body lift `max(0,(x(1-x))²(2x-1))*0.65`) + R83 chromatic floor (lms_illum_norm from NeutralIllumTex) + R84 log-density offsets + R85 dye masking + R19 3-way CC
2. **TONAL** — Zone S-curve + Spatial norm (auto from zone_std) + R29 Retinex (illum_s0 from LowFreqMip1, illum_s2 from LowFreqMip2) + Shadow lift + R62 Oklab-stable tonal (L-substitution, chroma preserved) + R65 Hunt coupling + R66 ambient shadow tint (illum from LowFreqMip2)
3. **CHROMA** — HELMLAB Fourier hue correction + R52 Purkinje + R22 sat-by-luma (shadow arm only — highlight arm removed) + R133 Munsell per-hue highlight rolloff (`HueBandRollN()`, `MUNSELL_HIGHLIGHT_ROLLOFF`) + R21 hue rotation + R75 hue-by-luminance + chroma lift (CHROMA_STR × 0.04 raw, R68A spatial mod) + R15 HK + R69/R12 Abney + density + R71 vibrance self-mask + R73 memory color ceilings (`HueCeil()` from hue_bands.fxh, full 12-hue wheel) + gamut pre-knee + gclip + R105 halation DoG PSF (LowFreqMip1 inner / LowFreqMip2 outer ring) + R106 Lorentzian tail

**DiffusionDownsample + DiffusionBlurH + DiffusionBlurV + DiffusionPS passes (same technique):** Diffusion merged into grade.fx. DiffusionDownsamplePS: 4-tap box → DiffusionTex (1/4-res). DiffusionBlurHPS: 9-tap horizontal Gaussian (σ=2 output texels) → DiffusionHorizTex. DiffusionBlurVPS: 9-tap vertical Gaussian → DiffusionTex (final blurred source). DiffusionPS composites via HBM dual-component model: A) additive shimmer `max(0, diff_blur − base) * src_gate * adapt_str` — highlight scatter only; B) soft midtone overlay `lerp(result, diff_blur, eff_diff * 0.06 * mid_gate)` — bell-gated, zero at blacks/whites. Radial vertical oval (xs=1.6, ys=0.08): full clarity top-to-bottom, diffusion increases left/right.

**Data highway (BackBuffer y=0):** x=0–128 luma hist · x=130–193 hue hist · x=194–196 p25/p50/p75 · x=197 R90 slope · x=198 median Oklab C (CDF p50) · x=199 scene cut · x=200 p90 · x=201 chroma angle (atan2 encoded) · x=202 achromatic fraction · x=203 zone_key · x=204 zone_std · x=205 slow_key · x=210 warm bias · x=213 fc_stevens (encode ÷1.3) · x=214 fc_knee · x=215 zone_str (encode ÷0.30) · x=217 shadow_lift_str (encode ÷1.5) · x=218 chroma_str base (encode ÷0.10) · x=219 mist adapt_str (encode ÷0.10)

**Highway encoding rule:** 8-bit UNORM highway clips at 1.0. Values that can exceed 1.0 must be
encoded on write (÷scale) and decoded on read (×scale). Document encode/decode in highway.fxh comment.

## Debug

Log: `/tmp/vkbasalt.log` — read this before diagnosing any shader or launch issue.
