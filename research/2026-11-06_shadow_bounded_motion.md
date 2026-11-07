# Bounded-work temporal motion screen

The expensive feature/RANSAC motion producer now has a fixed-work CPU alternative.
It retains useful temporal support in the controlled course, including when
estimated from the whole frame. This narrows the implementation blocker; it
does not establish an inexpensive GPU producer or authorize a shader change.
Production, profiles, configs and all effectiveness estimates remain unchanged.

## Algorithm and runtime path

`tools/temporal_course/bounded_motion.py` fits six affine displacement coefficients
from observed code-luminance only. Two box-averaged guides, at 1/16 and 1/8 scale,
use the same 24×16 grid and three robust updates each. There are 2,304 sampled
moment observations and six small solves per adjacent source pair. Each solve
uses a Schur complement and two explicit 3×3 inverses. No corners, descriptors,
matching, RANSAC, SVD or variable iteration count remain.

This is a direct photometric alignment reference, informed by the
[Lucas–Kanade framework](https://publications.ri.cmu.edu/storage/publications/pub_files/pub3/baker_simon_2004_1/baker_simon_2004_1.pdf),
not an implementation of every method in that paper. Normalized coordinates,
regularization, robust residual weights, capped updates and explicit validity
checks bound the numerical work. Flat and single-direction aperture fixtures
reject history. Adjacent matrices compose to the existing four observations
over 100 ms. The original 19-pixel history range and 2-code local-RMS/3-code
point residual checks remain unchanged. Scene IDs, clean images and known
geometry do not enter estimation or acceptance.

A possible GPU implementation needs current/previous guides, coefficient state,
six ordered reduction/solve updates, and timestamped coefficient history.
Brightness reconstruction additionally needs image history. The work count is
bounded, but GPU latency, reduction layout, bandwidth and added pass cost are
unmeasured. The Python vectorized reductions do not establish GPU equivalence.
Existing grade guides are not a free substitute: their source domain/filter
kernel differs from this code-domain box average. No production resource or
pass has been added. Odd dimensions and source loss still need a concrete port
contract. Global affine motion cannot represent independent object motion or
general parallax.

## Matched controlled evidence

Artifacts: `captures/shadow_bounded_motion_20261106/`. Inputs are the frozen
[JavaScript course](2026-11-06_temporal_course_results.md), including timestamped
100-fps source images, RGB8 changing noise, clean images and surface-fixed grain.
These are offline source clocks, not achieved FPS or measured GPU updates.
The scalar affine brightness benchmark remains separate from the full grade.

The first crop-only estimator retained steady motion but rejected substantial
occlusion/lighting history. Whole-frame estimation was then tested explicitly;
the material crop is used only for scoring and reconstruction. In the same
20 selected target updates, whole-frame changing-noise results are:

| Phase | Source error, codes RMS | Mean enhancement support | Conditional brightness error / baseline |
| --- | ---: | ---: | ---: |
| Stationary | .579 | .963 | 1.0128 |
| Camera motion | .556 | .935 | 1.0094 |
| Occlusion | .835 | .530 | 1.0093 |
| Lighting | .831 | .589 | 1.0083 |
| Cut and recovery | .920 | .216 | 1.0014 |

The input changing-noise RMS is about 1.04 codes. Selected steady-motion
alignment-only signed 16-pixel material gaps improve about 8.77% for timber and
7.73% for metal. These are selected same-surface measurements, not a full-grade
appearance score or a universal separation gain. The native comparison remains
subtle; no clear naked-eye full-grade improvement is established.

The evidence gate is an explicit ablation: multiply the existing source gate by
smoothstep(1,4,accepted observation count), then recompute the weighted pivot.
It preserves the zero-mean/two-code/SDR budget and returns the exact baseline
when no history supports enhancement. It prevents the old single-frame fallback
from retaining the full noisy enhancement. It also sacrifices brightness
recovery: conditional-ideal error ratios above compare with the *reduced*
enhancement, using observed support. They must not be presented as equal-strength
noise results. Error against the original full-strength ideal is also recorded.
The gate gives unsupported pixels zero correction. No temporal smoothing of
support is introduced or claimed; pumping and spatial confidence boundaries
remain open costs.

Persistent surface grain retains high apparent support and gets amplified.
Accepted image history without known visible correspondence remains about
0.59% in selected camera motion, 5.92% occlusion, 4.78% lighting and 14.04% in the
cut/recovery window. Those fractions include range/context exclusions and are
not visible ghost rates or proof of cross-cut reuse. Ground-truth visibility is
diagnostic only. This is still insufficient evidence for unrestricted reuse.

## Verification and preserved epochs

Two dense 320-state 100-fps-clock runs cover the original crop model and the
whole-frame supported model. Selected clean, surface-fixed, 30-fps-clock and
support ablations remain separate. `summary.json` distinguishes full-phase dense
results from selected windows; do not substitute the favorable selected pan for
the entire camera segment. The dense whole-frame run gives:

| Whole phase | States | Source RMS | Conditional error / baseline | Timber / metal gap gain |
| --- | ---: | ---: | ---: | ---: |
| Stationary, including startup | 54 | .644 | 1.0120 | 8.26% / 6.88% |
| Camera motion | 106 | .633 | 1.0108 | 7.90% / 7.11% |
| Occlusion | 54 | .802 | 1.0088 | 6.55% / 6.23% |
| Lighting | 53 | .807 | 1.0125 | 7.19% / 5.18% |
| Cut and recovery | 53 | .776 | 1.0027 | 6.01% / 5.41% |

The dense camera result is less favorable than the selected .556-code result.
Its error against the original full-strength ideal is 1.0412× baseline error,
showing the cost of attenuating the requested recovery. Surface-fixed selected
camera error remains 1.0864× baseline even against the conditional ideal.

All input, geometry and original model identities
are checked. Earlier 30/100 course artifacts remain byte-identical.

The small solver agrees with 100 conventional double-precision SPD solves to
1.21e-10 absolute error. Seventeen actual crop pairs agree on validity in FP32
and FP64, with maximum predicted-corner difference below .000048 pixels.
These are CPU arithmetic checks, not GPU readback. Identity, aperture rejection,
zero-support baseline, zero mean, SDR headroom and two-code bounds are checked;
the existing 22 diagnostic tests pass. The initial bounded source is frozen
separately. `rate100_support_gate` preserves an early reporting error: point and
oracle comparisons there used the conditional ideal. Use `support_gate_final`
and subsequent reports for those comparisons. No failed epoch is relabeled.
The final audit freezes 1,141 artifacts, verifies 4,382 previous artifacts and
all 17 production identities. No runtime was launched in this screen, and no
processing job is intentionally left active.

## Decision

Retain the bounded solver as a concrete motion-producer research lead. Do not
port the old feature matcher or claim real-time feasibility from these results.
The next decision requires stable support through moving boundaries plus a
worthwhile full-grade/native case; persistent grain remains a separate blocker.
Only then does an isolated GPU producer/readback port have a justified target.
No production adoption, score increase, profile edit, commit or publication
follows this screen.
