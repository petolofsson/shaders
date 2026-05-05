# Job — Shader System Stability Audit

**Trigger ID:** trig_01CR4BpHeoEZ41yjpAx2PuM5
**Schedule:** 0 2 * * * (2 AM UTC)
**Output:** `research/R{next}_{YYYY-MM-DD}_stability.md`

## Summary

Nightly code audit — no web search, no source modifications. Five tasks:
A. Register pressure in ColorTransformPS (spill threshold: 128 scalars)
B. Unsafe math sites (log/pow/div-by-zero/sqrt/atan2)
C. BackBuffer row guard verification (y=0 data highway)
D. Temporal history accumulation (EMA coefficients, format, Sage-Husa stability)
E. Targeted review of most recent additions

## Known-good baseline (from R102 audit, 2026-05-05)

- **R88/R89/R90**: all pass. No issues.
- **Register pressure**: 59 VGPRs / 87 SGPRs verified via RADV dump. No spilling.
- **BackBuffer guards**: all present and correctly placed in grade.fx, corrective.fx,
  inverse_grade.fx, inverse_grade_debug.fx.
- **EMA coefficients**: all bounded (0,1) via saturate() or literal range. All history
  textures use RGBA16F or R16F. No RGBA32F.
- **Data highway slots**: no write collisions. Slots 0–128, 130–193 (analysis_scope_pre),
  194–202 (analysis_frame), 210 (corrective Passthrough).

## Current targeted review (Task E): 2026-05-05 changes

- **OPT-1 — sincos elimination** (grade.fx): H-K `sh`/`ch` now derived via small-angle
  HELMLAB + exact R21 angle-addition. Verify `dh` is hoisted correctly from the HELMLAB
  line (line ~374) and that `sh_p`/`ch_p`/`sh`/`ch` values match the original `sincos`
  result to within 1.28×10⁻⁴. Verify `r21_cos`/`r21_sin` are in scope before the H-K block.

- **OPT-2/3/4 — dead code + tex2Dlod** (grade.fx): Verify `lin_pre_tonal`,
  `CORRECTIVE_STRENGTH` lerp, and `TONAL_STRENGTH` lerp are fully absent. Verify
  `tex2Dlod` is used for PercSamp, both ChromaHistory reads (zstats + pivot loop),
  and ZoneHistorySamp. Verify BackBuffer reads (LCA lines) still use `tex2D` (correct —
  varying UV, not constant).

- **R101 F1 Bezold-Brücke** (grade.fx): Verify `r21_delta += (lab.x - 0.50) * 0.006 *
  (sh_h * 0.1253 + ch_h * 0.9921)`. Confirm `sh_h`/`ch_h` are in scope at this point
  (they are: computed at line ~373 for HELMLAB). Confirm no remnant of R75 `lerp(-0.003,
  +0.003, lab.x)`.

- **R101 F2 H-K exponent** (grade.fx): Verify `hk_exp = lerp(0.52, 0.64,
  saturate(zone_log_key / 0.50))` is present and `zone_log_key` is in scope (it is:
  read from ChromaHistory at line ~229). Confirm `pow(final_C, hk_exp)` not
  `pow(final_C, 0.587)`.

- **R101 F3 Abney C_stim** (grade.fx): Verify `float C_stim = C` is declared immediately
  after `float C = length(lab.yz)` (line ~366). Verify Abney coefficient line ends with
  `* C_stim`, not `* final_C`. Verify `dtheta` line (green hue rotation) still uses
  `final_C` — that is correct and intentional (not changed).

## Important: HUNT_LOCALITY is not missing

Previous audits (R102) flagged HUNT_LOCALITY as a regression. This is incorrect.
HUNT_LOCALITY was **intentionally removed** in commit `e155e6c` (2026-05-04) as part of
the chroma lift simplification. It fed only into `hunt_scale`, which was part of a
5-factor pipeline replaced by `chroma_str = CHROMA_STR * R68A`. Do not flag its
absence in Task E.

## Files audited
grade.fx, corrective.fx, analysis_frame.fx, analysis_scope_pre.fx,
inverse_grade.fx, inverse_grade_debug.fx, pro_mist.fx, highway.fxh

## Last updated
2026-05-05 — Updated Task E to focus on OPT-1/2/3/4 and R101 F1/F2/F3.
Added known-good baseline from R102. Added explicit note that HUNT_LOCALITY
absence is intentional — do not flag as regression.
