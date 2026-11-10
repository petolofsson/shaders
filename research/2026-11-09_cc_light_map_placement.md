# 3-way CC placement: brightness zones vs light map (2026-11-09)

**Purpose (user, 2026-11-09).** The light/shade map work was meant to let Shadow CC
place colour where light and shade really are, not to replace the shadow lift. The
lift work ([broad stills](2026-11-09_light_lift_broad_stills.md)) continues as a
side branch. The user chose: all three CC zones should follow the light map, but
first show where colour lands today vs with the map.

## Method

- Test copy `captures/light_lift_20261109/general/grade/grade.fx`, two debug views
  (production profile values + `LL_DEBUG_VIEW`, profiles `prof_*_cc3`/`cc4`):
  - **3, today:** at the CC call, R = `ZoneShadowW(L, key_L)`, G = `ZoneHighlightW`,
    B = the CC gate (`smoothstep(0,.15,L)` × neutral share), from the corrective
    stage's own `lin_e`. Mid = 1 − R − G.
  - **4, light map:** R = `ss(1.75,2.75,d)`, G = `1 − ss(.75,2,d)`, B = same gate;
    d = stops below the frame's lit level from the shader's own anchor (the zones
    the user approved).
  - Written undithered, sRGB code = value × 255.
- Failed attempts kept: an early `return` failed to compile ("unreachable code",
  `run_ccmap_failed_unreachable.log`); the next run read the post-corrective colour
  and gave near-zero weights (`stills_ccmap_INVALID_wrong_input/`). Fixed by keeping
  the corrective input (`dbg_lin_in`).
- `run_ccmap.sh`: 16 stills × 2 views, 32/32 + 2 A rechecks, 0 errors, identities
  stable. A (shade lift 1.0) recheck within 1–2 codes of before: view-0 output
  unchanged by the debug code.
- `make_local_ccmap.py` → local native-resolution page `review_ccmap_local/index.html`.
  Shares are gate-weighted (where CC actually acts).

## Results

| Still | Today S/M/H | Light map S/M/H | Shadow colour on lit | Shade missing shadow colour |
| --- | --- | --- | ---: | ---: |
| GZW 133444 darkest | .86/.14/.00 | .36/.29/.35 | .50 | .00 |
| GZW 133424 | .69/.31/.00 | .48/.25/.27 | .21 | .00 |
| GZW 133302 | .47/.53/.00 | .32/.30/.38 | .15 | .00 |
| GZW 133525 | .65/.34/.01 | .52/.15/.33 | .13 | .00 |
| GZW 133831 | .49/.51/.00 | .44/.06/.50 | .05 | .00 |
| GZW 133058 | .34/.66/.00 | .27/.23/.50 | .08 | .00 |
| GZW 133750 | .57/.43/.01 | .46/.18/.36 | .10 | .00 |
| GZW 133932 menu | .58/.37/.05 | .55/.13/.32 | .04 | .01 |
| GZW 101035 | .46/.50/.05 | .39/.09/.52 | .07 | .00 |
| Arc 205938 menu | .70/.26/.04 | .65/.14/.20 | .05 | .01 |
| Arc 210448 | .69/.29/.02 | .67/.12/.20 | .04 | .02 |
| Arc 210417 dark | .89/.11/.01 | .46/.33/.22 | .43 | .00 |
| Arc 210723 | .70/.24/.05 | .75/.08/.16 | .01 | .06 |
| Arc 210111 | .66/.28/.06 | .69/.07/.24 | .00 | .04 |
| Arc 211202 | .60/.36/.04 | .55/.09/.36 | .05 | .00 |
| Arc 210519 | .43/.46/.11 | .41/.23/.36 | .02 | .00 |

## Reading

1. **Shadow placement.** In daylight the two mostly agree (shadow share within
   ±.05). Brightness CC errs one way: it cools things the map calls lit (dark
   clothing and edges in sun, e.g. 211202's character), and almost never misses
   real shade. In dim interiors it cools nearly everything (133444 .86, 210417 .89);
   the map keeps shadow colour to the corners and puts the lamp-lit wall and floor
   in light. 43–50% of CC there would move from shadow colour to lit colour.
2. **Highlight CC is almost unused today** (≤ .11 of the frame; `ZoneHighlightW`
   starts at key + 50% of the headroom). The map's light zone covers .16–.52, so
   "all three follow the map" moves most lit surfaces from MID to HIGHLIGHT colour.
   In GZW that doubles their warmth (`HIGHLIGHT_TEMP` is 2× `MID_TEMP`). This is
   a look change, not only a placement fix, and the user has trimmed red/yellow
   before.
3. **Gate unchanged** (≤ 1 code between views): only zone choice differs.
4. Within plank texture, both maps still follow brightness steps (v3 treats every
   step as light unless colour vetoes it), so streaks remain in both.

## Open choice

How the light map should feed the three zones:
- **a. All three from the map** (as chosen): shade → shadow, partial → mid,
  lit → highlight. Lit surfaces get highlight colour.
- **b. Map for shadow vs lit, brightness for highlight within lit:** shade →
  shadow, lit → mid, with highlight colour only on bright pixels inside the lit
  zone, as today. Fixes placement without warming every lit surface.

## Option b wired, then ideas 1 and 1+2 (2026-11-09)

The user's "yes" was taken as option b (recommended). `SHADE_CC_MAP` in the test
copy selects the zone weights through one helper, `CCZoneW`, shared by CC and its
debug view (view 3 now shows the weights CC actually uses):
- **1 = D:** shadow = `ss(1.75,2.75,d)` from the map; highlight = brightness
  highlight × (1 − shadow); mid = rest.
- **2 = E (idea 1):** shadow = relative shade soft-OR low absolute light,
  `1 − ss(−9,−5, log2 light)`.
- **3 = F (ideas 1+2):** E with the relative ramp widened to `ss(.75,2.75,d)`.

**Runs.** `run_ccD.sh` (D ×2 + debug, 50/50, plus a control: test pipeline at
production values vs production, max 1 and 8 codes vs a production repeat of
1 and 6). `run_ccEF.sh` (E, F + debug views, 66/66; D recheck after the patch 1
and 7 codes vs D repeat 1 and 3). Identities stable. The first E/F run used an
absolute ramp of −6.5…−3.5 and was stopped: it gave the darkest room .92 shadow
colour, more than today (`stills_ccEF_INVALID_abs_too_strong/`). The ramp was
recalibrated offline from the decoded light maps; the shader matched the offline
estimate (.59 vs .58 on 133444). The user asked to try ideas 1 and 2 before a
plain 50/50 blend, which would bring back half of the brightness error.

**Shadow-colour share (gate-weighted)** and mean warmth change vs production
(Oklab b):

| Still | Today | D | E | F | Δb D / E / F |
| --- | ---: | ---: | ---: | ---: | --- |
| GZW 133444 | .86 | .36 | .59 | .66 | +.0034 / +.0019 / +.0014 |
| GZW 133424 | .69 | .48 | .55 | .66 | +.0017 / +.0011 / +.0002 |
| GZW 133302 | .47 | .32 | .32 | .48 | +.0016 / +.0015 / −.0001 |
| GZW 133525 | .65 | .52 | .52 | .61 | +.0016 / +.0016 / +.0006 |
| GZW 133831 | .49 | .44 | .44 | .48 | +.0005 / +.0005 / +.0001 |
| GZW 133058 | .34 | .27 | .28 | .40 | +.0007 / +.0006 / −.0006 |
| GZW 133750 | .57 | .46 | .47 | .57 | +.0009 / +.0009 / .0000 |
| GZW 133932 | .58 | .55 | .55 | .63 | +.0002 / +.0003 / −.0002 |
| GZW 101035 | .46 | .39 | .39 | .44 | +.0008 / +.0008 / +.0002 |
| Arc 205938 | .70 | .65 | .65 | .74 | +.0008 / +.0008 / −.0007 |
| Arc 210448 | .69 | .67 | .69 | .75 | +.0002 / .0000 / −.0010 |
| Arc 210417 | .89 | .46 | .71 | .78 | +.0069 / +.0029 / +.0018 |
| Arc 210723 | .70 | .75 | .76 | .81 | −.0008 / −.0008 / −.0016 |
| Arc 210111 | .66 | .69 | .69 | .73 | −.0005 / −.0005 / −.0010 |
| Arc 211202 | .60 | .55 | .55 | .60 | +.0007 / +.0007 / .0000 |
| Arc 210519 | .43 | .41 | .41 | .53 | +.0003 / +.0003 / −.0015 |

**Reading.**
- **E** equals D except in dim rooms (133444, 133424, 210417), where it lands
  between today and D, as intended.
- **F** keeps about today's total amount of shadow colour (overall warmth within
  ±.002 of production) but places it by light: shade and partial shade instead of
  dark materials. It relocates colour rather than changing the overall balance.
- All changes are small in absolute terms (mean Δb ≤ .007); CC itself is a gentle
  grade, so judge on the flips, not the means.
- Local page: `captures/light_lift_20261109/review_ccEF_local/index.html`.

## G: between E and F (user request, 2026-11-09)

The user wanted F closer to E, with a ramp that ends shorter. Added `SHADE_CC_RAMP`
(start of the relative ramp in stops below lit; default .75 keeps F). G =
`SHADE_CC_MAP 3`, `SHADE_CC_RAMP 1.25`. `run_ccG.sh`: G + debug on 16 stills,
32/32 with 0 errors, identities stable. F rechecked after the edit: 1 code on
133444 and 11 on Arc 211202. That still had repeats of 3–7 codes in other
variants and F has no repeat of its own, so 11 is more likely capture noise than
a code change (the default path is the same expression), but it is not proven.

Shadow-colour share, today / E / G / F: 133444 .86/.59/.62/.66, 133424
.69/.55/.61/.66, 133302 .47/.32/.39/.48, 133525 .65/.52/.56/.61, 133831
.49/.44/.46/.48, 133058 .34/.28/.33/.40, 133750 .57/.47/.52/.57, 133932
.58/.55/.59/.63, 101035 .46/.39/.41/.44, 205938 .70/.65/.70/.74, 210448
.69/.69/.72/.75, 210417 .89/.71/.74/.78, 210723 .70/.76/.78/.81, 210111
.66/.69/.71/.73, 211202 .60/.55/.57/.60, 210519 .43/.41/.45/.53. Mean warmth
change of G vs production is within ±.0024 Oklab b on every still.

**User verdict (2026-11-09): "G is good!"** G (`SHADE_CC_MAP 3`, `SHADE_CC_RAMP 1.25`)
is the chosen CC placement look. Not adopted; next are repeats, menu/UI and motion
checks, then an adoption request.

## G repeats and visibility (2026-11-09)

`run_ccG_rep.sh`: G_1 on 16 stills, 16/16 with 0 errors, identities identical to
the G run. G_0 vs G_1 max 1–7 codes.

**Visibility.** Oklab ΔE of G vs production: max .018–.023 per still; pixels
above .01: .03–3.0%; above .02 (about one just-noticeable step): ≤ .07%. At
the current profile strengths (`SHADOW_TEMP` −.15 GZW / −.225 Arc, scaled by
.06 and the neutral-share gate), moving CC's placement changes the final image
by less than one just-noticeable step almost everywhere. The approval was given
mostly from the zone overlays, which exaggerate the change. What G changes is
**where** shadow colour lands, which matters in proportion to CC strength. Its
practical value is that shadow CC can be made stronger without cooling dark
materials in light. A G-vs-production comparison at higher shadow CC would show
that; plain G at current strengths would add the light map's cost (11 passes at
1/8 + 16-tap upsample, unless shared with the shade lift) for a sub-threshold
change.

## G scene cuts (2026-11-09)

`run_ccG_transition.sh`: `compare_frame.py --transition` (first 20 s / second 8 s /
first 20 s, fresh playback per snapshot), production vs G, outputs moved to
`captures/light_lift_20261109/transitions_ccG/`. The first run only did GZW: the
player consumed the script's input list, so the Arc pair never started. It was fixed
with `< /dev/null` and Arc was run separately.

GZW 133058 → 133444 (daylight shelf → darkest interior), mean ΔE between snapshots,
production / G: second early→late .1031 / .1033; first early→late .0472 / .0471;
first late→recovered .0644 / .0650; first before→after .1794 / .1674; before→
recovered .1337 / .1163. No dropped or delayed frames, 0 vkBasalt errors. G
settles like production after both cuts; production's own adaptation dominates.

Arc 211202 → 210417 (daylight → dark room), production / G: second early→late
.0147 / .0056; first early→late .0137 / .0006; first late→recovered .0185 / .0000;
first before→after .0592 / .0000; before→recovered .0421 / .0000. No dropped
frames, 0 errors. **Unexplained:** G only changes CC placement, which cannot account
for production drifting after the cut while G does not. The configs also differ in
pipeline file (production vs test copy). A control is pending: the test copy at
production values (`Ptest`) through the same cut. Until then, the Arc probe is
inconclusive.

## Shadow CC strength ×2/×3/×4, today's placement vs G (user request, 2026-11-09)

`run_ccStrength.sh`: `SHADOW_TEMP` and `SHADOW_TINT` ×2/×3/×4 (GZW −.30/−.06,
−.45/−.09, −.60/−.12; Arc −.45, −.675, −.90, tint 0), other values production,
test pipeline with `SHADE_CC_MAP` 0 (P) or G. 8 stills, 48/48 with 0 errors,
identities stable, single capture each. Local page
`captures/light_lift_20261109/review_ccStrength_local/index.html`.

Share of pixels beyond about one just-noticeable step (Oklab ΔE > .02):

| Still | Today vs production ×2/×3/×4 | G vs today ×2/×3/×4 |
| --- | --- | --- |
| GZW 133444 | 0 / 0 / 4.1% | 0 / 0 / 1.2% |
| GZW 133058 | 0 / 0 / 7.6% | 0 / .1 / .2% |
| GZW 133932 menu | 0 / .1 / 5.3% | 0 / .2 / .4% |
| GZW 101035 | 0 / .4 / 28.5% | .1 / .7 / 1.5% |
| Arc 205938 menu | 0 / 54.9 / 65.7% | .4 / .7 / 1.2% |
| Arc 210448 | 0 / 41.0 / 62.1% | .1 / .3 / .6% |
| Arc 210417 (end-of-round menu over a dark tunnel) | 0 / 74.1 / 87.6% | .1 / 7.5 / 16.2% |
| Arc 211202 | 0 / 35.8 / 51.1% | .9 / 1.8 / 2.8% |

- At ×2 shadow CC is still below one just-noticeable step everywhere; Arc becomes
  visible at ×3, GZW at ×4.
- The G-vs-today difference grows with strength and is largest in dark frames
  (210417 16% at ×4: today turns the whole frame navy, G keeps the lit tunnel areas
  closer to production). In daylight it stays ≤ 3%.
- CC knows nothing of UI: the 210417 menu panel is cooled under both placements.
- 210417 had been labelled "Arc dark room" in earlier tables; it is an end-of-round
  menu over a dark tunnel. Its "dim room" numbers include the UI panel.

**Arc control (`run_ccG_transition_ptest.sh`):** the test copy at production values
reproduces production's Arc cut numbers (.0136 / .0139 / .0185 / .0592 / .0421), so
the pipeline file is not the cause; the drift difference comes with
`SHADE_CC_MAP`. Likely mechanism (not verified): production's CC zones are relative to
the time-smoothed scene key (`key_L` from `slow_key`), which keeps moving after a cut,
while G's shadow zones come from the per-frame light map. In GZW, both drift alike
(other adaptive stages dominate). Open: paused snapshots cannot show whether a
per-frame map flickers in camera motion; that needs a motion check.

## G at shadow CC ×2.5 (user request, 2026-11-09)

`run_ccStrength25.sh`: P and G at ×2.5 (GZW `SHADOW_TEMP` −.375 / `SHADOW_TINT`
−.075; Arc −.5625 / 0), 8 stills, 16/16 with 0 errors, identities stable. Added to
`review_ccStrength_local`.

| Still | Today ×2.5 vs production > .02 | G vs today ×2.5 > .02 | G ×2.5 vs production > .02 | Mean Δb G ×2.5 vs production |
| --- | ---: | ---: | ---: | ---: |
| GZW 133444 | 0% | 0% | 0% | −.0021 |
| GZW 133058 | 0% | .1% | 0% | −.0026 |
| GZW 133932 menu | 0% | .1% | 0% | −.0031 |
| GZW 101035 | 0% | .3% | 0% | −.0039 |
| Arc 205938 menu | 15.1% | .5% | 19.2% | −.0123 |
| Arc 210448 | 4.7% | .2% | 13.5% | −.0124 |
| Arc 210417 menu/tunnel | 7.9% | 2.5% | 1.6% | −.0106 |
| Arc 211202 | 15.8% | 1.3% | 15.2% | −.0086 |

In GZW, ×2.5 stays below one just-noticeable step per pixel (a broad cooling of
about −.002 to −.004 Oklab b); in Arc it is visible on 2–19% of pixels. Single
capture each.

## Strength knob, pan stability and staged port (2026-11-09)

**Knob:** `SHADOW_CC_STRENGTH` (default 1.0) multiplies `SHADOW_TEMP`/`SHADOW_TINT`
inside 3-way CC only (no other stage reads them). With the knob at 2.5 and today's
placement, the test copy matches the profile-scaled ×2.5 capture: max 8 codes on 133444
(the time-smoothed key; the same order as production repeats) and 6 on 211202.
The first 211202 check showed 230 codes, all of them on row 1439 (the last row, columns
512–2559). The source PNG is identical, so this is a capture artifact on the bottom row. The
last row is now masked in all pan/port comparisons.

**Pan (`run_pan.sh`, `analyze_pan.py`, 48/48, 0 errors):** two stills captured with the
camera moved 0–7 px, shifted back and compared with shift 0. Both are at ×2.5. The table
gives the range over shifts 1–7.

| Still | Today: px > .02 ΔE | G: px > .02 ΔE | G shadow-weight change p99 |
| --- | ---: | ---: | ---: |
| GZW 133444 | .02–.07% | .05–.11% | .09–.16 |
| Arc 211202 | ≤ .003% | .17–.57% | .19–.44 |

G shimmers slightly more than today on 133444. On 211202 it shimmers clearly more,
and the change sits on shade boundaries smaller than the map's 1/8 grid: pillar edges,
foliage, the railing and the scaffold. Today's zones follow pixel brightness, which moves
with the image. G's shadow weight comes from a map at 1/8 resolution plus a 16-tap joint
bilateral upsample, so it is phase dependent below about 8 px. This is
aliasing; the map does not lag in time. Whether it reads as visible crawl in real motion is
for the user's eye (`review_pan_local/`). This is an 8-phase static simulation, not
dense motion.

**Staged port (`general_port/`, `run_port.sh`):** the G-only `CCZoneW`, `light_map.fxh`
(map code only, no lift or debug) and the 11 map passes, with `SHADOW_CC_STRENGTH 2.5`.
It was compared with the test copy's G ×2.5 on 8 stills. Six matched within 3 codes. Two did
not on the first pass: 211202 was darker by 2.4 codes on all bright pixels, and the 133932 menu by up to 11
codes. Those two came from the capture, not the code. `run_portc.sh` repeated PORT and
added a variant with the test copy's no-op lift ceiling. The PORT repeat matches G within 2
codes on both stills. The ceiling variant matches on 211202 but again differed on 133932,
so the ceiling is not the cause. The failed first captures are kept in `stills_port/`.
Port = G within capture noise. Occasional whole-frame offsets of a few codes between runs
are a capture-state effect worth remembering.

## Pan shimmer fix (2026-11-09, after the user saw shimmer on Arc 211202, not on GZW 133444)

Two causes, each tested on the test copy at ×2.5 with the same 8-phase pan as above (row 1439
and right 24 px masked). The metric is px > .02 Oklab ΔE vs shift 0, as the mean over shifts 1–7.

| Variant | GZW 133444 | Arc 211202 |
| --- | ---: | ---: |
| Today (brightness zones) | .041% | .001% |
| G | .070% | .371% |
| + `LL_LANE 1`: the map's own full-area 1/8 input | .042% | .286% |
| + upsample range σ .35→.7 | – | .201% |
| + upsample spatial σ 1→1.5 | – | .277% |
| + range .7 and spatial 1.5 | – | .187% |
| + `LL_LANE 1` + `LL_UP_MODE 1` ("G fixed") | .042% | .030% |

1. **Input lane.** The shared spatial lane is a 4-tap box at ±1.5 px. It covers 16 of each 8×8
   cell's 64 pixels, so thin shade gaps are caught or missed by camera phase. `LL_LANE 1` adds
   one 1/8-res pass (`GradeLLLane`, 16 bilinear taps = full 8×8 mean, from the native BackBuffer
   before AnalysisSpatial) used only by the map. Production's lane is untouched. This fixes
   GZW but not Arc.
2. **Reconstruction.** The pixels that still flip on Arc are 1–3 stops below lit, the band
   where shade on bright paint and light on dark paint look alike. The joint bilateral
   upsample picks among 16 coarse taps, and which taps match changes with phase. Wider range
   or spatial σ only reduces this. `LL_UP_MODE 1` replaces it with native log luma + the
   bilinear coarse paint correction: detail below the 1/8 grid follows the pixel (like
   today's brightness zones), and the material veto acts at map scale. It is also cheaper:
   16 iterations × 2 full-res reads per pixel are replaced by 1 read, and the new lane adds
   16 taps per 64 px.

What remains on Arc (shifts 4/6/7, about .06–.08%): a soft patch on the ground beside the
rifle, p99 ΔE .04, where the dark character crosses 8-px cells and changes the coarse
correction. It is low-frequency, not edge crawl.

Placement (`stills_panLU`, 8 stills, zones from `PANLUdbg`): G fixed vs G ×2.5 differs on
.03–.76% of pixels > .02 ΔE, with mean Δb ≤ .0003. The gate-weighted shadow share moves by
≤ .008. The added shadow colour sits on sub-8-px dark detail (pillar-gap edges, shelf
edges, gun), which is where G's fine placement was phase-unstable. Review:
`review_pan_local/` (key 3) and `review_ccLU_local/`. Failed compile kept:
`run_panLU_failed_unreachable.log` (early return; fixed with `#else`).

## Adoption (2026-11-09, user: "do it")

The pan fix was folded into `general_port/`, with no test switches. The lane reads BackBuffer
with `tex2D`, per CODE_RULES; it was identical to the `tex2Dlod` build (max 1 code, 2 stills,
`stills_port3`). Port vs the test copy's G fixed on 8 stills: ≤ 5 codes on 7 of them. On 211202
the test copy's own still capture was 2.4 codes darker than its shift-0 frame of the same scene,
so the gap is a capture-state offset. Port shift 0 vs test shift 0 is 9 codes on 28 px. The port's
pan on 211202 is .030%, identical to the test copy. It was then copied to `general/`, and
`SHADOW_CC_STRENGTH 2.5` was added to both profiles. The production smoke test (`stills_prod`,
3 stills, own configs) matches the port: max 1 code; on 211202, 8 codes on 13 px.
