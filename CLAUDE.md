# Shader Pipeline

vkBasalt HLSL post-process chain, game-agnostic. Arc Raiders used as test platform
(exceptional lighting/contrast/color). SDR. Linear light throughout —
vkBasalt auto-linearizes the sRGB swapchain. HDR must be OFF in-game.

## Active chain (`arc_raiders.conf`)
```
analysis_frame : inverse_grade : inverse_grade_debug : analysis_scope_pre : corrective : grade : pro_mist : analysis_scope
```

## Silent-failure gotchas — verify before every shader edit

**SPIR-V:**
- No `static const float[]` or `static const float3` — compiles silently, wrong output
- No `out` as a variable name — reserved keyword in HLSL/SPIR-V

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
| `gamespecific/arc_raiders/shaders/debug_text.fxh` | 3×5 debug font, included by all effects |
| `gamespecific/arc_raiders/arc_raiders.conf` | Chain config — never touch without ask |

## `ColorTransformPS` stage order (`grade.fx`)

Reads from BackBuffer (post-inverse_grade, post-corrective). Analysis textures
(ZoneHistoryTex, ChromaHistoryTex, PercTex, CreativeLowFreqTex) written by corrective.fx.
inverse_grade.fx runs before corrective — R90 chroma expansion on pre-corrective signal.

**Pre-grade:** inverse_grade.fx — Oklab chroma expansion (slope from highway x=197, INVERSE_STRENGTH)

1. **CORRECTIVE** — CAT16 chromatic adaptation + `pow(rgb, EXPOSURE)` + FilmCurve (p25/p50/p75) + R83 chromatic floor + R84 log-density offsets + R85 dye masking + R19 3-way CC
2. **TONAL** — Zone S-curve + Spatial norm (auto from zone_std) + R29 Retinex + Shadow lift + R62 Oklab-stable tonal (L-substitution, chroma preserved) + R65 Hunt coupling + R66 ambient shadow tint
3. **CHROMA** — HELMLAB Fourier hue correction + R52 Purkinje + R22 sat-by-luma + R21 hue rotation + R75 hue-by-luminance + chroma lift (CHROMA_STR × 0.04 raw, R68A spatial mod) + R15 HK + R69/R12 Abney + density + R71 vibrance self-mask + R73 memory color ceilings + gamut pre-knee + gclip

**Data highway (BackBuffer y=0):** x=0–128 luma hist · x=130–193 hue hist · x=194–196 p25/p50/p75 · x=197 R90 slope · x=198 mean Oklab C · x=199 scene cut · x=200 p90 · x=201 chroma angle (atan2 encoded) · x=202 achromatic fraction · x=210 warm bias · x=211 zone key · x=212 zone std

## Debug

Log: `/tmp/vkbasalt.log` — read this before diagnosing any shader or launch issue.
