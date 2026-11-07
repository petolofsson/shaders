# Half-strength shadow-color restoration: adoption review

**Recommendation: offer this fixed half-strength color change for an explicit adoption decision as a modest material-color improvement.** It retains more of the game's weak shadow colors through the configured positive black offset, with subtle warmth/material distinctions in the reviewed shelf, timber and pack. It provides essentially no brightness-gradient improvement. The brightness lead remains open; the rejected compact curve and local-slope references are not included.

The tradeoff is real: more source chromatic variation, including noise, survives. In the measured full-chain code-16 noise fixtures, chromatic standard deviation rises about 24% versus current, while staying below the input in float. Quantized ordering/weak-color shifts and one-code repeat variation remain. This is not a claim of universally better shadows or elimination of tint/noise costs. Native appearance is an agent review, not blind/user or moving-game preference.

Production is unchanged. The concrete patch and local visual review are:

- `captures/shadow_color_half_review_20261106/candidate.patch`
- `captures/shadow_color_half_review_20261106/review.html`
- `captures/shadow_color_half_review_20261106/verification.json`

## Exact scope

Use the existing half-strength bounded candidate; no new strength or profile search was performed. Immediately after the early affine mapping `lin=(WHITES-BLACKS)*RGB+BLACKS`, add

```text
0.5 * BLACKS * gate(Y) * (RGB/max(Y,1e-6)-1) * common_headroom_budget
```

`Y` is actual decoded grade-input luminance. The source window fades in over 0.0005–0.005 and out over 0.08–0.15 linear Y. The common budget limits positive-channel correction using the affine result's available SDR headroom. In ideal arithmetic this correction has zero weighted luminance; it transfers some neutral pedestal into existing input-color ratios. Gray and exact black retain the existing mapping, and BLACKS=0 disables the addition. Downstream grading can change luminance slightly, as the same-update measurements show.

The proposal changes only the shared grade body. Profiles/configs/headers, producers, source observation, histories/rates, resources, passes, spatial dither and activity marker remain. Grade remains eight passes. There is no new control, exposure adaptation or HDR output. Current profiles both use BLACKS=0.0025 and WHITES=0.995; the current GZW FilmCurve/temperature/tint choices are preserved. Performance is unmeasured.

Current root grade SHA-256 is `efea23e8c8e061a77619c8c42f89f1d73c35523623ea90a1f3ee4028e8f40c56`. Applying the patch would produce root grade SHA-256 `2a49a3bd973b4adcd80299e2bdf878564c712ccbfb03089f902168173825d858`. The compiled isolated snapshot hash is `aa8439f1d7f7e4a243bca22a6002503aea6315529f7bc6c983784bf336d249fb`; its absolute include paths account for the different file hash. Normalized bodies are verified equal to exactly the current root plus the proposed insertion.

## Material/color evidence

The earlier two-scene [half-color screen](2026-11-06_subtle_shadow_color.md) records shelf group distance 0.327→0.420 and metal 1.575→1.779, with almost unchanged brightness gaps. The new [held warm-material screen](2026-11-06_shadow_color_held.md) adds an independent GZW timber interior. In source L 12–20 warm samples, group distances change 0.7015→0.7693 rear timber, 0.5573→0.6167 lower timber and 0.5396→0.7256 pack. Median L changes are small. These are source-selected Oklab ×100 group comparisons; groups can differ in brightness and distances are not quality scores. They do not cover the deepest red-black assets or establish a universal palette response.

An important [attribution correction](2026-11-06_shadow_neutral_alignment.md) is now recorded: all 5,744 GZW and 5,138 Arc sampled weak-color source pixels match grade-input RGB exactly in their existing screenshots. They did not acquire their measured color in inverse processing. All 56/109 sampled exact source grays also have identical current/half-candidate output. The weak-color mask is not an exact-neutral mask. Weak-source output casts can still change, particularly Arc's output chroma, so this correction does not remove all neutral-material appearance concerns.

The [same-update GPU comparison](2026-11-06_shadow_color_same_update.md) samples four 64×64 patches at four-pixel spacing. All four encoded repeats are exact; input and baseline match earlier independent float-detail readbacks exactly. In 1,247 eligible input-signed pairs neither baseline nor candidate reverses brightness order. Shelf/metal pre-dither a/b-group distances increase, confirming a genuine color change before screenshot quantization. Brightness-gap changes remain tiny and mixed. Thirty-one of 1,024 samples are excluded for low input Y or readback ceiling. These sparse patches do not clear the earlier larger-region screenshot reversal costs.

## Fresh broad still controls

Twelve fresh processes provide baseline/candidate repeats for GZW daylight, GZW-profile Arc vivid content, and Arc emitters. All six pairs are exact. These fresh baselines remove reliance on the older daylight inverse-snapshot provenance limitation for this control comparison. The vivid case is another Arc source under GZW settings, not a third game.

| Control | Maximum full-frame change | Selected response |
| --- | ---: | --- |
| GZW daylight | 3 codes | Foliage C 2.564→2.716; hue shift changes about -0.207°; neighboring brightness gap 0.169291→0.169041 stops |
| Vivid | 6 codes | Blue sky median C unchanged; blue-field L gap 27.3897→27.3733, C 6.4213→6.4572 |
| Arc emitters | 4 codes | White-core/halo selected shape and C unchanged; red-lamp L gap 18.5460→18.4923 |

The respective counts above two codes are 431, 1,035 and 27,851 pixels. No new all-channel-black pixels or code-255 channels appear in these controls. The six total ordinary still comparisons, including the earlier dark scenes and held warm scene, also add no black/255 samples; this is screenshot coverage, not an exhaustive endpoint proof. Native reviewed controls show no conspicuous broad tint, while the small foliage/red-light/quantization changes remain costs.

The held warm scene is not exact on repeat: candidate varies in 1,188 pixels by one code; its current baseline varies in 675. Retain both. Static warmup and exact pairs elsewhere do not prove full temporal convergence.

## Numeric, bypass and chart checks

One direct RGBA32F compiled probe exercises the actual half-helper statements on 256 constructed inputs, including gray, black, near-black mixed colors, primary/mixed colors and a headroom-active face. Both current profiles share its B/W values. Maximum RGB error against independent double precision is 2.94e-7 or less; luma difference from the affine base is at most 3.51e-7; gray difference is zero at readback resolution. Zero-BLACKS arithmetic matches `0.995*RGB` within 2.94e-7. One sample engages the headroom multiplier. This is finite sampled arithmetic, not an exhaustive GPU continuity/gamut proof. Nominal readback step is approximately 4.77e-7.

Two whole-chain BLACKS=0 baseline/candidate pairs, using isolated profile copies under the two games, are pixel-identical with the marker masked. Active profiles remain at 0.0025.

Eight fresh full-chain chart processes cover both profiles' neutral, warm, cool, mixed and neutral-to-warm 56-step ramps plus deterministic one-code red perturbations. Every mean-luma step is positive in every variant/profile; the mean perturbation response is positive at all levels. Candidate differences reach two codes and add no all-channel black samples. **All four chart repeat pairs vary by one code:** GZW baseline/candidate 13,104/18 pixels, Arc 13,766/11,062. Thus small chart changes are not exact between-process contracts or proof of pixelwise/color monotonicity. The source is synthetic; this is not real-game noise or dense motion.

## Measured motion and source-black/noise checks

Four independent private replays cover the cached 15-pose/sec Babylon source under both profiles and repeats. Source/token and explicitly measured source/cut-update ages match. Candidate clones match ordinary candidate output in all 192 controls on the common marker/tag mask. Temporal repeat maxima are one code in all night/return/daylight windows. Selected maximum same-source night/return steps are similar or slightly smaller; Arc daylight's mean-DE maximum rises 0.147600→0.147874. These small costs remain, not a universal temporal improvement. The diagnostic source is sparse and duplicated to 30 fps; dense game motion, actual grain and physical high-refresh behavior remain unassessed. Appended pose 2220 is not used in these claims.

A separate same-update RGBA32F probe samples exact source black and independent one-code RGB-noise fields at codes 8/16/32 under both profiles. Each band has 64 samples. The 64 black samples in each profile have zero grade input and identical baseline/candidate outputs, including both independent captures. The noise probe repeats are **not float-exact**: maxima are 2.55e-6 GZW and 9.98e-7 Arc, with input unchanged. No encoding-ceiling values occur.

| Noise fixture | GZW a/b std current → candidate | Arc a/b std current → candidate | Input std |
| --- | ---: | ---: | ---: |
| Code 8 ±1 | 0.1901→0.2294 | 0.1936→0.2338 | 0.3532 |
| Code 16 ±1 | 0.1971→0.2453 | 0.1993→0.2481 | 0.2845 |
| Code 32 ±1 | 0.2564→0.2782 | 0.2600→0.2819 | 0.2861 |

These continuous pre-dither values show restored noise alongside color. They are not perceptual thresholds or temporal-noise acceptance. Simulated 8-bit rounding can change the relation to input: Arc code-16 candidate std is 0.2896 versus input 0.2852. No 16-bit game output was enabled. Independent CPU random-color sampling also finds 45 of 100,000 cases with helper C above incoming C, maximum ratio about 1.0094; do not claim a universal source-chroma ceiling.

## Provenance and decision boundary

The audit checks 852 distinct referenced files and 18 ordinary configurations. Each ordinary configuration matches its corresponding active config after only isolated path substitution; copied profiles are exact, pipelines differ only in include paths, and grade bodies are exactly current or current plus the insertion. The retained Nov 4 material baselines' actual recorded shader/include hashes, profile text, source references, active configs and full/repeats also match current files. Labels alone are not used as identity proof.

Forty-three new completed private headless GPU processes in this validation have zero reported dropped/delayed frames. Source/profile/config hashes remain unchanged. Reports preserve logs and all repeat failures/variation. Local captures/scripts/review remain ignored; nothing is committed or pushed. Existing untracked research is preserved.

This is a **color-only adoption proposal with explicit costs**, not a whole-chain 80 claim, a brightness fix, or an automatic activation. Ratings stay at their retained provisional values. If the user adopts the patch, apply only this shared grade body change, then capture both unchanged actual active configs with repeats and compare them with the verified candidate before calling activation complete. No config/profile/header changes or parameter sweep are part of that step. Until that decision, production remains current.

Artifacts: `captures/shadow_color_half_review_20261106/` (patch/review/audit); `shadow_color_same_update_20261106/`; `shadow_color_held_20261106/`; `shadow_color_half_numeric_20261106/`; `shadow_color_half_controls_20261106/`; `shadow_color_half_motion_20261106/`, all under `captures/`.
