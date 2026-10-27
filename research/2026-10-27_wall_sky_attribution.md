# Yellow-wall and sky separation attribution — 2026-10-27

The remaining wall/sky differences have different causes. On the selected Arc
view, `INVERSE_LUMA` accounts for most yellow-wall contrast reduction; Retinex
normalization adds a smaller reduction. Shadow lift accounts for most sky
reduction. Zone contrast expands both sampled gaps. FilmCurve does not engage
in the selected regions, and look/chroma/gamut are not the primary cause.

This assessment adds no production shader, profile or config edits. The current
[blue-cusp correction](2026-10-27_gamut_continuity_repair.md), Retinex/zone repairs
and history/signal contracts remain. The measured equations behave as coded;
this is a model-cooperation tradeoff, not a newly demonstrated gain-unit or
history defect. Removing an entire stage is not a justified general repair.

## Matched input and method

Source is Arc `autof_20260515_210621.png`, with the unchanged Arc profile and
combined-trial pipeline. The fixed source-selected rectangles/quartile groups
from the [color assessment](2026-10-26_color_continuity.md) are retained:
sunlit yellow paint, mixed yellow boundary, dark opening, blue sky and lit ground.
Only the first and fourth are the primary shade-separation measurements here.
The boundary/ground regions mix lighting and materials; they are not flat-face
halo tests. No per-frame profile tuning or source-equal contrast target is used.

Eleven fresh private headless ordinary processes capture full, unchanged repeat
and nine isolated bypasses. Every run uses five seconds for compilation and
twenty seconds continuous playback. Local profile copies carry the bypasses;
original profiles/configs remain untouched. Source, clip, profile, shader,
config and image hashes are retained. Full/repeat are pixel-identical.
Twenty seconds is a fixed protocol, not proof that every history converged.

The lossless RGB clip decodes byte-for-byte to the PNG. Original rendered RGB
is additionally observed on GPU for numerical comparisons: file pixels alone
are not assumed to equal every floating-point BackBuffer observation. Ordinary
screenshots contain no hidden highway telemetry.

## Whole-region bypass results

L gaps are mean source-high minus source-low Oklab L, on a 0–100 scale. The
linear-Y contrast metric is the corresponding difference in mean log2 Y, with
a 1e-8 numerical floor. Groups are fixed from source L quartiles for every
variant. Higher values are changes in separation, not quality scores.

| Variant | Wall L gap | Sky L gap | Wall log-Y gap (stops) | Sky log-Y gap (stops) |
|---|---:|---:|---:|---:|
| Source | 9.924446 | 8.125487 | 1.061479 | 0.618496 |
| Full | 8.623788 | 7.238588 | 0.940704 | 0.591600 |
| Repeat | 8.623788 | 7.238588 | 0.940704 | 0.591600 |
| Inverse chroma off | 8.623788 | 7.310590 | 0.940704 | 0.593454 |
| Corrective off | 9.789817 | 7.012421 | 1.058400 | 0.553236 |
| Tonal off | 8.751950 | 8.110490 | 1.025807 | 0.689043 |
| FilmCurve off | 8.623788 | 7.238588 | 0.940704 | 0.591600 |
| Look off | 8.619078 | 7.143726 | 0.869703 | 0.552665 |
| Inverse luma off | 9.814750 | 6.998848 | 1.055084 | 0.552028 |
| Retinex off | 9.164802 | 7.257885 | 1.002173 | 0.588442 |
| Zone off | 8.491792 | 7.093977 | 0.926081 | 0.583406 |
| Shadow lift off | 8.379328 | 8.172487 | 0.979947 | 0.696254 |

The wall's inverse-luma bypass restores most source separation while changing
median L only 40.657398→40.897097. Its normalized L gap improves
0.213915→0.240856, against source 0.241809. This is a genuine contrast difference,
not merely scaling an absolute L interval through a uniform brightness change.
That same bypass worsens sky separation and relative contrast.

Sky shadow-lift bypass restores its absolute L gap, but median L falls
54.885001→52.558455 and log-Y separation rises to 0.696254 stops, above source
0.618496. Full output is closer to source in that relative metric. Choosing a
repair solely by the absolute L gap would therefore overcorrect one aspect of
the relationship. Look contributes positive relative-Y separation even though
its absolute-L contribution is small. These counterfactuals are not additive
stage budgets: downstream luma-dependent weights respond to upstream changes.

## Explicit cumulative GPU readback

Two final fresh private processes record 110 source-selected native points:
eleven source-low and eleven source-high points in each of five regions.
The same points are used throughout. A diagnostic pass before actual grade
output calls cumulative copies of the current orchestration; separate records
observe original rendered RGB before inverse reconstruction, four tonal lumas,
Retinex inputs/gain/strength and six context vectors. Results go to RGBA32F and
are explicitly encoded as binary fields for readback: 1,326 records per run.
Point-trace gaps are sampled evidence, not the whole-region means above.

Both readbacks are identical. Sampled final colors match ordinary full output
within 0.684386 channel codes, including dither/capture quantization. Signed
RGB-to-Oklab math is retained for intermediate stages; negative internal RGB is
not silently clipped by an image-only analysis conversion.

| Cumulative point stage | Wall L gap | Sky L gap |
|---|---:|---:|
| Observed original source | 9.429192 | 8.521527 |
| Inverse RGB | 9.429192 | 8.502867 |
| Affine black/white | 9.413437 | 8.488660 |
| Corrective | 8.292561 | 8.473228 |
| Tonal | 8.191934 | 7.520652 |
| FilmCurve | 8.191934 | 7.520652 |
| Chroma | 8.191934 | 7.520649 |
| Gamut projection | 8.191931 | 7.520658 |
| Look | 8.203892 | 7.602876 |

The observed film knee is 0.739799 linear Y; the selected points stay below it.
Its nonzero global strength therefore does not imply local intervention.
Chroma and gamut preserve sampled L to numerical/readback precision. No change
to the completed blue-cusp repair is supported by these material measurements.

The tonal trace separates its arms before RGB reconstruction:

| Point tonal arm | Wall implied L gap | Sky implied L gap |
|---|---:|---:|
| Input | 8.292561 | 8.473228 |
| Retinex | 7.788297 | 8.400312 |
| Zone curve | 7.931926 | 8.540554 |
| Shadow lift | 8.191908 | 7.520682 |

Reconstruction against the measured input luma agrees with actual tonal output
within 0.000572 L. The Retinex mix agrees within 0.000000448 linear Y, and the
actual bounded gain formula within 0.000001407. These are much smaller than the
material differences. They do not support reverting the earlier RGB gain-unit
or guide-domain corrections.

[Measured stage/tonal-arm illustration](../captures/wall_sky_attribution_20261027/stage_attribution.png).

## Interactions and interpretation

The sky samples all use the same Retinex gain 0.784585 and strength 0.118861.
Their effective luminance multiplier is therefore uniform. Sampled log-Y
contrast stays 0.675239→0.675241 stops through Retinex, while the absolute L gap
shrinks slightly through the cube-root brightness scaling. Calling that small
L change lost texture would be misleading.

The wall differs: mean low/high Retinex gains are 1.207525/0.879912 at the same
strength. Normalization compresses its sampled log-Y gap 0.896329→0.840448
stops. Zone contrast returns part of the separation. Shadow lift increases the
absolute wall L gap while reducing its relative-Y contrast, demonstrating why
both metrics matter.

The published scene key is 0.072083 linear Y (key L 0.416176), shadow floor
0.009567, and automatic shadow-lift strength 1.322966 before the existing manual
0.75 gate and other pixel factors. The fixed linear-luma lift window extends to
0.35, so the sampled above-key sky remains eligible. Lift reduces its sampled
log-Y gap 0.682330→0.579908 stops. This explains the sky result, but does not
by itself prove that removing lift is better: corrective grading had expanded
relative sky contrast, and the complete result must be judged jointly.

No arithmetic defect is demonstrated in this measured case. The inverse-luma
model's material-dependent contrast response and shadow lift's broad eligibility
are calibrated behavior with real costs. Source tone-map provenance is not
established here. Do not infer that every SDR source warrants an ACES-derived
inverse or optimize the global controls to one wall. Preserve profiles while
broadening material/highlight and already-balanced-input coverage; assess
source-reconstruction/Retinex cooperation and above-key lift selectivity there.
No coarse-edge strength fading or previous spatial repair is restored.

## Provenance, checks and limits

The read-only audit verifies 63 artifact hashes across eleven ordinary and two
final GPU-trace captures. All thirteen accepted processes have zero dropped or
delayed frames. All production shader/profile/trial hashes match the preceding
applied gamut report. Source black is preserved in every bypass. Relative to
full's 2,567 black pixels, corrective/tonal/Retinex bypasses add 3/1/1 pixels;
look bypass reduces black to 2,556 but introduces six white-channel pixels.
No bypass is promoted to production.

An initial 120-point trace pair is retained separately. Its file-pixel guide
check used an inadequate transfer allowance for a few textured samples. The
refined observation records actual pre-inverse GPU RGB instead. Native guide
log-luma agrees within quantization-aware bounds of that observation; maximum
central decoded discrepancy is 0.000051740 stops. The clip itself remains
byte-exact. Measured file-to-render differences are recorded rather than
misclassified as a guide signal-domain defect. All fifteen runtime processes,
including the initial pair, reported zero dropped/delayed frames.

Ignored `captures/wall_sky_attribution_20261027/` retains `run.py`, coarse/local
reports, isolated configs/profiles, source/clip/image hashes, `analyze.py` and
`metrics.json`; `trace.py`, source-selected points, `trace_source_report.json`,
`trace_analysis.py` and `trace_metrics.json`; original trace artifacts;
`source_transfer.json`, `plot.py`, `audit.py` and `audit_report.json`. Ordinary
images supply spatial metrics; only explicit diagnostic output supplies GPU
state. All 22 tooling tests and `git diff --check` pass. This held-scene
assessment adds no motion/cut/high-refresh, new-game or full-chain acceptance
claim, score increase, new effect, HDR output, auto-exposure, golden suite or
GPU profiling. Active-chain resource sharing remains unresolved and neither
active config is switched.

The bounded broader follow-up is now complete in the
[material/highlight coverage report](2026-10-27_material_highlight_coverage.md).
It retains these model-cooperation costs; temporal/resolution work is next.
