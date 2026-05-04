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

## Current targeted review (Task E): R88 / R89 / R90 / R61
- R88: Sage-Husa Q clamped to [Q_MIN, Q_MAX], forgetting factor b in (0,1)
- R89: Blue-noise dither fires after all ops, before output only
- R90: Oklab matrix b-row matches grade.fx; slope decode; mid_weight/c_weight bounds
- R61: hunt_la lerp uses HUNT_LOCALITY from creative_values.fx, substituted in both _k and fl

## Files audited
grade.fx, corrective.fx, analysis_frame.fx, analysis_scope_pre.fx,
inverse_grade.fx, inverse_grade_debug.fx

## Last updated
2026-05-04 — Updated targeted review from R19-R22 to R88/R89/R90/R61.
Added inverse_grade.fx and analysis_frame.fx to file list. Updated chain.
