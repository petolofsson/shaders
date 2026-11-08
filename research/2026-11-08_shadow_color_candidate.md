# Frozen shadow-color candidate: darker-range 110%

After brightness recovery was closed, the user chose the darker-range 110%
shadow color as the single adoption candidate, with production BLACKS .0025 and
lift unchanged and no new control. Artifacts: `captures/shadow_color_candidate_20261108/`
(native review `review.html`, `stills_report.json`, `noise/noise_report.json`,
transition outputs).

## Candidate

An isolated copy of the current `general/` (including the uncommitted
2026-11-08 [review fixes](2026-11-08_ultrareview_fixes.md)) differs from
production only in `ColorTransformPS`: before corrective/tonal stages,

`delta = 1.10 × BLACKS × gate × (rgb/y − 1)`, `gate = smoothstep(.00025,.0025,y) × (1 − smoothstep(.01,.04,y))`,

added with the shader headroom budget. It ties the amount to production BLACKS
(the validated formula), not the decoupled experimental offset or the lift
.25 / BLACKS 0 visual config. Candidate grade SHA-256
`31d99bc1d642f7ee2766b17fcd9179c79276f33f6489a82db15d507290694b37`.
Profiles and active configs were hashed before and after all runs: unchanged.

## Matched stills

Twenty private headless `compare_frame.py` runs (5 s compile, 20 s settle):
candidate ×2 and production ×2 on GZW shelf, warm interior and daylight, and
two Arc interiors. All vkBasalt logs report zero errors and the intended
pipeline. Marker-masked differences (pixels, max code):

| Scene | Candidate repeat | Production repeat | Candidate vs production | Dark ΔC ×100 |
| --- | --- | --- | --- | ---: |
| GZW shelf `133058` | 28,973 / 1 | 4,590 / 1 | ~1.58 M / 9 | +.23 |
| GZW warm `133444` | 20,842 / 1 | 160,331 / 1 | ~3.38 M / 9 | +.56 |
| GZW daylight `101035` | 2.53 M / 2 | 2.87 M / 2 | .55–.71 M / 9 | +.03 |
| Arc `205938` | 150,996 / 2 | 1.09 M / 2 | 1.80–2.45 M / 12 | +.20 |
| Arc `210448` | 372,283 / 1 | 721,896 / 1 | 2.73–2.83 M / 8 | +.25 |

Dark = output linear luma < .04; dark ΔL stays within ±.0008 (×100: ≤.08).
Native crops: dark timber becomes slightly warmer brown, dark Arc structure
slightly deeper navy; no visible artifacts. A navy HUD label is also tinted
slightly; the helper cannot distinguish UI. Daylight changes little, as intended.

## Output noise

The 2026-11-07 synthetic fixture (black band plus RGB codes 8/16/32 ±1;
SHA-256 `a1b76bc5…f09bac`) was captured through each pipeline (×2 per game),
measuring the final dithered 8-bit screenshots instead of float readback.
Oklab a/b σ ×100 (GZW; Arc within .01):

| Code | Input | Production | Candidate |
| --- | ---: | ---: | ---: |
| 8 | .366 | .225 | .434 |
| 16 | .301 | .236 | .339 |
| 32 | .277 | .263 | .304 |

Repeats are identical; mean L is identical between candidate and production,
and the black band is the same in both (production's BLACKS offset). The
candidate amplifies existing chroma noise in near-black above the input level,
because it scales each pixel's chroma by its own RGB ratios; material color and
chroma noise are amplified alike. This is synthetic ±1-code noise, not a visual
threshold.

## Scene cut

`--transition` (GZW shelf → courtyard → shelf), one run each: zero dropped or
delayed frames. Settling ΔE candidate/production: second early→late .070/.045,
first early→late .119/.122, late→recovered .164/.166, before→recovered .295/.298.
No pumping difference beyond the small second-scene settle.

## Status

Provisional judgment: the candidate delivers the requested subtle material
color in near-black shadows with luminance preserved and restraint in bright
scenes; its costs are amplified near-black chroma noise, slight HUD tinting and
some color on dark materials in light (see the shadow oracle). The estimate stays
near 70–75 pending the user's visual verdict on the native review. Adoption
would be a production `grade.fx` change; nothing has been adopted.
