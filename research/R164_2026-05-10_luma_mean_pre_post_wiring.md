# R164 — Wiring LUMA_MEAN_PRE and LUMA_MEAN_POST

**Date:** 2026-05-10
**Scope:** inverse_grade.fx — slope cap; highway slot audit follow-up

---

## Background

Highway slots 128 (`HWY_LUMA_MEAN_PRE`) and 129 (`HWY_LUMA_MEAN_POST`) were flagged
as dead writes in a full highway slot audit (2026-05-10). On investigation, both ARE
read by `analysis_scope.fx` for the scope display — pre/post luma histograms with
yellow mean-line needles. They are not dead writes; they have a display consumer.

The gap: no **processing** stage reads them. The audit was correct that no shader
uses them for control decisions.

## Signal definitions

| Slot | Value | Written by | Timing |
|------|-------|-----------|--------|
| 128 LUMA_MEAN_PRE  | Arithmetic mean of raw game luma (before all vkBasalt stages) | analysis_scope_pre | Available same frame to all downstream stages |
| 129 LUMA_MEAN_POST | Arithmetic mean of final pipeline output luma | analysis_scope | Available next frame (written last in chain) |

## LUMA_MEAN_PRE — slope cap in inverse_grade (implemented)

The R90 slope is derived from the IQR (p75−p25), which measures luma spread but not
absolute brightness. A scene with a wide IQR can have a high slope even if the game's
raw output is already bright — meaning the tonemapper was not compressing heavily.

LUMA_MEAN_PRE provides this missing absolute-brightness cross-check. High mean_pre =
game output is inherently bright = less headroom for expansion before clipping.

```hlsl
float mean_pre  = ReadHWY(HWY_LUMA_MEAN_PRE);
float slope_cap = lerp(2.2, 1.5, saturate((mean_pre - 0.25) / 0.35));
float slope     = clamp(slope_enc * 1.5 + 1.0, 1.15, slope_cap);
```

At mean_pre < 0.25 (dark scene): slope_cap = 2.2 — no additional restriction.
At mean_pre = 0.425 (moderate): slope_cap = 1.85.
At mean_pre > 0.60 (bright scene): slope_cap = 1.5 — expansion bounded conservatively.

Previously the slope had no upper bound. This prevents over-expansion in already-bright
scenes where the IQR might suggest compression that isn't actually harming the image.

## LUMA_MEAN_POST — display-confirmed, no processing consumer added

LUMA_MEAN_POST is one frame delayed relative to any stage that could act on it. Using
it as a control signal would introduce a one-frame feedback loop with oscillation risk.
Its display use (showing actual pipeline output mean in the scope) is the correct and
sufficient consumer. No processing use added.

If future work requires pipeline gain monitoring (e.g., detecting overcorrection
across sessions), LUMA_MEAN_POST / LUMA_MEAN_PRE is the right ratio to expose — but
as a diagnostic, not a real-time control signal.
