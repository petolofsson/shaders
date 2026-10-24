# Preserve shadow separation in local contrast — 2026-10-24

The local contrast shadow arm subtracted an offset based on distance below the
zone median, then clamped the result to zero. At a fixed nonzero median, its
subtraction stayed nonzero as pixel luminance approached black. This creates a
flat black interval and loses distinctions between positive shadow inputs.
The preceding dark GZW check alone did not establish its extent. Reviewing
the matched GZW sunset and rendering a contextual neutral ramp did.

## Change

`general/grade/grade.fx`, in `ApplyTonal`, replaces
`max(L + adjustment, 0)` with
`L / (1 + max(-adjustment, 0) / max(L, 1e-10)) + max(adjustment, 0)`.
For positive L and negative adjustment, the result approaches zero smoothly.
The positive arm and a zero-adjustment bypass retain their original mapping;
exact black remains black. No new control, branch, history, or exposure is
introduced. Existing creative values still determine contrast strength.
The tradeoff is less aggressive darkening below the local pivot, specifically
where the previous subtraction consumed much of the available luminance.

## Evidence

All captures use fresh processes, continuous lossless RGB playback, 5-second
compile delay, 20-second settle, and an unchanged full repeat. The original
and corrected shaders render the same source PNGs under the same tuning and
configs. Previously retained baselines were checked against the starting
shader/profile hashes; their only shader difference from the candidate is
this change to `grade.fx`. They remain fixed-startup comparisons, not proof
of universal temporal convergence.

The diagnostic ramp has 64 steps (8-bit codes 0–63), a ±2-code checker texture,
and four surrounding brightness contexts. It is a disposable input under
ignored `captures/contrast_toe_20261024/`, not a golden-image suite.

| Surrounding context scale | Distinct step medians, original → corrected | Positive steps at zero, original → corrected | Textured steps retaining ≥1 code, original → corrected |
|---|---:|---:|---:|
| 0.25 | 60 → 60 | 1 → 1 | 60 → 60 |
| 0.50 | 56 → 58 | 7 → 2 | 56 → 60 |
| 0.75 | 32 → 50 | 11 → 5 | 29 → 51 |
| 1.00 | 20 → 46 | 14 → 7 | 18 → 49 |

Step medians sample the flat half of each ramp across four replicated columns;
texture counts cover nominal input codes 4–63, using the median difference of
the bright/dark checker phases in code-domain Rec.709 weighted gray. Neither
metric measures perceived fidelity by itself. Some lowest steps still end up
black after the full chain. Exact-black step centers remain RGB (0,0,0).
Both original and corrected median step sequences are nondecreasing.
Original/candidate unchanged repeats were 0.000/0.005 ΔE. The zero-strength
bypass differs by at most one 8-bit channel code between runs.

The genuine GZW sunset (`autof_20260515_133932.png`) shows:

| Metric | Original | Corrected |
|---|---:|---:|
| Whole-frame exact black | 2.42497% | 0.49620% |
| Whole-frame max RGB < 5 | 5.65002% | 3.65200% |
| Source-selected shadows becoming exact black | 4.30558% | 0.10973% |
| Source-selected shadows becoming near black | 10.84757% | 6.29712% |
| Eligible adjacent shadow pairs below 0.5 output code difference | 2.98463% | 0.42162% |

Shadow selection is 4 < max(source RGB) <= 64; the marker is excluded. There
are 1,616,740 selected pixels and 540,770 eligible horizontal pairs whose
source weighted-gray difference is ≥2 codes. The original/corrected unchanged
repeats are 0.01206/0.000002 ΔE. Whole-image original→candidate change is
0.451 ΔE (4× spatial sampling), which describes magnitude, not improvement.
Zone contrast remains active: corrected full-minus-bypass is 0.96 ΔE compared
with the original 1.39. The correction restores detail while retaining a
stronger contrast operation than the bypass.

## Artifacts

- Original ramp: [report](../gamespecific/gzw/full_analysis/alternate/effects_2026-10-24_142004.json), `captures_2026-10-24_141812/`.
- Corrected ramp: [report](../gamespecific/gzw/full_analysis/alternate/effects_2026-10-24_142254.json), `captures_2026-10-24_142103/`.
- Original sunset: [report](../gamespecific/gzw/full_analysis/alternate/effects_2026-10-24_025209.json), `captures_2026-10-24_024326/`.
- Corrected sunset: [report](../gamespecific/gzw/full_analysis/alternate/effects_2026-10-24_142503.json), `captures_2026-10-24_142309/`.
- Ignored `captures/contrast_toe_20261024/` retains the original shader, starting hashes, ramp/region definitions, measurement scripts/JSON, and `ramp_comparison.png`.

Regression checks are recorded below. GZW and Arc Raiders
creative values and both GZW configs remain unchanged; shader header comments
are preserved. The normal GZW four-effect config still lacks shared analysis
resources, so the demonstrated benefit is in the combined trial. Matched
moving Babylon capture remains a separate outstanding validation task.

## Dark, bright and color regression

| Input/profile | Exact black %, original → corrected | Source-selected shadow black %, original → corrected | Whole-image change ΔE | Corrected unchanged repeat ΔE |
|---|---:|---:|---:|---:|
| gzw_sunset | 2.42497 → 0.49620 | 4.30558 → 0.10973 | 0.4513 | 0.000002 |
| gzw_dark | 0.02984 → 0.00616 | 0.00000 → 0.00000 | 0.0083 | 0.000009 |
| gzw_cloud | 0.68403 → 0.01118 | 1.92908 → 0.01723 | 0.2683 | 0.000001 |
| gzw_vivid | 4.08545 → 0.35954 | 20.75643 → 1.51575 | 0.7426 | 0.000008 |
| arc_cloud | 0.34318 → 0.00692 | 0.95855 → 0.00618 | 0.1368 | 0.002704 |

Cloud and vivid sources are Arc Raiders stress inputs. `gzw_cloud` and
`gzw_vivid` use the GZW profile; `arc_cloud` uses the Arc Raiders profile in
its combined trial. They are not GZW calibration footage. Every test adds
zero white-channel clipping. Source-bright regions (max source RGB ≥217)
change by less than 0.002 ΔE on average under the GZW profile. In the vivid
stress image, source-vivid regions change by 0.0357 ΔE on average with zero
median hue shift. The pointwise correction does not establish hue fidelity
for arbitrary scenes. Region analysis uses 4× spatial subsampling; endpoint
counts use full resolution with the activity marker masked.

Full paired measurements and source-selected region definitions are retained
in `captures/contrast_toe_20261024/comparisons.json` and `compare_candidate.py`.
The measured ramp plot is `ramp_response.png` in the same directory. Candidate
reports retain each fresh full/repeat capture and runtime logs.

The active Arc Raiders four-effect chain also compiled and rendered the vivid
reference with a near-zero unchanged repeat; this is a runtime check, not an
old/new comparison of its inactive cross-effect contrast path. All retained
full/repeat images were inspected in `regression_contact_sheet.png` and show
the intended unobscured scenes. Source-selected exact-black pixels remain
RGB (0,0,0) in every tested image containing them. The 12 diagnostic tests
pass, and `git diff --check` is clean. Both tuning files and both GZW configs
match the starting hashes.

## Two-cut recovery check

The corrected [dark→sunset→dark probe](../gamespecific/gzw/full_analysis/alternate/transition_2026-10-24_143133/report.json)
completed six fresh continuous-playback captures. Sunset at 0.5→6 seconds
changed by 0.12654 ΔE; returned dark at 0.5→6.5 seconds by 0.21090. Returned
dark at 6.5 seconds remained 0.32020 ΔE from the initial settled frame,
essentially the earlier 0.320 observation. By 18 seconds it differed by
0.0000346 ΔE. All six playbacks reported zero dropped/delayed frames.
This supports keeping the contrast correction without a newly observed static
cut-recovery problem. The pre-existing adaptation lag remains; this test uses
static source images and does not establish moving-edge stability or motion
history behavior. Those are the next validation/improvement targets.

Follow-up: [near-black zone precision](2026-10-24_shadow_zone_precision.md)
improves the measurements feeding this contrast path and shadow lift. Its
normal-output and cut-recovery results are recorded separately.
