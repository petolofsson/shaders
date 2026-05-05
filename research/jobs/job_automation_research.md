# Job — Shader Automation Research

**Trigger ID:** trig_01Cm4QTimdKcVX5ZwoiSvhBg
**Schedule:** 0 2 * * * (2 AM UTC)
**Output:** `research/R{next}_{YYYY-MM-DD}_automation.md`

## Summary

Core scene-descriptive automation is complete (R41). This job now focuses on:
1. Adaptive base values — can remaining knobs be auto-derived from scene statistics?
2. Knob count reduction — can rarely-changed knobs be eliminated or merged?
3. New highway slots — HWY_P90, HWY_CHROMA_ANGLE, HWY_ACHROM_FRAC are available.
   Investigate what pipeline stages could consume them usefully.

## Closed investigations (do not re-open)

These were evaluated in R102 (2026-05-05) and rejected:

| Knob | Verdict | Reason |
|------|---------|--------|
| HUNT_LOCALITY | N/A — removed | Intentionally removed (commit e155e6c, 2026-05-04). Fed only into the dropped hunt_scale. Not a regression. Do not flag as missing. |
| INVERSE_STRENGTH base | REJECT | `slope` (highway x=197) already encodes inverse-IQR scaling via `2.5/log_iqr`. Adapting INVERSE_STRENGTH on top creates double-counting with super-quadratic response. |
| HAL_STRENGTH auto-enable | REJECT | Per-pixel `max(0, blur−sharp)` naturally evaluates to zero in scenes with no highlights. Physical model — no scene-level gate needed or appropriate. |
| ZONE_STRENGTH inverse scaling | REJECT | Inner `lerp(0.26, 0.16, smoothstep(0.08, 0.25, zone_std))` already provides 38% inverse scaling. Adding outer adaptation double-counts and over-suppresses legitimate high-contrast scenes. |

## Open candidates

- **CHROMA_STR (1.0)** — can the calibrated constant be derived from achromatic fraction
  (HWY_ACHROM_FRAC)? Gray-heavy scenes might want less lift.
- **HWY_CHROMA_ANGLE** — scene colour direction now on highway. Could inverse_grade
  use it to bias expansion toward scene's dominant hue rather than expanding uniformly?
- **Pro-Mist warm scatter** — scatter_r=1.05/scatter_b=0.92 is a baked warm push.
  Now that R47 is removed, investigate whether this should be neutralised or kept.
- **HUNT_LOCALITY adaptive formula** — if R61 per-pixel Hunt is ever re-implemented,
  a zone_std-adaptive version is ready: `HUNT_LOCALITY * smoothstep(0.06, 0.20, zone_std)`.
  Do not implement until R61 itself is implemented first.

## Locked artistic knobs (do not propose automating)
EXPOSURE, all CC wheels, CURVE_*_KNEE/TOE, ROT_*, PRINT_STOCK, MIST_STRENGTH,
PURKINJE_STRENGTH, VIEWING_SURROUND, LCA_STRENGTH, stage gates.

## Last updated
2026-05-05 — Added closed investigation verdicts from R102. Removed HUNT_LOCALITY
from open candidates (intentional removal, not a gap). Documented HUNT_LOCALITY
adaptive formula for future reference if R61 is ever re-implemented.
