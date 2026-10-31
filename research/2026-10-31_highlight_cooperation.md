# FilmCurve / print highlight cooperation — 2026-10-31

**Adopted and validated. This finite highlight-cooperation decision is closed.**
The user authorized moving to the next recommended candidate after the combined
tonal-gain limits were rejected.

## Mechanism and scope

The candidate keeps FilmCurve, including its overrange protection, and the print
power toe. It measures the actual fractional linear-luminance loss through the
strength-blended FilmCurve. That per-pixel scalar is passed through `ApplyLook`
to `ApplyPrintStock`, where it relieves overlapping secondary print-shoulder
compression:

```text
film_loss = saturate(1 - Y_after_FilmCurve / max(Y_before_FilmCurve, 1e-10))
power_rgb = max(print_input, 0)^1.15
shoulder_rgb = existing_secondary_shoulder(power_rgb)
print_loss = Y(power_rgb - shoulder_rgb) / max(Y(power_rgb), 1e-10)
relief = film_loss / max(film_loss + print_loss, 1e-10)
print_rgb = lerp(shoulder_rgb, power_rgb, relief)
```

The existing print desaturation, shadow-protected color ratios, couplers and
strength blend follow. This is smooth overlap restraint, not a claim of an
exact physical print model or a strict maximum of the two losses. The losses
are relative quantities in their respective processing domains, separated by
chroma/gamut processing. No source HDR data or clipped information is recovered.

When FilmCurve spends no luminance, print retains its existing shoulder. With
print/look disabled, the relief is unused. The original FilmCurve always runs;
the candidate does not shift its knee or weaken the user-selected print toe.
The earlier 1.5→0.75 shoulder-coefficient decision remains intact. This is a new
consumer coupling rather than another sweep of that coefficient.

Only three grade functions and their internal argument plumbing would change.
No profile setting, resource, history/rate, pass, exposure behavior, output format
or user-facing control is added. GZW inverse luma remains the external 0.60.
Current GZW baselines come from the preceding tonal screen at 0.60; Arc baselines
come from verified current-code captures. A vivid GZW-profile view requires a
fresh baseline at 0.60. That vivid source itself is an Arc screenshot and is
labelled by profile, not misrepresented as another GZW scene.

## Early held result

The selected Arc white-core visible L gap rises 5.33386→5.81497, about 9.0%.
Its relative gap rises about 0.2460→0.2675 stops and median L 94.9669→95.4956.
Selected halo and red-lamp pixels remain unchanged in the first observation.
No selected core code-255 channel pixels are added. First held/repeat pairs are
exact. GZW daylight paving/wall/foliage and Arc vehicle/road/sky selections are
unchanged; cloud visible gaps rise modestly (GZW 28.3893→28.4811 and Arc
5.5481→5.5606). All six final held/repeat pairs are exact, and all six baseline pairs are exact.
The selected shelf, dark metal, warm floor, paving, wall, foliage, vehicle, road
and blue-sky pixels are unchanged. The interior cool-window rectangle contains
88 changed bright-detail pixels (at most two codes); the dark surfaces remain.
Six held comparisons add no black or code-255 channel pixels. Whole-image
changes reach four codes in brighter parts of the set.

The independent print-helper GPU probe uses 1,280 gray and mixed-color inputs,
strengths 0/0.7/1 and baseline/selected functions: 7,680 records. Frozen supplied
FilmCurve-loss fractions include zero and positive losses. CPU agreement is
within 0.000000423; repeat readbacks are identical and strength-zero GPU controls
match. The 256 supplied-zero FilmCurve-loss cases also match the baseline
readback exactly (these belong to the lower-input mixed-color group). The
separate CPU composition sweep includes bright zero-FilmCurve inputs. This probe validates the new helper math with explicit scalar inputs;
it does not infer offscreen state from ordinary screenshot pixels.

A separate CPU sweep composes the actual rational FilmCurve formula and print
relief on gray input Y=0–4, two knees, four FilmCurve strengths and three print
strengths. Tested curves are monotone and bounded, with film-zero print identity.
The sweep includes a clipping stand-in for the intervening SDR boundary; it is
not a full chroma/gamut model or a proof over all spatial contexts.

Final held, bypass, boundary, motion and actual-config results below support
adoption. No effectiveness score increase is awarded from this focused screen.
Local scripts/media: `captures/highlight_cooperation_20261031/` (ignored).

## Boundary and zero-control observations

Two profile variants of the 24-band hue/brightness chart add no new input
fixture design or profile tuning. Final output differences are at most two codes.
At row centers, source-adjacent changes of at most one code define smooth pairs.
The maximum increase in adjacent-output pair ΔE is 0.35014 (GZW) / 0.35860 (Arc).
Most rows are unchanged. This retains a small quantization cost; it is not a
claim of universal banding improvement or a dense two-dimensional continuity proof.

Arc FilmCurve-zero and look-zero pairs are pixel-identical. GZW look-zero is
also exact. The first GZW FilmCurve-zero comparison differs in a single pixel
by one code, with zero mean/p99 ΔE on the ordinary subsampled metric. This
observation is retained. Both unchanged zero controls repeat exactly, and their
cross-comparison retains that same one-pixel/one-code difference. It is persistent
rather than explained by measured repeat variation. Its precise numerical cause
is unproven. This bounded difference is accepted as a numerical bypass residual;
bit-exact GZW FilmCurve-zero identity is not claimed. The helper GPU contracts
with explicitly supplied zero loss remain independent of this whole-pipeline
observation.

History producers are unchanged and do not consume the new scalar. The cut
technique therefore renders old/new consumer views against the same GPU update,
and separately extracts the actual candidate output. Four fresh replays cover
both profiles and repeats, with explicit source/token/source-update/cut-update
identities. All 192 candidate/actual extraction controls are exact on the
common 12,984-pixel support, with no added black or code-255 channel samples.

## Measured transitions

| Profile/window | Baseline max duplicate-step ΔE | Candidate | Repeat baseline / candidate |
|---|---:|---:|---:|
| GZW night | 0.113115 | 0.113115 | 0.112824 / 0.112824 |
| GZW return | 0.725352 | 0.723312 | 0.722382 / 0.720523 |
| GZW daylight | 0.130015 | 0.124991 | 0.129793 / 0.124819 |
| Arc night | 0.117988 | 0.117988 | 0.118061 / 0.118061 |
| Arc return | 0.762340 | 0.760771 | 0.762555 / 0.760987 |
| Arc daylight | 0.140263 | 0.135324 | 0.142531 / 0.137524 |

The candidate is pixel-identical to the original consumer in these night windows.
Return/daylight steps are slightly smaller here; no universal temporal improvement
is claimed. Candidate temporal repeats reach two codes / mean ΔE 0.009164 for GZW,
mostly in unchanged night views; Arc reaches one code / mean ΔE 0.003831. These
are phase-matched temporal repeats with real timing variation, distinct from the
six exact static pairs. Maximum same-update candidate/baseline mean change is
0.166891 ΔE. The source remains 15 unique poses/sec doubled to 30 fps; this is
sparse measured continuity, not dense native gameplay or physical high refresh.

The stage/history producers do not consume the new relief scalar, and their
formulas and rates are unchanged. Baseline and candidate consumer views therefore
share the same live state in each replay; these are not falsely described as
independent old/new history trajectories. Both profiles and their repeats use
fresh processes and measured integer source/cut ages.

## Adoption decision

The pre-adoption artifact audit passes six exact held baseline/repeat pairs,
six exact candidate/repeat pairs, both profile charts, the documented bypass
results, the independent helper probe and 192 exact motion extraction controls.
The light-core separation benefit is repeatable while selected ordinary materials
and the useful print toe remain. The chart quantization cost, small changes in
bright cloud/window detail, and the persistent one-pixel GZW FilmCurve-zero
residual are retained rather than described as solved.

The candidate is adopted. Only `ApplyPrintStock`, `ApplyLook` and the argument/
loss calculation in `ColorTransformPS` change. Shader header comments, profiles,
active configs, earlier working changes, history producers/rates, resources,
pass count, FilmCurve itself and the print power toe remain. No extra effect,
knob, auto-exposure or HDR output is introduced. Current GZW inverse luma 0.60
and all other current profile edits are preserved.

This is a bounded highlight-cooperation enhancement. Whole-chain, FilmCurve and
print effectiveness scores are not freshly re-rated; a nine-percent selected
core-gap improvement is not a nine-point score increase or proof of universal
appearance improvement. The earlier GZW 0.30 rating evidence retains its profile
epoch. No new mandatory repair or additional parameter search follows.

Both actual active-config full/repeat pairs match the isolated candidate exactly:
GZW daylight and Arc emitters all have maximum code difference 0 and mean ΔE 0.
The final artifact audit verifies 182 isolated files and 644 images, including
all four actual outputs. Protected profile/config/inverse/history identities pass.

The screen completes 28 fresh ordinary captures (including two targeted GZW zero
repeats), two numeric readbacks, four cut replays and four actual-config outputs:
38 new private/headless GPU processes, all with zero dropped/delayed frames.
Ten existing ordinary baseline images are verified and reused. All 22 diagnostic
tooling tests and whitespace checks pass. Fresh static captures use five seconds
of compile wait and twenty seconds of continuous settling; elapsed warmup is a
protocol rather than proof of complete convergence. Marker/tag masks and measured
GPU ages are used for the corresponding static/temporal claims. Other games,
resolutions, dense native motion, physical high refresh and calibrated-display
acceptance remain outside the measured scope. GPU performance is unprofiled.
No commit or push is made. Artifacts/scripts/media remain ignored under
`captures/highlight_cooperation_20261031/`; this report is versioned.

- [Interactive final comparison](../captures/highlight_cooperation_20261031/review.html).
- [Small-light core comparison](../captures/highlight_cooperation_20261031/arc_emitters_white_core_final.png).
- [GZW cloud comparison](../captures/highlight_cooperation_20261031/gzw_day_cloud_final.png).
- [Shadow shelf comparison](../captures/highlight_cooperation_20261031/gzw_dark_shelf_final.png).
