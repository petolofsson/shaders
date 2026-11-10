# Light lift A at .5 — broader matched stills (2026-11-09)

Continues the [light lift candidate](2026-11-09_light_lift_candidate.md). The user
chose **A at `SHADE_LIFT` .5** (new zone lift only, `SHADOW_LIFT_STRENGTH` 0)
from review v5. This run is PLAN step 1: ten stills not used before, production vs
A, each captured twice. Nothing is adopted; production is untouched.

## Identity and protocol

- Candidate files are byte-identical to v3b (`stills/identities_after.txt` matches
  `stills_v4broad/identities_before.txt`, `_after.txt` and `_before_debug.txt`).
- `run_v4broad.sh`: `compare_frame.py --capture-backend headless --delay 5 --settle 20`,
  fresh process per capture, variants `production_0 A_0 production_1 A_1`; then
  `run_v4broad_debug.sh` for the light-map debug view. 50/50 captures, 0 vkBasalt errors.
- Analysis: `make_review_v4broad.py` (helpers copied; `make_review.py` runs on import).
  2×2 marker masked. Bands use production linear luminance: dark < .05, low .05–.18,
  bright ≥ .18. All in `captures/light_lift_20261109/` (ignored).
- Review page: private artifact "Light Lift Broad", version 1.

## Results (mean stops, A vs production; repeat pair in brackets)

| Still | Dark frac | All | Dark | Low | Bright | Repeat max codes P/A |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| GZW 133444 (darkest) | .96 | −.14 (−.14) | −.14 | −.20 | −.09 | 1 / 1 |
| GZW 133424 | .87 | −.07 (−.07) | −.05 | −.21 | −.05 | 1 / 1 |
| GZW 133302 | .78 | −.08 (−.08) | −.05 | −.21 | −.06 | 1 / 1 |
| GZW 133525 | .60 | −.01 (−.01) | +.06 | −.15 | −.05 | 1 / 2 |
| GZW 133831 | .54 | .00 (.00) | +.05 | −.06 | −.07 | 1 / 1 |
| Arc 210417 (dark) | .96 | −.19 (−.19) | −.19 | −.29 | −.02 | 1 / 1 |
| Arc 210723 | .87 | +.08 (+.07) | +.10 | −.13 | −.01 | 2 / 3 |
| Arc 210111 | .55 | +.14 (+.14) | +.18 | +.19 | +.02 | 2 / 6 |
| Arc 211202 | .47 | +.16 (+.17) | +.27 | +.19 | +.02 | 6 / 2 |
| Arc 210519 (brightest) | .28 | +.10 (+.10) | +.12 | +.29 | +.07 | 2 / 2 |

Band means move by ≤ .02 stop between repeats, so every entry above is outside
repeat noise. No white clipping or full-black pixels in either variant.

## Reading

- **Daylight with real cast shadow (Arc 210111/211202/210519):** A lifts the
  shadowed wall and sand by +.2–.3 stop and leaves sunlit surfaces unchanged — the
  intended behaviour.
- **Dim interiors (GZW 133444/133424/133302, Arc 210417):** A is darker than
  production nearly everywhere, including the lamp-lit wall. The zones are
  frame-relative (lit level = mean + 1.28 sd of log light), so in a uniformly dim
  frame the dimly lit parts are classed "light" or "mid" and get little or no
  lift, while removing the old lift takes away what production gave them. Net
  −.07 to −.19 stop over the frame, −.2 to −.3 in the low band.
- **Low band (.05–.18) is darker in 7/10** stills, including GZW frames whose
  darkest pixels gain. This is the mid zone at ≤ 30% replacing the old lift there.
- This matches v5's "A darker than production in three shadows" and shows it is
  systematic for dim scenes, not a per-still accident.

## Open question for the user

The GOAL asks for readable deep shadows. A at .5 darkens dim interiors by up to
~.2 stop. Options, none implemented:
1. keep A at .5 as chosen (accept darker interiors);
2. raise `SHADE_LIFT` (v5 recommendation ~1.0);
3. keep a reduced share of the old absolute lift alongside A, so dim frames are
   not lost to frame-relative zoning.

## Rename (2026-11-09, after this run)

The user renamed the new knob `SHADOW_LIGHT_LIFT` → `SHADE_LIFT`, to keep it
distinct from production's `SHADOW_LIFT_STRENGTH` (which lifts by pixel darkness;
`SHADE_LIFT` lifts by estimated light). Name-only change in
`general/grade/light_lift.fxh` and the `prof_*` profiles; the captures above were
made under the old name (`stills_v4broad/identities_pre_rename.txt`). The frozen
`general_v2_colouredge/` snapshot keeps the old name.

## SHADE_LIFT 1.0 (user request, 2026-11-09)

`SHADE_LIFT` .5 → 1.0 in `prof_*_A` only; production unchanged (hashes match
`stills_v4broad/identities_after.txt`). `run_shade10.sh`: A_0/A_1 on all 16 stills
(6 from v5 + 10 above), 32/32 captures, 0 errors; production and .5 captures reused.
`make_review_shade10.py`; artifact "Shade Lift Strength", version 1.

Mean stops vs production, .5 → 1.0 (repeat equal within .01 stop except as noted):

| Still | Frame | Dark | Low | Bright |
| --- | --- | --- | --- | --- |
| GZW 133444 | −.14 → −.02 | −.14 → −.02 | −.20 → −.19 | −.09 → −.09 |
| GZW 133424 | −.07 → +.11 | −.05 → +.15 | −.21 → −.21 | −.05 → −.05 |
| GZW 133302 | −.08 → +.07 | −.05 → +.14 | −.21 → −.20 | −.06 → −.06 |
| GZW 133525 | −.01 → +.18 | +.06 → +.35 | −.15 → −.09 | −.05 → −.05 |
| GZW 133831 | .00 → +.18 | +.05 → +.37 | −.06 → +.11 | −.07 → −.07 |
| GZW 133058 | −.14 → −.03 | −.11 → +.03 | −.23 → −.23 | −.05 → −.05 |
| GZW 133750 | −.03 → +.15 | .00 → +.24 | −.20 → −.18 | −.07 → −.07 |
| GZW 133932 (menu) | +.16 → +.35 | +.26 → +.57 | +.06 → +.13 | .00 → −.02 |
| GZW 101035 | +.10 → +.25 | +.23 → +.55 | +.16 → +.38 | +.01 → +.02 |
| Arc 205938 (menu) | +.03 → +.22 | +.08 → +.34 | −.12 → −.09 | −.01 → −.01 |
| Arc 210448 | −.06 → +.14 | −.04 → +.19 | −.22 → −.21 | −.04 → −.04 |
| Arc 210417 | −.19 → −.02 | −.19 → −.02 | −.29 → −.29 | −.02 → −.02 |
| Arc 210723 | +.08 → +.31 | +.10 → +.36 | −.13 → −.11 | −.01 → .00 |
| Arc 210111 | +.14 → +.29 | +.18 → +.41 | +.19 → +.37 | +.02 → .00 |
| Arc 211202 | +.16 → +.31 | +.27 → +.51 | +.19 → +.36 | +.02 → +.05 |
| Arc 210519 | +.10 → +.21 | +.12 → +.26 | +.29 → +.61 | +.07 → +.13 |

Repeat max codes ≤ 7 except Arc 205938 (menu) at 10. No white clipping.

- Dim interiors are back to production level over the frame (−.02 to +.11), with
  shade (between planks, under shelves) lifted and dim-lit surfaces still
  slightly darker: light/shade separation increases inside.
- The low band (.05–.18) stays about −.2 stop in dim scenes: the old lift reached
  luminance up to .35, the shade lift gives mid/light zones little. GZW bright
  band −.05 to −.09 for the same reason.
- Strongest dark-pixel lifts are +.5 to +.6 stop (GZW 133932, 101035, Arc 211202).
- Menus: the GZW 133932 lift map shows the UI panel lifted with the scene behind
  it. This is PLAN step 2 (UI/motion), not yet assessed.

## Shape C: partial shade most (user request, 2026-11-09)

The user felt A at 1.0 "just brightens the shadows" and wanted range and depth.
Measured on A at 1.0: range inside dark pixels was kept or widened (13/16), but
the lit→shadow distance fell by .2–.6 stop, because deep shade got the most lift.

**Change.** `SHADE_LIFT_SHAPE` (compile-time, default 0 = A unchanged) in
`light_lift.fxh`. Shape 1 keeps the zones and reverses the weights:
`band = ss(.75,2,d) · (1 − .7·ss(2,4,d))` — partial shade full, deep shade 30%
by 4 stops, same fade and near-black floor. Lift slope vs d ≤ .72 stop/stop at
1.0, so pixel order is kept. Profiles `prof_*_C` = A + `SHADE_LIFT_SHAPE 1`.

**Run.** `run_shapeC.sh`: C_0/C_1 on 16 stills, 34/34 captures with 0 errors,
identities stable. A recaptured on 133444 and 211202 after the code edit: max 1
and 6 codes vs the earlier A, inside the A repeats (1 and 7), so shape 0 is
unchanged. Artifact "Shade Lift Shape", version 1; `make_review_shapeC.py`.

**Measures.** Depth = p90 log luminance − median of dark pixels (< .05); range =
median − p2 of dark pixels. Stops, production / A / C:

| Still | Depth | Range in shadow | Dark A/C | Low A/C |
| --- | --- | --- | --- | --- |
| GZW 133444 | 1.67 / 1.47 / 1.13 | 2.54 / 2.27 / 2.88 | −.02 / +.06 | −.19 / −.19 |
| GZW 133424 | 2.84 / 2.36 / 2.31 | 2.62 / 2.70 / 3.00 | +.15 / +.13 | −.21 / −.21 |
| GZW 133302 | 2.23 / 1.85 / 1.71 | 3.22 / 3.19 / 3.64 | +.14 / +.16 | −.20 / −.17 |
| GZW 133525 | 3.75 / 3.29 / 3.67 | 2.48 / 2.59 / 2.54 | +.35 / +.08 | −.09 / +.13 |
| GZW 133831 | 3.98 / 3.55 / 3.98 | 2.70 / 2.96 / 2.76 | +.37 / +.01 | +.11 / +.32 |
| GZW 133058 | 1.38 / 1.19 / .84 | 3.67 / 3.57 / 4.17 | +.03 / +.07 | −.23 / −.22 |
| GZW 133750 | 3.69 / 3.19 / 3.36 | 2.79 / 2.98 / 3.07 | +.24 / +.14 | −.18 / −.13 |
| GZW 133932 | 4.35 / 3.70 / 4.15 | 3.23 / 3.80 / 3.43 | +.57 / +.26 | +.13 / +.30 |
| GZW 101035 | 3.73 / 3.20 / 3.61 | 1.05 / 1.07 / 1.09 | +.55 / +.16 | +.38 / +.42 |
| Arc 205938 | 4.13 / 3.56 / 4.01 | 1.87 / 2.23 / 1.95 | +.34 / +.10 | −.09 / +.05 |
| Arc 210448 | 3.43 / 2.88 / 3.18 | 1.45 / 1.69 / 1.65 | +.19 / +.04 | −.21 / −.21 |
| Arc 210417 | 1.60 / 1.16 / 1.02 | 1.19 / 1.09 / 1.40 | −.02 / +.07 | −.29 / −.29 |
| Arc 210723 | 3.23 / 2.67 / 3.01 | 1.48 / 1.73 / 1.64 | +.36 / +.14 | −.11 / −.11 |
| Arc 210111 | 5.62 / 5.05 / 5.49 | 1.91 / 2.47 / 2.06 | +.41 / +.12 | +.37 / +.47 |
| Arc 211202 | 5.10 / 4.55 / 4.99 | 1.91 / 2.51 / 2.07 | +.51 / +.14 | +.36 / +.43 |
| Arc 210519 | 5.85 / 5.68 / 5.87 | 1.60 / 1.81 / 1.66 | +.26 / +.07 | +.61 / +.25 |

Repeat max codes for C ≤ 9 except Arc 210111 at 19 (A was 7 there); treat that
still loosely. No white clipping.

**Reading.**
- Scenes with real shade structure (12/16): C keeps depth within .0–.3 stop of
  production (A lost .2–.6) and lifts partial shade and the low band instead.
- Dim interiors (133444, 133058, 133302, 210417): C reduces depth further than A
  (to .84–1.71) because most dark pixels there are classed partial shade, while
  range inside the shadows widens most (+.2 to +.5 stop). The low band there stays
  ~−.2 stop with both shapes (old lift removed).
