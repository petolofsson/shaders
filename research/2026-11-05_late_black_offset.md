# Late black-offset stage-order screen — 2026-11-05

**Decision: reject the candidate.** The user authorized testing whether moving the configured black offset after the grade would retain the black anchor while restoring shadow separation. This isolated version does neither in the selected examples: shelf and dark-metal gaps decrease, and exact-black source patches become brighter and more neutral. Production shaders, profiles/configs and scores are unchanged.

## Isolated candidate

The current mapping before corrective processing is `col.rgb * (WHITES-BLACKS) + BLACKS`. The isolated candidate preserves the `(WHITES-BLACKS)` multiplier but omits the early offset, adding `BLACKS` in linear RGB after look and before dither/output with `saturate`. Thus the configured value is not modified, but its interaction with every intervening stage and the actual output black point can change. This is one literal stage-order candidate, not a proof about every possible relocated-offset architecture. Zero-BLACKS bypass, pre-quantization black identity and HDR/gamut contracts were not numerically validated.

## Held stills

| Source-selected region | Current | Late offset | BLACKS=0 diagnostic |
|---|---:|---:|---:|
| GZW shelf: median L | 15.735 | 16.376 | 12.364 |
| GZW shelf: quartile L gap | 2.661 | 2.339 | 4.387 |
| Arc dark metal: median L | 17.589 | 18.047 | 14.958 |
| Arc dark metal: quartile L gap | 8.981 | 8.442 | 11.130 |

Fixed source L quartile gaps and source masks are not visual quality scores. On source-selected neighboring pairs at 1/4/16-pixel offsets, mean signed log-Y gaps change from 0.100760/0.115991/0.126915 to 0.087549/0.100787/0.110718 stops on shelf, and from 0.113594/0.136975/0.156600 to 0.103074/0.123050/0.138709 on dark metal. Selected cool window gap changes 31.973→31.768 and vivid blue-field gap 27.390→27.062. The candidate therefore does not restore the desired within-material gradient in these cases; disabling BLACKS is a counterfactual, not a proposed user-profile edit.

Four current-profile isolated candidate/repeat pairs cover GZW dark, Arc interior, Arc emitter and Arc vivid source under GZW settings. All candidate pairs are pixel-identical with the 2x2 marker masked, and all eight private GPU processes reported zero dropped/delayed frames. Whole-image maximum differences from current are 7/10/9/10 codes respectively. No newly all-channel-black pixels or newly saturated channel-255 samples were counted in these examples; this is not an endpoint or gamut proof. Selected white-core L gap is 5.860→5.883, white halo 20.449→20.402, red lamp 18.546→18.456. Existing current baseline and BLACKS=0 diagnostic capture epochs/identities are recorded in the November 4/5 reports; current baseline and isolated source/profile/config/shader hashes must match before reuse. Twenty-second continuous settling and still repeats do not prove motion stability.

## Exact source endpoint fixture

An independent 2560×1440 source fixture has black, white and code-64 gray fields. One current and one candidate capture for each profile use the same isolated chain and 20-second settling; all four private GPU processes report zero drops/delays. In central field rectangles away from the marker and boundaries, median 8-bit screenshot RGB for exact-black source is GZW current [5,6,6], candidate [8,8,8]; Arc current [5,6,7], candidate [8,8,8]. Dither produces adjacent codes. White medians are GZW [243,241,237] in both and Arc [243,242,240]→[243,243,240]. These are screenshot observations in this fixture's adaptive context, not a direct linear GPU readback or endpoint behavior across all scenes. Candidate exact-black is visibly raised numerically, not identical to the current configured response.

The four material candidate pairs and endpoint diagnostic isolated configs and grade files match capture hashes; production hash sets before/after match. No candidate gradient/edge charts, repeated endpoint captures, temporal controls, numerical GPU helper contract, zero bypass or actual active-config activation was performed; the early negative result does not justify adoption or a stage-order parameter sweep. Native comparisons, scripts and capture artifacts remain ignored in `captures/late_black_20261105/`.
