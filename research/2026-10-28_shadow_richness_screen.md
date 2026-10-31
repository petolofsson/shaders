# Shadow richness: lift-distribution screen — 2026-10-28

The first shadow-richness experiment is complete. Neither tested redistribution
earns adoption as a general default. The narrower curve improves selected wood
and vehicle separation, with a smaller dark-metal benefit, but loses separation
in the dark shelf, daylight shadow paving and warm floor. Whole-image review
shows a subtle treatment rather than a substantial, consistent improvement.
Stable 1.0 (`1724bb6`, tag `v1.0`) remains the active shader implementation.

The user's target is deeper, more dimensional shadows with distinguishable dark
materials and visible nuance, rather than more global color richness or merely
brighter shadows. This is a finite decision about lift distribution, not a
declaration that the broader shadow goal is achieved or impossible. No technical
defect, effectiveness re-score or mandatory follow-up repair follows.

## Hypothesis and isolated candidates

The original lift weight is `w(Y) = Y * smoothstep(0.35, 0, Y)`, where `Y` is the
pre-lift, post-Retinex linear luminance. Multiplication by the existing adaptive
lift coefficient follows. In the deep range this is approximately proportional
to Y: it improves visibility without necessarily increasing relative separation.

Four treatments were compared with source images:

- Stable 1.0, with the current user profiles unchanged.
- More lift: only the isolated profile's `SHADOW_LIFT_STRENGTH` changes from 0.75
  to 1.0. This is a simple alternative against which to judge the prototypes.
- Broad redistribution: multiply w by `1.5*Y/(Y+0.02)`. Lower shadows receive
  less lift; values above Y=0.04 receive more. The original Y=0.35 cutoff stays.
- Narrow redistribution: blend that multiplier with 1 using the window
  `smoothstep(0.003,0.012,Y) * (1-smoothstep(0.04,0.12,Y))`. This preserves the
  original weight at Y<=0.003 and Y>=0.12, reducing the broad curve's deep-shadow
  and upper-tone costs. These are processing-domain limits, not source masks.

Both prototypes are temporary grade copies. They change no analysis, history,
time constant, texture, pass count, color control, active config or user profile.
The expressions were screened on nonnegative luminance; they are rejected
prototypes, not a new signed-domain production contract.

The dense CPU curve check in `curve_contract.json` finds minimum lift-weight
derivatives of -0.6875 original, -0.9437425 broad and -0.6875 narrow. The broad
curve therefore spends more of a fixed coefficient's monotonicity margin.
The narrow window avoids that additional cost and exactly preserves the outer
ranges in the CPU model. This is not GPU numeric readback or a monotonicity proof
for the full adaptive chain, whose coefficient and other operations vary.

## Fresh inputs and capture protocol

| Case | Profile | Source filename |
|---|---|---|
| Dark shelf | GZW | `autof_20260515_133058.png` |
| Shop wood/floor | GZW | `autof_20260515_133505.png` |
| Daylight paving | GZW | `Screenshot_20260516_101035.png` |
| Interior metal/floor | Arc Raiders | `autof_20260515_205938.png` |
| Vehicle/road | Arc Raiders | `autof_20260515_210825.png` |

Sources are the native 2560x1440 PNGs under each game's `analysis/reference/`.
The current GZW profile differs from earlier reports: inverse chroma 0.60,
inverse luma 0.30, saturation 0, contrast 1, film curve 0.60 and BLACKS=0.
Arc retains the user's inverse strengths 0.5/0.5, BLACKS=0.005, film curve 0.6
and neutral shadow tint. Earlier outputs were not reused as current baselines.

Each case has six fresh private headless Vulkan processes: full, full repeat,
more lift, broad redistribution, narrow redistribution and narrow repeat.
All thirty runs report zero dropped/delayed frames and pass the activity-marker
check. Five seconds compile wait and twenty seconds continuous lossless RGB
playback precede each capture. All five full/repeat and five narrow/repeat pairs
are pixel-identical. This is a measured static protocol, not proof of complete
long-history convergence or temporal stability in gameplay.

The audit checks 236 artifact/source/isolation assertions. All five clips decode
to byte-exact source first frames. Shader and profile hashes remain identical to
the initial stable checkpoint; isolated grades differ only by their stated edit.
The intentional top-left 2x2 activity marker is excluded from global statistics.
Whole-image statistics still include game UI, especially the Arc trader scene.

## Material separation and costs

Native rectangles below are selected from source content, following the earlier
material coverage regions. Shelf, wood, metal and body masks require source
Oklab L<45; the other rectangles retain all their pixels. Within each mask,
source-L lower/upper quartiles define fixed pixel groups for every output.
The visible gap is their mean Oklab L difference (0–100 scale); relative gap is
their mean log2 linear-Y difference, floored at 1e-8. Neither is a quality score.

| Region | Native rectangle `(x0,y0,x1,y1)` | Median L, full→narrow | L gap, full→narrow | Relative gap, full→narrow (stops) |
|---|---|---:|---:|---:|
| GZW shelf | `(80,450,540,650)` | 12.212→12.212 | 4.388→4.366 | 1.643→1.637 |
| GZW wood | `(358,545,470,858)` | 27.353→26.858 | 10.522→10.983 | 1.774→1.874 |
| GZW floor | `(545,895,825,1012)` | 36.136→36.267 | 12.805→13.286 | 1.520→1.580 |
| GZW shadow paving | `(662,1075,825,1145)` | 40.985→41.108 | 9.892→9.814 | 1.064→1.055 |
| GZW lit paving | `(625,1300,838,1400)` | 57.839→57.839 | 16.927→16.913 | 1.396→1.394 |
| Arc dark metal | `(100,988,438,1288)` | 19.611→19.306 | 7.766→7.804 | 1.526→1.548 |
| Arc warm floor | `(1088,910,1355,1000)` | 58.236→58.236 | 32.351→32.247 | 2.494→2.483 |
| Arc rear body | `(1538,850,1950,975)` | 21.891→21.688 | 13.868→14.071 | 2.416→2.464 |
| Arc road | `(150,925,750,1175)` | 51.531→51.531 | 18.908→18.877 | 1.711→1.707 |

The broad curve has a larger shelf cost: median L falls to 11.420 and visible gap
to 4.250, although its relative gap grows to 1.721 stops. That is a concrete
example of deeper shadows and more relative contrast without better visible
separation. Its wood gap improves to 11.109/1.908 stops, but it also changes
the lit paving and warm-floor treatment more. It adds one exact-black shop pixel
(45→46). Those costs reject the broad version.

More lift brightens every selected dark material, but does not consistently
improve relative structure. Shelf gap becomes 4.488/1.636 stops, wood
10.811/1.778 and dark metal 7.812/1.516. It is a visibility/taste alternative,
not demonstrated improvement in depth and separation across the set.

The narrow version adds no exact-black or channel-255 pixels compared with full.
Full/narrow black counts are 0/45/0/0/0 in table case order; every full/narrow
image has zero channel-255 pixels. Source black is not necessarily output black:
Arc's deliberate BLACKS=0.005 produces maximum channels 14/13 on source-black
pixels in interior/day, unchanged by either prototype in these captures.

Narrow/full whole-image mean delta-E is 0.269/0.291/0.037/0.218/0.043; maximum
channel changes are 3/4/1/2/1 codes. These are change magnitudes, not fidelity.
For horizontal source-smooth dark pairs (source L<45, max-channel difference<=1),
shadow-paving pair delta-E p99 rises 0.756→0.821 despite the one-code maximum
pixel change. Wood p99 rises 0.851→0.859; metal falls 0.788→0.775. This is a
measured quantized-gradient cost, not a general noise or banding diagnosis.
The mostly near-neutral selected materials do not establish rich dark-color
retention. Mixed-material rectangles do not establish physical reflectance or
uniform-surface halo behavior.

## Decision, review and limits

Reject both redistribution candidates as general defaults. The narrow version
is the better experiment: its selected wood gap grows about 4.4%, rear-body gap
about 1.5%, and dark-metal gap about 0.5%, with smaller upper-tone changes.
Those modest, uneven gains do not establish a substantial improvement in shadow
richness across the assessed inputs. Preserving stable 1.0 is preferable to
shipping a curve solely because some contrast numbers increase.

The result narrows the hypothesis: redistributing the existing lift alone is
too blunt to consistently distinguish useful shadow structure from material
brightness, lighting differences and small code variations. It does not prove
that adding more local contrast or a new effect would solve that problem.
Further shadow work should begin from a concrete visible shortcoming and its
responsible existing stage, rather than automatically escalating lift strength
or extending this parameter screen. No additional candidate is queued here.

Local review artifacts:

- [Three-way comparison](../captures/shadow_richness_20261028/comparison.png): stable, more lift, narrow prototype.
- [Interactive native-size comparison](../captures/shadow_richness_20261028/review.html).
- Full source/four-treatment sheet `contact.png` and native-region sheet `crops.png`.
- `run.py`, `report.json`, `analyze.py`, `metrics.json`, `audit.py`, `audit.json`,
  `curve_contract.json`, isolated profiles/grades/configs and per-run runtime logs.

Scripts and media remain ignored local artifacts. Only this decision and its
documentation are versioned. Twenty-two tooling tests pass; no production
shader/profile/config is modified. No GPU scalar readback, diagnostic bypass,
uniform-boundary test, moving/cut test, dense gameplay, new resolution/game,
performance profile or effectiveness re-score is claimed for these prototypes.
Those further tests are unnecessary to reject the held-image candidates.
