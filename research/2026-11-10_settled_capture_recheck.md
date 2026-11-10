# Settled-capture recheck and scene-cut trigger (2026-11-10)

## Why

Single-PNG captures never settled frame-time histories: mpv shows a still without a steady
frame stream. At capture, smoothed entropy read .04–.16 (settled .75) and the adaptation gate
.38–.44 (settled 1.0), varying per run. `compare_frame.py` single-PNG mode now plays a lossless
looping 30-fps clip; repeats are bit-identical (6 stills, 3 repeats each). It also gained
`--save-after` so scripts keep only the output PNG (`--keep` filled the 16 GB RAM-backed `/tmp`).

## Settled vs unsettled production (same build)

Settled frames are brighter in darks/mids and darker in highlights (Retinex and zone shaping at
full strength): GZW user 172413 mean |Δ| 2.05 codes (max 16; Oklab L +.005 below L .5, −.013
above .7); Arc 211202 3.43 codes (max 27; +.012 mids, −.022 highlights).

## Effect visibility, settled

Rerun of the [2026-11-09 sweep](2026-11-09_effect_visibility.md) with settled captures, current
profiles, plus `SATURATION`, `WARM_RESTRAINT`, `SHADOW_CC_STRENGTH` and the user's GZW still.
84 captures, 0 errors, identities stable, production repeats bit-identical
(`captures/effect_visibility_20261110_settled/`). Mean |Δ| codes, settled (earlier unsettled):

| Knob off | Daylight 101035 | Foliage 133058 | Arc dark 210448 | GZW 172413 |
| --- | --- | --- | --- | --- |
| Retinex | **3.41** (1.56) | 0.00 (0.00) | 0.75 (0.30) | 3.94 |
| Contrast / zone | 1.78 (1.77 / 1.49) | 0.05 | 0.02 | 2.19 |
| Shadow lift | 0.99 (1.47) | **4.00** (6.04) | 3.49 (3.29) | 0.48 |
| Endpoints | 0.36 (0.77) | 1.12 (2.90) | 4.60 (4.23) | 0.64 |
| Inverse luma | 4.00 (3.96) | 0.21 | 0.38 | 2.30 |
| Print / look gate | 4.50 (4.49) | 3.57 (3.71) | 3.36 (3.28) | 3.67 |
| FILM_CURVE | 0.01 (0.07) | 0.00 | 0.02 | 0.00 |
| Shadow CC (×strength, light map)* | 1.79 | 0.95 | 4.19 | 1.80 |
| Mid/highlight warmth* | 0.72 | 0.61 | 0.31 | 0.53 |
| Surround tint | 0.44 | 0.74 | 1.02 | 0.93 |
| `SATURATION` .075 | 0.45 | 0.20 | 0.26 | 0.81 |
| `WARM_RESTRAINT` 1.0 | 0.35 | 0.51 | 0.34 | 0.22 |

\* Profile values changed since 2026-11-09 (CC strength, light-map placement, warmth), so these
rows are not settled-vs-unsettled comparisons.

Findings:
- **FILM_CURVE stays inert** (design: print relieves its shoulder in proportion).
- **Retinex is about twice as strong in game** as the earlier stills showed (daylight 80% of
  pixels changed > 2 codes); it acted at ~40% because of the stalled adaptation gate.
- **Shadow lift is about a third weaker in foliage** than measured before (4.0 vs 6.0). The
  user's shade-lift ranking (2026-11-10) and the light-lift reviews used unsettled stills; the
  ranking compared variants under equal conditions, but absolute strengths differ in game.
- Other knobs are within capture noise of the earlier values.

## Scene-cut trigger

The brightness trigger compares the current frame's mean log2 lane luma (576 samples, floor
.004) with the previous frame: smoothstep(0.6, 1.1 stops). p50 (raw or smoothed) was unusable:
the smoothed one rarely fired, and the raw one jumped > 1 stop when a sky/ground median crossed
during a camera flick. CPU flick emulation (4 scenes, up to a full screen height in 125 ms): mean
log ≤ 0.38 stop/frame → no cut; uniform cuts ×0.45 (1.13 stops) and ×0.25 → full cut.
GPU probes with a readout strip (test copies, `captures/bugfix_20261110/diag/`):
- flick (2× zoomed GZW 101035, sky → ground in 0.5 s): no cut (slow key only drifts at 20 s);
  the p50-stop trigger had reset it ~28%;
- brightness-only cut ×0.45 and back: full slow-key reset both ways (p50 trigger: ~68%);
- dark ↔ bright cut: full reset.
Static stills are unchanged (production repeats across the change are bit-identical).
