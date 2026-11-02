# Zone contrast / shadow-lift composition — 2026-11-01

**Rejected after three exact candidate/repeat pairs. Production is unchanged.**
The user authorized the proposed test of applying lift gain to zone-shaped
luminance. The candidate has small, repeatable benefits in paving and several
cool/cloth regions, but worsens the two targeted floor regions. Its algebraic
cooperation does not establish consistently better material separation.

## Concrete mechanism

Let `y` be post-Retinex luminance, `z` the zone-shaped result, and `g` the existing
per-pixel lift gain coefficient, including the unchanged lift fade, detail
protection, adaptive product, manual strength and `SHADOWS` setting.

```text
baseline:   final_Y = z + y*g
candidate:  final_Y = z + z*g = z*(1+g)
difference: candidate - baseline = (z-y)*g
```

The isolated implementation changes only the amplitude used by `lift_w`:

```text
before: lift_w = shadow_base_luma * smoothstep(0.35, 0, shadow_base_luma)
after:  lift_w = new_luma         * smoothstep(0.35, 0, shadow_base_luma)
```

Thus lift classification remains unchanged. The existing coefficients and manual
gain ceiling remain; absolute added lift changes with the zone-shaped value.
There is no new source classifier, global-key taper, combined-gain limit, spatial
filter or control. Profiles, headers, resources, histories/rates, stage order and
eight grade passes remain. All edits exist only in isolated shader copies.

At a fixed lift gain, the zone correction is carried through by the same gain.
In actual images, `g` varies across shades and lighting. The original rationale
that this might preserve material contrast is therefore a hypothesis, not a
general consequence of the formula. Downstream Hunt/chroma/print responses also
remain live.

An independent CPU composition sweep covers 551,265 fixed contexts: 257 positive
luminances from 1e-10 to 2, 65 supplied zone ratios from 0.5 to 1.5, and 33 supplied
lift gains from 0 to 0.5. The zone-delta identity agrees within 5.56e-16. Zero-zone
and zero-lift contexts agree exactly with baseline, and positive fixed-context
response is monotone. These are standalone algebra checks, not full-pipeline
monotonicity, actual-context range bounds or numerical GPU bypass contracts.

## Matched held results

The baseline is current production at the weak-color checkpoint, with both
preserved profiles, including GZW inverse luma 0.60 and Arc `BLACKS=0.005`.
Current interior, bedroom/menu and GZW daylight sources use the same fixed
regions and source-selected neighboring pairs as the preceding
[tonal-material screen](2026-11-01_tonal_material_selectivity.md).

Visible gaps are differences between fixed source-L quartile groups, measured
in output Oklab L ×100. The neighboring ratio is the median signed output/source
log-Y difference at a native four-pixel horizontal offset. The earlier report
documents the source-only pair filters and their limitations. Neither metric
is a quality score or a requirement to match source contrast exactly.

| Region | Baseline visible L gap | Candidate | Baseline neighboring ratio | Candidate |
|---|---:|---:|---:|---:|
| GZW shadow paving | 10.3121 | 10.3263 | 1.1017 | 1.1030 |
| GZW lit paving | 17.2628 | 17.2850 | 1.1198 | 1.1208 |
| Arc interior dark metal | 7.7517 | 7.7544 | 0.5727 | 0.5730 |
| Arc interior warm floor | 32.3939 | 32.3838 | 0.9375 | 0.9365 |
| Arc interior cool upper | 19.7903 | 19.8181 | 0.9524 | 0.9531 |
| Arc interior cool window | 30.5956 | 30.6170 | 0.8359 | 0.8370 |
| Arc bedroom cloth | 37.3847 | 37.4156 | 0.8497 | 0.8503 |
| Arc bedroom plaster/rack | 16.2184 | 16.2469 | 0.8673 | 0.8677 |
| Arc bedroom floor | 17.4681 | 17.4481 | 0.8711 | 0.8683 |

Most selected benefits are small: visible separation increases about 0.13–0.14%
in the paving, 0.14% in the cool upper region, 0.07% in the cool window, and
0.08%/0.18% in bedroom cloth/plaster. The warm floor loses about 0.03% visible
separation and 0.11% in its neighboring ratio. The bedroom floor loses about
0.11% visible separation and 0.32% in its neighboring ratio. Its relative
whole-region gap also falls 1.5165→1.5145 stops; warm-floor relative separation
falls 2.4962→2.4952 stops. The configured near-black pedestal remains.

Native crops show subtle changes, with no convincing improvement sufficient
to accept the mixed floor response. This rejects the candidate on the measured
goal, rather than because small improvements are intrinsically unacceptable.
No half-strength sweep, new effect, profile retuning or score increase follows.

## Repeats, identity and scope

Six fresh private headless GPU processes capture the candidate and unchanged
repeat for each of the three cases. All three pairs are pixel-identical. Every
process has zero dropped/delayed frames, using five seconds compile wait and
twenty seconds continuous settling. This protocol is not proof of universal
history convergence. The intentional activity marker is checked and excluded
from image metrics.

Candidate/baseline changes reach one code in GZW daylight/interior and two codes
in the bedroom. Sampled mean ΔE is 0.02851 / 0.01460 / 0.02327 respectively, using
the established stride-four interior samples. No case adds black or code-255
channel pixels. These image measurements are not offscreen-state telemetry.

The audit verifies 88 isolated files and 22 images, including sixteen reused
baseline/repeat images. All eight available baseline pairs are exact. Reuse
checks current production hashes, source/profile/normalized grade, isolated-file
and clip identities. Production shader/profile/trial-config hashes and both
active-config hashes remain unchanged. All 22 diagnostic tooling tests and
whitespace checks pass.

The rejection screen does not claim independent numerical GPU, zero-bypass GPU,
boundary-chart, motion/cut or actual-config adoption validation. No production
change is selected, so current production baseline hashes remain in
`captures/weak_color_20261031/verification.json`. No effectiveness re-score,
commit or push is made. No further mandatory repair or composition sweep is queued.

Local ignored artifacts: `captures/zone_lift_cooperation_20261101/report.json`,
`metrics.json`, `scalar.json`, `audit.json`, isolated shaders/configs/profiles,
capture media and runtime log paths.

- [GZW paving](../captures/zone_lift_cooperation_20261101/gzw_day_lit_paving_candidates.png).
- [Interior cool window](../captures/zone_lift_cooperation_20261101/arc_interior_cool_window_candidates.png).
- [Interior warm floor](../captures/zone_lift_cooperation_20261101/arc_interior_warm_floor_candidates.png).
- [Bedroom floor](../captures/zone_lift_cooperation_20261101/arc_bedroom_floor_candidates.png).
