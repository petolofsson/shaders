# Night-settling stage and control attribution — 2026-10-27

Completes the next attribution step from the
[consecutive cut assessment](2026-10-27_temporal_cut_coverage.md). The dominant
night response comes from shadow lift: its smoothed strength drives the early
jump, and its later specular-protection release drives a second jump. Zone
contrast accounts for a smaller residual, and the direct ambient-tint cut gate
accounts for most of the first residual color step after lift and zone removal.
FilmCurve, chroma and print do not explain the dominant settling in this window.
No production shader, profile, history rate or active config changes follow.

## Same-update method and coverage

Ten fresh private headless replays use the verified existing Babylon source,
unchanged original packet prefix, five-second compilation wait and original
20-second continuous pre-roll. Both existing profiles are retained. All source,
profile, config, shader and diagnostic hashes are recorded, and every run
reports zero dropped/delayed frames. No desktop fallback or physical display
change is used.

The diagnostic extracts the current `ColorTransformPS` executable body and
calls the actual shared helpers. Immediately before the ordinary color pass,
it evaluates local image interventions against the same post-inverse BackBuffer,
spatial surfaces, scene context and previous histories. The ordinary full grade
still runs and advances all histories normally. The interventions only affect
the frozen diagnostic images; they do not alter subsequent targets or updates.

The atlas freezes 32 consecutive GPU updates after the night cut, poses
1440–1500, at both measured presentations of sixteen unique poses. Every record
contains pose/token/source-update/cut-update identity, and all 32 keys match
across the ten runs. All these night records are inside the original clip.
This is 15-pose/sec input duplicated at 30 fps, with native point samples rather
than full-resolution motion imagery.

Each image is a 160×90 native point sample at pixel `(16*x+4,16*y+4)`. A two-pixel
tile border plus common masks for the new atlas tag and the older comparison
atlas tag leave 12,984 samples in every image. The same support applies to source,
full, bypass, control and repeat comparisons. Spatial dither uses the native
pixel position. Frozen results use RGBA32F and explicit binary context readback.

An eighth atlas variant samples the real ordinary grade output immediately
after its color pass. The extracted full diagnostic and ordinary full output
are pixel-identical on valid samples at all 320 measured updates across the ten
runs. This checks the diagnostic's source domain, pass position, dither and
output quantization empirically. Comparisons with the preceding run's full
images retain small elapsed-time/repeat variation and are not treated as exact
same-update controls.

| Batch | Runs | Interventions evaluated simultaneously |
|---|---:|---|
| Stage attribution, GZW and Arc full/repeat | 4 | Full; lift, zone, film, chroma, look and tonal bypasses; actual-full control |
| Measured-control holds, GZW and Arc full/repeat | 4 | Full; first-cut lift strength, specular contrast, context ratio and all lift controls held; lift bypass; lift+zone bypass; actual-full control |
| Residual attribution, GZW full/repeat | 2 | Full; lift+zone bypass; lift+zone+ambient bypass; ambient bypass; tonal/lift/zone bypasses; actual-full control |

There are 2,560 frozen point images. Oklab distances below use the ×100 scale.
Consecutive images of the same source pose/token have byte-identical source
samples, so their differences isolate state evolution. Bypass effects interact
nonlinearly and are not additive contribution percentages or quality scores.

## Stage attribution

| Image intervention | GZW maximum identical-source step ΔE | Arc maximum identical-source step ΔE |
|---|---:|---:|
| Full | 0.646525 | 0.652269 |
| Lift bypass | 0.216603 | 0.162076 |
| Zone bypass | 0.653236 | 0.659558 |
| FilmCurve bypass | 0.646525 | 0.652269 |
| Chroma bypass | 0.653297 | 0.645489 |
| Look bypass | 0.676659 | 0.671586 |
| Tonal bypass, FilmCurve retained | 0.002484 | 0.002366 |

The full peak is at night update four. Lift bypass removes most of that peak
and the broad output brightening, leaving a later residual at update eight.
Zone bypass alone retains the dominant full response; its smaller signed change
can partially cancel or reinforce lift. Tonal bypass leaves only a small step.
Retinex's zone-spread gate is zero throughout this window in both profiles,
consistent with the preceding controlled Retinex-off replays.

The first/last mean L values illustrate the response without assigning a
preferred brightness. GZW full moves 19.268→21.190, while lift bypass moves
18.253→16.762. Arc full moves 19.178→21.173 and lift bypass 18.157→16.740.
The source also moves through the scene; the identical-pose step measurements
separately remove that motion from the causal comparison.

FilmCurve's equal peak and endpoint summaries initially suggested exact image
identity. The pixel audit finds a small contribution in GZW: up to four samples
per image change by one code at updates five through eight. Maximum mean
full/bypass difference is 0.000061824 ΔE; Arc's valid samples are pixel-identical.
The nonzero GZW result is retained. It is far below the dominant temporal response.

Chroma and look bypasses leave the main settling. Look bypass also changes the
absolute lightness and permits channel code 255 in up to 151 GZW / 34 Arc
samples where full output has none. All sampled exact source-black pixels remain
black, and these interventions add no exact-black samples relative to full.
These are diagnostic bypass observations, not proposed replacements for the
existing look or evidence about unsampled pixels.

## Two distinct lift-control transitions

The image uses a product of smoothed lift strength, local detail protection,
slow-key/zone-key context gain and specular protection. Only the strength is
inside the existing adaptive-history recurrence; the context and specular
factors multiply it afterward in `ApplyTonal`.

Separate diagnostics retain the full histories while holding the measured
first-night-update strength, specular contrast or slow-key/zone-key ratio.
A dedicated RGBA32F observation captures those first values before any image
intervention. Its records remain constant within each run and match the native
first context to within 0.000003 readback uncertainty. The context-ratio hold
does not change the already computed corrective lightness pivot or other context
fields. No producer or recurrence is frozen.

| Identical-source step / intervention | GZW ΔE | Arc ΔE |
|---|---:|---:|
| Update 4, full | 0.637794 | 0.647975 |
| Update 4, strength held | 0.030716 | 0.030902 |
| Update 4, specular contrast held | 0.637794 | 0.647975 |
| Update 18, full | 0.532788 | 0.537719 |
| Update 18, strength held | 0.250806 | 0.237762 |
| Update 18, specular contrast held | 0.007992 | 0.009201 |
| Update 18, context ratio held | 0.526174 | 0.530994 |

The first peak follows lift strength: its used value rises from approximately
0.443 on the first update to 1.078 on update four and approaches 1.5. Holding
specular contrast has no early effect because protection is already at its
0.65 floor. Holding the context ratio does not remove that peak either.

The second peak occurs after lift strength is essentially constant at 1.5.
The published p90 and p50 make `specular_contrast` fall through its smoothstep,
releasing attenuation from 0.65 toward one at updates 16–20. Holding that
measured contrast reduces the update-18 step to about 0.008–0.009 ΔE, comparable
to its maximum same-phase repeat bound of 0.008256/0.009638. Strength held at
its smaller first value still permits a reduced late jump; the context hold
retains nearly the entire late jump.

Independent CPU evaluation of the source formulas from GPU context records
puts the GZW context gain near 3.26 at entry and 3.36 at update 32. The product
of strength, context and specular attenuation grows approximately 0.94→5.05
before the local detail/profile factors. These are control coefficients, not
RGB output or exposure values. SDR output remains bounded by the existing path.
The slower context drift contributes to the small later steps and is distinct
from the larger early strength and later specular-release events. The earlier
slow-key precision audit and its deliberate time constants remain preserved.

## Zone and ambient residual

Holding all three lift controls leaves a maximum duplicate-pose step of
0.206851 GZW / 0.140891 Arc, both at update eight. Lift bypass gives
0.216038/0.161525 in the same batch. Removing zone adjustment as well reduces
the peak to a first-update color step of 0.068308/0.056288. The later zone
residual is therefore independently present, even though zone bypass alone
does not suppress the dominant lift response.

The final GZW batch isolates ambient tint. It overrides the local `scene_cut`
argument only after `BuildSceneCtx` has computed all adaptive values and gates.
At that point the direct image consumer of this field is `ApplyAmbientTint`;
the real detector and all actual histories continue unchanged.

| GZW first identical-source step | Mean ΔE |
|---|---:|
| Lift + zone bypass | 0.068278 |
| Lift + zone + ambient-tint bypass | 0.002468 |
| Tonal bypass | 0.002484 |

The ambient factor `(1-scene_cut)` changes from zero to one between the first
two identical night inputs. This explains most of the remaining color step
after lift and zone removal. Across all 64 full/repeat update records in this
batch, the three-intervention output differs from tonal bypass by at most one
code and 0.000027798 mean ΔE. Remaining small corrective/chroma state evolution
and numerical reconstruction costs are retained.

## Verification, limits and next work

Maximum per-image full repeat difference across the batches is 0.017367 mean
ΔE, while the paired same-update full/actual control is exactly zero. Repeats
bound replay variability; causal interventions within one update share the
same histories and timing. All 32 phase keys and source hashes match across
the ten replays. The read-only audit verifies 3,274 artifacts, including all
frozen atlas extractions, records, profiles, sources, completed runtime logs,
controls, plots and full-output equivalence at all 320 measured updates.
All 22 diagnostic tooling tests and the whitespace check pass.

Ignored [captures/night_attribution_20261027/](../captures/night_attribution_20261027/)
retains stage, measured-control and residual runners, isolated shader/config/
profile snapshots, ten runtime reports and 2,560 images. `metrics.json`,
`controls_metrics.json`, `residual_metrics.json`, `residual_identity.json`,
`lift_control_terms.csv`, contact sheets and plots retain the comparisons;
`audit.py` and `audit_report.json` retain integrity checks. Helper scripts/media
remain local and ignored.

This completes attribution for the measured night window. The holds and bypasses
are diagnostics. A repair needs to preserve useful steady-state lift, source
structure and existing spatial safeguards while addressing the complete control
transition, including specular protection and direct cut gates. No frozen
first-frame value or global bypass is adopted, and no profile is retuned.

Next: assess a conservative temporal treatment for lift/control and cut-gate
transitions, with held-scene and motion rejection controls including daylight
poses 1428/1432. Larger timing variation, dense unique gameplay, physical high
refresh, remaining resolutions/aspect ratios, broader games and active-chain
resource sharing remain open. The older effectiveness estimate is not re-scored.
