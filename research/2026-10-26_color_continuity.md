# Hue continuity and additional material coverage — 2026-10-26

Follow-up: the [blue-cusp repair](2026-10-27_gamut_continuity_repair.md) is now
applied. This report preserves the preceding assessment and its original state.
The separate [wall/sky attribution](2026-10-27_wall_sky_attribution.md) is also
complete, with no further production edits. Broader current-set material and
highlight coverage is now [assessed](2026-10-27_material_highlight_coverage.md);
temporal/resolution coverage is next.

Continues PLAN 3 after the completed zone/Retinex repairs. This is an assessment
of current shared code, with isolated local bypasses and unchanged profiles.
It identifies a separate blue-cusp gamut-search limitation; it does not certify
broader color behavior or change production shader math.

## Inputs and method

A 2560×1440 diagnostic chart contains twelve horizontal hue sweeps: six
maximum sRGB codes (8, 16, 32, 64, 128, 255), each at HSV saturation 1 and 0.6.
Twelve further rows sweep brightness at fixed hues spaced by 30 degrees.
The source is rounded to 8-bit before lossless RGB video creation. Consequently,
these are quantized smooth ramps, not infinitesimal derivatives. It is a GPU
diagnostic input, not a restored golden-image regression fixture.

Both existing profiles process that same chart. Two additional native gameplay
inputs broaden held coverage: GZW `autof_20260515_133322.png` (dark colored
barrels/bins and concrete), and Arc `autof_20260515_210621.png` (sunlit yellow
wall, dark opening, sky and lit ground). Each case uses full output, an unchanged
full repeat, a chroma-stage bypass and a look-stage bypass. Bypasses are local
profile copies; no production profile is edited.

All captures use fresh private headless processes, five seconds for compilation
and twenty seconds of continuous playback. Combined-trial techniques retain
the live adaptive data path. Source, clip, shader, profile, config and output
identities accompany the captures. This fixed settling protocol does not prove
complete convergence of every history. Ordinary held images contain no highway
telemetry. Source-selected region quartiles define low/high lightness groups;
measurements use those same groups in every output. Hue differences exclude
source/output chroma at or below 2 on the Oklab ×100 scale.

## Reproducible blue step

At chart row 3 (saturation 1, maximum code 64), adjacent columns 1709/1710
change source RGB `(0,0,64)`→`(1,0,64)`. Averaging 32 identical-source
scanlines reduces spatial dither before Oklab conversion. Source change is
0.286109 ΔE. Output changes are:

| Profile | Full | Chroma bypass | Look bypass |
|---|---:|---:|---:|
| GZW | 3.031499 | 3.032234 | 3.387757 |
| Arc | 2.731126 | 3.057944 | 3.024264 |

The same discontinuity therefore survives both isolated stage bypasses. In GZW,
mean output codes jump approximately `(0,5.8125,45.5)`→`(0,0,59.5625)`.
This is a measured amplification of a one-code source step, not a claim that
all ramp banding comes from the shader. Very dark source rows already contain
large Oklab steps and unstable hue angles from 8-bit quantization.

## Radial gamut assumption

`OklabToSDR` bisects a chroma scale from the neutral axis, assuming valid SDR
colors form one continuous interval along every fixed-lightness/hue ray.
The actual conversion matrices violate that assumption near saturated blue.
For source `(0,0,64)`, the CPU matrix evaluation gives:

| Relative source chroma | Linear red | Linear green | Linear blue |
|---|---:|---:|---:|
| 0.7 | 0.0002689 | 0.0027401 | 0.0311411 |
| 0.8 | 0.0000588 | 0.0019705 | 0.0371699 |
| 0.9 | −0.0000322 | 0.0010594 | 0.0438677 |
| 0.95 | −0.0000318 | 0.0005486 | 0.0474784 |
| 1.0 | approximately 0 | approximately 0 | 0.0512695 |

The ray leaves gamut and returns near its outer endpoint. A search that first
rejects the intervening negative-red interval can discard that outer region.
The existing ±1e-6 initial face guard correctly preserves valid originals;
it cannot make the intervening interval valid or repair the search assumption
when a genuinely out-of-gamut chroma expansion invokes projection. Widening
that numerical tolerance would conceal real negative values.

## Additional gameplay findings

All four full/repeat pairs are byte-identical. The sixteen main processes
report zero dropped/delayed frames. Full-raster endpoint counts exclude only
the intentional 2×2 marker. Neither gameplay full output has a white-channel
pixel or loses any exact source black. GZW adds one black pixel from source
`(2,2,2)`; Arc adds twelve from source codes no greater than 2. These are
source→current output costs, not regressions against a proposed repair.

The source-defined low/high groups retain the following Oklab lightness gaps:

| Region | Source | Full | Chroma bypass | Look bypass |
|---|---:|---:|---:|---:|
| GZW blue barrel | 8.567380 | 8.799860 | 8.810576 | 9.275224 |
| GZW rust barrel | 6.525695 | 6.877840 | 6.876700 | 7.078857 |
| GZW red barrel | 7.994319 | 8.346007 | 8.343846 | 8.640837 |
| GZW blue bin | 8.033038 | 8.276492 | 8.303998 | 8.418238 |
| Arc sunlit yellow | 9.924446 | 8.623788 | 8.613517 | 8.619078 |
| Arc yellow boundary region | 30.700392 | 29.104077 | 29.086074 | 29.237406 |
| Arc dark opening | 6.306783 | 6.407105 | 6.407355 | 6.825982 |
| Arc sky | 8.125487 | 7.238588 | 7.258640 | 7.143726 |
| Arc lit ground | 28.664960 | 27.564939 | 27.568286 | 26.748028 |

This additional sky and yellow-wall input still has lower source-defined shade
separation in the full output. Neither chroma nor look bypass restores those
gaps to source values. That is a recorded tonal/inverse interaction for further
attribution, not evidence to undo the completed Retinex repair or to force
source-equal contrast everywhere. Larger gaps alone do not establish quality.
The yellow boundary rectangle includes mixed lighting/materials; it is not a
flat-face halo test or proof that every illumination boundary is clean.

Median blue-bin chroma changes 3.762791→5.718343 (chroma bypass 4.480416).
Sunlit yellow changes 7.716136→8.254751 (bypass 7.712505). Dark-opening median
chroma changes 1.765766→0.861851 and rust-barrel chroma 1.305433→0.555585;
these low-chroma populations cannot support strong hue-angle conclusions.
Only 90 rust-barrel and 22 red-barrel full-output samples pass the stated hue
gate. The gray-barrel and concrete regions have no qualifying samples.

Downsampled source/full review shows retained barrel/wall structure and visible
lighting boundaries, with the existing profiles' differing color response.
This is limited visual inspection, not acceptance of all hue relationships,
colored-highlight shape or the complete chain. Removing the look introduces
1045 white-channel pixels in GZW and 6 in Arc, compared with zero in full;
bypass comparisons therefore include genuine stage cooperation and should
not be interpreted as independent effect-quality scores.

## Focused GPU confirmation and disposition

Two additional GZW chart captures isolate the projection. Disabling inverse
reconstruction leaves the selected blue step at 2.914942 ΔE. Replacing both
calls to the shared projection helper with direct RGB clipping in an isolated
shader reduces it to 0.151282. That destructive diagnostic changes the selected
absolute blue response and discards fixed-lightness/hue protection; it is not
a candidate repair. The shared helper is implicated beyond inverse expansion.

Two fresh private headless GPU probes call the actual current `OklabToRGB` and
`OklabToSDR` helpers on 64 controlled inputs: four blue amplitudes, four small
red offsets and four chroma scales (1, 1.001, 1.01, 1.05). Each call writes an
RGBA32F target; a later pass explicitly encodes all four fields into binary
screen strips. These are 128 direct numerical records per process, separate
from ordinary image metrics. Repeated readbacks are identical and both processes
have zero dropped/delayed frames. Raw matrix output agrees with the CPU oracle
within 0.000000546. Projected RGB stays within the bounded encoding tolerance
of [0,1].

A CPU scan of 65,537 radial scales followed by boundary refinement finds two
valid runs in twelve tested inputs. For source `(1,0,255)` with chroma expanded
by 1.001, GPU projection retains 0.864257705 of target chroma, while the highest
feasible fraction is approximately 0.999001033. The difference is 0.134743328
of target chroma. The outer point corresponds to the original SDR color,
which is also directly exercised at scale 1. This is a valid-interval search
failure, not evidence of output overflow or a storage-history defect. The
CPU interval scan is diagnostic evidence, not proposed shader code.

No production repair is applied in this assessment. Simply finding a higher
valid interval is not sufficient to establish continuity as hue changes and an
outer interval appears or disappears. Next work must address both the search
assumption and continuity around the cusp, preserve exact in-gamut identity
and the existing face-roundoff guard, and validate shared inverse/final-grade
consumers. The current RGB-clipping control must not be promoted as a fix.
Retain the prior signed/overrange contracts and final SDR ceiling. Do not
compensate by retuning profiles or weakening all blue colors.

## Retained evidence and limits

Ignored `captures/color_continuity_20261026/` contains:

- `run.py`, `report.json`, source chart/layout, lossless clips, isolated configs,
  shader/profile snapshots, sixteen main images and source/config/output hashes.
- `analyze.py`, `metrics.json`: source-selected rectangles, quartile-group gaps,
  endpoint counts, ramp steps and four unchanged-repeat checks.
- `diagnose.py`, `diagnose_report.json`, `diagnose_metrics.json`: inverse bypass
  and projection-clipping attribution controls.
- `probe.py`, `probe_report.json`: controlled inputs, explicit GPU readback,
  interval oracle and unchanged numerical repeat.
- `audit.py`, `audit_report.json`: 104 artifact hash checks, all twenty successful
  capture records and unchanged shared shader/profile/trial-config identities.

The initial sandboxed runtime attempt failed to start its private display;
`/tmp/shader-runtime-4c9qxajn/` retains that failure. The successful batch used
sandbox escalation and never fell back to the desktop. All twenty successful
processes report zero dropped/delayed frames. The 22 diagnostic tooling tests
pass and `git diff --check` is clean. The tools check capture/error contracts;
they do not certify visual quality.

Production shaders, profiles, active configurations and the completed zone,
Retinex, history and signal repairs remain unchanged. Active separate effects
still lack shared analysis resources. No dense-motion, physical-high-refresh,
new-game, complete colored-highlight or general visual-acceptance claim follows.
There is no effectiveness re-score, golden suite, new effect or GPU profiling.
