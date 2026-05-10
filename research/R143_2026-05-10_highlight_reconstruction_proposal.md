# R143 — Highlight Reconstruction: Proposal

**Date:** 2026-05-10
**Status:** Plan only — not implemented
**Scope:** `general/inverse-grade/inverse_grade.fx` — `InverseGradePS` only
**Findings:** `R143_2026-05-10_highlight_reconstruction_findings.md`

---

## Problem

SDR games clip channels at 1.0. When 1–2 channels clip while at least one survives below 1.0,
the surviving channels encode the correct hue direction but the clipped channel creates a
false color cast (e.g., R clips first on a warm specular → orange tint where the surface
should be near-white). Our grading stages see and amplify this artifact.

Reconstruction must run in `inverse_grade.fx` — before R90 chroma expansion — so we
correct the signal before the rest of the pipeline acts on it.

---

## What the research says

- **Per-pixel reconstruction is feasible** only for the 1–2 channel clipped case.
  Fully blown (all channels = 1.0) is unrecoverable without spatial neighborhood data.
- **Correct operation:** reduce Oklab chroma toward 0 as max_ch approaches 1.0.
  Hue direction (ab angle) is preserved; only magnitude rolls off. Never introduces color.
- **C gate is mandatory:** suppress reconstruction for Oklab C > 0.18 — protects
  intentionally saturated colored lights that happen to be bright.
- **Near-clip zone must be wide:** 8-bit sRGB quantization near clip means only 3–4
  discrete linear levels between 0.95 and 1.0. Smoothstep from 0.88→0.995 covers
  ~10 levels and prevents the aliased ring artifact.
- **Cost:** integrates into the existing Oklab block in `InverseGradePS`. No extra
  texture reads, no extra passes. Marginal cost: 2 smoothsteps + 1 multiply.

---

## Algorithm

```hlsl
// Before R90 expansion, inside InverseGradePS:
float max_ch  = max(max(col.r, col.g), col.b);
float3 lab    = RGBtoOklab(col.rgb);
float  C      = length(lab.yz);

float recon_w = smoothstep(0.88, 0.995, max_ch)   // near-clip zone (wide for 8-bit)
              * smoothstep(0.18, 0.08, C)           // C gate: skip colored lights
              * HIGHLIGHT_RECONSTRUCT;

lab.yz *= (1.0 - recon_w);
col.rgb = saturate(OklabToRGB(lab));

// ... then continue with existing R90 expansion
```

Properties:
- Desaturates only — never introduces or shifts hue, never adds energy
- Self-limiting on both axes (max_ch and C)
- No hard gates — both smoothsteps are continuous
- Output always [0,1]
- Non-overlapping with R90: R90 gates on C > 0.10 and mid-luminance weight;
  reconstruction fires on high-L, low-C pixels — opposite population

---

## Knob

One new knob in `creative_values.fx` under the INVERSE section:

```hlsl
uniform float HIGHLIGHT_RECONSTRUCT <
    ui_label   = "Highlight Reconstruction";
    ui_tooltip = "Desaturates near-clipped highlights to recover plausible hue. 0=off.";
    ui_type    = "slider"; ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.0;
```

Default 0.0 (off, awaiting calibration).

---

## What does NOT change

- R90 chroma expansion logic — untouched
- `HueCeil()` ceilings — untouched
- No new passes, no new textures

---

## Open question before implementing

The known yellow/orange over-saturation issue (documented in memory) may be caused by
channel clipping OR by R90 overexpansion. This implementation will help if it's a
clipping artifact. If it's an expansion artifact, the fix belongs in R90/HueCeil tuning.

Empirical test: set INVERSE_STRENGTH 0.0, check if orange cast disappears. If yes →
expansion artifact. If no → clipping artifact → this is the right fix.

---

## Estimated size

`HighlightReconstruct` inline block: ~6 lines added to `InverseGradePS`.
`InverseGradePS` currently short — well within Rule 4.
