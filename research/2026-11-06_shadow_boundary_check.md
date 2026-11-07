# Motion history boundary check

Tested an additional 9×9 residual RMS check at the existing two-code threshold
alongside the prior 3×3 and per-pixel checks. The estimator sees only observed
images; known geometry is used solely to assess correspondence afterward.
The 20 selected 100-fps-clock changing-noise targets use the same inputs and
whole-frame motion estimates as the previous bounded-motion screen.

| Phase | Accepted history without visible correspondence, before → after | Mean enhancement support, before → after |
| --- | ---: | ---: |
| Camera | 0.59% → 0.60% | 0.935 → 0.894 |
| Occlusion | 5.92% → 0.51% | 0.530 → 0.424 |
| Lighting | 4.78% → 0.22% | 0.589 → 0.502 |
| Cut/recovery | 14.03% → 6.54% | 0.216 → 0.185 |

These correspondence counts include range and context exclusions, not measured
visible ghost rates. The check reduces unsupported acceptance near transitions
at the cost of rejecting valid support; it does not solve the cut case or
persistent grain. This is a selected-window CPU ablation, not a dense temporal
or GPU test. Production identities were verified by the evaluator. The full
report and comparison frames are in `captures/shadow_boundary_check_20261106/`.
No adoption or effectiveness score change follows.

## Dense follow-up

All 320 changing-noise source states were subsequently compared against the
previous whole-frame reference. During the entire occlusion phase, accepted
history without visible correspondence fell from 6.39% to 1.09%, while mean
support fell from .599 to .498. Across camera motion, support fell from .869 to
.796 and the measured timber/metal gap gains fell from 7.90%/7.11% to
7.03%/6.34%. In the lighting phase the unsupported fraction fell from 3.67% to
.42%; in cut/recovery it fell from 4.64% to 1.65%. Fractions retain the context
and range caveat above.

The 99th percentile of frame-to-frame changes in mean support increased from
.058 to .077 in camera motion and from .110 to .123 in occlusion. These are
spatial averages, not a measurement of visible flicker; local temporal stability
remains unverified. In the selected surface-fixed grain control the conditional
brightness error during camera motion remains 1.085× baseline, versus 1.086×
before. This check is therefore a useful correspondence tradeoff but does not
solve persistent grain or establish a production candidate. Reports and the
comparison summary are under `captures/shadow_boundary_check_20261106/`.
