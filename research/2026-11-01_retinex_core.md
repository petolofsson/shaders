# Retinex native-response soft core — 2026-11-01

**Rejected on the four-case held screen. Production is unchanged.** The user's
“next” instruction continued the search after the zone/lift composition decision.
This candidate produces larger lit-paving and cool-window gains, with shaded
paving/wall and several local material-response costs. It does not demonstrate
a consistently useful default improvement.

## Candidate and anticipated tradeoff

The current Retinex uses a bounded native log response plus its original spatial/
native correction ratio. The candidate softens only the native response near
the scene key:

```text
d = log2(scene_key) - native_source_log_Y
baseline_native_log_gain = clamp(0.35*d, -0.35, 0.35)
candidate_core = d*abs(d)/(abs(d)+0.5)
candidate_native_log_gain = clamp(0.35*candidate_core, -0.35, 0.35)
```

The original `spatial_gain/native_gain` ratio, final gain clamp, Retinex strength,
native-guide conditioning, zone/lift/film/chroma/look, histories/rates/resources
and eight grade passes remain. It is not the previously rejected replacement
of the complete spatial model with a direct curve, nor coarse-edge strength
fading. There is no new tuning surface. All code changes are isolated grade-body
copies; profiles/configs, headers and production shaders remain.

The native log-gain difference reaches about 0.1166 stops before the existing
Retinex mix. Saturated outer native responses match again beyond about 1.367
stops from the key. Delaying saturation introduces a risk: the old saturated
transition can acquire new compression even as the center becomes gentler.
This was identified before judging the images, not inferred solely from a
larger gap in a favored region.

An independent CPU helper sweep covers 245,820 output contexts: 4,097 positive
luminances from 1e-6 to 1, four supplied keys, three fixed spatial correction
ratios, and five strengths from zero to one. The guide uses the existing 0.001
floor. Output stays positive and monotone at fixed context; zero strength and
the outer native responses above 1.367 stops match exactly. Minimum sampled
log-Y slope is about 0.6752. The candidate-minus-baseline slope spans about
-0.3248 to +0.3481 over these supplied contexts, confirming displaced compression.
Those values are not observations of actual scene strengths or proof of
whole-pipeline spatial monotonicity. No numerical GPU contract is claimed.

## Current held observations

Four fresh candidate processes use Arc interior, Arc bedroom/menu, GZW daylight
and Arc daylight sources. Baseline reuse starts from the current weak-color
verification and the preceding verified bedroom capture. Both distinct profiles
remain, including GZW inverse luma 0.60/tint -0.015 and Arc BLACKS 0.005.

Fixed regions, source-L quartile groups and source-selected neighboring pairs
are unchanged from the [tonal-material report](2026-11-01_tonal_material_selectivity.md).
Visible L gaps are Oklab ×100. The local ratio uses native horizontal four-pixel
pairs. These regions include illumination/object boundaries, and neither metric
is a quality score or a requirement to match source contrast exactly.

| Region | Baseline visible L gap | Candidate | Baseline neighboring ratio | Candidate |
|---|---:|---:|---:|---:|
| GZW shaded paving | 10.3121 | 9.8126 | 1.1017 | 1.0344 |
| GZW lit paving | 17.2628 | 18.0399 | 1.1198 | 1.1372 |
| GZW wall | 12.7307 | 12.3910 | 1.1188 | 1.1156 |
| Arc interior warm floor | 32.3939 | 32.2301 | 0.9375 | 0.9326 |
| Arc interior cool upper | 19.7903 | 20.0397 | 0.9524 | 0.9485 |
| Arc interior cool window | 30.5956 | 30.7483 | 0.8359 | 0.8745 |
| Arc bedroom cloth | 37.3847 | 37.3894 | 0.8497 | 0.8468 |
| Arc bedroom plaster/rack | 16.2184 | 16.1992 | 0.8673 | 0.8610 |
| Arc bedroom floor | 17.4681 | 17.4663 | 0.8711 | 0.8710 |

The lit-paving visible gap gains about 4.50%; the cool-window local ratio gains
about 4.62%. These are useful directions rather than a negligible perturbation.
However shaded paving loses about 4.84% visible separation and wall about 2.67%.
The warm-floor local ratio loses about 0.52%; cool upper loses about 0.41% despite
its larger whole-region gap. Bedroom cloth/plaster local ratios lose about
0.33%/0.72%. The bedroom floor barely changes.

The shaded-paving relative whole-region gap moves 1.1452→1.0964 stops, closer
to source 1.0689, while median L falls 39.7558→39.6215 against source 43.2883.
Thus its lower contrast is not automatically a fidelity regression, but it also
does not establish improved nuanced shadow appearance. Lit-paving relative
separation expands 1.4569→1.5176 stops against source 1.4006. Judging solely by
larger gaps or closeness of one statistic would favor conflicting conclusions.
Native review does not justify accepting the broader shaded-material/local
response costs for the selected gains.

Arc sky visible separation grows 7.6603→8.1672 toward/slightly beyond source
8.0070, but relative separation grows 0.5812→0.6206 stops, farther from source
0.5565. Cloud visible separation falls 5.5605→5.3149 against source 4.7282.
The selected vehicle region is unchanged. These remain tonal tradeoffs, not
evidence that the candidate recovers unknown scene information.

The finite decision rejects this default soft core. No directional variant,
width/strength sweep, new effect, profile retuning or score increase is queued.

## Validation scope

All four private headless GPU processes have zero dropped/delayed frames. Each
uses five seconds compile wait and twenty seconds continuous settling, with
marker checks and masks. That protocol does not prove universal convergence.
Candidate observations are single runs, without candidate-repeat or temporal
claims. Early rejection does not require adoption-level validation.

Maximum candidate/baseline changes are five codes GZW daylight, three interior,
six Arc daylight and one bedroom. Corresponding sampled mean ΔE is about
0.26256 / 0.09806 / 0.23554 / 0.04706. No case adds black or code-255 channel
pixels. Ordinary captures contain no hidden history telemetry.

The identity/scope audit verifies 80 isolated files and 20 images, including
sixteen reused baseline/repeat images; all eight baseline pairs are exact.
Source, clip, profile, normalized-grade and shared shader identities match.
Production shader/profile/trial-config and both active-config hashes remain.
All 22 diagnostic tooling tests, fixed-context CPU checks and whitespace checks
pass. No numeric GPU, zero-bypass GPU, boundary-chart, motion/cut or actual-config
adoption claim follows. Current production validation/hashes remain at
`captures/weak_color_20261031/verification.json`. No commit or push is made.

Local ignored artifacts: `captures/retinex_core_20261101/report.json`,
`metrics.json`, `scalar.json`, `audit.json`, isolated code/profiles/configs,
capture media and runtime log paths.

- [Lit paving](../captures/retinex_core_20261101/gzw_day_lit_paving_candidates.png).
- [Shaded paving](../captures/retinex_core_20261101/gzw_day_shadow_paving_candidates.png).
- [Cool window](../captures/retinex_core_20261101/arc_interior_cool_window_candidates.png).
- [Bedroom plaster/rack](../captures/retinex_core_20261101/arc_bedroom_plaster_candidates.png).
