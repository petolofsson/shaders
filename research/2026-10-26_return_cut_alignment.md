# Return-cut presentation and history alignment — 2026-10-26

Resolves the apparent 1.588 mean ΔE repeat outlier at pose 2160:541 from the
[zone follow-up](2026-10-26_zone_scene_pivot.md). Those images shared source
pose/token labels but represented different GPU updates of that duplicated
pose. Measured phase-aligned repeats are stable. Production shader behavior,
profiles, histories/rates and active configs are unchanged in this audit.

## Source and capture protocol

The cached lossless clip has two identical presentations of pose 2160:541:
video frames 1680/1681 at PTS 56.000/56.033 seconds. Frame 1682 at 56.067 is
already pose 2164:542. Direct decoding recovers the original cached RGB pixels
exactly. Host `time-pos` is not a GPU presentation identifier: the old outlier
was requested at 56.067 but the captured image still labeled pose 2160.

Four fresh private headless replays capture two unchanged full-chain runs and
two runs bypassing only Retinex in temporary profile copies. They use the
current combined GZW trial, five-second compile wait and the original
20-second pre-roll. All source-frame, manifest and clip hashes are checked.

An eight-second readback tail is appended after the original clip. All 1,710
original compressed video-packet payloads and timestamps match the new clip's
prefix exactly; the 240 appended packets are only for reading already frozen
diagnostics. No source frame, route, speed, pre-cut input or settling protocol
is altered to create the phase match.
The causal image comparison uses the first two cut updates, both inside that
unchanged prefix; late ring records in the appended tail are not motion evidence.

## Explicit same-update GPU readback

An isolated diagnostic technique decodes the original source-pose label before
analysis/inverse grading. An RGBA32F clock tracks actual GPU updates, updates
within the current pose, and updates since crossing the return cut. This is
independent of host screenshot timing and the duplicated video labels.

The technique copies the native scene-cut history before its update. Immediately
after the actual color transform, it records the context used by that image,
native percentiles, old/new cut records, authoritative slow key, adaptive
previous/used controls and frame-time uniforms. A 64-row RGBA32F ring freezes
32 updates before and 32 at/after the cut. Two full-resolution RGBA32F textures
freeze the first and second actual graded outputs. Recording precedes the
adaptive-history update, so the captured controls are the ones used for that
image, rather than an extra computed temporal step.

The appended tail displays the frozen images and 24-bit binary-encoded records.
Ordinary screenshots are not treated as hidden telemetry. Image metrics mask
the outer eight pixels, excluding the diagnostic tag, marker and source label,
and sample every fourth pixel, matching the retained motion measurements.
Numeric readback is independently scaled per field and update ages are rounded
to integers; its precision is sufficient to distinguish adjacent updates.

All four successful replays have zero dropped/delayed frames and clean vkBasalt
logs. Their first two GPU updates both decode pose 2160:541, with pose-update
ages 1 and 2. No source identity is inferred from host time.

## Cause of the difference

| Image state | First update | Second update |
|---|---:|---:|
| Source pose/token | 2160:541 | 2160:541 |
| Updates since return cut | 1 | 2 |
| Scene-cut confidence | 1 | 0 |
| Retinex adaptation gate | 0 | 1 |
| Zone key | 0.235352 | 0.235352 |
| Zone standard deviation | 0.217407 | 0.217407 |
| Published p50, representative run | 0.008453 | 0.008804 |

The raw-entropy history changes approximately 0.065674→0.676758 on the first
new image, triggering the cut. On the second identical source image its delta
is zero; the p50 delta remains well below its cut threshold. Thus the cut flag
correctly falls to zero. `BuildSceneCtx` consequently changes its adaptation
gate from zero to one, enabling Retinex on the second update. The live zone
key/spread and used adaptive film/lift/print/gamut controls do not make a large
change between these two images. Slow-key differences are small and consistent
with elapsed-time updates, not false initialization or lost accumulation.

| Comparison | Mean ΔE, Oklab ×100 |
|---|---:|
| Full first→second, run A | 1.588273 |
| Full first→second, run B | 1.588243 |
| Full first→first, A/B | 0.000364 |
| Full second→second, A/B | 0.000426 |
| Retinex-off first→second, run A | 0.038319 |
| Retinex-off first→second, run B | 0.038427 |
| Retinex-off first→first, A/B | 0 |
| Retinex-off second→second, A/B | 0.000192 |

In run B, full and Retinex-off first images are identical on the sampled
interior: Retinex was already gated off. Their second images differ by about
1.580864 mean ΔE. The controlled bypass therefore identifies the main response
as the existing Retinex cut-confidence handoff, rather than assuming that
every temporal filter must be reset or accelerated. The smaller remaining
first/second difference includes real percentile/context evolution.

Mapping the retained images to these frozen phases resolves the apparent
outlier. Retained `repeat-0` matches the first phase at 0.000000 ΔE and
`repeat-2` at 0.000188; `repeat-1` matches the second at 0.000373. The retained
candidate-1/candidate-2 also match the second at 0.000747/0.000303. Comparing
candidate-2 with repeat-2 had therefore compared update 2 with update 1.
The old numbers are retained; their interpretation as a phase-aligned repeat
is corrected.

The one-update Retinex handoff is a real, deterministic tonal transition. This
audit does not erase it or certify its perceptual unobtrusiveness. Dense native
gameplay, other cuts and physical high-refresh acceptance remain open. What is
resolved here is the repeat uncertainty at this specific return pose.

## Tooling correction and verification

`tools/babylon_scene/background.py` now explicitly labels ordinary summaries as
source-pose/token matches and counts verified render-phase matches separately.
`matched_motion` and `summarize_motion` accept `require_render_phase=True` for
captures with explicit GPU-derived `render_phase` records containing integer
`source_update` and `cut_update` ages. Strict mode rejects missing, invalid or
mismatched phases, and still requires coverage of every requested window.
It never manufactures phase data from pose labels or mpv timestamps.

The final artifact audit verifies successful image, diagnostic, shader, profile
and config hashes, completed vkBasalt logs, all 32 recorded post-cut ages and
the original-image phase classification. All production shader/profile/trial
config hashes remain identical to this audit's starting state. See the local
`verification.json` and `prefix_verification.json` manifests.

Two new diagnostic tests exercise a duplicated pose with conflicting phases
and reject host-time-only records. Existing source-only comparison behavior
remains available and is labeled honestly. All 22 diagnostic tests pass.

Ignored [captures/return_cut_20261026/](../captures/return_cut_20261026/) retains
source/prefix verification, the isolated diagnostic, exact shader/config/profile
hashes, all four readback runs, frozen images, native records, metrics and crops.
The first probe failed compilation on an unsupported `fmod` intrinsic; its
shader and log are retained. The next stopped before the cut at the existing
50-second transport-wait limit; its runner/log are retained. Replacing the
intrinsic and splitting the wait produced the four successful runs. Neither
failure required a production shader repair or desktop fallback.

The subsequent [Retinex sky repair](2026-10-26_retinex_sky.md) retains the cut
gate and uses GPU-frozen output/state for 14 phase-matched motion samples.
