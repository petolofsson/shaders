# Controlled JavaScript temporal course

The existing Babylon test engine now has an isolated temporal fixture and a
verified source export. This removes the need for real game footage as the next
controlled-test prerequisite. It does not remove the need for later game coverage
or establish a real-time shader implementation.

The RGB temporal mechanism works under changing noise in the controlled course.
Fixed grain, unreliable history around occlusions/cuts, modest visible return and
the missing inexpensive motion producer remain. Production and effectiveness
estimates are unchanged: new brightness ~45, unadopted color ~70–75, carried
chain/grade 78 and tonal 80.

## Testbed and provenance

Versioned code: [tools/temporal_course](../tools/temporal_course/README.md).
It reuses the original private headless Babylon source backend and pinned vendor
cache without editing the original scene or its cached sources. No desktop
display, focus change or physical-refresh change is used.

The 1280×720 scene contains baked timber/metal material references, procedural
cloth, a moving foreground occluder, a thin bright feature and black/code-3/code-8
targets. Baked lighting is not claimed to be recovered albedo. Scene phases cover
a stationary camera, camera movement, occlusion, lighting change and camera cut.
Textures are cropped from frozen post-inverse source floats and quantized to RGB8
for rendering. These independent textured planes do not reproduce original game
rendering or furnish a new raw-game fidelity reference.

The original 30-fps export contains 96 commanded states over 3.2 seconds: 16
intentional stationary controls and 80 distinct changing scene states. Each state
has a matching visible-surface-ID image and recorded camera/world matrices and
projected mesh corners. First-state repeat is scene-exact. IDs and matrices are
used only by the diagnostic oracle and evaluation; the RGB estimator receives
image observations alone. Ground truth is not a production-available input.

Source verification checks 96 clean/ID pairs, 384 controlled RGB8 inputs and
276 exact visible calibration centers. Twelve calibration centers become
occluded; the initial assumption that every center remains visible failed and
is preserved. Actual texture projection agrees with the rendered colors to
approximately .51 code at the 99th percentile, consistent with RGB8 rounding.

Four matched input populations are clean, independent changing noise,
screen-fixed grain and surface-fixed grain. Nominal noise is one common RGB-code
unit, clipped/rounded before evaluation. Grain uses sixteen small binomial blurs;
surface grain is defined in known local plane coordinates and screen grain in
viewport coordinates. These are specified controls, not measured game noise.
Quantization/clipping change the actual scalar code-Y noise distribution.

## Reference and 30-fps findings

Reuse the frozen shared-projective/subpixel RGB estimator from the
[preceding screen](2026-11-06_shadow_temporal_planar.md), with unchanged matching
and photometric gates. Evaluate four observations over 100 ms in a 512×384 native
working crop. The oracle has known per-surface correspondence and visibility,
the same ±19-pixel range and photometric acceptance limits. It remains subject
to resampling, source quantization and changes in lighting; it is not noiseless truth.

All 96 changing-noise updates are evaluated. Variant comparisons use the same
four target updates per phase, 20 total, with overlapping spatial populations:

| Phase, changing noise | Source error | RGB temporal estimate | Known geometry | RGB samples |
| --- | ---: | ---: | ---: | ---: |
| Stationary | 1.044 | .587 | .590 | 3.91 |
| Camera motion | 1.042 | .566 | .546 | 3.86 |
| Occlusion | 1.041 | .779 | .622 | 2.78 |
| Lighting | 1.041 | .837 | .704 | 2.67 |
| Cut window | 1.043 | .901 | .925 | 1.87 |

Errors are scalar source-estimation RMSE in code equivalents against the known
clean current source. The oracle can abstain more strongly at the cut, so lower
RGB error there does not establish more correct motion. Clean-input RGB mismatch
is approximately .201/.408/.473/.283 code in motion/occlusion/light/cut windows.
Interpolation and temporal lag remain even without added noise.

Approximately .8% of accepted RGB histories during the pan, 5.3% during occlusion,
5.2% during lighting and 15.1% in the cut window lack supported known visible
correspondence. This diagnostic includes range/context restrictions; it is not a
direct visible-ghosting rate. It exposes a confidence gap that low photometric
error alone cannot resolve. No special cut flag from the scene is supplied to
the RGB method.

## Brightness contribution and limits

The reference still uses the scalar configured affine black stage and the prior
half-missing-contrast budget: source gate, weighted zero mean code correction,
two-code cap and SDR limit. Current-pixel output remains the baseline term;
temporal averaging supplies only the enhancement increment. This is **not** the
complete production grade, a new GPU candidate or an adopted temporal denoiser.

Compare errors against each clean enhanced reference, so intended contrast is
not counted as noise. In the steady-pan window, RGB temporal enhancement error
is .843 code versus .831 baseline error: **+1.50%**, compared with **+8.90%** for
instantaneous residual enhancement. Stationary gives +1.65%; occlusion/light/cut
give +4.83%/+4.67%/+6.33%. These ratios include noise, alignment, gates and
nonlinear response; they are not pure noise-standard-deviation claims.

Selected same-surface four-pixel comparisons retain approximately 9.1–9.3%
timber and 7.7–7.8% metal gap gain during the pan in the noisy affine benchmark.
They are overlapping source-signed pair measurements, not appearance scores or
full-chain separation gains. Native approximate frame comparisons show a modest
effect; no clear general visual acceptance or new effectiveness estimate follows.

Both fixed-grain populations retain roughly 8–9% brightness-reference error
increase across the tested phases, close to instantaneous enhancement. Screen
grain remains correlated over the tested slow motion; surface grain moves with
the material. More frames cannot be presented as a solution to these cases.

The complete changing-noise sequence has a 30-fps comparison replay with baseline,
instantaneous enhancement, RGB temporal and known geometry panels. All 96 FFV1
decoded frames exactly match their PNG references. The MP4 is a lossy viewing
preview; exact images/FFV1 remain the precision reference. A replay artifact does
not establish blind/user acceptance or dense native-game performance.

## Frame-rate target and implementation readiness

The user clarified normal operation is **80–110 fps**. The 30-fps experiment is
controlled feasibility evidence, not validation at that operating range.
The source clock now supports 80/100/110-fps timestamps and a reproducible
80–110-fps variable cadence. It generates distinct commanded states rather than
duplicating a 30-fps clip. The renderer exports these states offline; no achieved
game-rate rendering or production GPU-update cadence is claimed.

The evaluator selects history in elapsed milliseconds. At 100 fps, its default
four observations span approximately 100 ms, with ages 100/70/30/0 ms; four adjacent
frames would instead span only 30 ms and change the model. Actual selected times
are recorded. Matching physical times are tested separately from source labels.

The full 100-fps-clock export has **320 commanded states** over 3.2 seconds,
with 1,280 matched RGB8 control images. All 320 changing-noise updates are evaluated;
surface-fixed grain has 20 matched-time targets. At the 32 exact common physical
times, clean/changing/screen-fixed/surface-fixed RGB8 scene pixels are each
identical across the 30- and 100-fps exports, excluding identity strips. The 20
comparison targets differ by at most 3.33 ms because not all 30-fps times exist
on a 100-fps grid. Independent changing-noise seeds match at exact shared times;
additional high-rate frames use distinct seeds, not repeated noise frames.

| Changing-noise phase | 30-fps source-estimate RMSE | 100-fps RMSE | 30 / 100 brightness-reference error increase |
| --- | ---: | ---: | ---: |
| Stationary | .587 | .586 | 1.65% / 1.65% |
| Camera motion | .566 | .569 | 1.50% / 1.51% |
| Occlusion | .779 | .774 | 4.83% / 4.76% |
| Lighting | .837 | .834 | 4.67% / 4.61% |
| Cut window | .901 | .909 | 6.33% / 6.39% |

The result is stable under this source-rate change when the history window is
held in milliseconds. Surface-fixed grain still incurs roughly 8.5–9.2%
brightness-reference error increase at 100 fps. A second FFV1 replay contains
all 320 CPU comparison updates at 100 fps; decoded images match the PNG references.
This is not a live 100-fps shader or actual production-history validation.

Separate source-clock smoke tests at 80, 100, 110 and variable 80–110 fps each
capture six selected states with an exact first-state repeat. The variable clock
has 9.09–12.5-ms intervals. These sparse tests verify clock/state plumbing;
only the 100-fps-clock run receives the full dense evaluation described above.

There is a working testbed and CPU reference, **no viable real-time shader
candidate yet**. Remaining engineering includes a bounded inexpensive motion
producer, safe invalid-history behavior, a worthwhile full-production-grade
contribution and actual GPU timing/stability/cost checks at the operating rate.
The feature/RANSAC/iterative solver is not a direct vkBasalt port, and test-engine
matrices cannot substitute for a real-game motion input. No credible implementation
date or completion percentage follows from these results.

## Preserved failures and artifacts

The first smoke used upside-down/full-frame texture assets; its client, sources
and manifest remain separate. Final material textures are correctly oriented and
exclude the old HUD area. The first diagnostic coordinate implementation used
integer indices rather than physical pixel centers and rejected zero-weight
bilinear taps at surface boundaries. Its code, inputs and analysis remain under
the initial epoch; corrected centered results supply this report. No initial
oracle or surface-grain result is silently promoted to the corrected epoch.

Local artifacts: `captures/shadow_temporal_course_20261106/`. The original source
exporter version is preserved with a hash matching its recorded identity. No
production shader/profile/config/header/history/resource/pass change, adoption,
commit or push is made. The original Babylon cache and prior failed experiments
remain intact. Runtime remains private/headless; source generation is distinct
from measured GPU history readback and candidate rendering.

Final verification manifests **4,159 local artifacts**, checks the 65 prior
temporal and 158 prior planar artifacts unchanged, and confirms all 17 production
identities. All 22 diagnostic tooling tests and whitespace/link checks pass.
Both lossless CPU replays verify exactly, 416 frames total. All source exports,
evaluations and replay jobs are complete; no runtime is intentionally left active.
