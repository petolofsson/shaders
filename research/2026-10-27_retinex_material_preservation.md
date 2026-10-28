# Retinex material preservation — 2026-10-27

**Decision: adopt a gentler native luminance response while retaining the original
relative spatial correction.** The change improves measured paint/paving and some
interior separation, retains bounded illumination normalization, and avoids the
new purple edge exposed by replacing the guided gain directly. Benefits are
modest and scene-dependent. Shadow-paving/cloud compression, stronger blue-sky
separation and a small daylight timing cost remain recorded below.

Only Retinex gain assembly in `general/grade/grade.fx` changes in this task.
The preceding [inverse restraint](2026-10-27_tonal_selectivity.md), original-source
guide and conditioned residual, profiles, configs, statistics, history rates,
textures, eight grade passes and SDR projection remain. No user control or
auto-exposure target is added. Arc's current `BLACKS=0.005` and `FILM_CURVE=0.6`
are existing user edits, preserved as assessment inputs. Fresh baselines use
those values; earlier reports with different profile hashes are historical.

Both actual active configs pass fresh full/repeat captures against the isolated
candidate, pixel-identically. Captures and numerical readbacks remain private/
headless throughout.

## Native response and retained spatial correction

The original bounded response is `G0(K,x) = clamp(2*K/(K+x), lo, hi)`, with
`lo=exp2(-0.35)` and `hi=exp2(0.35)`. Its log-gain derivative at `x=K` is −0.5:
near the scene key it compresses source luminance variations that may belong
to materials. Globally weakening Retinex had already sacrificed useful cloud
normalization in the preceding screen.

Let `I` be native source luminance from the existing R32F log observation, `J`
the existing conditioned guided illuminant, and `K` the existing scene-wide mean
zone median. The adopted response is:

```text
M(K,I) = clamp(exp2(0.35*(log2(K)-log2(I))), lo, hi)
Gnew   = clamp(M(K,I) * G0(K,J) / G0(K,I), lo, hi)
```

The code uses the already-available native log value and the existing positive
key floor. The native component has a 0.35 log-gain slope before its limits,
reducing compression near the key. The ratio retains the original spatial
correction relative to its native response. A self-model `J=I` reduces to `M`;
at the native key the original spatial gain remains; where native responses
reach the same far-field limits, the original gain remains.

For a flat native input, the new modifier is constant across that material.
An originally constant guided gain therefore stays constant, including cases
protected by the old gain limits. The final clamp preserves the same gain
bounds. Retinex strength, highlight protection and cut confidence still blend
the gain exactly as before. No coarse-edge strength fading is introduced.

This is a controlled response within the existing illumination model. It does
not identify physical albedo or infer artistic lighting intent. The 0.35 slope
describes the native component; it is not a guarantee for every full-pipeline
spatial gradient or material region.

## Source-selected material and lighting results

Seven real held inputs cover Arc wall/interior/cloud, GZW daylight/shop/dark,
and vivid Arc content under GZW tuning. The cached uniform-material source is
also tested under both profiles: nine source/profile cases, eight distinct PNGs.
Each real baseline and final candidate has an unchanged repeat; each boundary
candidate also has an unchanged repeat. All are pixel-identical at the measured
states. Five seconds compilation plus twenty seconds continuous playback is a
fixed protocol, not proof of universal convergence.

Regions retain the source-selected rectangles from the wall/sky and material
reports. Dedicated cloud uses native `(160,100,1040,500)`, vivid sky
`(1500,100,2100,360)`, and dark shelf `(80,450,540,650)`. Source-L quartile groups
are fixed across variants. L uses Oklab ×100; relative gap is the difference in
mean log2 linear Y between those groups. These measure relationships rather
than overall quality.

| Region | Baseline→adopted L gap | Baseline→adopted relative gap, stops |
|---|---:|---:|
| Arc yellow wall | 8.145→8.280 | 0.865→0.879 |
| Arc interior cool upper | 19.672→19.735 | 2.115→2.124 |
| Arc interior amber strings, whole rectangle | 34.405→34.525 | 3.074→3.090 |
| Arc interior cool window | 30.446→30.533 | 3.607→3.616 |
| GZW sunlit paving | 16.789→17.398 | 1.402→1.448 |
| GZW shadow paving | 9.314→9.110 | 1.013→0.993 |
| GZW cloud | 28.058→27.469 | 1.611→1.570 |
| Arc dedicated cloud | 16.300→16.076 | 0.886→0.871 |
| Arc interior warm floor | 32.450→32.351 | 2.503→2.494 |
| Vivid blue sky under GZW tuning | 9.824→10.547 | 0.700→0.748 |

Sunlit/shadow paving's median-L difference increases about 16.040→16.273,
retaining more of the source's 19.061 difference. These are different positions
with mixed material/lighting, not a physical identical-reflectance experiment.
The shadow paving loses some internal separation even as the broad lighting
difference grows. More separation in one relationship is not a universal gain.

Vivid sky source gaps are 9.990 L / 0.641 stops; its stronger final separation
exceeds those source values. Selected sky median C changes 12.665→12.672 and
median hue displacement from source 3.565°→3.583°. This retains a tonal expansion
cost rather than establishing improved sky fidelity. Dedicated cloud source
gaps are 16.891 L / 0.861 stops: the candidate's relative gap is closer while
its absolute gap shrinks. Cloud, shadow-paving and warm-floor costs remain.

Whole-frame mean changes are about 0.038 ΔE wall, 0.053 interior, 0.140 cloud,
0.167 GZW daylight, 0.207 vivid input and 0.009 shop. Dark output is pixel-
identical to baseline. No case adds exact-black or code-255 channel pixels.
GZW source black remains black; Arc's deliberate positive black setting retains
the same source-black treatment as its fresh baseline. The largest individual
channel changes are 1/2/5/3/4/1/0 codes in that real-case order.

[Source/baseline/direct-curve/refined contact sheet](../captures/retinex_material_20261027/contact.png).

## Native uniform-material protection

Nine exact source colors in native `(800,700,1840,870)` are evaluated under each
profile. Masks use ≤4-pixel edges, >24-pixel far interiors and >8-pixel interiors;
8×8 block averages separate coherent shading from pixel quantization/dither.
All boundary candidate repeats are identical.

Replacing the guided gain directly with the 0.35 power curve creates a −0.065 L
purple median edge difference under Arc, from zero in baseline. The adopted
relative-spatial correction returns it to zero. Across the final 18 records,
maximum absolute median edge-minus-far L is 0.009686 (GZW red); all median C edge
gaps are zero. Maximum growth of the block-averaged L95−L5 spread is 0.003803 L.
Small quantization/variation costs remain; these held boundaries do not prove
every gameplay edge is halo-free.

The finite screen rejects the direct 0.25 curve for its larger cloud/shadow and
sky tradeoffs, and the direct 0.35 curve for the new purple edge response.
The adopted native/spatial composition retains the measured real-region gains
of 0.35 while removing that edge difference. These candidate decisions are closed.

## Independent GPU and measured-phase checks

The initial curve probe covers five keys and 129 luminance ratios, with gain
and 0.75-strength reconstructed luminance output: 1,290 RGBA32F records per run.
Two runs are identical. Maximum CPU-oracle error is 0.000003018; unity, gain
bounds, monotonic output and native log-slope bounds pass at encoding tolerance.

The adopted composition has a separate 975-record probe over five keys, 65
native ratios and three guided/native offsets. Two runs are identical; maximum
oracle error is 0.000000441. Self-model response, native-key spatial identity,
far-native original-gain identity, gain bounds and monotonic mixed output for
the sampled offsets pass. Values are explicitly rendered and binary encoded;
ordinary screenshots supply no hidden history or highway telemetry.

Two final point-image replays retain 48 source/token/GPU-update/cut-update
identities per profile: 24 night, 20 return and four daylight controls. All 96
extracted full outputs match ordinary production output exactly. Night candidate
images match full exactly in both profiles. Return maximum duplicate-source
steps change 0.784→0.750 ΔE for GZW and 0.808→0.774 for Arc. This changes the
rendered treatment, not adaptation rates or the prior cut/lift repair.

Arc's maximum sampled daylight duplicate step increases 0.1185→0.1364 ΔE; GZW's
changes 0.1232→0.1225. Maximum candidate/full daylight mean differences are
0.547/0.578 ΔE (GZW/Arc). These costs remain explicit. No cross-run temporal
repeat or dense continuity claim is made. The source remains 15 unique poses/sec
duplicated at 30 fps; readback tails are excluded from motion claims. Common
masks remove borders and overlapping atlas tags. All processes have zero
dropped/delayed frames.

At `RETINEX_STRENGTH=0`, original and adopted-model image controls are pixel-
identical on the vivid source, confirming the independent visual bypass.

## Checkpoint and scope

Local [artifacts](../captures/retinex_material_20261027/) retain source/profile/
config/shader hashes, all rejected candidates, gain probes, same-update images,
native boundary metrics, source snapshots and active-config verification.
All nine lossless first frames match their source PNGs byte-for-byte. Scripts
and media remain ignored; this report is versioned. Profiles, configs and all
prior working changes remain intact. Shader header comments are preserved.

Four final actual-active-config captures cover Arc wall and GZW daylight,
full/repeat under each current profile. All four match the isolated candidate
exactly. This verifies the adopted shared grade source and actual bindings,
without a live-gameplay or physical high-refresh claim.

The final audit passes 684 checks across 674 unique artifacts: 50 held images
(including rejected candidates and the bypass pair), 18 identical repeat pairs,
four numerical probe runs, two measured-phase replays with 96 exact full-output
controls, and four actual-active-config captures. All 22 diagnostic tooling tests
and `git diff --check` pass.

This closes the direct-curve/refined-response decision on its measured scope.
The adopted response is a modest improvement toward the visual goal, with the
documented lighting, sky and quantization costs. Source semantics, wider games
and dense engaged motion remain limits on generality, not new mandatory repairs.
No effectiveness re-score follows, and prior technical repair decisions remain
closed.
