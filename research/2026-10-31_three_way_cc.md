# Three-way CC material-color preservation — 2026-10-31

**Adopted and closed:** half-strength shadow temperature/tint in both profiles.
Held repeats, measured cut controls and actual active-config verification pass.

The requested bounded CC follow-up selects gentler **shadow temperature/tint**
in the existing profiles. Midtone/highlight settings and shader weighting remain.
Half strength retains a visible cool-shadow direction while reducing cancellation
of subtle shelf warmth and the selected foliage shifts. Quarter strength tracks
some source colors more closely, but weakens the intended cool treatment further;
it is not selected as the default for this task.

The user explicitly authorized all tests and changes needed to finish three-way
CC. That permits the selected CC-only profile update after isolated comparison;
it does not authorize changes to unrelated settings, active configs or headers.
The earlier instruction to preserve profiles during assessment applies to the
screen; the subsequent authorization covers the adopted CC tuning.

## Cause and bounded alternatives

The existing correction adds a scene-relative weighted Oklab opponent-color
offset. At full shadow weight and black gate, `SHADOW_TEMP=-0.15` contributes
`b=-0.009`, or -0.9 on this report's 0–100 scale. GZW's `SHADOW_TINT=-0.05`
also contributes `a=-0.003`. Those shifts are comparable with the entire subtle
source shelf color, whose median C is about 0.988 on that scale. Source inverse
and subsequent grading also affect that relationship. This explains why a
predictable creative control can cancel weak warm material color.

Shadow weights use `1-smoothstep(key_L-0.10,key_L+0.04,L)`, with scene-key-relative
`key_L` in 0.30–0.80. Some dim foliage legitimately falls within that shadow
range. The issue is the strength of the current treatment in these profiles,
not a demonstrated arithmetic or initialization defect. Gentler tuning is tested
before changing tonal weighting, as requested.

Two isolated profile candidates scale only `SHADOW_TEMP` and `SHADOW_TINT`:

- **Half:** scale both existing shadow controls by 0.5.
- **Quarter:** scale both by 0.25.

A CC-off control zeros all six temperature/tint settings. That bypass also
removes the deliberate midtone/highlight treatment; it is an attribution control,
not the selected profile. Starting full output uses the newly adopted print
shoulder from the [print/look decision](2026-10-30_print_look_preservation.md).
No pre-print-change CC-off images are reused.

Both candidates and bypass are captured for GZW dark/day/muted and Arc interior.
Half is then checked on the vivid blue view, Arc daylight and Arc emitters, with
new CC-off controls and unchanged half repeats for all seven scenes. Starting
full/repeat pairs are reused only after exact profile/helper/source identity
and normalized grade checks against the verified post-print baseline.

## Held observations and decision

L and C use Oklab's 0–100 reporting scale. Visible L gaps compare fixed source-L
quartiles. Color separation compares mean output a/b vectors in fixed lower and
upper source-b quartiles; it describes selected color relationships, not known
material reflectance or recovered information. Source rectangles/masks are held
constant across variants. Hue angles are not reported for weakly colored samples.
UI remains in the ordinary screenshots. The whole-image neutral-shadow mask is
a color diagnostic, not semantic material segmentation.

| Selection / measurement | Starting full | Half | Quarter | CC off |
|---|---:|---:|---:|---:|
| GZW shelf median C | 0.359 | 0.694 | 0.839 | 1.008 |
| GZW shelf median b | 0.302 | 0.619 | 0.796 | 0.946 |
| GZW shelf color separation | 0.482 | 0.526 | 0.549 | 0.567 |
| GZW shelf visible L gap | 4.388 | 4.389 | 4.387 | 4.391 |
| GZW day foliage source-relative hue shift | +12.266° | +4.515° | +0.882° | -2.810° |
| GZW muted foliage source-relative hue shift | +11.256° | +4.845° | +1.896° | -1.156° |
| Arc dark-metal median b | -0.725 | -0.289 | -0.094 | +0.100 |
| Arc dark-metal visible L gap | 7.752 | 7.752 | 7.752 | 7.751 |
| Arc cool-window color separation | 2.407 | 2.594 | 2.689 | 2.950 |

Half restores more of the shelf's subtle warm variation without a lift/exposure
change. Shelf median L changes only 12.212→12.257; its visible luminance gap is
essentially unchanged. Arc metal remains cool while its large source-opposing
blue component is reduced. Arc cool-window color separation improves about 7.8%
without a meaningful luminance-gap change. This is not a claim that additional
chroma itself is better: Arc metal median C falls 0.824→0.518, and window C falls
2.033→1.909, while their color directions/relationships change differently.

The half candidate still makes selected neutral shadows cool. A fixed
source-neutral shadow mask uses source C<0.5 and L=12–35, sampled every eight
pixels within the ordinary border crop:

| Profile case | Samples | Starting output median b | Half | Quarter | CC off |
|---|---:|---:|---:|---:|---:|
| GZW dark | 5,660 | -0.492 | -0.124 | approximately 0 | +0.151 |
| Arc interior | 5,032 | -0.835 | -0.411 | -0.192 | approximately 0 |

Half is selected because it balances retained cool shadows and material-color
restraint in both profiles. Quarter offers stronger source-relative foliage
preservation, but the GZW neutral-shadow median becomes approximately neutral;
it is rejected for the present default, not declared universally inferior.
The screen is not extended to search for an apparently optimal decimal.

The selected settings are:

| Control | GZW before → selected | Arc before → selected |
|---|---|---|
| `SHADOW_TEMP` | -0.15 → **-0.075** | -0.15 → **-0.075** |
| `SHADOW_TINT` | -0.05 → **-0.025** | 0.0 → **0.0** |
| Midtone/highlight temperature and tint | unchanged | unchanged |

The gentler settings address the measured spill while retaining the intended
direction. No unavoidable weighting failure is demonstrated, so no shader-code
change is warranted. `creative_values.fx` remains the only tuning surface.

## Preserved behavior and retained costs

All seven selected half/half-repeat pairs are pixel-identical, as are the seven
verified starting pairs. The selected Arc white-core, halo and red-lamp pixels
are unchanged, retaining the preceding print improvement. Midtone/highlight
controls are not weakened along with shadows.

The improvements are not lossless. Arc dark-metal source-b-quartile color
separation falls 1.496→1.463, about 2.2%, while median source-opposing blue is
reduced. The cool window loses some median chroma despite improved selected
color separation. Foliage still has a deliberate residual shift; no source-color
identity or automatically inferred artistic intent is claimed.

The vivid blue field also becomes less chromatic, C=7.635→7.188, with its
source-relative hue shift growing 1.028°→1.958°. Arc daylight road median C
falls 2.064→1.780. These are retained palette costs of weakening a cool bias,
not evidence that every material's color is improved. The Arc cloud and selected
emitter colors/structure retain the preceding print treatment.

In the held set, half adds **24 black pixels in GZW dark and one in GZW day**.
All were previously only `(0,0,1)` or `(0,1,1)`, from source pixels no higher
than code 2. These are one-code near-black quantization costs; the selected
shelf/material luminance structure is retained. No new code-255 channel pixels
appear. Treatment changes elsewhere reach eight codes; that difference is not
an error against known ground truth.

Among 30,787 existing source-smooth blue horizontal pairs, p99 pair ΔE changes
0.754148→0.753253. Maximum local pair growth is 0.649049 ΔE, with mean growth
0.002097. Both growth and reductions occur; the slightly lower p99 is not proof
that every gradient improves. These are retained finite costs, not a mandatory
gamut repair or another parameter-search queue.

## Validation

The held screen adds **25 fresh ordinary captures**: seven new CC-off images,
seven half images, seven unchanged half repeats and four quarter images. All
use fresh private/headless processes, five-second compilation wait and twenty
seconds of continuous static settling. Completed playback has zero dropped/
delayed frames. Starting image reuse verifies the actual current print baseline;
it does not reuse stable 1.0 or assume source PNG equals rendered shader input.

Four measured cut replays cover both profiles and repeats. Each freezes 48
explicit source/token/source-update/cut-update keys: 24 night, 20 return and
four daylight phases. The ordinary full, selected half and CC-off evaluations
use the same update's production context. All **192 full/actual controls are
pixel-identical** on the common 12,984-sample mask, excluding borders and both
atlas-tag footprints. No added black or code-255 channel samples occur there.

| Profile/window | Starting maximum duplicate-step ΔE | Half | Repeat starting / half |
|---|---:|---:|---:|
| GZW night | 0.115663 | 0.115677 | 0.115645 / 0.115693 |
| GZW return | 0.746788 | 0.742412 | 0.746865 / 0.742482 |
| GZW daylight | 0.150150 | 0.151105 | 0.150354 / 0.151309 |
| Arc night | 0.127204 | 0.122563 | 0.127377 / 0.122308 |
| Arc return | 0.757177 | 0.756775 | 0.760491 / 0.759944 |
| Arc daylight | 0.145646 | 0.141299 | 0.145646 / 0.141299 |

These small changes do not establish a general temporal improvement. In
particular, GZW's first night duplicate step grows 0.019776→0.025844 even though
its window peak is essentially unchanged; that is a retained startup cost.
The small daylight peak growth is comparable with repeat variation. Measured
phase-matched half repeats reach one code, with maximum mean ΔE 0.001289 in
GZW and 0.005196 in Arc. Temporal repeats are not pixel-identical. The maximum
half/full mean difference over these windows is about 0.467 ΔE. Producer rates,
key history, initialization, cuts and automation formulas remain unchanged.

After applying the authorized profile changes, four fresh **actual active-config
full/repeat captures**, two per profile, match the isolated half candidate
pixel-for-pixel. All completed runs have zero dropped/delayed frames. The final
artifact audit verifies all input/image/media identities, seven starting and
seven selected exact held pairs, 192 exact controls, 176 unique isolated files,
and the one-code endpoint costs. It proves that only the three selected profile
literals changed and that every HLSL source and both active configs retain their
initial hashes. All 22 diagnostic tooling tests and whitespace checks pass.

No numeric shader repair is proposed: HLSL sources remain byte-identical
throughout the CC work. Existing numerical contracts are not rerun by association
with a profile-strength change. All other creative values, including Arc's
`BLACKS=0.005` and `FILM_CURVE=0.6`, remain. Header comments, resources, histories
and eight grade passes are preserved.

The source remains two games with their distinct preserved non-CC choices.
Static settling is a fixed protocol, not proof of universal convergence. The
existing Babylon clip is 15 unique poses/sec duplicated at 30 fps. Sparse
measured samples do not establish dense gameplay continuity, physical high
refresh, untuned new-game generality or calibrated-display acceptance.

## Effectiveness judgment

My focused estimate for **three-way CC as now applied is 75/100, borderline**,
up from the earlier 70. The basis is more restrained, repeatable cool-shadow
grading: shelf warm variation and foliage palette are better retained, Arc
keeps a deliberate cool metal treatment with useful window color separation,
selected density/light cores remain, and measured transitions retain bounded
costs. This is a judgment about the current two-profile cooperation, not a
new algorithm or evidence that every source needs this grade.

Uncertainty remains roughly 5–10 points. The estimate is not a fidelity
percentage, population preference result or universal game-agnostic acceptance.
The chain/grade remain at their prior borderline 75 estimates; print/look and
inverse chroma remain 70. A better CC judgment does not automatically raise
those blocks or establish the all-retained-effects target.

This closes the half/quarter CC decision. No mandatory weighting-code repair,
new CC search or extra confidence audit is queued. Subsequent baseline reuse
must check the new profile hashes: older print/reassessment full images use
the previous CC values. The current verification report and half/repeat images
provide the new baseline identities.

The next separately requested improvement is inverse chroma selectivity.
The current request covers CC only; no inverse changes are made here.

Artifacts started on October 30 and finish on October 31 under
`captures/three_way_cc_20261030/`. Scripts, media and diagnostic configs remain
ignored; the report is versioned. No commit or push is made.

- [Interactive source/full/half/quarter/bypass comparison](../captures/three_way_cc_20261030/review.html).
- [Shelf comparison](../captures/three_way_cc_20261030/gzw_dark_shelf_decision.png).
- [Day foliage comparison](../captures/three_way_cc_20261030/gzw_day_foliage_decision.png).
- [Muted foliage comparison](../captures/three_way_cc_20261030/gzw_muted_foliage_decision.png).
- [Arc dark-metal comparison](../captures/three_way_cc_20261030/arc_interior_dark_metal_decision.png).
- [Arc cool-window comparison](../captures/three_way_cc_20261030/arc_interior_cool_window_decision.png).
