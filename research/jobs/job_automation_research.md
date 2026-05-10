# Job — Shader Automation Research

**Schedule:** 0 2 * * * (2 AM UTC)
**Output:** `research/R{next}_{YYYY-MM-DD}_automation.md`

## Summary

Investigate whether remaining artistic knobs can be auto-derived from scene statistics
already on the data highway. No web search needed. Focus: can we reduce knob count
or make calibrated defaults scene-adaptive without affecting artistic control?

## Closed investigations (do not re-open)

| Candidate | Verdict | Reason |
|-----------|---------|--------|
| HUNT_LOCALITY | N/A — removed | Intentionally removed (commit e155e6c, 2026-05-04). Fed only into dropped hunt_scale. Not a regression. |
| INVERSE_STRENGTH base | REJECT | `slope` (HWY x=197) already encodes inverse-IQR via `2.5/log_iqr`. Double-counting creates super-quadratic response. |
| HAL_STRENGTH auto-enable | REJECT | Per-pixel `max(0, blur−sharp)` evaluates to zero in no-highlight scenes. Physical self-limiting — no gate needed. |
| ZONE_STRENGTH inverse scaling | REJECT | Inner `lerp(0.26, 0.16, smoothstep(0.08, 0.25, zone_std))` already provides 38% inverse scaling. Additional outer adaptation double-counts. |
| HWY_CHROMA_ANGLE directional bias | REJECT (R117) | Multi-hue scenes under-expanded off-axis colours. C-gate + mid_weight already protect neutrals — directional constraint was redundant. Uniform expansion is correct. |
| Pro-Mist warm scatter neutralization | CLOSED (R123) | No warm scatter tint exists in current ProMistPS. `adapt_str` is scalar; bloom is spectrally neutral. Pre-merge artifact from old pro_mist.fx — never carried into grade.fx. |

## R116 statistical fixes — context only, not automation candidates

These were bugs, not automation opportunities:
- Zone_log_key now linear mean of medians (was geometric → dark-biased)
- Zone_std now intra-zone pixel variance E[X²]−E[X]² (was inter-zone spread)
- Chroma median CDF p50 (was arithmetic mean → outlier-biased)
- eff_p25/p75 now pure global histogram percentiles

## Open candidates

**CHROMA_STR from HWY_ACHROM_FRAC (x=202)**
Gray-heavy scenes (interiors, overcast) may want less chroma lift. `HWY_ACHROM_FRAC`
measures the fraction of near-neutral pixels. Hypothesis: `chroma_str *= lerp(1.0, 0.70, achrom_frac)`.
Risk: achrom_frac fluctuates with scene content, not just neutrality. Validate correlation
with subjective over-saturation before recommending.

**HUNT_LOCALITY adaptive formula (future, if R61 ever re-implemented)**
`HUNT_LOCALITY * smoothstep(0.06, 0.20, zone_std)`. Do not implement until R61 itself exists.

## Locked artistic knobs (do not propose automating)
EXPOSURE, all CC wheels (SHADOW/MID/HIGHLIGHT_TEMP), CURVE_*_KNEE/TOE, ROT_*,
PRINT_STOCK, MIST_STRENGTH, PURKINJE_STRENGTH, COUPLER_STRENGTH, HAL_STRENGTH, HAL_GAMMA

## Last updated
2026-05-07 — Closed Pro-Mist warm scatter candidate (R123: not present in ProMistPS).
Closed HWY_CHROMA_ANGLE candidate (R117). Added R116 statistical fixes as context block.
Updated locked knobs list. Removed stale open candidates.
