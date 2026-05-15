# R177 — MeanChroma EMA Slowdown — 200ms to 1s Time Constant: Findings
**Date:** 2026-05-10
**Status:** Implemented

## Problem
MeanChroma EMA alpha = frametime × 0.005 (~200ms τ) was fast enough to track scene composition as the camera moved along a wall. Chroma grade visibly shifted in ~200ms — enough to be noticed as color flicker during movement.

## Solution
Slowed to frametime × 0.001 (~1s τ). Scene cuts reset alpha→1.0 via SceneCutSamp — hard transitions still snap immediately to the new scene chroma.

## Implementation
analysis_frame.fx MeanChromaPS alpha coefficient 0.005→0.001; SceneCutPS runs earlier in pass order so SceneCutSamp is valid to read at MeanChroma update time.

## Result
Chroma grade stable during camera movement. Scene cuts still respond immediately.
