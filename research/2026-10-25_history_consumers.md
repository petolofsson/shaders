# Remaining history consumers — 2026-10-25

Continues the [slow-key precision repair](2026-10-25_slow_key_precision.md).
This audit identifies which remaining histories influence the combined pipeline
before deciding where a precision or initialization repair would matter.
No shared shader, profile, active config, rate or header comment changes.

## Per-hue histories have no live image consumer

`UpdateHistoryPS` writes six hue-band records in `ChromaHistoryTex` row 0,
columns 0–5. Each record contains mean C, standard deviation, weighted sample
count and posterior covariance. `UpdateChromaKalman` reads the prior record
through `ReadTexHwyChroma(0, band_idx)`, hence through the RGBA16F publication
even though the underlying history was widened for slow key.

Searching all shared and game shader sources finds no image consumer of those
six records. Grade's only chroma-record reads are column 6 (zone key/std) and
column 7 (slow key). Its vibrance pivot is `HueCeil(h_out) * 0.5`; creative
per-band hue rotation and saturation use pixel hue weights and profile knobs,
not per-band statistical histories. Those creative controls remain live.

Consequently neither widening the six filters' feedback nor repairing their
initialization can currently improve the ordinary rendered image. Restoring
their use would change the chroma algorithm and requires a separate reason.
This finding does not make the live zone and slow-key columns disposable.

## GPU consumer perturbation

Isolated corrective copies retain the current baseline or replace only the
six band records with either `(0,0,0,0)` or `(0.25,0.125,8,1)`. Columns 6/7,
zone history, scene analysis, processing logic and profiles remain unchanged.
The high payload exceeds the normal mean-C clamp and covers maximum possible
eight-sample weight; it remains finite and exactly representable in half float.

A temporary grade copy explicitly renders all four channels from all six
records, both directly and through their metadata publication, as 24-bit
binary cells. Weighted count is divided by eight for encoding. This proves
that both perturbations reach actual GPU state and its publication. The
readback occupies rows 2–7; all comparison metrics exclude an eight-pixel
border, which also excludes the activity marker. Ordinary scene output is
never interpreted as hidden telemetry.

Three held sources cover dark GZW, vivid Arc input under GZW tuning, and Arc
clouds under the Arc profile. Each has fresh baseline/zero/high/baseline-repeat
processes with five-second compile wait and 20-second continuous settling.
This protocol bounds unchanged capture/history variation; it does not prove
full slow-key convergence. Sources and lossless clips are hashed, together
with shared shaders, profiles and both trial configs.

All twelve processes report zero dropped/delayed frames. All 48 normalized
readback fields in every zero/high capture agree with their requested payload
within two 24-bit encoding codes, verifying direct state and publication.

| Source / profile | Baseline→zero mean Delta E | Baseline→high mean Delta E | Baseline→repeat mean Delta E |
|---|---:|---:|---:|
| GZW dark / GZW | 0.00001660 | 0.00002104 | 0.00001855 |
| Vivid Arc / GZW | 0.00000526 | 0.00000455 | 0.00001089 |
| Arc clouds / Arc | 0.00000057 | 0.00001868 | 0.00002270 |

Delta E summaries use the existing every-fourth-pixel interior sample. Separate
full-interior comparisons find at most one code of channel difference in every
comparison. Changed-pixel counts for zero/high/repeat are 375/376/381 (dark),
63/72/130 (vivid), and 30/348/363 (clouds). None adds black pixels or pixels with
a white-clipped channel. Differences are comparable to unchanged-repeat
variation, rather than consistently zero or always below that repeat.

Together with the exhaustive source trace, this supports the absence of an
ordinary image dependency on those records. It does not establish universal
determinism, temporal quality or the safety of deleting adjacent live fields.
No runtime change is adopted from this audit.

## Inventory of remaining state

The following is a source-level data-flow inventory, not GPU certification of
each recurrence. Authoritative feedback and publication are distinguished.

| State | Authoritative feedback | Live downstream use / initialization |
|---|---|---|
| `LumHistTex` | R16F self-history; alpha `saturate(0.0043 * frametime)` | Percentiles, mode and entropy. Starts from zero; CDF/entropy normalize histogram mass. Raw histogram is not a history. |
| `PercTex` | RGBA16F self-history; VFF Kalman | Grade percentile context and current p50 for cut detection. Positive covariance is valid; prior audit repaired the sentinel. |
| `SceneCutTex` | RGBA16F previous p50/raw entropy | Current cut detection compares against one preceding measurement; `.r` is not itself an EMA. Cut signal reaches multiple live histories and grade gates. |
| `NearClipTex` | R16F self-history; 167.5 ms half-life, cut reset | Inverse-grade global clipping restraint via slot 210. Starts at zero. |
| `MeanChromaTex` | RGBA16F self-history; alpha `saturate(0.001 * frametime)`, cut reset | Median C → inverse slope, grade chroma/print/gamut; a/b centroid → inverse hue alignment; achromatic fraction → inverse gate and grade confidence. Starts at zero. All four channels are live. |
| `PercHighTex` | RG16F self-history; alpha `saturate(0.005 * frametime)` | p90 → film/specular context; p10 → shadow floor, via scalar slots. Starts at zero. |
| `ModeTex` | R16F self-history; same alpha as high percentiles, cut reset | Grade toe and shadow-lift context. Starts at zero. |
| `EntropyTex` | R16F self-history; alpha `saturate(0.002 * frametime)` | Grade zone attenuation and film strength. Starts at zero. |
| `ZoneHistoryTex` | RGBA16F self-history; elapsed-time EMA, cut reset | Grade's interpolated median/p25/p75; aggregate key/std → context and slow-key target. Starts at zero. |
| `ChromaHistoryTex`, band columns 0–5 | RGBA32F storage, RGBA16F publication feedback | Only own updates consume records; no ordinary image consumer. See perturbation above. |
| `ChromaHistoryTex`, column 6 | Recomputed aggregate; no recurrence of its own | Zone key/std → grade context; also scalar publication. |
| `ChromaHistoryTex`, column 7 | RGBA32F direct self-history | Slow key → grade through RGBA16F metadata. Prior repair retains 20-second/67-ms half-lives and existing startup guard. |
| `AdaptiveHistoryTex` | RGBA16F direct self-history; 32.4/186.7 ms directional half-lives, cut reset | Film, lift, print and gamut strengths. Grade computes the next state for image use before its history pass stores the same result. Sum below 0.001 selects initial raw values; gamut target is always at least 0.75, keeping legitimate initialized state above that sentinel. |
| `NeutralIllumTex` / metadata RGB | Current-frame estimate; metadata retains one frame | Next-frame inverse warm-scene gate. Grade also assigns current `ctx.illum_warm`, but never reads that field. No repeated EMA in this estimate. |

`HighwayTex` and `TexHwyTex` are publications with pass-through persistence;
most live authoritative recurrences above read their private textures directly.
The per-hue feedback is the remaining recurrence through the lower-precision
texture publication. Scalar aliases 203–205 and 208 have writers but no direct
processing reads; grade obtains zone/slow-key values from texture metadata and
computes IQR from percentiles. Unused aliases do not make their source statistics
unused. Likewise `ReadTexHwyPercHigh`, `ReadTexHwyMeanChroma` and
`ReadTexHwySceneCut` have no ordinary call sites, while their scalar equivalents
and source histories have live consumers.

## Precision and initialization triage

The six unused chroma filters retain `prev.a < 0.001` as their startup test.
At full observation confidence, minimum Q=0.0001 and R=0.01 allow positive
steady covariance approximately 0.000951249, below that threshold. A CPU
round-to-nearest float16 recurrence with the actual P-driven Q expression
reseeds on updates 1, 20, 39 and 58. This is a source/CPU finding, not an
explicit GPU covariance trace. It is recorded without changing unused filters
or repeating the completed live-percentile audit.

The remaining live precision priority is `MeanChromaTex`. At 144 simulated
updates/sec its non-cut alpha is 0.00694444. Around state 0.5, half the upward
half-float spacing divided by alpha is approximately 0.03516; sufficiently
small intended changes can therefore disappear in a nearest-rounding model.
At 60 updates/sec the analogous scale is 0.01465. These are local quantization
risk scales, not measured GPU error bounds or evidence for a particular
Vulkan conversion mode. Signed a/b additionally merit attention when the
centroid passes near zero and its derived hue changes rapidly.

Next: explicitly probe that four-channel recurrence with controlled signed
targets, small rises/falls, startup and cuts at simulated cadences. Compare
actual stored states and publication against the unchanged formula before
considering any format change. Independently assess visual impact through
matched captures if a live defect is proved. Do not widen other histories by
association or retune their rates to hide quantization. Other table entries'
precision, startup transients and variable timing remain open.

Follow-up: [scene-chroma precision](2026-10-25_scene_chroma_precision.md) now
confirms the live recurrence defect on the GPU and adopts RGBA32F authoritative
history with unchanged coefficients and half-float publications. Its report
records held/motion validation and a small one-code motion shadow cost. The
RGBA16F inventory entry above describes the state at this audit's start.

## Artifacts and scope

Ignored [captures/history_consumers_20261025/](../captures/history_consumers_20261025/)
contains isolated corrective/grade/pipeline copies, configs, lossless source
clips, captures, `run.py`, `report.json` and `cpu_risks.json`. The GPU check is
a consumer perturbation, not a golden-image suite or performance measurement.
The CPU screen deliberately does not assert the GPU's rounding behavior.

All protected shader/profile/config hashes remain unchanged throughout the
batch. `report.json` also retains isolated shader/config/script hashes and
per-capture source-clip hashes. Twenty diagnostic tooling tests pass, report
links resolve, HANDOFF remains at 59 lines, and `git diff --check` passes.
Only this report and startup/plan/handoff documentation change in the tracked
working tree; diagnostic scripts and media remain local and ignored.

The separate active-chain resource-sharing defect remains. These combined
trials neither repair it nor certify the active configs. No motion continuity,
physical high-refresh acceptance, aesthetic score increase or new effect is
claimed.
