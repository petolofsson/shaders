# Weak material color preservation — 2026-10-31

**Adopted and validated. This finite weak-material color decision is closed.** The user authorized proceeding to the remaining recommendation after
the highlight-cooperation improvement was adopted.

## Concrete target and candidate decision

The previous print-ratio change improved palette preservation but reduced some
subtle cool-material color distinctions. This screen targets the measured blue
wall and cool-window losses rather than adding a global saturation increase.
The baseline includes adopted highlight cooperation, inverse/print color work
and preserved current profiles, including GZW inverse luma 0.60 and tint -0.015.

Two initial isolated candidates reduce the ratio-preserving print weight when
print-input Oklab C/L is weak. One uses the full smooth chroma gate, the other
retains half the original weight. Relative chroma uses C/max(L,0.001), with a
smooth transition over 0.03–0.12. These are internal calibration constants, not
new creative controls or hue-specific masks.

The unrestricted full gate improves selected blue-wall color separation about
3.8% and cool-window separation about 2.8%, but reduces warm-floor separation
about 1.6%. It also worsens the Arc bright-cloud source-relative hue shift from
-2.2424° to -4.3852°. The half version offers smaller target gains; it is checked
on three initial cases rather than represented as a seven-scene decision.
The unrestricted response is not selected because the cloud regression undoes
part of the preceding palette improvement.

The refined `bounded` candidate fades protection out over print-input linear
Y=0.10–0.25. Thus weak lower-tone colors can retain more of the original channel
curve, while brighter colors retain the current ratio path:

```text
relative_C = length(Oklab(print_input).ab) / max(Oklab(print_input).L, 0.001)
color_weight = smoothstep(0.03, 0.12, relative_C)
color_weight = lerp(color_weight, 1, smoothstep(0.10, 0.25, input_Y))
ratio_weight = existing_smoothstep(0.01, 0.10, input_Y) * color_weight
print_rgb = lerp(existing_channel_print, existing_ratio_print, ratio_weight)
```

Both mixed paths have the same linear luminance by construction, apart from
floating-point roundoff. Existing deep-shadow, print toe, highlight relief,
manual print strength and couplers remain. This does not identify reflectance or
artistic intent. It is a bounded cooperation change within the print helper.

## Early refined results

All color gaps below use fixed source-b quartile groups and Oklab ab separation
on the ×100 scale, not a quality score. Masks/rectangles are retained from prior
material attribution. L gaps use fixed source-L quartile groups.

| Selection | Current baseline | Brightness-guarded candidate |
|---|---:|---:|
| GZW blue-wall color gap | 1.24709 | 1.29513 |
| Arc cool-window color gap | 2.43064 | 2.50258 |
| Arc warm-floor color gap | 5.24287 | 5.19879 |
| Arc bright-cloud hue shift | -2.24243° | -2.24243° |
| Arc white-core visible L gap | 5.81497 | 5.81497 |
| Arc red-lamp visible L gap | 18.39935 | 18.39935 |

The target gains are modest: about 3.85% and 2.96%. The refined warm-floor cost
is about 0.84%. Blue-wall source-relative hue shift grows slightly, about
4.5768°→4.6045°. Bright-cloud palette and the preceding light-core gain are
retained in these early refined observations. Other regions, muted-scene,
repeat, endpoint and temporal results are recorded in the final validation
sections below; adoption remains pending at this checkpoint.

A CPU print-helper sweep covers 622,689 valid fixed-context inputs over eight
lightnesses, 72 hue rays, 1,025 chroma samples and three supplied FilmCurve-loss
fractions. All sampled valid adjacent chroma steps remain positive; gray output
matches baseline within double precision. This tests sampled helper response,
not full-pipeline spatial behavior, every possible RGB value or adaptive timing.
The initial unrestricted model/results remain separately preserved.

No new effectiveness score is assigned. Numeric GPU, boundary, zero, measured
motion and actual-config results will determine final adoption or rejection.
Local scripts/media: `captures/weak_color_20261031/` (ignored).

## GPU and luminance contracts

The 7,680-record helper GPU probe covers 1,280 gray/mixed-color inputs at print
strengths 0/0.7/1, with fixed zero/positive supplied FilmCurve-loss fractions.
Both readbacks are identical. Maximum CPU-reference error is 0.000000423, and
the maximum observed baseline/candidate helper-Y difference is 0.0000000597.
Print strength-zero controls preserve the GPU inputs. The existing highlight
relief is exercised equally in both helper versions.

An independent 4,913-color CPU RGB grid at three FilmCurve-loss fractions and
three print strengths preserves helper luminance within 3.3e-17 and remains
bounded. These are helper properties: downstream couplers, quantization and
Oklab reporting can still change final luminance slightly.

The initial standard hue/brightness charts are retained as strong-color controls.
Dedicated low-saturation hue ramps and chroma ramps are also checked under both
profiles to exercise the C/L transition directly. Their layout and hashes are
saved separately; ordinary source screenshots are not treated as hidden GPU
state telemetry. Boundary and temporal metrics are pending.

## Held cost/benefit and transition observations

The brightness-guarded helper preserves the previous selected bright-cloud hue
and white-core visible gap. GZW shaded-paving color separation rises
1.90240→1.99311 (about 4.8%); wall separation rises 1.04122→1.09562 (about 5.2%).
The selected warm-floor gap loses about 0.84%; daylight foliage color separation
loses about 0.48% and its hue shift grows 3.5251°→3.8111°. Muted foliage changes
very little (gap 2.93109→2.92491, median C 3.27717→3.28421), with no measured hue
penalty. These modest costs are retained. Strong blue-sky median C is unchanged;
the wider blue-field gap loses about 0.19%. This is partial preservation of weak
color variation, not restoration of every earlier loss or a universal material
improvement. Native crops supplement the gap numbers, which are not quality scores.

Both look-zero comparisons are pixel-identical to their verified current-code
controls. The preceding highlight task's GZW FilmCurve-zero residual remains a
historical observation; this task does not claim to repair it or incorrectly
expect FilmCurve-zero to disable the new independent weak-color response.

Four new private cut replays compare old/new print consumers at the same measured
GPU update and extract the actual candidate output independently. Source pose,
token and source-update/cut-update ages match. All 192 candidate/actual controls
are exact on the common 12,984-pixel support. No added black/code-255 channel
samples appear. The producers do not consume the new local print quantities;
producer code, histories/rates and pass order remain unchanged.

| Profile/window | Baseline max duplicate-step ΔE | Candidate | Repeat baseline / candidate |
|---|---:|---:|---:|
| GZW night | 0.112897 | 0.113460 | 0.113086 / 0.113563 |
| GZW return | 0.720822 | 0.720769 | 0.717449 / 0.717252 |
| GZW daylight | 0.125296 | 0.125352 | 0.124819 / 0.124874 |
| Arc night | 0.117766 | 0.119057 | 0.117885 / 0.119274 |
| Arc return | 0.760922 | 0.761032 | 0.757608 / 0.757476 |
| Arc daylight | 0.137428 | 0.137490 | 0.137524 / 0.137585 |

Small night-step increases are retained. Candidate temporal repeats reach one
code, with maximum mean ΔE 0.005584 GZW / 0.005497 Arc. Maximum same-update
candidate/baseline mean difference is 0.015012 ΔE. This does not establish a
general temporal improvement. Cached source remains 15 unique poses/sec doubled
to 30 fps; sparse update-matched results do not prove dense native gameplay or
physical high refresh. Ordinary static captures contain no highway telemetry.

Both dedicated low-saturation charts are complete. Across the standard and weak
charts, output changes are at most one code, with no added black or code-255
channel pixels. Dedicated weak-ramp maximum local pair ΔE growth is 0.40264 GZW /
0.39845 Arc; maximum row p99 growth is 0.01233 / 0.07837. These small quantization
costs remain explicit; larger differences between adjacent codes are not
presented as universal banding improvement. The standard charts mostly retain
the original output. The chart row-center selection and source-smooth pair mask
are documented in `boundary_metrics.json`.

The pre-adoption artifact audit passes seven exact baseline pairs, seven exact
brightness-guarded candidate pairs, exact look-zero controls, four chart/profile
combinations, the numerical contracts and 192 measured motion extraction
controls. The bounded candidate is adopted for its targeted weak-color recovery
with retained bright palette/light behavior. The unrestricted variants are not
adopted. Native review indicates a subtle change, not a substantial all-scene
transformation or a guarantee of improved physical material reflectance.

Only the ratio-path weight inside `ApplyPrintStock` changes in this task.
All earlier highlight/inverse work, profiles, configs, shader header comments,
histories/rates/resources and pass count remain. GZW inverse luma stays 0.60.
The new RGB-to-Oklab conversion is local arithmetic; no analysis feedback or
exposure behavior is introduced. GPU performance remains unprofiled.

Both actual active-config full/repeat pairs (GZW daylight and Arc interior)
match their isolated candidates pixel-for-pixel: all four comparisons have maximum
code difference 0 and mean ΔE 0. The final artifact audit verifies 252 isolated
files and 664 images, with protected profiles/configs/other shaders unchanged.
The selected shelf, white core, red lamp and muted neutral-sky pixels also match
their baseline exactly; weak-region benefits do not require bright-light changes.

The complete finite screen adds 41 ordinary captures, two numeric readbacks,
four measured cut replays and four actual-config outputs: 51 fresh private GPU
processes, all with zero dropped/delayed frames. Sixteen existing baseline/control
images are verified and reused. This includes retained unrestricted/half variants;
only the brightness-guarded version is adopted. All 22 diagnostic tooling tests,
whitespace checks and artifact checks pass.

Static captures use fresh processes, five seconds of compile wait and twenty
seconds continuous settling. This is a fixed protocol, not a universal history-
convergence guarantee. Ordinary screenshots contain no hidden state telemetry.
The numerical probe and measured cut records use explicit readback; marker and
atlas-tag footprints are masked in their respective image metrics.

No fresh effectiveness score is assigned. The measured gain is modest and does
not establish an 80/100 chain, universal material acceptance or untuned new-game
behavior. Broader games, aspects/resolutions, dense native motion, variable timing
and physical high-refresh coverage remain optional confidence work. No further
mandatory parameter screen or shader repair is queued. No commit/push is made.

- [Interactive final comparison](../captures/weak_color_20261031/review.html).
- [Blue-wall comparison](../captures/weak_color_20261031/gzw_dark_blue_wall_final.png).
- [Cool-window comparison](../captures/weak_color_20261031/arc_interior_cool_window_final.png).
- [Preserved light cores](../captures/weak_color_20261031/arc_emitters_white_core_final.png).
