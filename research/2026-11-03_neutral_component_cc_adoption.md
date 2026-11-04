# Shared-component CC adoption — 2026-11-03

**Adopted in `general/grade/grade.fx` and verified through both unchanged active
configurations.** The user explicitly authorized completing the implementation
and the remaining checks. The selected implementation adds three arithmetic
lines inside `Apply3WayCC`: scale its existing opponent-color offsets by the
common linear-RGB component divided by luminance. All profile values are preserved.

The [initial lead](2026-11-03_neutral_component_cc.md) explains the model and
source-inspection rationale. This is an appearance/selectivity enhancement, not
a confirmed arithmetic-defect repair. It preserves exact gray-axis correction
and reduces hue steering on colored materials. It is an algebraic rule, not
reconstruction of physical reflectance or semantic material identification.

## Appearance decision and retained costs

The five selected cases cover GZW daylight foliage, weak dark shelf/materials,
vivid Arc content using GZW settings, Arc interior and Arc colored/white emitters.
All five candidate/repeat and five baseline/repeat pairs are exact. Baselines
are independently matched by source/clip/profile/include/producer identities and
normalized shader body, not by directory label or grade hash alone.

The selected foliage source-relative hue shift changes +2.96165°→−0.13131°.
Its lightness gap is nearly unchanged, 5.22996→5.22604. The weak shelf retains
more color separation with nearly unchanged lightness gap, 2.65884→2.65993.
The white-core L gap stays 5.85885→5.85968; halo shape remains in the native
review. Red-lamp source-relative hue shift is +1.01550°→+0.53285°.

Color separation uses fixed lower/upper source-b quartiles and the gap between
mean output a/b vectors on the Oklab ×100 reporting scale. More separation is
not a quality target or recovered-information claim.

| Selection | Before | Adopted | Change |
|---|---:|---:|---:|
| GZW foliage | 1.84390 | 1.90091 | +3.1% |
| GZW weak shelf | 0.41681 | 0.47988 | +15.1% |
| Arc dark metal | 1.62732 | 1.69436 | +4.1% |
| Arc cool upper | 3.08872 | 3.22567 | +4.4% |
| Arc warm floor | 5.22446 | 5.14254 | -1.6% |
| Vivid blue sky / GZW | 3.41134 | 3.19003 | -6.5% |
| Vivid blue field / GZW | 5.90894 | 5.78372 | -2.1% |
| Arc red lamp | 3.34894 | 3.26621 | -2.5% |

The initial cloud and shadow-paving separation costs remain about −1.1%/−0.4%.
Blue-field source-relative hue shift increases +1.42562°→+1.60793°. Warm-floor
hue shift decreases +3.67887°→+2.88596° despite its separation cost. Native
sky, shelf, foliage, floor, cool/dark materials and light-core/halo reviews
support the selected balance: restrained neutral treatment, less foliage/lamp
hue steering and selected subtle material relationships improve; bright blue
and some warm-material relationships are modestly reduced. This is not universal
palette acceptance.

Source-neutral shadow masks are not identical to gray input at the CC helper.
Arc interior median output b changes −0.399180→−0.396311 and remains cool.
GZW dark changes −0.214142→−0.127714, a larger reduction of cool tint than the
initial daylight samples suggested; it still remains cool. That is a retained
cost/behavior change, not described as full neutral-source image identity.
Exact gray-axis identity is established directly at the helper below.

No selected held comparison adds black or code-255 channel pixels. Whole-image
maxima are 3–21 codes across the five scenes, with the largest Arc interior
change in a colored UI logo. UI receives the same material-selectivity rule;
no semantic exclusion is introduced. Large deltas do not establish improvement.

## Numeric, bypass and gradient validation

A direct RGBA32F GPU readback exercises the actual candidate helper and a frozen
original helper on 256 supplied contexts: gray, RGB primary faces, cyan, mixed
colors, signed input, exact black, near-black and positive overrange; eight
scales, four scene keys, both profile parameter sets and zero offsets.
An independent CPU matrix/cube-root calculation agrees within 0.000004463 linear RGB.
The weight/zone maximum error is 0.000000676. Gray input produces
exactly the original GPU output. Primary-face input produces exactly the zero-CC
GPU output. Values use signed 24-bit readback over [-2,6]; CPU algebra is
separate from these compiled checks.

Both current-profile full-frame all-six-CC-zero comparisons are exact. Both
hue/brightness gradient charts add zero black or code-255 channel samples.
Their largest p99 adjacent-color-gap increases are 0.018736 / 0.016920
(GZW/Arc), and largest local increases are 0.078529 / 0.070318.
These are retained quantization costs from single before/candidate chart
observations with 32-line averaging; no chart repeat or physical-display claim.
The helper retains the original near-black fade, signed conversion and output
projection/saturation boundaries. No temporal grain is introduced.

## Motion and activation

Four independent-history private replays supply 192 exact candidate/ordinary
same-update extraction controls. Identity includes source pose/token plus
measured source/cut update ages. The shared tag/interior mask is applied to all
variants. All measured requested windows are present: 24 early night, 20 return,
and four daylight updates per replay. Appended pose 2220 is excluded.

The table gives the largest same-source mean color step in each window, using
the existing common-support mask and Oklab ×100 scale. The repeat column is
maximum screenshot code difference at measured matching updates.

| Window | Before step | Adopted step | Adopted repeat max code |
|---|---:|---:|---:|
| gzw night | 0.122780 | 0.119171 | 1 |
| gzw return | 0.735090 | 0.733914 | 1 |
| gzw daylight | 0.131941 | 0.133881 | 1 |
| arc night | 0.123370 | 0.119101 | 1 |
| arc return | 0.738883 | 0.737275 | 1 |
| arc daylight | 0.146407 | 0.147618 | 1 |

These retain actual temporal/quantization costs rather than treating exact
extraction controls as temporal identity. The source is 15 poses/sec doubled
to 30 fps; dense/high-refresh continuity is not established. State/rates are
unchanged. No new history or delayed source signal is introduced.

After the production edit, both actual active configurations were captured
full/repeat. All four images match the corresponding isolated candidate
exactly. No active config was edited. All completed 29 fresh private GPU processes
plus 8 reused processes have zero reported drops/delays. All 22 diagnostic
tooling tests and whitespace checks pass. Runtime testing remained private and
headless, with no desktop fallback.

## Scope, ratings and artifacts

Only three body lines in the shared grade change. Shader headers, profiles,
configs, inverse/analysis/corrective producers, source guide, history resources,
rates and pass counts remain. Grade stays eight passes. There is no HDR output,
auto-exposure, new control/effect, working texture or profiling. A few extra
arithmetic operations are unprofiled; no throughput acceptance is claimed.

Chain/grade remain 78/100 and the CC estimate remains provisionally 75, with no
fresh full-effectiveness re-score. Focused selected improvements do not justify
raising the whole-chain estimate or removing documented blue/warm-material costs.
The finite adoption task is complete; no mandatory sweep follows.

Local ignored artifacts: `captures/neutral_cc_20261103/`. `adoption_report.json`
records held and controlled captures; `numeric_report.json` and `cc_numeric.npy`
record direct helper contracts; `control_metrics.json` records zero/gradient
results; four `shared_*` replay folders and `motion_metrics.json` record measured
controls/transitions; `actual_report.json` verifies actual configs.
`adoption_verification.json` records initial/final production hashes and scope;
`artifact_manifest.json` hashes archived evidence. [Local review](../captures/neutral_cc_20261103/review.html).

The shared-code change and documentation are uncommitted and not pushed.
