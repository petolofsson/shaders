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

## Current targeted review (Task E): highway migration + chroma simplification + OPT reverts

- **Highway Phase 1** (this session): WarmBiasTex/SceneCutTex migrated to BackBuffer y=0
  slots HWY_WARM_BIAS (210), HWY_SCENE_CUT (199). Verify ReadHWY() reads are at correct
  pixel x-coordinates in all consuming effects.
- **New highway slots** (this session): HWY_P90 (200), HWY_CHROMA_ANGLE (201),
  HWY_ACHROM_FRAC (202) written by analysis_frame.fx DebugOverlayPS. Verify one-frame
  delay is acceptable for all consumers.
- **ShadowBias removed**: corrective.fx ShadowBias pass removed entirely (corrective now
  7 passes: ComputeLowFreq → ZoneHistogram → ZoneLevels → SmoothZoneLevels →
  UpdateHistory → WarmBias → Passthrough). Verify no dangling reads anywhere.
- **R47 removed**: grade.fx shadow auto-temp removed. Verify r19_sh_delta no longer
  references any shadow_bias variable.
- **Chroma lift simplified** (R68A only): CHROMA_STR now multiplies 0.04 raw constant.
  Hunt block (hunt_la, _k, _k4), chroma_exp, chroma_mc_t, chroma_drive all removed.
  Verify no dangling variable references in grade.fx chroma stage.
- **OPT-2/3 reverted**: max(zone_log_key, 1e-6) and zk_safe guards restored after
  white-screen regression. The proof was valid in steady-state but missed cold-start
  frame where ChromaHistoryTex reads 0. Do not re-propose removal without cold-start
  proof.
- **R22 mid_C_boost**: restored to 0.04 (was zeroed to 0.0 in previous session).
  Monitor for luminance-boundary rings.

## Files audited
grade.fx, corrective.fx, analysis_frame.fx, analysis_scope_pre.fx,
inverse_grade.fx, inverse_grade_debug.fx, pro_mist.fx, highway.fxh

## Last updated
2026-05-04 — Full rewrite. Reflects highway migration, ShadowBias/R47 removal,
chroma simplification, OPT-2/3 revert. Updated file list to include pro_mist.fx
and highway.fxh.
