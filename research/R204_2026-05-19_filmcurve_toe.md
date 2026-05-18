# R204 — Film Curve Toe: Physical Justification Audit

**Date:** 2026-05-19
**Trigger:** Shadow detail loss observed when CORRECTIVE_STRENGTH is enabled, even with all corrective knobs at zero. Root-caused to the unconditional `tc_comp` toe in `FilmCurveApply`.

## Problem Statement

`FilmCurveApply` (grade.fx) contains three components:

```
return x + body_s - sh_comp + tc_comp;
```

- `body_s` — upper-mid lift (x > 0.5 only, fires toward the shoulder)
- `sh_comp` — rational shoulder compression (pulls highlights gracefully to SDR ceiling)
- `tc_comp` — rational toe: `(0.06 / ktoe) * below² / (ktoe + below)`

`tc_comp` fires unconditionally in shadows. With typical auto-derived `ktoe = 0.20`, it produces:

| Location | Slope | Shadow contrast |
|----------|-------|-----------------|
| x = 0.00 (black) | 0.775 | −22.5% |
| x = 0.10         | 0.983 | −1.7%  |
| x = ktoe = 0.20  | 1.000 | 0% (C1 join) |

The coefficient `0.06 / ktoe` scales inversely with ktoe — in a dark game scene where the histogram pulls ktoe to its minimum clamp (0.08), shadow compression at black reaches **56%**. This is the cause of the "smoothing" artifact.

## Research Questions

1. Is a film print toe physically justified when applied to display-referred SDR content (post-ACES linear [0,1])?
2. Does ACES 2383 print emulation include a toe/black lift, and where in the pipeline does it fire?
3. How do reference implementations (ACES CTL, DaVinci Resolve, FilmConvert) handle the print stock toe?
4. What does the toe represent physically in display-referred space?

## Scope

- ACES reference CTL output transforms and 2383 LMT
- H&D curve literature: D-min, characteristic curve in log vs linear space
- Real-time film emulation prior art (Hable, ACES Narkowicz, Gran Turismo)
- Effect of removing `tc_comp` on the existing `PRINT_STOCK` effect (which already handles print emulation)
