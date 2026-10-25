# Flat-face shading attribution — 2026-10-25

The [initial visual baseline](2026-10-25_visual_baseline.md) exposed shading
inside uniform Babylon target faces. Fresh private headless held captures
isolate contributions from Retinex and zone contrast, rather than shadow lift.
Existing profiles and active configs remain intact. Candidates were tested as
isolated shader copies before adopting the full-resolution reconstruction.

## Attribution

Exact cached source pose 1044/token 262 is looped losslessly at 30 fps.
Six fresh processes capture full/repeat, Retinex-off, zone-off, lift-off and
all-three-off after a five-second compile wait and 20-second continuous settle.
Each output retains the exact identity and activity marker, and every process
reports zero dropped/delayed frames. Only temporary profile copies alter gates.

Source-selected exact RGB masks are eroded eight pixels from boundaries for
interior L95−L5 spread. Boundary measurements use the full source raster to
avoid false crop edges: compare median L within four pixels of a different
source color against the same exact color more than 24 pixels from an edge.
The target ROI is (800,700)–(1840,870). These source faces are spatially uniform;
their output variation is not retained texture. The earlier shader-disabled
replay bounds transfer variation, but global color/brightness shifts remain
intentional grading decisions rather than fidelity scores.

| Source face | Full | Retinex off | Zone off | Lift off | All three off |
|---|---:|---:|---:|---:|---:|
| Magenta interior spread L | 1.705 | 0.589 | 1.547 | 1.705 | 0.203 |
| Purple interior spread L | 1.066 | 1.125 | 0.281 | 1.066 | 0.265 |
| Orange edge minus center L | +2.634 | −0.396 | +3.242 | +2.634 | 0.000 |
| Magenta edge minus center L | +1.334 | +0.268 | +1.115 | +1.334 | 0.000 |

Retinex contributes most of magenta's interior variation and orange's rim;
zone contrast contributes most of purple's variation. Their signed effects
can partially cancel, so bypass contributions are not additive. Shadow lift
does not explain these target artifacts. No blanket reduction of every local
stage is justified by this attribution.

## Candidate development

The existing Retinex gain compares the global zone key with box-filtered local
illuminance. Mixing neighboring materials changes gain inside a flat face.
The first candidate uses the existing guided log-luma base for that comparison,
retaining the ±0.35-stop correction bound and all strength/confidence gates.
Magenta's interior spread falls to 0.729 L, but orange's edge gap increases
to +2.999 L. That candidate is rejected. Its cross-game batch was stopped
after completing dark and sunset cases; this is not a completed regression set.

The next candidate also retains the averaged guide coefficients in the
existing base pass, and evaluates their linear model at the full-resolution
pre-corrective input luma. The original low-resolution base stays in `.r`
for existing consumers; `.g/.b` store mean a/b in RGBA16F. This changes neither
the number of passes nor exposed tuning. Only the Retinex illuminant-gain
consumer uses the new reconstruction; zone contrast, lift, history rates,
chroma's local-variance signal and the adopted coarse-edge halo fix stay intact.

| Measurement | Current | First candidate | Full-resolution candidate |
|---|---:|---:|---:|
| Magenta interior spread L | 1.705 | 0.729 | 0.733 |
| Orange edge minus center L | +2.634 | +2.999 | −0.302 |
| Magenta edge minus center L | +1.334 | +0.932 | +0.391 |
| Purple interior spread L | 1.066 | 1.066 | 1.066 |

Candidate repeats reproduce these values. The orange face loses its bright
outline in the inspected [source/current/candidate/repeat crop](../captures/flat_face_attribution_20261025/upsampled_targets.png).
Purple's zone-driven shading remains. This is a scoped Retinex correction,
not a claim that all local tone-mapping artifacts are resolved.

## Artifacts and verification

Ignored [`captures/flat_face_attribution_20261025/`](../captures/flat_face_attribution_20261025/)
retains source/image/profile hashes, temporary profiles/configs, copied shaders,
capture and analysis scripts, PNGs and JSON records. `report.json` records
the six attribution runs; `guided_report.json` the rejected candidate;
`upsampled_report.json` the full-resolution candidate. `metrics.json` and
`face_edge_metrics.json` hold all face results. Runtime logs are printed as
unique `/tmp/shader-runtime-*/` paths. Shared source hashes are unchanged in
all completed batches so far.

## Held cross-game regressions

Twelve fresh private processes cover before/candidate/repeat for dark GZW,
GZW sunset, vivid Arc input under GZW tuning, and Arc clouds under Arc tuning.
Each uses five-second compile wait and 20-second continuous settling.
All report zero dropped/delayed frames; all shared source hashes remain intact.
The [report](../captures/flat_face_attribution_20261025/upsampled_regressions/report.json),
[region metrics](../captures/flat_face_attribution_20261025/upsampled_regressions/metrics.json)
and inspected contact sheet/native crops remain in the artifact directory.

| Case | Before→candidate mean ΔE | Candidate/repeat mean ΔE | Exact black %, before→candidate |
|---|---:|---:|---:|
| GZW dark | 0.000015 | 0.000011 | 0.006592→0.006592 |
| GZW sunset | 0.395248 | 0.000002 | 0.456652→0.441841 |
| Vivid Arc input, GZW profile | 0.380889 | 0.000003 | 0.263998→0.263482 |
| Arc cloud, Arc profile | 0.346634 | 0.000039 | 0.005724→0.005425 |

No case adds white-channel clipping; source black remains zero where present.
Source-selected sunset shadows move +0.227 L on average, bright pixels −0.075 L.
Arc's bright region changes only 0.00435 ΔE; its 43-pixel vivid selection moves
−1.187 L and is too small to represent broad vivid-material behavior. Inspected
sunset facade/ground, vivid sky/character/roof and Arc cloud/foliage crops show
the expected material structure without a newly obvious outline. These are
scoped regressions, not universal visual acceptance or higher effectiveness scores.

## Matched motion and remaining tradeoffs

Two fresh candidate/repeat replays use the validated cached 15-pose/sec source,
duplicated 30 fps playback, and 20-second initial pre-roll. Cache protocol and
source hashes are checked. Both processes report zero dropped/delayed frames.
Before images are the retained adopted halo fix, not its earlier predecessor.
Only exact decoded three-way source identities enter comparisons.
[Motion report](../captures/flat_face_attribution_20261025/upsampled_motion/report.json),
[region measurements](../captures/flat_face_attribution_20261025/upsampled_motion/region_metrics.json),
and [inspected matched contact sheet](../captures/flat_face_attribution_20261025/upsampled_motion/contact_sheet.png).

| Window | Matched identities | Before→candidate mean ΔE | Candidate/repeat mean ΔE |
|---|---:|---:|---:|
| Foliage | 1 | 0.27498 | 0.02268 |
| Clearing | 5 | 0.14518 | 0.04153 |
| Corridor | 4 | 0.00260 | 0.00229 |

Magenta interior spread falls from 0.717–1.796 to 0.498–0.766 L across all five
clearing poses; repeats span 0.498–0.861. Its edge gap falls from 0.990–1.647
to 0.270–0.382 L. The three poses with the exact selected orange RGB reduce
their edge gap from +1.405–2.807 to −0.302 L in both candidate runs. Other
poses have a slightly different source orange code and are excluded from that
exact-color statistic. The matched crops retain the obvious rim reduction.

Purple's interior spread is unchanged, but its edge gap worsens on poses
1020 and 1116: 0.328/0.467→0.734 L. This is a retained tradeoff, smaller than
the removed orange/magenta outlines; next attribute zone contrast's spatial
field rather than asserting all targets improve. Sky border gaps remain
within 0.37–0.88 L across these before/candidate/repeat frames. The corridor
change is comparable to repeat variation and does not establish an improvement.
Sparse matches and repeat differences do not prove dense continuity or full
matched cut coverage, although cut windows were captured.

## Adoption

The full-resolution candidate is now applied in `general/grade/grade.fx`.
Its executable code matches the tested copy after normalizing include paths
and removing comments. Shader header comments, profiles, active configs,
shadow-toe/zone-precision changes and the earlier coarse-edge halo correction
are preserved. Twenty diagnostic tests and `git diff --check` pass.
Three final fresh shared-path captures complete verification. GZW sunset matches
the validated candidate to 0.000024 ΔE, and Arc cloud to 0.000002. The active
Arc chain control matches its retained unchanged output to 0.000023; its
cross-effect resource limitation still means this control does not validate
adaptive behavior. All three report zero dropped/delayed frames. Profiles and
all source files other than the intentional grade change retain their original
hashes. [Applied-path report](../captures/flat_face_attribution_20261025/applied_report.json).

Next work is the remaining zone-driven flat-face shading, then shelf shadow
color and sunset stage interactions. The bounded local purple-edge tradeoff
and sparse motion coverage remain explicit; live visual acceptance and the
75+ effectiveness target have not been established.
