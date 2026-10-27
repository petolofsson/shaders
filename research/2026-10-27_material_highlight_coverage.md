# Material, highlight and daylight coverage — 2026-10-27

The requested broader material/highlight assessment is complete for the available
two-game input set. Four fresh views supplement eight verified current-code held
views. Dark-surface structure, colored highlights and light/shadow ordering survive
in the selected regions, but intervention is not uniformly beneficial: daylight
and interior midtone separation can shrink, bright-core separation compresses,
and some above-shadow sky remains affected by lift. These are recorded model and
quantization costs, not a new demonstrated arithmetic defect.

No production shader, original profile or active/trial config changes accompany
this assessment. The previous zone, Retinex and blue-cusp repairs remain applied.
This closes the coverage task, not overall spatial/color acceptance or the 75+
effectiveness target. Next work is temporal/resolution coverage in PLAN 4.

## Inputs, identities and runtime

| Fresh case | Reference filename | Selected content |
|---|---|---|
| Arc day | `autof_20260515_210825.png` | Dark vehicle, rust strip, road, blue sky, cloud |
| Arc interior | `autof_20260515_205938.png` | Dark metal, warm/cool lighting, colored practicals |
| GZW shop | `autof_20260515_133505.png` | Dark wood, yellow siding, foliage, warm lamp |
| GZW day | `Screenshot_20260516_101035.png` | Sunlit/shadow paving, wall, foliage, clouds |

References remain under each game's `analysis/reference/`. Each fresh view has
five fresh private headless processes: full, unchanged full repeat, inverse-luma
off, Retinex off, shadow-lift off. Diagnostic gates change only isolated local
profile copies; full/repeat retain their original game profile. Combined trial
techniques supply live analysis resources. Five seconds compilation wait and
twenty seconds continuous lossless RGB playback precede each capture. All twenty
processes report zero dropped/delayed frames. All four full/repeat pairs are
pixel-identical. Warmup/repeat identity is not proof of complete convergence.

The eight reused current-code cases are GZW sunset, dark, vivid, muted and barrels;
Arc cloud, emitters and wall, from the
[blue-cusp report](2026-10-27_gamut_continuity_repair.md). Their source, old-output,
current-output and repeat image hashes were reverified; eight current/repeat pairs
are identical. The prior applied report's complete shader/profile/trial hash map
equals this run's initial and final maps. Thus there are twelve distinct held
inputs, four newly captured here, not twelve new capture sets. Earlier wall/sky
GPU attribution is retained rather than rerun.

Current shared `common.fxh` SHA256:
`6bfdb55e45c0cd694679c7d537479cb06923917af61ef9328a9eee83a5eef9a3`.
Full profile SHA256 values are Arc
`e4c126a8f0bd534ad3e9efcd1ca5081d8ce5504080f5c19c363ea687dcc2e0d7`
and GZW `ed371ec361c6590442dd6f0aaaf35aeab93f829395576fffe60fe5d5f4811aa1`.
The profiles differ; this is shared-logic coverage, not a unified-preset test.

Local evidence: `captures/material_coverage_20261027/{run.py,report.json,analyze.py,
metrics.json,boundaries.py,boundary_metrics.json,summary.json,audit.py,audit_report.json}`.
The audit checks 140 artifact identities, source-exact first-frame FFV1 decoding,
runtime logs, repeat identity and unchanged production/profile/trial hashes.
Reports contain per-process `/tmp/shader-runtime-*/` paths. Scripts/media remain
ignored local artifacts. [Source/full/lift-off contact sheet](../captures/material_coverage_20261027/contact.png).

## Measurement rules and reproducible regions

Oklab L/C use a 0–100 scale. For within-region separation, source-L lower and upper
quartiles define fixed pixel groups for every output. L gap is their difference
in mean L; relative contrast is the difference in mean log2 linear Y, floored at
1e-8. Medians, hue, chroma and endpoint counts accompany these metrics. Changes
are not fidelity scores. Hue is omitted when source/output chroma is too small.
The marker's top-left 2x2 pixels are excluded from global counts.

Rectangles below use a 1024x576 preview coordinate system; multiply each endpoint
by 2.5 and round to native 2560x1440 pixels. They were selected from source content.
Paving rectangles were corrected against source to exclude the player's arm;
the Arc sky excludes mountains. No output-dependent mask or profile tuning is used.

| Case | Rectangles `(x0,y0,x1,y1)` |
|---|---|
| Arc day | rear body `(615,340,780,390)`; rust `(590,327,690,343)`; road `(60,370,300,470)`; sky `(90,25,310,90)`; cloud `(680,75,850,165)` |
| Arc interior | cool upper `(610,75,760,140)`; dark metal `(40,395,175,515)`; amber strings `(413,475,596,533)`; red practical `(330,317,357,345)`; warm floor `(435,364,542,400)`; cool window `(641,281,719,330)` |
| GZW shop | wood `(143,218,188,343)`; floor `(218,358,330,405)`; lamp `(333,263,356,288)`; siding `(11,64,123,151)`; foliage `(843,67,950,174)`; road `(657,356,773,405)` |
| GZW day | lit paving `(250,520,335,560)`; shadow paving `(265,430,330,458)`; wall `(340,342,420,405)`; foliage `(35,245,110,275)`; cloud `(526,100,704,200)` |

Dark metal/wood masks require source L<45. Foliage requires source hue 70–185°,
C>2. Colored practical masks require source C>5 and L>40, with source-L thirds
also reported. The interior is a UI-heavy trader scene; chosen regions avoid
large cards, but whole-frame statistics still include UI. Daylight examples are
usable SDR controls, not established artistic ground truth for “already balanced.”
Mixed material/lighting rectangles do not establish flat-surface halo behavior.

## Dark materials and colored highlights

| Source-selected region | Median L source→full | L gap source→full | log-Y gap source→full (stops) |
|---|---:|---:|---:|
| Arc rear body, mixed panel/bumper | 22.42→19.12 | 17.648→17.583 | 3.112→3.584 |
| Arc dark metal | 16.62→15.01 | 11.397→11.141 | 2.637→2.836 |
| GZW dark wood | 28.25→27.32 | 9.806→10.535 | 1.596→1.776 |
| Retained GZW dark shelf | 13.57→12.26 | 4.408→4.389 | 1.479→1.647 |

Deepening these regions does not erase the measured structure; absolute and
relative gaps need separate interpretation. Dark shelf/metal are near-neutral,
so they do not prove rich dark color retention. Dark selected GZW foliage retains
nonzero chroma (shop 2.62→2.95, day 2.86→3.10) and expands measured L/log-Y gaps,
but median hue shifts +17.51°/+14.07°. Those shifts remain palette costs for
acceptance; earlier green displacement was chiefly profile color correction,
and this pass does not newly attribute every foliage pixel to that stage.
Rust chroma is 2.96→2.84 with median hue shift −6.32° and L gap 28.898→27.870.

| Colored highlight mask | Pixels | Median C source→full | Median hue shift | L gap source→full |
|---|---:|---:|---:|---:|
| Arc amber strings | 16,886 | 7.308→7.560 | +0.19° | 30.918→30.536 |
| Arc red practical | 2,072 | 6.062→6.277 | +2.11° | 20.305→19.079 |
| GZW warm lamp | 716 | 12.458→13.963 | −2.66° | 30.651→28.748 |
| Retained Arc red emitter | 1,513 | 19.218→18.744 | +0.54° | 22.329→18.501 |

Colored light remains colored; this does not mean every highlight shade is
preserved. In the brightest source-L third, median C changes amber 7.377→7.258,
red practical 6.164→6.105, warm lamp 13.215→11.682. The lamp's relative-Y gap
is nearly unchanged (2.055→2.049 stops) while its absolute gap compresses.
Its 177 source pixels with a channel at 255 become zero such output pixels;
this does not recover detail that was clipped in the source.

Retained emitter masks use native coordinates: red `(770,470,950,650)` with
R>160,G<160,B<140; white core `(2000,250,2480,570)` with source L>90; halo
`(2000,200,2500,640)` with source 60<L<85. Core median L 98.202→93.837 stays
above halo 73.472→69.082. However, core L gap compresses 6.821→4.463 and log-Y
gap 0.306→0.207 stops; halo gaps expand 19.327→20.881 and 1.161→1.330.
Highlight shape/order survives with a real internal-core compression cost.
The core's 11,887 source channel-clipped pixels become zero at output; lost
source information remains lost. Dark shelf uses native `(80,450,540,650)`.

## Cooperation, light boundaries and restraint

The ablations extend the [wall/sky attribution](2026-10-27_wall_sky_attribution.md).
They are downstream counterfactuals, not additive stage budgets.

| Region | Source L gap | Full | Inverse luma off | Retinex off | Lift off |
|---|---:|---:|---:|---:|---:|
| Arc day road | 21.114 | 19.212 | 20.394 | 20.331 | 19.606 |
| Arc day sky | 8.007 | 7.427 | 6.765 | 8.600 | 7.836 |
| Arc day cloud | 4.728 | 5.414 | 5.394 | 4.261 | 5.415 |
| Arc interior cool upper | 24.023 | 20.123 | 22.398 | 22.043 | 19.973 |
| GZW shop dark wood | 9.806 | 10.535 | 10.538 | 10.496 | 9.586 |
| GZW day lit paving | 18.168 | 16.789 | 16.858 | 19.452 | 17.265 |
| GZW day shadow paving | 10.578 | 9.256 | 10.998 | 9.099 | 9.251 |

Inverse luma contributes almost no resolved wood-gap change but retains sky
separation compared with its bypass. Retinex expands the selected Arc cloud gap
yet compresses the selected lit-paving/cool-upper gaps. A single global bypass
would sacrifice measured contributions elsewhere. Full road log-Y gap remains
1.778 versus source 1.770 despite its smaller absolute L gap; cool-upper contrast
really shrinks in both metrics (2.496→2.250 stops). Thus not every absolute-L
reduction is lost relative structure, and some reductions are substantive.

GZW lit/shadow paving median-L difference stays positive but falls
19.061→15.984; median linear-Y log ratio falls 1.566→1.430 stops. Inverse-luma
bypass gives 17.770/1.540; Retinex bypass gives 18.141/1.643; lift bypass gives
16.324/1.482. This broadens the evidence of material/light normalization costs.
It preserves ordering, not the complete source lighting relationship. Different
paving positions are not an identical-reflectance physical lighting experiment.

Lift's full-minus-bypass mean L change is 2.299 on shop wood versus 0.414 on Arc
blue sky and 0.113 on GZW clouds. Arc bright cloud is nearly unaffected:
0.000083 mean L, 99th-percentile max-channel difference zero, maximum two codes.
This supports measured bright-region restraint while retaining the known broad
sky eligibility. In GZW day, shadow paving changes +0.918 L versus lit +0.540;
both remain eligible. Images show net effects, not hidden gate/key telemetry.
No assertion that every sample is below/above its current adaptive key follows.

Whole-frame source→full exact-black counts are Arc day 105→105, interior
1,893→2,082, shop 0→44, day 0→0. Every source black stays black in all variants;
the new output blacks in interior/shop remain costs, not endpoint improvements.
Lift bypass increases output black counts to 2,237/45 respectively. All fresh
full outputs have zero pixels with any channel at 255, versus sources
8,285/2,068/334/2,028. This describes compression, not an automatic quality gain.

For controlled spatial boundaries, retained GPU atlases use pose/token 1044:262
at two independently matched source/cut-update phases. Nine exact source colors
per phase in native `(800,700,1840,870)` have sufficient edge/interior coverage.
Full-raster masks define ≤4-pixel edge, >24-pixel far interior and >8-pixel interior;
`[2::5,2::5]` point sampling matches the atlas grid. Current versus pre-gamut-repair
edge-minus-far median L/C changes are zero for all eighteen records; current and
repeat metrics are identical. Existing maximum absolute edge gaps are 0.085025 L
and 0.067590 C; maximum interior 95–5 spreads 0.379409 L/0.223243 C. This supplies
retained uniform-boundary regression evidence, not a claim that every textured
gameplay lighting boundary is halo-free or that motion continuity is established.

## Blue gradients, decision and limits

The retained vivid GZW view supplies 172,811 source-selected blue pixels
(hue 250–278°, C>2,L<65, native x200:2200/y150:1150). There are 30,787 horizontal
neighbor pairs with both pixels selected and source max-channel code difference
≤1. Before/current pair ΔE p99 is 0.863861→0.859458, with maximum individual
pair amplification growth +0.361706. Mean before/current pixel change is
0.006980 ΔE, maximum 4.695429; current repeat is identical. This is end-to-end
image evidence, not readback identifying which pixels entered gamut projection.

The prior mathematical limits still apply: the selected large blue step improved
3.031499→0.112662 ΔE, but a finite code-128 pair increased
0.222091→1.307523 (source 0.270592). Far out-of-gamut blue retains up to 3.685429°
hue shift and edge convergence/plateau. Real-source p99 improvement does not
remove isolated quantized amplification or certify universal banding freedom.

Visual contact review is consistent with retained dark structure, practical-light
color and lighting order, alongside darker midtones and the measured compression.
No further production change is justified merely to equal source gaps in these
regions. Preserve the profiles and calibrated stage behavior while carrying the
recorded costs into eventual effectiveness review. This pass neither proves an
inverse-tone-map provenance for every source nor certifies automatic nonintervention
on all already-balanced content. Those remain acceptance limits, not an unfinished
capture checklist for this bounded item.

Twenty-two diagnostic tooling tests pass; artifact audit passes; whitespace check
passes. No new GPU telemetry, dense motion/cut capture, resolution change, physical
high-refresh test or new game is claimed. Active separate-effect resource sharing
remains broken; combined-trial evidence does not certify that path. No effectiveness
re-score, new effect, HDR/auto-exposure, golden-image suite or GPU profiling follows.
