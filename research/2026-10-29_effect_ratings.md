# Current effect effectiveness reassessment — 2026-10-29

For the latest recorded scores and subsequent implementation outcomes, use the
[current 0–100 board](2026-10-31_75_goal_report.md). This dated report retains its
original profile/code epoch and measurements; later focused judgments supersede
only the entries identified in the current board.

**Not every retained block reaches the 75/100 target.** My current estimate for
the complete chain remains **75/100, borderline**. Inverse chroma reconstruction,
the current three-way CC application and print/look are **70/100**. The other
listed blocks are at or above 75 within the assessed scope, including several
borderline 75s. This does not certify a game-agnostic 75+ result.

This user-requested review supersedes the current-assessment table in
[the October 25 ratings](2026-10-25_effect_ratings.md). It assesses the current
combined pipeline, including the guarded shadow reconstruction, and the existing
GZW/Arc profiles. No shader, profile, active config or effect strength is changed
to improve a score. Earlier working-tree changes are preserved.

## Meaning of the scores

These are approximate visual-effectiveness judgments on a 0–100 scale, not
measured fidelity percentages or statistical confidence levels. Five-point
increments are directional; uncertainty of roughly 5–10 points is reasonable
for the appearance-oriented blocks. A 75 entry is borderline and remains sensitive
to broader inputs and preference. A central estimate below 75 means the target
is not demonstrated, rather than a formally established population-level failure.

The assessment considers repeatable usefulness, source palette/lighting restraint,
artifact and transition costs, and consistency across the assessed inputs. Larger
delta-E, more chroma, darker shadows, fewer black pixels or more activity do not
earn points by themselves. Correct abstention on an unnecessary intervention is
positive behavior. Technical correctness supports the judgment but does not
substitute for useful appearance.

Foundation blocks are judged in their signal/measurement role; creative blocks
are judged by their contribution as currently used. The chain and grade are
judged separately, not averaged from the rows. Rows overlap and are not eighteen
independent effects whose pass rate can be averaged. Profile changes since
October 25 also affect this comparison: score changes cannot be attributed solely
to algorithm revisions or precision repairs.

## Reassessed ratings

| Effect or block | October 25 | Current effectiveness | Target judgment and evidence |
|---|---:|---:|---|
| Complete combined chain | 75 | **75** | Borderline. Useful depth, visibility and a coherent treatment in current inputs, with retained material, palette and bright-core costs. Two games and sparse motion do not establish universal acceptance. |
| Analysis frame | 80 | **85** | Meets its measurement role on assessed contracts. Normalized statistics, exact-count recovery, current-source observations and independent GPU readback support reliable downstream restraint. |
| Inverse grade / chroma reconstruction | 65 | **70** | Below target. Bounded expansion can restore color diminished by later processing, but the assumed compression model cannot establish that an arbitrary SDR source needs reconstruction. |
| Corrective zone/chroma/slow-key analysis | 80 | **85** | Meets its analysis/history role. Near-black precision, initialization and authoritative histories are independently checked; deliberate slow-key context and its remaining return tail stay explicit. |
| Grade overall | 75 | **75** | Borderline. Improvements cooperate usefully, but density, material separation and palette are not consistently better in every view. Grade-off controls preserve input inverse reconstruction and output bounds/dither. |
| Explicit sRGB / SDR boundaries | 90 | **90** | Meets its signal-handling role. Explicit linear-light processing, UNORM boundaries, bounded output and endpoint contracts remain strong. Wider physical-display acceptance is untested. |
| Gamut projection | 80 | **85** | Meets its bounded-projection role. The disconnected blue-ray defect is repaired and valid-input identity is protected. Extreme blue hue/separation and quantized-gradient costs remain. |
| Zone contrast | 75 | **80** | Useful separation with repaired scene-wide pivot/black-tail behavior and bounded strength. Cloud and some material-gap costs prevent a higher score. |
| Shadow lift | 75 | **80** | Useful dark-material visibility and better incoming transitions after the current-source coefficient repair. Broader sky eligibility, light/shadow flattening and dark quantization remain costs. |
| Print stock / look | 65 | **70** | Below target. Adds convincing density and some color restraint, but darkens/compresses small light cores and alters palette. A coherent style is not proof of broadly unobtrusive improvement. |
| Inverse-luma reconstruction | 80 | **75** | Borderline. Correct units, source-span restraint and guarded shadow preservation improve intended behavior; the partial inverse model and measured Arc vehicle gap cost remain. Better evidence moderates the earlier optimistic rating. |
| FilmCurve shoulder | 75 | **75** | Borderline. Luminance-preserving, restrained below the knee and active on compact white cores; it still spends core brightness and internal separation. |
| Active chroma processing | 70 | **75** | Borderline. Current zero saturation boost, gentle midtone response, shadow restraint and source-chroma floor avoid forcing richness. Visible contribution is modest; blue-gradient and dark-color generality remain limited. |
| Adaptive histories / cut handling | 70 | **80** | The gate/current-source lift repairs remove demonstrated large settling costs, with independently checked timing/state behavior. Sparse matched cuts support this scope, not dense native/high-refresh continuity. |
| Three-way CC, as currently applied | 65 | **70** | Below the appearance target. The tool executes predictably, but current cool shadow tuning cancels subtle shelf warmth and shifts selected foliage away from source hue. This is a preset-cooperation judgment, not an instruction to overwrite user settings. |
| Black/white mapping | 80 | **75** | Borderline as currently used. Useful deliberate range/visibility control; Arc's positive black offset is also the largest measured reduction in selected dark-metal distinctions. That user choice is preserved. |
| Spatial dither | 70 | **75** | Borderline. New controlled gradients demonstrate lower low-frequency quantization error with a one-code maximum cost and stable repeats. Pixel noise increases, and physical-display/general-game benefit is not certified. |
| Retinex | 80 | **80** | Bounded normalization, native-guide material preservation and repaired held-edge behavior make a useful contribution. It still compresses some lit-material relationships and cannot infer artistic lighting intent. |

The below-target group is deliberately left below 75. No score is rounded upward
to declare the goal achieved. Several improved technical confidence claims now
have much stronger support, while complete-chain effectiveness remains at the
same borderline estimate.

## Current runtime evidence

The assessment adds **42 fresh ordinary captures** and **three controlled dither
captures**, all private/headless with zero dropped/delayed frames. Five existing
current-code full/repeat pairs are reused after exact source/profile/helper
identity and normalized grade-code verification; their grade contains the actual
adopted guarded change. This is not reuse of the stable-1.0 pre-change baseline.
Two new input cases add fresh full/repeats, giving seven current scene repeat
pairs, all pixel-identical. The dither full/repeat is also pixel-identical.

| Case | Profile | Source filename | New comparisons |
|---|---|---|---|
| GZW day | GZW | `Screenshot_20260516_101035.png` | Inverse chroma/luma, CC, Retinex, zone, lift, film, chroma, look, endpoints and grade bypasses |
| Arc interior | Arc | `autof_20260515_205938.png` | Same eleven bypasses |
| GZW dark | GZW | `autof_20260515_133058.png` | CC, tonal, lift, chroma and look bypasses |
| Vivid Arc view | GZW | `autof_20260515_210958.png` | Inverse chroma, CC, chroma and look bypasses |
| GZW overcast/muted | GZW | `autof_20260515_133810.png` | Fresh full/repeat, CC, chroma and look bypasses |
| Arc emitters | Arc | `autof_20260515_210448.png` | Fresh full/repeat, film and look bypasses |
| Arc day | Arc | `autof_20260515_210825.png` | Endpoint and look bypasses |

Each new ordinary capture uses a fresh process, five-second compilation wait and
twenty seconds continuous lossless 30-fps RGB playback. Isolated profile copies
disable only the specified controls. The actual game profiles and active configs
retain their hashes. A fresh process/repeat protocol is not proof of universal
long-history convergence. Bypasses include downstream responses and therefore
are not additive stage budgets.

Current existing evidence also informs the reassessment: the
[shadow-stage study](2026-10-29_shadow_stage_preservation.md) supplies direct
cumulative GPU observations, numeric current-code checks, active dark boundaries,
zero-strength bypass and actual active-config verification. Its two-profile
candidate point replay covers 48 measured source/cut-age keys per profile using
unchanged history producers; its ordinary-full controls validate the extraction
of that study's baseline. This is not an independent dense current-game replay.
The [lift closure](2026-10-27_lift_transition_repair.md),
[Retinex decision](2026-10-27_retinex_material_preservation.md),
[gamut decision](2026-10-27_gamut_continuity_repair.md) and earlier
signal/history contracts support their unchanged implementation portions.
Those probes are historical evidence, not newly rerun tests in this review.

## Observations behind the appearance judgments

Material selections use fixed source rectangles and source-L quartiles, with
source masks for dark metal/wood, green foliage, neutral sky and light cores.
L/C use Oklab's 0–100 reporting scale. Whole-frame summaries subsample inside an
eight-pixel border; full endpoint counts exclude the intentional 2x2 marker.
UI remains in the actual source and analysis, especially Arc's trader view.
Source PNGs are references; the preceding direct readback found up to about
1.215-code file/rendered-input differences. Internal full/bypass comparisons use
the same backend. Subtle source-relative changes should not be overinterpreted.

**Shadow visibility and normalization:** GZW shelf median L is 12.212 full versus
11.101 with lift off; its visible gap is 4.388 versus 4.042. Lift contributes
readable structure. Print-off raises the shelf to 14.559 and its gap to 4.822,
but lowers relative contrast 1.643→1.506 stops. Deeper shadows, visible separation
and relative contrast remain separate judgments. In day paving, zone-off lowers
the lit-paving gap 17.102→16.001, while Retinex-off raises it to 19.204. These are
real opposing contributions rather than a reason to credit every normalization
stage merely for changing the picture.

**Palette:** Muted foliage median C is 3.685 source, 3.218 full and 3.587 CC-off.
Its source-relative hue shift is +11.256 degrees full versus -1.156 CC-off.
Daylight foliage is +12.266 full versus -2.810 CC-off. On the near-neutral dark
shelf, median C is 0.988 source, 0.359 full and 1.008 CC-off; a hue angle is not
reported for this weakly colored selection. These support a current CC/palette
limitation. They do not prove that a user's deliberate cool-shadow choice is a
software error or that disabling CC universally improves the image.

**Chroma and reconstruction:** In the vivid sky crop, median C is 10.233 source,
10.231 full, 9.566 inverse-chroma-off and 10.118 chroma-stage-off. The reconstruction
can help replace color lost elsewhere, and active chroma work is gentle. That
single matching chroma statistic is not evidence of fidelity or proof that the
source was compressed by the assumed model. Source-relative full hue shift is
3.351 degrees; print-off gives 0.082 degrees and C=11.309, showing that the stages
also compensate for one another. The grade already documents isolated blue
gradient amplification, so this review does not certify all blue shades/bands.

**Small lights:** White-core source/full visible gaps are 6.821→4.621 L.
Film-off raises the gap to 5.361; look-off to 5.861. Full core median L=94.065
versus 94.742 film-off and 96.724 look-off. The halo stays at 69.427 with film
disabled, demonstrating useful shoulder selectivity; print-off raises it to
71.800. Red-lamp C is 19.218 source, 19.008 full and 20.507 look-off: print can
restrain color while still compressing lamp structure. Existing clipped source
information is not recovered by reducing output code-255 counts.

**Dither:** Four procedural float-output gradient bands are injected immediately
before the current output dither in isolated grade copies. They compare actual
dither with a bounded no-dither output and an unchanged repeat, without changing
the live shader. For gray code 0–64, column-average RMS error drops 0.2960→0.0655
codes; code 64–192 drops 0.3045→0.0974; full gray drops 0.3005→0.0841. Pure blue
behaves similarly. Pixel RMS error increases about 0.30→0.42 codes, the expected
noise-versus-contouring tradeoff. Full/off changes never exceed one code, and
black/white endpoints remain exact. This is a private 10-bit UNORM capture to
8-bit PNG experiment, not recovery of original 8-bit source detail or a universal
physical-display/visibility study. It supports a borderline 75 in dither's role.

## Inventory limits: what “all effects” covers

The table covers the previously rated logical blocks, including infrastructure
and parent stages. Children are included in their parent contribution; this
review does not claim independent 75+ validation of every internal heuristic:

- DIR couplers belong to corrective grading/grade overall.
- Hunt coupling and ambient tint belong to tonal processing/grade overall.
- Sat-by-lightness, fixed green hue bias, memory-color nudges, ceilings and soft
  compression belong to the active chroma block; final projection is rated in its
  own bounded-gamut role.
- Print stock, masking and dye couplers belong to print/look. With printer lights
  neutral, PRINT_STOCK=0 and the look gate remove that same active bundle.
- Guided-filter passes support Retinex; SHADOWS and SHADOW_LIFT scale one lift
  contribution, while CONTRAST and the zone gate control one zone contribution.
  Duplicate controls/passes are not counted as separate successful effects.

The following controls are neutral in both current profiles and receive **no new
standalone effectiveness rating**: exposure, user hue rotations, optional
vibrance, user saturation boost/per-hue saturation, hue-selective luminance
contrast and printer lights. Their neutral setting is not a failure. Fixed
chroma operations remain active even with SATURATION=0 and VIBRANCE=0.
Diffusion is removed, so it is not a retained effect requiring a score.

## Decision and evidence limits

The 75+ target is **not met for every retained block** under this assessment.
The chain/grade's 75 estimates are useful but borderline current judgments.
Below-target rows identify appearance/cooperation limitations and uncertain
general usefulness, not newly demonstrated arithmetic defects. The strong
correctness/stability evidence does not erase those costs or establish a public
preference result.

This review uses two games with different preserved profiles, seven screenshot
cases and retained sparse/simulated temporal contracts. It does not establish
a unified untuned preset, new-game generality, dense native gameplay, physical
high refresh, every aspect/resolution, display calibration or subjective
population acceptance. Preference and confidence limits are disclosed without
turning them into another mandatory repair queue. No changes are adopted in
this assessment and no score-driven fixes are started automatically.

Local evidence: `captures/effect_reassessment_20261029/` contains `report.json`,
`metrics.json`, source/profile/config/grade snapshots, scene overviews, native
material crop strips, dither report/metrics and `audit.json`. The audit checks
all sixty RGB frames in each static clip against source pixels, all image and
isolated-file identities, current-code baseline reuse, every game repeat and
protected production/config hashes. All 22 diagnostic tooling tests pass.
The final audit passes 1,222 assertions across 275 unique image/configuration
artifacts and verifies 720 source-exact frames in twelve static containers.
Whitespace checks pass; production/profile/config hashes remain unchanged.

- [Interactive current/full/bypass review](../captures/effect_reassessment_20261029/review.html).
- [Emitter core comparison](../captures/effect_reassessment_20261029/arc_emitters_white_core.png).
- [Muted-scene comparison](../captures/effect_reassessment_20261029/gzw_muted_overview.png).
- [Dither enabled](../captures/effect_reassessment_20261029/dither_full.png) and
  [disabled](../captures/effect_reassessment_20261029/dither_off.png).

Scripts/media remain ignored local artifacts. This report is the current rating
checkpoint; the October 25 table is retained as history, not current acceptance.
