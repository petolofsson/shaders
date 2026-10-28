# Source-aware inverse-luma restraint — 2026-10-27

**Decision: adopt current-source restraint of inverse luma alone.** This is the
first bounded enhancement from the user's request to improve tonal cooperation.
It gives back some interior/midtone separation while keeping the existing
Retinex and shadow-lift treatments. Benefits are modest and scene-dependent;
cloud and warm-floor separation costs below remain accepted on this measured set.
The known technical repair pass and its lift/activation decision remain closed.

Both actual active configs pass fresh full/repeat captures against the isolated
candidate, pixel-identically. Production shader changes preserve both profiles,
including the user's pre-existing Arc edits, and both active configs.

## Behavior and source contract

The original inverse-luma model applies a luminance-dependent darkening before
Retinex/zone/lift. Its material-dependent compression was already documented in
the [wall/sky attribution](2026-10-27_wall_sky_attribution.md) and
[material assessment](2026-10-27_material_highlight_coverage.md). The new restraint
backs off that reconstruction when the current source already spans a broad
range. A broad histogram is a limited intervention signal, not proof that the
source is balanced or that an ACES-derived inverse matches its tone mapper.

For the existing trimmed anchors (CDF targets 0.275 and 0.725), the shared scalar
is `span = max(p75-p25,0) / max(p75+p25,0.001)`. A smoothstep from 0.6 to 15/17
reduces inverse-luma strength from its original manual ceiling to half that
ceiling. Those endpoints correspond to two- and four-stop percentile ratios.
Missing current-source validity selects the original full-strength behavior.
No exposure target, new control, history or render pass is added. Grade remains
eight passes; exposure, Retinex, zone contrast, lift, look, gamut and output
formulas retain their prior implementation.

The raw-observation CDF walk additionally computes p75 using the same normalized
576-count population, trimmed interpolation and arithmetic locking as its other
anchors. It occupies the previously spare B channel of `PercHighTex` record three:
`(p10, mass, current p75, validity)`, sampled at 2.5/3. The existing scalar highway
publishes it in slot 218 (`HWY_TONAL_P75`); slots 212 and 217 supply current p25
and validity. Publications retain the normalized half-float convention. Texture
dimensions/formats and all original observation fields, histories, rates and lift
recurrences remain. The older lift-oriented helper/slot names are retained.

## Finite candidate decisions

The screen used isolated copies of shaders/profiles, with no production change
until the final decision. Rejected source and image artifacts remain available.

| Candidate | Decision and evidence |
|---|---|
| Lift taper above source scene key | Reject. It worsens sampled interior cool-upper relative separation 2.290→2.161 stops and shop road 2.084→1.959. Source brightness relative to a global key does not identify which lifted materials benefit. |
| Joint inverse/Retinex restraint using smoothed quartiles | Reject. Held interior separation improves, but the return-cut quartiles briefly traverse a broad-span state. Candidate/full mean difference reaches 0.804 ΔE in GZW and 0.784 in Arc, then disappears. In GZW a later duplicate-source step rises 0.031→0.217 ΔE. |
| Joint inverse/Retinex restraint using current quartiles | Reject for production. It removes that history-driven pulse and retains the held gains, but dedicated cloud relative separation falls 0.893→0.814 stops. The interior also gains 35 exact-black pixels. |
| Current-source inverse restraint alone | Adopt on this scope. It retains useful interior gains, substantially reduces the cloud cost, adds no black/white clipping in six held cases, and preserves the measured cut/daylight windows. |

## Held materials and retained costs

Six sources cover Arc daylight, interior and cloud, plus GZW shop, daylight and
dark material. Each final baseline/candidate has a fresh unchanged repeat;
all twelve pairs are pixel-identical. Every process uses five seconds for
compilation and twenty seconds of continuous playback. This protocol establishes
repeatability at the measured states, not universal history convergence.

Regions retain the source-selected rectangles and source-L quartile groups from
the material report. Dedicated cloud uses native `(160,100,1040,500)` and dark
shelf `(80,450,540,650)`, with quartile-mean measurements here; older reports using
20/80 median groups are a different metric. L is Oklab on a 0–100 scale, and
relative separation is the difference in mean log2 linear Y between the same
source-selected high/low groups. Neither is an overall quality score.

| Region | Baseline→adopted L gap | Baseline→adopted relative gap, stops |
|---|---:|---:|
| Arc interior cool upper | 20.523→20.990 | 2.290→2.330 |
| Arc interior amber practicals, whole rectangle | 35.543→35.799 | 3.265→3.284 |
| Arc interior cool window | 33.257→33.543 | 4.333→4.359 |
| GZW daylight shadow paving | 9.256→9.314 | 1.007→1.013 |
| GZW daylight wall | 12.083→12.121 | 1.472→1.475 |
| GZW dark shelf | 4.389→4.389 | 1.647→1.647 |
| Arc dedicated cloud | 16.299→16.107 | 0.893→0.880 |
| Arc interior warm floor | 33.161→33.053 | 2.592→2.579 |

Dedicated cloud source separation is 16.891 L / 0.861 stops. The candidate's
relative gap is closer to that source value while its absolute gap shrinks;
these are different relationships, not a reason to label the change recovered
detail. Bright cloud median L remains 91.015. GZW daylight cloud also loses a
small relative gap (1.616→1.611). The warm floor loses some separation. These
costs remain part of acceptance rather than being hidden by the interior gains.

Whole-frame mean changes from baseline are 0.0224 ΔE Arc day, 0.0606 interior,
0.0518 GZW day and 0.2190 dedicated cloud. Shop and dark each change one pixel by
one code; selected wood/shelf measurements are unchanged. Maximum channel
changes are 1/3/1/1/1/5 codes for Arc day/interior, GZW shop/day/dark, Arc cloud.
No case adds exact-black or code-255 channel pixels, and all source-black pixels
stay black after masking the intentional 2×2 marker. Existing black counts are
105/2085/44/0/0/93 in that case order. No broad palette, material fidelity or
new flat-boundary acceptance is inferred from these six views.

[Source/baseline/rejected joint/adopted contact sheet](../captures/tonal_selectivity_20261027/contact.png).

## GPU contracts and cut scope

An independent numerical oracle covers ten populations: black, white, uniform,
bimodal, trimmed boundaries, empty, sparse, mode ties and partial mass. Both GPU
probe runs agree exactly. Maximum raw-observation error is 0.000000084. Published
values remain within a half-float ULP (maximum absolute error 0.000390649 near
white). Original smoothed p90/p10 records match the unmodified recurrence exactly,
all original raw observations match their reference, and publication validity
and the new budget including missing-source fallback pass.

Two final candidate replays use the current GZW and Arc profiles. Each retains
48 measured source/token/update/cut identities: 24 night updates, 20 return
updates and four daylight controls. Every extracted baseline matches the ordinary
output exactly. Candidate output also matches baseline exactly throughout both
sets: its observed source-span budget is one in these windows. This proves
nonintervention there and removal of the rejected history-driven pulse; it does
not exercise moving, engaged restraint or establish dense gameplay continuity.
No temporal repeat comparison between separate runs is claimed.

The original cache remains 15 unique poses/sec duplicated at 30 fps. Diagnostic
tails supply readback only; appended poses are excluded. Common masks remove
borders and overlapping atlas tags. Ordinary screenshots provide no hidden
highway telemetry; percentile/budget data comes from explicit binary GPU output.

## Checkpoint and limits

Local [capture artifacts](../captures/tonal_selectivity_20261027/) retain source,
clip/profile/config/shader identities, 52 held captures, five diagnostic replays
(including rejected candidates), two source probes, candidate/baseline source
snapshots and final active-config verification. All successful processes report
zero dropped/delayed frames. Lossless clips' first frames match their six PNG
sources byte-for-byte. Scripts/media stay ignored; research documentation is
versioned. Shader header comments, profiles and active configs are preserved.

Four final actual-active-config captures cover Arc interior and GZW daylight,
full/repeat under each game's current profile. All four match the isolated
inverse-only candidate exactly. This verifies the adopted shared sources and
actual bindings, with no live-gameplay or broader temporal claim.

The final audit passes 1,328 checks across 1,204 unique artifacts: 52 held runs,
22 identical held repeat pairs across all candidates, five replays with 240 exact
extracted-full controls, two source probes and four actual-active-config runs.
All 22 diagnostic tooling tests and `git diff --check` pass. The two final
inverse-only replays provide 96 of those exact controls; the older candidate
replays remain separate evidence for their rejection/refinement decisions.

This closes the finite lift/joint/inverse-only candidate decision. Source-tone-map
provenance, local material/lighting semantics, engaged dense motion and wider
game coverage remain limits on generality. The improvement is modest; no new
mandatory defect task or effectiveness re-score follows. Prior lift/activation,
spatial and precision decisions remain closed.
