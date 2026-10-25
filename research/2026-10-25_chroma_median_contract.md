# Scene-chroma median population — 2026-10-25

The user clarified that current work should prioritize technical correctness and
how reliably each stage performs its intended role, without waiting on personal
palette/print preference. Profiles remain intact. This audit starts with
producer/consumer contracts in the combined pipeline; the active four-effect
resource-sharing limitation remains separate and unresolved.

## Defect and correction

`HWY_MEDIAN_C` is documented as the median Oklab chroma over all scene samples.
`MeanChromaPS` instead added only samples with C >= 0.05 to its histogram and
used their count for the percentile target. A completely neutral scene returned
the fallback C=0.10. The result was a conditional median of the colored minority,
which is a different statistic from the one expected by scene-vividness,
chroma-slope, vibrance, print and gamut adaptation.

The candidate counts every one of the existing 576 samples in the chroma
histogram and computes its median against that full population. Hue-centroid
averaging still excludes near-neutral samples; its colored count and fallback
remain. Achromatic fraction, sampling, histogram bins, temporal rates, textures,
pass order and creative values are unchanged. No new parameter is introduced.

## Explicit GPU contract probes

Three lossless 2560x1440 sources contain neutral gray, 75% neutral gray/25% red,
or 100% red. The split aligns with the existing 32x18 sampling grid. A temporary
combined technique explicitly renders the measured median, achromatic fraction
and colored a-centroid as encoded diagnostic channels. These are deliberate
GPU readbacks, not telemetry inferred from ordinary screenshot scene pixels.

Nine fresh private headless processes capture before/candidate/repeat for each
input after five-second compilation wait and 20-second continuous playback.
All report zero dropped/delayed frames. An independent CPU calculation uses the
known sample population and the existing intra-bin percentile interpolation.
Raw Oklab C is used below, not C multiplied by 100.

| Red coverage | Expected full-population histogram median | Before GPU | Candidate GPU | Repeat GPU |
|---|---:|---:|---:|---:|
| 0% | 0.004688 | 0.098333 | 0.004563 | 0.004563 |
| 25% | 0.006250 | 0.208162 | 0.006087 | 0.006087 |
| 100% | 0.210938 | 0.208162 | 0.208162 | 0.208162 |

All candidate readings agree with the histogram model within 0.003 raw C,
including half-float history and 8-bit encoded capture uncertainty. The neutral
median remains in the first finite histogram bin rather than claiming exact
zero chroma. The two unchanged statistic channels match before/candidate/repeat
at capture precision. The fully colored control is unchanged.

## Six-scene held checks

Eighteen fresh private headless before/candidate/repeat processes use the same
five-second compile wait and 20-second continuous settle. No prior output image
is reused as a baseline. Sources, shaders, profiles and configs are hashed;
the shared working shaders remain untouched throughout the candidate batches.
Vivid Arc input uses GZW tuning; clouds and lamps use the existing Arc profile.

| Case | Before/candidate mean Delta E | Candidate/repeat mean Delta E |
|---|---:|---:|
| GZW dark | 0.000048 | 0.000003 |
| GZW sunset | 0.002326 | 0.000500 |
| Vivid Arc input, GZW profile | 0.135944 | 0.000000 |
| Arc clouds | 0.057948 | 0.000000 |
| GZW overcast | 0.000088 | 0.000000 |
| Arc lamps | 0.000812 | 0.000006 |

All processes report zero dropped/delayed frames. At full raster, excluding the
intentional 2x2 marker, no case adds a newly black pixel or newly white-clipped
pixel relative to its fresh before capture. Source black remains zero wherever
present. Vivid-input black coverage decreases 0.252360% to 0.239828%; other
black coverage is unchanged or within repeat variation. Lower clipping alone
is not a quality score. The inspected before/candidate/repeat contact sheet
retains scene structure without a newly obvious artifact.

## Matched motion and limits

Three fresh private before/candidate/repeat processes replay the verified cached
15-pose/sec source at duplicate 30 fps with 20-second initial pre-roll. Source
manifest and clip protocol are checked. Each run captures 27 unique identities
and reports zero dropped/delayed frames. Nine identities match exactly across
all three runs:

| Window | Exact matches | Before/candidate mean Delta E | Candidate/repeat mean Delta E |
|---|---:|---:|---:|
| Foliage | 2 | 0.036505 | 0.032218 |
| Clearing | 3 | 0.027998 | 0.000663 |
| Corridor | 2 | 0.010352 | 0.002080 |
| Before return cut | 2 | 0.002225 | 0.001785 |

The two night-cut windows and post-return window have no three-way identity
matches. They were sampled but cannot enter matched comparisons. Foliage and
pre-return changes are close to repeat variation and are inconclusive as small
effect measurements. This is scoped motion regression evidence, not dense
continuity, complete matched-cut coverage or proof of better motion quality.
The report preserves empty coverage windows explicitly.

## Adoption and shared-path verification

The three-line correction is applied in `general/analysis-frame/analysis_frame.fx`.
The applied file exactly matches the isolated candidate after normalizing its
include paths. Shader header comments, existing reconstruction/spatial fixes,
profiles, active configs and adaptation rates are preserved. Twenty diagnostic
tests and `git diff --check` pass.

Two final fresh private captures run the shared combined pipeline with the GZW
profile on vivid input and the Arc profile on clouds. Applied-versus-candidate
mean Delta E is respectively 0.000000 and 0.000011; both processes report zero
dropped/delayed frames. Hashes retain all shared sources unchanged during every
runtime batch, with only the intentional analysis change between validation
and adoption. This restores a statistic's contract; it does not justify raising
effectiveness scores or establish cross-game acceptance. The active separate
effects still lack shared analysis resources, so this does not fix or validate
their downstream adaptive behavior.

## Artifacts

Ignored [captures/chroma_median_20261025/](../captures/chroma_median_20261025/)
retains isolated shader snapshots, diagnostic sources, configs, scripts, hashes,
captures and JSON reports. `probe_metrics.json` records the independent contract
check; `regress_metrics.json` records full-raster clipping and image deltas.
`motion_report.json` retains identity coverage and repeat measurements;
`verify_report.json` records final applied-path checks.
The tools print unique `/tmp/shader-runtime-*/` log directories for each run.

## Next separate technical investigation

The percentile Kalman filter uses `prev.a < 0.001` to detect initialization.
At zero innovation, its R=0.005 and minimum Q=0.00005 produce a legitimate
steady-state posterior variance around 0.000476, below that threshold. A CPU
recurrence with float16 storage restarts on frames 1, 7, 13, 19 and 25, cycling
gain from roughly 0.995 down to 0.181. This is a separate initialization-contract
finding; it is not GPU-confirmed or fixed in this change. Preserve intentional
slow-key rates while investigating it. The retained CPU trace is
`percentile_initialization_cpu.json` in the artifact directory.

Follow-up: [the percentile initialization audit](2026-10-25_percentile_initialization.md)
now confirms this behavior with explicit GPU history and adopts its isolated
initialization correction. The CPU-only status above describes this earlier
chroma-median batch, not the current implementation.
