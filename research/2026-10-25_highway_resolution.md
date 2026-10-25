# Metadata texel identity across resolutions — 2026-10-25

Continues the technical producer/consumer audit after the
[percentile initialization correction](2026-10-25_percentile_initialization.md).
`ReadTexHwyData` uses a coordinate based on full framebuffer width rather than
the allocated metadata texture's integer width. At widths not divisible by
eight, bilinear filtering blends neighboring fields.

## Contract and isolated candidate

`TexHwyTex` has integer width `BUFFER_WIDTH / 8`. Column c must be sampled at
`(c + 0.5) / texture_width`. The original expression instead uses
`(c + 0.5) * (8.0 / BUFFER_WIDTH)`. These agree for divisible widths but diverge
when texture dimensions truncate the remainder. At W=1366 the texture width is
170, not 170.75. Column 7 is approximately 0.032943 texels left of its center.

The candidate changes only that denominator to `float(BUFFER_WIDTH / 8)`.
Texture dimensions, metadata layout, linear sampling, pass order, profiles,
analysis values and time constants remain unchanged. All metadata aliases share
the corrected reader. The previous all-pixel median and percentile initialization
corrections are retained.

This can affect history as well as immediate reads: `ComputeSlowKey` reads its
previous value from column 7 beside column 6's current zone key. A blend weight
w changes a nominal update coefficient alpha to `alpha + w - alpha*w` when
the neighboring value equals the current target. Thus a coordinate error can
create unintended per-update adaptation even though the time-based formula is
unchanged. This is an inference from the data flow and measured slot blending;
no measured physical slow-key half-life is claimed here.

## Explicit GPU texel-identity probes

A temporary two-pass technique writes known exactly representable half-float
RGBA values into each of eight metadata columns across all five data rows.
Alternating column values expose cross-column mixing; distinct row values expose
vertical misaddressing. Alpha alternates between -0.25 and +0.25, so signed
metadata is checked too. Output tiles explicitly render the absolute read error
multiplied by 16 before sRGB encoding. No test error reaches that encoding's
ceiling. These are deliberate diagnostic outputs, not telemetry inferred from
ordinary screenshot scene pixels.

The output also encodes the compiled `BUFFER_WIDTH` and `BUFFER_HEIGHT` as binary
cells; every capture must decode to its requested resolution. The private
compositor therefore cannot silently round an odd-size test into a normal-size
pass. Each case uses a fresh private headless process, five-second compilation
wait and 20-second continuous playback. The 1366x768 candidate has an unchanged
repeat. Eleven processes report zero dropped/delayed frames.

| Compiled dimensions | Original max RGB error | Original max signed-alpha error | Candidate max error, all 40 slots |
|---|---:|---:|---:|
| 1366x768 | 0.023516 | 0.015635 | 0 |
| 1366x769 | 0.023516 | 0.015635 | 0 |
| 1919x1079 | 0.020486 | 0.013720 | 0 |
| 1920x1080 | 0 | 0 | 0 |
| 2560x1440 | 0 | 0 | 0 |

The primary candidate repeat also measures zero error in all four channels at
all 40 slots. The continuous coordinate-error model agrees with the original
measurements within 0.002 raw units, including finite subtexel filtering and
encoded capture precision. Divisible-width controls remain exact.
[Error overview](../captures/highway_resolution_20261025/metadata_error_overview.png).

## Full-chain comparisons

Twelve fresh private headless before/candidate/repeat processes assess vivid
Arc input under the existing GZW profile and Arc clouds under the Arc profile,
at 1366x768 and 2560x1440. Each source is prepared as RGB with Pillow LANCZOS
resampling to the stated size, retaining original and prepared PNG hashes.
Before/candidate/repeat use the exact same prepared source within each case;
cross-resolution images are not treated as matched native pixels. The shared
working shaders remain untouched throughout these isolated candidate batches.
All twelve processes use five-second compilation wait and 20-second continuous
playback, and report zero dropped/delayed frames.

| Input / profile / resolution | Before/candidate mean Delta E | Candidate/repeat mean Delta E |
|---|---:|---:|
| Vivid Arc / GZW / 1366x768 | 0.141074 | 0.000006 |
| Vivid Arc / GZW / 2560x1440 | 0.000000 | 0.000002 |
| Arc clouds / Arc / 1366x768 | 0.109889 | 0.000008 |
| Arc clouds / Arc / 2560x1440 | 0.000000 | 0.000000 |

Full-raster comparisons exclude only the intentional 2x2 marker. No case adds a
newly black pixel or newly white-clipped pixel; source black remains zero in
all four cases. Vivid low-resolution black coverage decreases 0.269664% to
0.263182%, with an identical candidate repeat; other black coverage is unchanged.
This is a bounded regression result, not a quality score. The inspected contact
sheet retains scene structure without a newly obvious artifact. Ordinary output
captures establish engagement and regression scope; the explicit metadata probe
establishes field identity.

## Adoption

The one-line correction is applied in `general/common.fxh`, which exactly
matches the isolated GPU-tested candidate. Twenty diagnostic tests and
`git diff --check` pass. Headers, profiles, active configs, prior corrections,
history formats and time constants remain intact. Other shared shaders do not
change in this validation/adoption.

Two final fresh captures run the shared combined pipelines at 1366x768, with
GZW and Arc profiles. Applied/candidate mean Delta E is 0.000006 and 0.000075;
both report zero dropped/delayed frames. These small differences are retained,
not presented as exact output determinism; the Arc value exceeds its particular
candidate/repeat delta. Header equivalence is established independently by exact
file comparison, and protected hashes show that only `general/common.fxh`
changes across validation/adoption. `verify_report.json` retains the images and
measured differences.

## Next separate precision investigation

The slow-key recurrence is also stored through half-float history. A CPU model
of its unchanged 20-second half-life, initial key 0.10 and target 0.20, rounds
the state to float16 after each update. At 30 / 60 / 144 updates per second it
stalls around 0.147217 / 0.125 / 0.099976 respectively, rather than reaching the
ideal 0.15 at 20 seconds and 0.1875 at 60 seconds. This is a separate storage-
precision hypothesis, not GPU-confirmed behavior or a fix in this change.
GPU-isolate it next; do not change the intentional half-life to compensate.
The retained CPU assumptions/results are `slow_key_precision_cpu.json`.

Follow-up: [GPU slow-key precision verification](2026-10-25_slow_key_precision.md)
now confirms the feedback defect and adopts a format/read correction with the
same half-lives. GPU values differ from the earlier CPU rounding assumptions;
use the measured follow-up for quantitative behavior.

## Artifacts and limits

Ignored [captures/highway_resolution_20261025/](../captures/highway_resolution_20261025/)
retains common/stage/pipeline snapshots, arithmetic diagnostic sources, actual
compiled-dimension readback, configs, images, scripts and hashes. The known
pattern is a contract probe, not a restored golden-image suite. Header comments,
profiles, active configs and earlier working-tree changes are preserved.

The active separate effects' cross-effect resource limitation remains unresolved.
This correction does not make those resources shared or establish complete
adaptive-chain behavior there. Other filter-kernel spacing, frame-rate behavior
and dense gameplay motion at unusual resolutions are not certified by metadata
texel identity alone. No score change, new effect or GPU profiling is implied.
