# Shader Pipeline

vkBasalt HLSL post-process chain, Arc Raiders on Linux. SDR. Linear light throughout —
vkBasalt auto-linearizes the sRGB swapchain. HDR must be OFF in-game.

## Active chain (`arc_raiders.conf`)
```
analysis_frame_analysis : analysis_scope_pre : corrective_render_chain :
creative_render_chain : olofssonian_chroma_lift : creative_color_grade : analysis_scope
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

## Non-negotiable rules

- **`creative_values.fx` is the only tuning surface.** All user-facing knobs live there.
  Nothing user-adjustable hardcoded elsewhere.
- **SDR by construction.** All outputs [0,1]. `saturate()` is the intentional SDR ceiling —
  not a soft clamp. No gates or asymptotic fallbacks as workarounds.
- **No gates.** Hard conditionals and smoothstep thresholds on pixel properties cause visible
  seams. Effects must be self-limiting by construction.
- **No auto-exposure.** `EXPOSURE` is a deliberate knob set by the user.
- **Propose significant architectural changes** and wait for approval before writing code.
- **Never modify shader header comments** without explicit approval.
- **Never touch `gzw.conf`** without explicit request.

## Key paths

| Path | Role |
|------|------|
| `gamespecific/arc_raiders/shaders/creative_values.fx` | Only tuning surface |
| `general/creative-color-grade/creative_color_grade.fx` | All color work — `MegaPassPS` |
| `gamespecific/arc_raiders/shaders/debug_text.fxh` | 3×5 debug font, included by all effects |
| `gamespecific/arc_raiders/arc_raiders.conf` | Chain config — never touch without ask |
| `research/backbuffer_requantization_fix.md` | Pending: single-file merge analysis |

## `MegaPassPS` stage order (`creative_color_grade.fx`)

1. **CORRECTIVE** — `pow(rgb, EXPOSURE)` + FilmCurve (PercTex p25/p50/p75)
2. **TONAL** — Zone S-curve (ZoneHistoryTex) + Clarity + Shadow lift
3. **CHROMA** — Oklab chroma lift + HK + Abney + density (gate-free, no outer C gate)
4. **FILM GRADE** — log matrix per preset + zone tints + sat rolloff

## Debug

Log: `/tmp/vkbasalt.log` — read this before diagnosing any shader or launch issue.
