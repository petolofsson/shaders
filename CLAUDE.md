# Shader Pipeline

vkBasalt HLSL post-process chain, game-agnostic. Arc Raiders used as test platform
(exceptional lighting/contrast/color). SDR. Linear light throughout —
vkBasalt auto-linearizes the sRGB swapchain. HDR must be OFF in-game.

## Active chain (`arc_raiders.conf`)
```
analysis_frame : analysis_scope_pre : corrective : grade : pro_mist : analysis_scope
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
- `corrective.fx` is one effect with 6 passes — the final Passthrough keeps BB alive
  for `grade.fx`. No inter-effect clears between corrective passes.

## How I work

- **90% clarity required before starting.** If the request is less than 90% clear, ask —
  don't guess and implement the wrong thing.
- **Plan before coding.** For any non-trivial edit: state which lines/approach will change
  and wait for a nod before writing code.
- **Strict scope.** Only change what was asked. No opportunistic cleanup of surrounding code.
- **Research naming:** `RXX_YYYY-MM-DD_title.md` (+ `_findings.md`). No N suffix — applies
  to CLI sessions and nightly jobs alike. Next number: `ls research/R*.md | tail -1`.

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
| `gamespecific/arc_raiders/shaders/debug_text.fxh` | 3×5 debug font, included by all effects |
| `gamespecific/arc_raiders/arc_raiders.conf` | Chain config — never touch without ask |

## `ColorTransformPS` stage order (`grade.fx`)

Reads from BackBuffer (post-corrective). Analysis textures (ZoneHistoryTex,
ChromaHistoryTex, PercTex, CreativeLowFreqTex) written by earlier passes in corrective.fx.

1. **CORRECTIVE** — `pow(rgb, EXPOSURE)` + FilmCurve (PercTex p25/p50/p75)
2. **TONAL** — Zone S-curve + Spatial norm (both auto from zone_std) + Clarity + Shadow lift
3. **CHROMA** — Oklab chroma lift + HK + Abney + density (gate-free, no outer C gate)

## Debug

Log: `/tmp/vkbasalt.log` — read this before diagnosing any shader or launch issue.
