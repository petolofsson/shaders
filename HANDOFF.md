# Handoff — 2026-05-04

## Current branch
`alpha` — active development. Last commit to be created this session.

---

## Pipeline state

All original plan phases complete. R86 prototype now running in Arc Raiders chain.

| Stage | Finished | Novel |
|-------|----------|-------|
| Stage 0 — Input | 92% | 75% |
| Stage 1 — Corrective | 90% | 75% |
| Stage 2 — Tonal | 90% | 88% |
| Stage 3 — Chroma | 95% | 90% |
| Stage 3.5 — Halation | 90% | 78% |
| Output — Pro-Mist | 90% | 72% |

---

## What shipped this session

- **R86 prototype** — `inverse_grade_aces.fx` running in Arc Raiders chain
  - Analytical ACES inverse + per-hue Oklab correction
  - Scene normalization via p75 highway read
  - Confidence gate: `blend = ACES_BLEND * aces_conf`
  - `ACES_BLEND = 0.30` in `creative_values.fx`
- **Data highway extended** — analysis_frame encodes PercTex→highway at x=194-196
- **aces_debug.fx** — live confidence overlay + 3-column p25/p50/p75 diagnostic display
- **tools/aces_calib.py** — screenshot-based calibration tool
- **Arc Raiders chain** — `aces_debug` reordered before `analysis_scope`
- **GZW tuning** — various knob adjustments (see CHANGELOG)

---

## R86 — active prototype

**Chain:** `analysis_frame : inverse_grade_aces : analysis_scope_pre : corrective : grade : pro_mist : aces_debug : analysis_scope`

**Key files:**
- `unused/general/inverse-grade/inverse_grade_aces.fx` — the inversion shader
- `unused/general/inverse-grade/aces_debug.fx` — debug overlay
- `general/analysis-frame/analysis_frame.fx` — highway encoding (DebugOverlay, x=194-196)
- `gamespecific/arc_raiders/shaders/creative_values.fx` — `ACES_BLEND 0.30`
- `tools/aces_calib.py` — calibration tool

**Current state:** Running. Inversion is applied (visually confirmed). Debug box
currently shows red in outdoor scenes despite valid chain order.

**Open diagnostic:** Debug box shows aces_conf ≈ 0 in bright outdoor scenes.
The box bottom half now shows 3 columns (p25=red, p50=green, p75=blue) so the
next screenshot will reveal what values are actually being read from the highway.

If bottom columns are near-black → PercTex is zero (CDFWalk not populating, or
highway write broken). If columns show values but conf=0 → formula issue:
`shadow_rat = p25/p50 >= 0.72` AND `highs_norm >= 3.0` simultaneously.

**To investigate:**
1. Take screenshot in bright outdoor scene
2. Crop box bottom-half, measure column brightness
3. Compute conf manually: `iqr=p75-p25`, `highs_norm=(1-p75)/iqr`, `shadow_rat=p25/p50`
4. If all zeros → test-write constant 0.5 to highway in DebugOverlay to isolate

---

## Known state

- `LCA_STRENGTH = 0.0` in Arc Raiders `creative_values.fx` (disabled for R86 validation)
- `ACES_BLEND = 0.30` in Arc Raiders `creative_values.fx`
- GZW: exposure 1.0, floor/ceiling 0/1, zone_strength 1.35, print_stock 0.30
- No known compile errors or visual regressions

Debug log: `/tmp/vkbasalt.log` — check first for SPIR-V issues.
