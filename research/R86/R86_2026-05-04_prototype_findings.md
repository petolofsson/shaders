# R86 Prototype Findings — 2026-05-04

## Status
Prototype running in Arc Raiders chain. Analytical ACES inverse fires, scene normalization
active, confidence gate implemented. Debug overlay operational. One open diagnostic.

---

## What was built

### `unused/general/inverse-grade/inverse_grade_aces.fx`
Full prototype:
- **ACESInverse**: quadratic formula, 4 ALU. Exact inverse of UE5 Hill 2016 ACES.
- **ACESHueCorrection**: per-hue Oklab rotation. Red −0.15, cyan −0.20, blue −0.10.
- **Scene normalization**: `scene_ceil = max(ACESInverse(p75), 1.0)` — divides the
  scene-linear output by the p75 ceiling. Prevents highlight clipping above ~0.85.
  Only activates in high-exposure scenes (p75 > ~0.85 display value → ACESInverse > 1).
- **Confidence gate**: `blend = ACES_BLEND * aces_conf` — direct multiplication,
  no smoothstep threshold. Prevents flicker at gate boundaries.
- **Data highway read**: p25/p50/p75 read from BackBuffer at x=194/195/196, y=0.
  Written by analysis_frame's DebugOverlay each frame.

### `unused/general/inverse-grade/aces_debug.fx`
Debug overlay (last meaningful effect before analysis_scope):
- Reads same highway positions.
- Top-right corner box, 40×40px:
  - Top half: red→green based on aces_conf (full green = conf ≥ 0.5)
  - Bottom half: three columns — red=p25, green=p50, blue=p75 raw brightness
- The 3-column display was added to diagnose persistent red-box issue (see below).

### `tools/aces_calib.py`
Python calibration tool. Takes periodic screenshots, reads highway pixels, computes
ACESConfidence in Python (same formula as HLSL), tracks running mean ± std. Declares
stability when σ < 0.005 over 20 samples. Outputs to `tools/calib_<game>.txt`.

---

## Key lessons

### 1. `pooled = true` is silently ignored by vkBasalt
ReShade's `pooled = true` texture annotation (for cross-effect sharing) does nothing
in vkBasalt. Each effect gets its own zero-initialized instance of every texture.
Do not attempt PercTex sharing via ReShade annotations.

### 2. BackBuffer data highway is the proven cross-effect sharing mechanism
Row y=0 of BackBuffer flows reliably through all effects. The convention `if (pos.y < 1.0)
return col` is honoured by every effect in the chain. analysis_scope_pre writes x=0..193
(lum histogram 0..128, hue histogram 130..193). Positions x=194+ are free.

analysis_frame's DebugOverlay (pass 4) encodes PercTex into the highway:
```hlsl
if (xi == 194) return float4(perc.r, 0.0, 0.0, 1.0);  // p27.5
if (xi == 195) return float4(perc.g, 0.0, 0.0, 1.0);  // p50
if (xi == 196) return float4(perc.b, 0.0, 0.0, 1.0);  // p72.5
```
(CDFWalk targets 0.275/0.50/0.725, referred to as p25/p50/p75 throughout.)

### 3. Chain order determines what aces_debug reads
analysis_scope overwrites ALL of y=0 with its scope visualization. aces_debug must
run BEFORE analysis_scope or it reads garbage. Chain order:
```
analysis_frame : inverse_grade_aces : analysis_scope_pre : corrective : grade :
pro_mist : aces_debug : analysis_scope
```

inverse_grade_aces reads highway after analysis_frame (valid) and before analysis_scope
(not yet overwritten). aces_debug reads after pro_mist, still valid.

### 4. `bright_gate` causes false negatives in hazy/dark-looking outdoor scenes
The original `bright_gate = smoothstep(0.04, 0.12, p50)` killed confidence in outdoor
scenes viewed away from the sun — the orange dust haze reduces median luminance even
in daylight. Removed. The `highs_norm` term in ACESConfidence already handles truly
dark scenes (loading screens etc.) because highs_norm explodes when the IQR is tiny.

### 5. smoothstep blend gate causes flicker
`blend = ACES_BLEND * smoothstep(0.1, 0.4, aces_conf)` amplified small fluctuations
in aces_conf around the threshold into visible blend swings. Replaced with direct
multiplication: `blend = ACES_BLEND * aces_conf`. Proportional — no threshold to bounce across.

---

## Open diagnostic: debug box shows red in bright outdoor scenes

The box shows pure red (aces_conf ≈ 0) in scenes where it should be green. The 3-column
p25/p50/p75 display was added to see what values aces_debug is actually reading from the
highway. Next session should:

1. Take a screenshot in a bright outdoor scene.
2. Measure the bottom 3 columns of the debug box (ImageMagick crop).
3. Compute conf manually from those values to verify the formula.
4. If columns are near-black → PercTex is zero or highway encoding broken.
5. If columns show values but conf is still 0 → formula issue (shadow_rat or highs_norm).

ACESConfidence gives 0 when BOTH:
- `shadow_rat = p25/p50 >= 0.72` (shadows close to midtones)
- `highs_norm = (1-p75)/iqr >= 3.0` (p75 far below ceiling relative to IQR)

This pattern occurs in tight-distribution scenes (heavy haze, uniform mid-grey).
It may also occur if PercTex contains equal or near-equal r/g/b values.

---

## ACES_BLEND tuning log

| Value | Observation |
|-------|-------------|
| 1.0   | Extreme magenta on start screen — highlights blow out |
| 0.60  | Visible, strong. Reds affected. |
| 0.30  | Current — subtle, passes visual check |
| 0.25  | Previous default |

---

## Next steps

1. **Resolve red-box diagnostic** — read 3-column values from screenshot, trace formula.
2. **If highway values are zero** → check CDFWalk output (may need to test-write a known
   constant to highway to isolate PercTex vs. highway issue).
3. **Revisit ACESConfidence formula** — may need to replace IQR-based detection with
   something more robust for hazy/mid-range scenes.
4. **Scene normalization validation** — test in high-exposure scenes (p75 > 0.85).
5. **GZW test** — confirm box stays red (low confidence) in Grey Zone Warfare.
