# R196 — Pipeline Audit: AI Analysis Review

**Date:** 2026-05-14
**Source:** realtime_shader_pipeline_research_notes.md (external AI analysis)

---

## Context

External AI analysis of the pipeline identified 10 areas for improvement.
This document records the evaluation of each against the actual pipeline state,
constraints (SDR, vkBasalt HLSL/SPIR-V, game GPU budget), and known issues.

---

## Actionable — implement or investigate

### A. Asymmetric temporal hysteresis on scene state signals (from point 2)

**The claim:** The pipeline is fundamentally frame-reactive. Halation strength,
Purkinje gating, shadow lift, and chroma adaptation react too quickly to
transient highlights and temporary dark frames, causing grade pumping and flicker.

**Assessment: Valid.**

Currently:
- `slow_key` (slot 205) is the only signal with an asymmetric time constant —
  it is a slow EMA on zone_key used specifically for shadow lift temporal context.
- Halation effective strength is driven by `specular_contrast` (p90−p50), which
  updates every frame via the Kalman-smoothed p90. No hysteresis.
- Purkinje weight is driven by `new_luma` (per-pixel, instantaneous). No
  temporal smoothing on the scene-level gate.
- Scene cuts are handled (hard Kalman reset via HWY_SCENE_CUT) but gradual
  transitions between lighting states have no asymmetric handling.

**Proposed direction:**

Introduce asymmetric rise/fall EMAs for the two most affected signals:

1. **Halation `eff_hal_str`** — currently `HAL_STRENGTH * lerp(1.0, 1.4, specular_contrast)`.
   Specular contrast rising fast (bright source enters frame): slow rise (τ ≈ 0.5s).
   Specular contrast falling (source leaves): fast fall (τ ≈ 0.1s).
   Avoids the halation "bloom pulse" when a bright source briefly enters frame.

2. **Shadow lift `shadow_lift_str`** — currently driven by `_sls_t` (linear from
   perc.r + scene_mode). Dark transition: allow fast lift increase. Bright
   re-entry: slower falloff (currently τ ≈ slow_key which is already 1s EMA).
   The slow_key mechanism partially handles this — audit before adding more.

**Highway slot needed:** 1 new slot for smoothed specular_contrast (or write
asymmetric EMA inside analysis_frame or corrective HighwayWritePS).

**GPU cost:** Near-zero — one EMA per affected signal in existing passes.

---

### B. Highlight classification for inverse_grade (from point 4)

**The claim:** Non-semantic inverse tone mappers occasionally invent colour in
clipped whites, over-warm practical lights, and oversaturate emissive FX.

**Assessment: Valid and documented.** testbed known issues include
yellow/orange over-saturation and mid-shadow off-color.

**Most viable signal: temporal persistence of near-clip pixels.**

Clipped or near-clipped highlights (luma > 0.90) are structurally static between
frames — they cannot change because the game's tonemapper has already crushed them.
A pixel that remains near-clip for N consecutive frames is almost certainly a
genuine specular/emissive, not compressed colour that benefits from expansion.
Temporal persistence is detectable cheaply via the existing scene-cut signal and
a per-frame near-clip fraction count.

**Secondary signal: local chroma gradient.**

Genuine compressed colour has neighbours with consistent chroma direction
(a colour light source surrounded by its own reflected light). Emissive FX and
specular spikes have near-zero surrounding chroma (white bloom over dark background).
Local Oklab C variance in a small neighbourhood around each near-clip pixel
distinguishes these two cases. Expensive per-pixel but cheap at 1/8-res.

**Proposed direction:**

- Add a near-clip fraction signal to analysis_frame (pixels with luma > 0.90,
  as a fraction of total — similar to achrom_frac structure).
- Write to a new highway slot. In inverse_grade, gate chroma expansion strength
  by `(1 − near_clip_weight)` — pixels in scenes with high near-clip fraction
  are likely in emissive/specular-dominated regions and get less expansion.
- Temporal persistence: compare near-clip fraction against slow EMA of itself.
  If fraction is stable across frames (persistent clip), reduce expansion further.

**Note:** Per-pixel local chroma gradient at 1/8-res is a stretch target —
research whether the scene-level near-clip fraction is sufficient first.

---

## Audit only — investigate before deciding

### C. Operator doubling in dark areas (from point 1)

**The claim:** LOCAL_TONE + shadow lift may be compounding on the same dark pixels,
Retinex + zone S-curve may be stacking local contrast amplification.

**Assessment: Plausible, needs measurement.**

LOCAL_TONE gate: `max(log_key - max(log_base, log_pixel), 0.0)` — lifts pixels
darker than scene key, gated by both local base and pixel luma.

Shadow lift: `shadow_lift_str` applied in L-space after Retinex, gated by
`_sls_t` (driven by p25 + scene_mode).

These touch different things: LOCAL_TONE is spatially aware (guided filter base),
shadow lift is global (percentile-driven). But for a uniformly dark scene, both
fire in full strength on the same pixels.

**Proposed direction:** Measure both in isolation on a dark interior testbed
frame. If shadow lift is already covering what LOCAL_TONE does in dark scenes,
LOCAL_TONE could be attenuated when shadow_lift_str is high. Not a rewrite —
a one-line cross-term attenuation.

**Do not act on until measured.** Prematurely coupling these would break the
current calibration.

---

## Rejected — skip

| Point | Reason |
|-------|--------|
| #3 — Move to JzAzBz/ICtCp | SDR [0,1] range; JzAzBz designed for HDR (0.001–10,000 nits). Oklab differences negligible in SDR. Not worth conversion cost. |
| #5 — Rational spline tone fields | FilmCurve already uses rational shoulder+toe. Already done. |
| #6 — Spectral diffusion energy conservation | Polydisperse R/G/B widths (1.15/1.00/0.85) already capture key effect. SDR difference would be subtle. |
| #7 — Replace gates with continuous confidence | Already the design principle (CLAUDE.md: no hard gates, smoothstep everywhere). Nothing to do. |
| #8 — Foveated perceptual importance maps | Requires spatial subject detection. ML territory for game content. Not actionable. |

---

## What to keep exactly as-is (confirmed by external analysis)

- Oklab workflow
- Constant-hue gamut projection (R78 gclip)
- Histogram percentile modeling
- Kalman stabilization (R39/R88)
- Hunt coupling (R65)
- Purkinje modeling (R52)
- Memory color attraction (R117D)
- Density-space masking (R84/R85)
- Chroma self-mask vibrance (R71)
- Asymptotic gamut ceilings (R73)
- Film-density style couplers (R110/R130)

---

## Priority order

1. **R196-A** — Asymmetric temporal hysteresis on specular_contrast / halation.
   Targeted, low cost, directly addresses observable grade pumping.

2. **R196-B** — Near-clip fraction signal for inverse_grade highlight classification.
   Requires new analysis pass but highway slot infrastructure already exists.

3. **R196-C** — Operator doubling audit (LOCAL_TONE vs shadow lift).
   Measure first, act only if compounding is confirmed.
