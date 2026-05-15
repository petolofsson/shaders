# R180 — Eye-Shape Diffusion Replacing Radial Oval: Findings
**Date:** 2026-05-10
**Status:** Implemented

## Problem
Old diffusion shape (xs=1.6, ys=0.08) was a narrow side-band oval — only the extreme left/right edges received diffusion. Center was 0% which nullified artistic intent. src_gate at smoothstep(0.15,0.45,L) killed bloom in dark scenes. Ramp starting at r=0.30 further delayed onset.

## Solution
90°-rotated eye shape: foci off-screen at |dy|=0.70 (screen goes ±0.50), widest at vertical center ±12.5% of screen width. `eye_x_bound = 0.125 × sqrt(max(0, 1 − (dy/0.70)²))`, `r = saturate(dist_out / 0.375)`. Three-band ramp: 0→0.25 at r=0.15–0.40, 0.25→0.75 at r=0.40–0.70, 0.75→1.00 at r=0.70–0.90. Center gets 10% midtone baseline: `(0.10 + eff_diff × 0.09) × mid_gate × ch_scatter`. src_gate lowered to smoothstep(0.10,0.40,L). adapt_str boosted 0.15→0.22, midtone scalar 0.06→0.09.

## Implementation
DiffusionPS in grade.fx — replaces previous abs(dist) radial formula with eye_x_bound geometry and three-band ramp.

## Result
Diffusion visible across the image. Center has gentle midtone softness. Edges receive progressively more bloom.
