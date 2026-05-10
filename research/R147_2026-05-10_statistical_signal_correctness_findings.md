# R147 — Statistical Signal Correctness Audit: Findings
**Date:** 2026-05-10
**Status:** Implemented

## Problem
Wrong highway signals wired to wrong processing decisions. fc_stevens was using zone_log_key; halation gate was using Bowley skewness; chroma lift used Bowley. Bowley is an unreliable asymmetry measure for the histogram shapes produced by game content. Dead code had accumulated: WarmBias, sat histogram (4 passes), zmin/zmax, k_med/k_ema.

## Solution
R147–R155 block replaced all Bowley uses. fc_stevens → histogram mode (argmax, added CDFWalkModePS in R147). Halation gate → p90−p50 gap (specular contrast, R148). Chroma lift → mean_C inverse (R149). Purkinje → mode-gated (R150). Bowley removed from all uses. Dead code stripped (~4 passes removed).

## Implementation
New HWY_MODE slot x=206, CDFWalkModePS pass added to analysis_frame.fx. All downstream reads updated to new slots.

## Result
All signals now semantically correct; scene-cut detection (HWY_SCENE_CUT) added as reset for temporal EMAs.
