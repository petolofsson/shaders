# Active pipeline code audit: three leads — 2026-11-04

Scope: active combined technique, source observation, analysis and corrective histories, inverse, grade and shared color/gamut helpers; current profiles and recorded decisions. This is code and evidence analysis, not a GPU defect confirmation or an appearance rating. Previously closed print, transport, tonal-base and gamut screens are not reopened. No shader or profile changes.

## 1. Slow-key initialization conflates valid darkness and missing history

`ComputeSlowKey` in `general/corrective/corrective.fx` uses `step(0.001, prev_slow)` as its initialization test. The zone key can legitimately be below 0.001. If it was 0.0005 and rises to 0.01 without a cut, the code substitutes 0.01 for the prior value and returns 0.01 immediately; the intended 20-second recurrence at 16.67 ms would instead return approximately 0.0005055. This is an algebraic contract failure for that state sequence, not yet evidence that it is visible in a real game. The grade floors the consumer at 0.001, but the incorrect jump can still cross that floor and affect slow-key/zone-key lift context and three-way zone weights. Scene-cut detection may also change the actual sequence, so it must be measured rather than assumed.

**Next test:** explicit history readback with genuine initialized near-black values, a non-cut gradual return and a cut control; compare the existing recurrence against a separate initialization flag while preserving both time constants. Follow with measured same-update dark-return output and startup checks only if the state defect appears in relevant inputs. Existing precision and timing work did not establish this sentinel contract. No rate retuning.

## 2. Scene hue direction has no confidence when colors cancel

`MeanChromaPS` averages colored Oklab vectors and publishes `atan2(mean_b, mean_a)` without publishing or applying the vector magnitude as confidence. Opposing colored populations can have a near-zero centroid even when each population is strongly colored. `InverseGradePS` treats the resulting direction as meaningful and multiplies expansion by `1 - 0.15 * alignment`; directions on opposite sides of an arbitrarily small centroid can change that factor from 0.85 to 1.15. This is a bounded 30 percentage-point span in the *multiplier*, not a 30% final-image change. On the current dark and interior samples inverse contribution was almost absent, so those scenes do not demonstrate an image defect.

**Next test:** explicit GPU readback of centroid, angle and inverse result for balanced opposing colors with small controlled changes, then current-profile vivid/mixed-hue scenes and repeats. Compare a confidence-weighted directional term that tends continuously to neutral scaling as the centroid loses direction; preserve existing scene statistics, hue bias, gamut budget and manual ceiling. Reject if downstream quantization or actual inputs make it immaterial, or if real palette relationships worsen. No claim is made about the GPU's `atan2(0,0)` result.

## 3. Sparse fixed scene observations can respond to spatial phase

The source highway is constructed from four filtered reads per 1/8-resolution cell, then global luminance and chroma statistics sample a fixed 32×18 lattice; zone statistics use fixed 10×10 grids in each of 16 zones. These are sparse samples of a downsampled signal, not exact whole-frame distributions. Moving a narrow feature or periodic pattern relative to the grids can change sampled histograms while the underlying population stays nearly unchanged. Those statistics feed scene cuts, percentile-based tone and lift, zone confidence, inverse and print adaptation. This is a demonstrable sampling limitation by construction, but its scale on real footage and after temporal smoothing is not established. Earlier sampling research does not establish a current visual failure.

**Next test:** GPU read back current raw and smoothed statistics while translating the same narrow highlight, shadow and periodic textures by sub-grid phases, with a full-resolution reference distribution. Follow with a headless camera-motion clip and same-update outputs. Assess whether deviations exceed unchanged-repeat and temporal variation before considering an observation change; compare possible antialiasing or stratification against added latency, bias, cost, and cut behavior. Do not adjust unused per-hue history records by association.

## Priority and limits

Lead 1 is the strongest correctness issue because its counterexample follows directly from the current recurrence. Lead 2 has a bounded but real model ambiguity and a targeted synthetic contract. Lead 3 has the broadest potential reach but the least evidence of practical impact. The ambient-tint idea is not promoted: source inspection alone did not demonstrate a material loss. Existing residuals and these algebraic counterexamples are not evidence that a specific improvement will be adopted.
