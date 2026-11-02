# Arc BLACKS 0.0025 trial — 2026-11-01

**Arc trial complete; subsequently adopted in both profiles by explicit user request.**
The user requested testing an isolated reduction from `BLACKS=0.005` to
`0.0025`. Four gameplay/menu cases show useful dark-material and neighboring-
shade gains with exact held repeats. Chart quantization, some palette and small
motion-step costs remain. The later authorized edits set Arc 0.005→0.0025 and
GZW 0→0.0025. The trial evidence below is Arc evidence; it does not assess that
GZW change. Post-edit active-config captures were deferred when the user asked
to wrap up and continue later.

## Scope and input contract

Only `BLACKS` changes in isolated Arc `creative_values.fx` copies. `WHITES=0.995`,
exposure, inverse strengths, CC, lift, print and every other setting remain.
During the trial, production profiles/configs/shaders, header comments, resources,
histories, rates and pass counts were preserved. This is profile tuning rather than a
shared shader enhancement or an automatically selected black level.

At the affine input boundary, source channel `x` changes by
`trial-current = -0.0025*(1-x)`. Source white still maps to 0.995; the input black
pedestal halves. Downstream grading remains live, including the guarded inverse
anchor's use of BLACKS. The final rendered change is not assumed to equal that
simple affine difference or to interpolate every channel between the old and
zero-offset outputs.

The trial-time 0.005 baselines come from the verified weak-color checkpoint and
the subsequent current-code bedroom/menu capture. Reuse checks source, profile,
normalized grade, isolated files, shared shader and clip hashes. The zero-offset
diagnostic is reused only for Arc interior, with WHITES still 0.995. It is a
single earlier observation, not a new zero-offset repeat suite.

## Held material and light results

Visible gaps use fixed source-L quartile groups in the existing source-selected
regions, measured in Oklab L ×100. Relative gaps use those same groups' mean
log2 linear Y. The native neighboring ratio is the median signed output/source
log-Y difference at a four-pixel horizontal offset. The
[tonal-material report](2026-11-01_tonal_material_selectivity.md) defines the
source-only filters and region limitations. These are descriptive measurements,
not fidelity scores; more contrast is not universally better.

| Region | Current visible L gap | Trial | Current neighboring ratio | Trial |
|---|---:|---:|---:|---:|
| Interior dark metal | 7.7517 | 8.9821 | 0.5727 | 0.7546 |
| Interior warm floor | 32.3939 | 32.6785 | 0.9375 | 0.9590 |
| Interior cool upper | 19.7903 | 20.3708 | 0.9524 | 0.9980 |
| Interior cool window | 30.5956 | 31.9572 | 0.8359 | 0.8925 |
| Daylight vehicle | 13.4380 | 14.6688 | 0.8265 | 0.9861 |
| Daylight road | 19.4273 | 19.6941 | 0.9783 | 0.9901 |
| Bedroom doorway/stairs | 9.1801 | 10.4963 | 0.7269 | 0.8975 |
| Bedroom cloth | 37.3847 | 38.9314 | 0.8497 | 0.9054 |
| Bedroom plaster/rack | 16.2184 | 16.8821 | 0.8673 | 0.8983 |
| Bedroom floor | 17.4681 | 17.6884 | 0.8711 | 0.8819 |

Selected dark-metal visible separation improves about 15.9%; vehicle improves
about 9.2%, doorway/stairs 14.3%, cool window 4.5%, and bedroom cloth/plaster
about 4.1%. Both whole-region and local measurements improve across these
selected materials. Native crops show a clearer dark anchor and less veiled
material shading. This retains existing source variation; it does not recover
information already clipped or quantized away.

The dark-metal comparison illustrates why the intermediate value is useful:

| BLACKS | Visible L gap | Relative gap, stops |
|---|---:|---:|
| Source | 11.3974 | 2.6367 |
| 0.005 trial baseline | 7.7517 | 1.5257 |
| 0.0025 trial | 8.9821 | 1.9497 |
| 0 diagnostic | 11.1324 | 2.8374 |

The trial restores part of the relationship without the zero diagnostic's
source-relative overshoot in this region. Metal median L falls 19.5240→17.5892
against source 16.6206. The vehicle also gains useful shape while darkening
21.1204→19.8196 L. These are intentional appearance changes, not a repair of an
arithmetic defect in the previous profile.

White-core median L remains 95.4956; its visible gap increases slightly
5.8150→5.8347. Red-lamp gap grows 18.3994→18.4902. Halo visible/relative contrast
expands a little, including 1.2910→1.2986 stops against source 1.1605. Daylight
road relative separation moves 1.7733→1.8149 against source 1.7703; sky moves
0.5812→0.5860 against source 0.5565. Cloud visible separation grows
5.5605→5.5809 against source 4.7282. Those small overshoot costs remain rather
than being labelled universal restoration.

Selected warm-floor source-relative hue shift grows about 3.6064°→3.6757°;
red-lamp shift grows 0.9564°→1.0176°. Cool-upper, sky and cloud hue shifts become
slightly smaller in magnitude. The lower pedestal also changes weak material
chroma; this is not exact palette identity or a universal color-fidelity claim.
Whole-image sampled mean changes range about 0.41–1.55 ΔE across the four cases,
with maximum changes of seven to nine channel codes. All four candidate/repeat
pairs are pixel-identical. No case adds black or code-255 channel samples.

## Charts and retained quantization costs

Two Arc-profile fixtures cover the existing hue/brightness chart and the
previous modified dark native-boundary source. That dark fixture contains
deliberately lowered constant-color faces; it is diagnostic material, not an
additional game or unmodified native gameplay. Both current and trial repeats
are exact for both fixtures. No new black or code-255 channel samples appear;
maximum code changes are eight/seven respectively.

Standard-chart row measurements average 32 identical-source scanlines and use
fixed adjacent pairs whose source channel changes are at most one code, excluding
identical pairs. The largest local pair ΔE growth is 0.16929, and the largest row
p99 growth is 0.10655. These are increased dark-gradient step sizes, not an
improvement in banding. Dither is unchanged. The headless UNORM-to-8-bit capture
does not establish visibility on every actual game/display path.

The dark fixture uses the same nine source-color masks, eroded by two pixels
inside the modified face region. Maximum p95–p5 field-spread growth is about
0.00413 L / 0.00235 log-Y stops. Native review shows no conspicuous new rim on
this fixture. The dark synthetic blue's source-relative hue shift worsens
-1.2848°→-2.1418°, about 0.86°. Other fields have smaller costs or gains, such
as the blue-gray field improving 5.2043°→3.9281°. The candidate retains these
finite synthetic-color and quantization costs.

## Measured sparse motion and cuts

Two independent private replays compare 0.005 and 0.0025 at the same measured
source/token/source-update/cut-update identities, with an independently sampled
ordinary 0.0025 output as the extraction control. All 96 candidate/actual
controls are exact on the common 12,984-sample support, including marker/border/
overlapping atlas-tag masks. No sampled new black or code-255 channels appear.

BLACKS has only two ordinary function consumers: affine color mapping and the
guarded inverse anchor. The diagnostic holds the baseline constants at 0.005
in copies of both functions while ordinary rendering uses a local 0.0025
profile. Other producers and history recurrences remain unchanged. Explicit
clock/state readback supplies ages; ordinary static captures contain no hidden
history telemetry.

| Window | Current maximum duplicate-step ΔE | Trial | Repeat current / trial |
|---|---:|---:|---:|
| Night | 0.119213 | 0.119931 | 0.119660 / 0.120504 |
| Return | 0.762004 | 0.742766 | 0.760880 / 0.741703 |
| Daylight | 0.135270 | 0.144894 | 0.135270 / 0.144894 |

The return maximum decreases, while small night/daylight increases remain.
Cross-run temporal repeats reach one code, with candidate maximum mean repeat
change about 0.00294 ΔE; daylight repeats are exact. This does not establish
a general temporal improvement. The cached source remains 15 unique poses/sec
duplicated at 30 fps. Appended pose 2220 is excluded; sparse measured results do
not prove dense native gameplay or physical high-refresh behavior.

## Audit, recommendation and activation state

The complete trial uses seventeen fresh private headless GPU processes:
eight held captures, seven chart captures and two measured replays. All have
zero dropped/delayed frames. Eighteen verified ordinary images are reused.
Static runs use five seconds compile wait and twenty seconds continuous
settling; elapsed warmup alone is not universal convergence proof.

The audit verifies 142 isolated files and 333 images, eight reused baseline
pairs, four held trial pairs, both chart current/trial pairs, all sixty exact
RGB frames of the new dark-fixture clip, and 96 same-update extraction controls.
All production shader/profile/trial-config and both active-config hashes matched
the trial checkpoint. The subsequent profile-only edits are recorded below.
The 22 tooling tests and whitespace checks pass. There is no fresh numerical
GPU helper, actual-active-config trial, whole-chain rating or new-game claim.

The evidence supported recommending 0.0025 as the Arc profile candidate, with
the costs above. The user then explicitly requested 0.0025 in both profiles and
redirected further improvement work to underlying shared code, without further
configuration/profile investigation. Both creative files now use 0.0025. All
other profile bytes, shared shaders and both config files remain unchanged;
`activation_state.json` records the exact before/after hashes and scope check.

The user requested wrapping up before post-edit runtime checks. Those checks
remain unperformed. Arc's saved 0.0025 trial may be reused only after identity
checks; GZW's prior BLACKS=0 images are not current-profile baselines. The weak-
color verification remains the shared-shader checkpoint, not a certification
of either actual active config after these profile edits. No new effectiveness
rating, commit or push is made. Future work should assess shared shader code.

Local ignored artifacts: `captures/arc_black_20261101/report.json`,
`metrics.json`, `charts_report.json`, `chart_metrics.json`, `motion_metrics.json`,
`audit.json`, isolated profiles/configs, source media, screenshots and logs.

- [Interactive source/current/trial review](../captures/arc_black_20261101/review.html).
- [Metal, including zero diagnostic](../captures/arc_black_20261101/arc_interior_dark_metal_candidates.png).
- [Vehicle](../captures/arc_black_20261101/arc_day_rear_body_candidates.png).
- [Bedroom cloth](../captures/arc_black_20261101/arc_bedroom_cloth_candidates.png).
- [Dark boundary](../captures/arc_black_20261101/dark_boundary_comparison.png).
