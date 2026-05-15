# R160 — Adaptive Print Stock: Findings
**Date:** 2026-05-10
**Status:** Implemented

## Problem
Fixed print stock parameters applied identically regardless of scene exposure. Very dark scenes got excessive black lift (crushing shadow detail into the pedestal). Bright scenes got insufficient shoulder compression.

## Solution
ApplyPrintStock receives p25 and p75 from BuildSceneCtx. Black lift backs off when scene shadows are already elevated: `0.025 × saturate(1 − p25/0.06)`. Shoulder exponent lerps 1.8→1.2 and cubic correction lerps 0.06→0.02 as p75 rises 0.40→0.70.

## Implementation
BuildSceneCtx passes p25/p75 to ApplyPrintStock in grade.fx.

## Result
Dark scenes retain shadow texture; bright scenes get appropriate shoulder roll.
