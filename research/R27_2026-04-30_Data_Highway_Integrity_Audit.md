# R27N — Data Highway Integrity Audit
**Date:** 2026-04-30  
**Type:** Static code audit  
**Risk:** High — silent failure, no log output, corrupts every frame

---

## Background

Row y=0 of BackBuffer is the data highway. `analysis_scope_pre` writes pre-correction
histogram data there (luma bins 0–127, mean at pixel 128, hue bins at pixels 130–193).
Every BackBuffer-writing pass between `analysis_scope_pre` and `analysis_scope` must guard
`if (pos.y < 1.0) return col` or it silently overwrites highway data with color-graded
pixels, corrupting the scope's pre-correction panel and the pipeline's analysis textures.

Failure mode is invisible: no log output, no compile error, visual corruption only in the
scope overlay (wrong pre-correction histogram / mean). The color grade itself is unaffected
by scope read corruption, but if highway data fed back into grade logic the blast radius
would expand.

---

## Active chain (arc_raiders.conf)

```
effects = analysis_frame : analysis_scope_pre : corrective : grade : pro_mist : analysis_scope
```

`veil` and `retinal_vignette` are declared in the conf but **not** in the effects line.

---

## Audit scope

### Check 1 — Guard coverage
For every pass that writes BackBuffer (no `RenderTarget` in the pass block), verify:
```hlsl
if (pos.y < 1.0) return col;   // or equivalent early-exit with unmodified highway row
```

### Check 2 — Writer correctness (`analysis_scope_pre`)
- Pixels 0–127: luma histogram (fraction per bin, R channel)
- Pixel 128: scene mean luma
- Pixels 130–193: hue histogram (64 bins, saturation-weighted)
- Pixel 129: should be left untouched or known value (reserved for scope post-mean)

### Check 3 — Reader correctness (`analysis_scope`)
- `data_v` must equal `0.5 / BUFFER_HEIGHT` (row y=0 center)
- pre_mean reads from pixel 128 at data_v
- post_mean reads from pixel 129 at data_v
- Hue bars read from pixels 130+ at data_v

### Check 4 — RenderTarget passes (should NOT touch BackBuffer)
All explicit-RenderTarget passes in `corrective.fx` (passes 1–5) must have a
`RenderTarget =` binding in the technique block.

### Check 5 — Inactive effects
`veil` and `retinal_vignette` are not in the effects line — verify their guards exist
anyway (defence-in-depth if chain order changes).

---

## Files under audit

| File | BB-writing passes |
|------|------------------|
| `general/analysis-frame/analysis_frame.fx` | `DebugOverlay` |
| `general/analysis-scope/analysis_scope_pre.fx` | `ScopeCapture` (writer) |
| `general/corrective/corrective.fx` | `Passthrough` only |
| `general/grade/grade.fx` | `ColorTransform` |
| `general/pro-mist/pro_mist.fx` | `ProMist` |
| `general/analysis-scope/analysis_scope.fx` | `Scope` (reader/restorer) |
| `general/veil/veil.fx` | `Apply` (inactive) |
| `general/retinal-vignette/retinal_vignette.fx` | `Apply` (inactive) |

---

## Research questions for web search

1. Does vkBasalt clear BackBuffer between effects in the chain, or does each effect
   receive the previous effect's output? (Affects whether inter-effect highway data
   survives at all.)
2. In HLSL/SPIR-V, what is the `SV_Position.y` value for the topmost pixel row —
   is it 0.5 (pixel center) or 0.0? Does `pos.y < 1.0` reliably catch only row y=0?
3. Does vkBasalt preserve BackBuffer contents across frames (relevant to scope
   temporal smoothing of post-mean at pixel 129)?
