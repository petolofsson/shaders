# Look target from a hand-graded mock — 2026-11-11

Question: what would the testbed's untouched daylight frame look like graded as a film
(first reference: Roger Deakins), and how much of that can today's `creative_values.fx`
knobs reach?

Source: user screenshot `Screenshot_20261110_172413.png` (untouched; copy at
`captures/bugfix_20261110/user_off_172413.png`). Note: `…172357.png` is the shader-on shot
(2×2 red marker at 0,0), not the untouched one.

Scripts: [2026-11-11_look_target/](2026-11-11_look_target/) (`mock_grade_v1.py`,
`mock_grade_v2.py`, `regions.py`, `make_knob_profiles.py`). Images stay local in
`captures/deakins_mock_20261111/` (`ab.png`, `ab2.png`, `grid2.png`, `stills/`).

## Mocks (offline, numpy; not shader code)

- **Mock 1** (subtle): warm sun / restrained shade colour, sky less cyan, slight olive,
  film toe/shoulder, light hand-masked haze. User: "a little difference".
- **Mock 2** (artistic): re-lit key/fill (sun +0.12 stop, surface shade −0.30 stop),
  amber-cream sun, neutral-cool shade with the game's cyan cast stripped, polariser sky,
  olive greens, layered aerial haze, contrast 1.18 in log, cream shoulder, faint warm
  halation, foreground/corner burn.
- Haze, sky and building masks are **hand-drawn** — no depth in a screenshot. The user agrees
  haze needs depth.

Region means (sRGB codes; sat = (max−min)/max):

| Region | Untouched | Production (Retinex 0, CC 2.25) | Mock 1 | Mock 2 |
|---|---|---|---|---|
| Lit wall | 169 174 162 · .07 | 168 173 158 · .09 | 176 175 156 · .11 | 189 183 157 · .17 |
| Shade wall | 51 69 78 · .35 | 40 63 78 · .49 | 51 60 66 · .23 | 41 52 58 · .28 |
| Sky | 135 174 202 · .33 | 133 172 199 · .33 | .23 | .25 |
| Far hill | .28 | .48 | .16 | .10 |
| Jungle | .31 | .43 | .31 | .24 |

Production moves opposite to both mocks on shade colour (bluer), far hill (more
saturated) and jungle (more saturated).

## Knob-only reach (settled headless captures, 0 vkBasalt errors)

Target "AB 1.35" = roughly between mock 1 and mock 2. Best: **profile D** (changes from
the working-tree GZW file):

```
SHADOW_CC_STRENGTH 0.5   MID_TEMP 0.20   HIGHLIGHT_TEMP 0.70   HIGHLIGHT_TINT 0.15
CONTRAST 1.6   SHADOW_LIFT_STRENGTH 0.10   SATURATION 0.0
SAT_GREEN -0.05   SAT_CYAN -0.30   SAT_BLUE -0.20
PRINT_STOCK 0.9   PRINTER_R 0.5   PRINTER_B -0.5
```

| Region sat | Production | A | C | D | Target |
|---|---|---|---|---|---|
| Lit wall | .09 | .09 | .11 | .15 | ~.13 |
| Shade wall | .49 | .39 | .36 | .31 | ~.25 |
| Sky | .33 | .31 | .28 | .25 | ~.24 |
| Jungle | .43 | .33 | .33 | .37 | ~.28 |
| Far hill | .48 | .37 | .33 | .29 | ~.13 |

Findings:
- `HIGHLIGHT_TEMP` is weak (Oklab b shift 0.06 × knob × highlight weight): .25 left the
  wall unchanged; D needed .7 plus printer lights, and lands yellow-cream, not amber.
- Shade stays slightly blue even at CC .5: the source already carries the cast.
- No knob changes the key/fill ratio. Contrast and lower lift darken all darks (jungle
  included); mock 2's building shape comes from re-lighting with the light map.
- Warm push raises jungle chroma (.37); `SAT_GREEN` ≈ −.15 untested.
- Haze: not reachable without depth.

Untested in game; one frame only. Big knob values — check shade, night/indoor and menus.

## Next (user, 2026-11-11)

1. **Restart the artistic stage with several references,** not Deakins alone (e.g. other
   naturalistic daylight cinematographers and stills photographers). Make a small set of
   mocks of the same frame, pick a direction, and write it into GOAL-level terms.
2. Then work toward it: knob profile first (D as the starting point), then shader work
   where knobs cannot reach — the light map driving brightness (key/fill), not only
   colour; a stronger, amber sun control; and a depth-free haze only with evidence.

## Reference directions (2026-11-11, second pass)

Script: [`mock_refs.py`](2026-11-11_look_target/mock_refs.py). It applies one parametric
offline grade to the same untouched frame, with one parameter set per reference and the
same hand masks as mock 2. Images: `captures/look_refs_20261111/` (native PNGs + `grid.png`).
Each reference's traits come from the sources listed under it. The mocks show my reading of
those traits applied to this frame; they are not matched to film stills.

| Mock | Reference | Traits taken from sources |
|---|---|---|
| `toll` | *The Thin Red Line* (John Toll) | Daylight 100-ASA Kodak 5248; no added fill, because it erased the jungle's subtle colour gradations; hot sun patches |
| `khondji` | *The Lost City of Z* (Darius Khondji) | 5219 + 812 warming filter in daylight; flashed negative; cooled shadows; sun-roughened patches |
| `burrows` | Larry Burrows, LIFE (Vietnam) | Colour transparencies; deep green, saturated reds; slide density |
| `fukunaga` | *Beasts of No Nation* (Cary Fukunaga) | Filtration in camera; slightly under-exposed for blacks and colour; steely blues and scarlets |
| `semler` | *Apocalypto* (Dean Semler) | Natural canopy light, no colour-correction filters; "painterly glow"; rich, healthy jungle palette |

Sources: [ASC Feb 1999, Toll](https://theasc.com/magazine/feb99/war/pg3.htm);
[ASC, Lost City of Z](https://theasc.com/article/the-lost-city-of-z-time-immemorial/);
[Kodak, Lost City of Z](https://www.kodak.com/en/motion/blog-post/the-lost-city-of-z/);
[Christian Century review, Apocalypto](https://www.christiancentury.org/reviews/2006-12/fall-empire);
[Bedford/Macmillan, Semler on filters](https://digfir-published.macmillanusa.com/filmmaking1e/filmmaking1e_ch6_12.html);
[New Statesman, Beasts](https://www.newstatesman.com/culture/2015/10/beasts-no-nation-reminds-us-fates-worse-death);
[Wikipedia, Beasts](https://en.wikipedia.org/wiki/Beasts_of_No_Nation_(film));
[Digital Journalist, Burrows](https://digitaljournalist.org/issue0302/halberstam.html);
[V&A, Burrows print](https://collections.vam.ac.uk/item/O1756281).

Region sat (lum lin) in sRGB:

| Region | Untouched | Deakins 2 | Toll | Khondji | Burrows | Fukunaga | Semler |
|---|---|---|---|---|---|---|---|
| Lit wall | .07 (.448) | .17 (.523) | .11 (.485) | .20 (.478) | .10 (.533) | .11 (.467) | .17 (.489) |
| Shade wall | .35 (.058) | .28 (.034) | .26 (.049) | .32 (.067) | .42 (.029) | .59 (.030) | .27 (.051) |
| Sky | .33 | .25 | .30 | .23 | .39 | .38 | .28 |
| Far hill | .28 (.046) | .10 (.058) | .12 (.058) | .06 (.085) | .28 (.031) | .60 (.026) | .09 (.064) |
| Jungle | .31 (.042) | .24 (.036) | .25 (.046) | .22 (.070) | .43 (.028) | .57 (.025) | .28 (.049) |

Notes:
- Two families: **naturalistic and soft** (Toll, Semler, Khondji, Deakins 2: less chroma in
  shade and distance, warm sun) and **dense slide** (Burrows, Fukunaga: darker, more
  saturated darks). Production is closer to the dense-slide family on shade and distance.
- Fukunaga's shade wall (sat .59) and far hill (.60) form a conspicuous blue cast, which
  GOAL rules out; it stays only as a contrast case.
- Khondji's flash lifts blacks (far hill lum .085), which conflicts with GOAL's deep-shadow aim.
- Mocks still depend on hand masks (haze, sky, hill) and one frame.

Blends (parameter sets mixed linearly, same script):

| Region sat (lum lin) | `mix_ts` (Toll .5 + Semler .5) | `mix_tsb` (Toll .35 + Semler .35 + Burrows .30) |
|---|---|---|
| Lit wall | .14 (.488) | .13 (.506) |
| Shade wall | .27 (.050) | .30 (.043) |
| Sky | .29 | .32 |
| Far hill | .10 (.061) | .13 (.051) |
| Jungle | .26 (.047) | .28 (.041) |

`mix_tsb` keeps the naturalistic shade/distance colour but brings back some depth in the darks.

**Decision (user, 2026-11-11):** `mix_tsb` is the look target ("looks like a good target",
judged on `mix_tsb_view.png`, 1600×900 of the native mock). It is naturalistic: cream-warm sun,
neutral shade without the game's cyan, distance that recedes, healthy greens, and darks
about 15% deeper than untouched. One frame; haze/sky masks are hand-drawn.

## Knob fit toward `mix_tsb` (2026-11-11)

Script: [`fit_knobs.py`](2026-11-11_look_target/fit_knobs.py). The profiles are copies of the
working-tree GZW `creative_values.fx` (Retinex 0, CC 2.25), and the configs are copies of
`gzw.conf` pointing at them; the originals were not changed. Captures were headless and private:
`compare_frame.py --delay 5 --settle 20` (looping 30-fps clip), all rc 0. Images:
`captures/look_fit_20261111/stills/`, grid `fit_grid.png` (untouched / production / H / mix_tsb).
Each profile was captured once (no repeats).

Best: **H** (overrides vs the working tree):

```
EXPOSURE 0.15   SHADOW_CC_STRENGTH 0.5   MID_TEMP 0.20   HIGHLIGHT_TEMP 0.60   HIGHLIGHT_TINT 0.0
CONTRAST 1.6    SHADOW_LIFT_STRENGTH 0.50   SATURATION -0.10
SAT_GREEN -0.20   SAT_CYAN -0.30   SAT_BLUE 0.0
PRINT_STOCK 0.9   PRINTER_R 0.5   PRINTER_B -0.5
```

| Region: sRGB · sat · lum lin | Production | D | H | Target `mix_tsb` |
|---|---|---|---|---|
| Lit wall | 168 173 158 · .09 · .447 | 174 172 148 · .15 · .449 | 182 180 157 · .14 · .497 | 182 182 159 · .13 · .506 |
| Shade wall | 40 63 78 · .49 · .048 | 44 57 64 · .31 · .041 | 48 61 68 · .29 · .047 | 45 59 65 · .30 · .043 |
| Shade paving | 125 124 111 · .11 · .201 | · .18 · .193 | 133 129 111 · .16 · .219 | 133 130 113 · .15 · .224 |
| Grass | · .44 · .098 | · .47 · .091 | 84 84 51 · .39 · .103 | 81 85 47 · .45 · .104 |
| Sky | · .33 · .387 | · .25 · .386 | 150 180 198 · .24 · .431 | 134 171 196 · .32 · .380 |
| Far hill | · .48 · .037 | · .29 · .033 | 37 48 50 · .27 · .037 | 53 61 61 · .13 · .051 |
| Jungle | · .43 · .035 | · .37 · .030 | 35 46 33 · .29 · .035 | 40 53 38 · .28 · .041 |

Other variants: E/F/G (more green/global desaturation; contrast 1.4 + lift .2 ≈ unchanged),
I (exposure .10 + lift .75: darks unchanged, all brighter areas darker), J (green −.30, sat −.15:
jungle .26, sky .23), K (exposure .25 + contrast 1.8: everything brighter, far hill .040).

Findings:
- **Knobs reach it:** lit wall colour (cream, R≈G), neutral shade with the cyan stripped,
  shade paving, grass, the warm/cool balance.
- **Knobs do not reach:**
  - *Far hill recession:* it stays dark (.037 vs .051) and green (.27 vs .13). That is aerial
    haze, which needs depth or a distance cue.
  - *Sky:* the sky and the shade wall share a hue (~200°), so `SAT_CYAN`, which neutralises the
    shade, also greys the sky (.24 vs .32). Raising exposure brightens the sky (.431 vs .380).
    Separating them needs zone- or light-map-aware chroma, not hue bands.
  - *Dark-foliage lift:* jungle .035 vs .041. `SHADOW_LIFT_STRENGTH` .5→.75 and
    `CONTRAST` 1.4→1.8 hardly move it.
- H uses large knob values on one frame. Shade, night, indoor and menu scenes have not been checked.

## H across other scenes (2026-11-11)

I captured 7 overcast/interior/UI references (`gamespecific/gzw/analysis/reference/autof_20260515_*`:
133119 village, 133343 and 133444 interiors, 133729 field, 133831 hills, 133912 inventory menu,
133932 warm title screen) with production and H, all settled and headless, rc 0, one capture each.
Review panels (image / 0–100 value study / zone overlay):
`captures/look_fit_20261111/review/review_*.png`. Script:
[`review_scenes.py`](2026-11-11_look_target/review_scenes.py).

| Scene | Mean sat: source / prod / H | Dark-20% sat: source / prod / H | Seen |
|---|---|---|---|
| 133119 village | .240 / .305 / .258 | .466 / .584 / .424 | H closer to source |
| 133343 interior | .493 / .427 / .506 | .545 / .563 / .605 | H keeps the warm wood |
| 133444 interior | .560 / .433 / .546 | .463 / .400 / .540 | prod cools it bluish; H keeps the warm source |
| 133729 field (overcast) | .300 / .380 / .274 | .437 / .630 / .379 | **H brown-olive, greens drained** |
| 133831 hills (overcast) | .248 / .309 / .196 | .413 / .627 / .403 | **H grey-brown, drab** |
| 133912 menu | .153 / .430 / .202 | .104 / .710 / .242 | prod tints the dark UI teal; H near neutral |
| 133932 title (warm sun) | .500 / .539 / .569 | .543 / .623 / .654 | H more amber; p95 .481→.510 |

No clipping in either profile (black ≤ .28%, white 0%). Mean luminance stays within ±.01.

Findings:
- **H fails on overcast scenes.** Its warmth (mid/highlight temp, printer R/B) is a sunlit look.
  With no sun, it becomes a global brown cast and the foliage loses its green. GOAL rules out
  conspicuous casts, and this does not preserve the scene's own lighting. A global knob profile
  therefore cannot carry the target.
- **Production also has a cast:** it adds dark-pixel chroma everywhere, which is teal in UI and
  bluish in interiors (dark-20% sat .10 → .71 in the menu). This comes from `SHADOW_CC_STRENGTH` 2.25
  with a cool `SHADOW_TEMP`. H's CC .5 avoids it.
- Implication: the warm sun has to depend on the scene's direct light (light-map key vs fill
  contrast), not a fixed temperature. This is the "amber sun" gap, now with overcast evidence.

## Warm key gated by direct-light evidence (2026-11-11, candidate code)

Problem: H's warmth is global and casts brown on overcast scenes. Goal: warmth only where the
frame has a warm key against a cool fill.

**Cue screen** ([`sun_cue_screen.py`](2026-11-11_look_target/sun_cue_screen.py),
[`sun_edge_screen.py`](2026-11-11_look_target/sun_edge_screen.py),
[`sun_edge_sparse.py`](2026-11-11_look_target/sun_edge_sparse.py)). 49 GZW and Arc references,
labelled by eye (16 sun, 20 overcast, 13 interior/menu/night).
- Lit-vs-shade mean colour split: **failed**. Sky dominates the lit set.
- Sun-edge share: 1/8-lane neighbour pairs that step > 1 stop with the darker side > .1 bluer along
  `LL_SKY`. Dense: sun 2.24–8.41%, overcast 0.27–1.85%, inner 0.37–5.72% (warm-lamp Arc
  interiors and menus read high). Sparse 16×16 points: sun 1.4–7.0 (median 3.7), overcast
  0.2–2.0 (median 0.8).
- What it measures is warm key / cool fill, not "outdoors". Warm lamp interiors can pass.

**Code** (uncommitted): `light_map.fxh` (`LLSunEdge`, `LLAnchorTex` → RGBA32F with `.b` cue,
+512 lane reads in the 1×1 anchor pass, `LLSunRaw`); `grade.fx` (`KEY_WARMTH` default 0,
`sun_key` smoothed in the adaptive history channel formerly written as zero, mid/highlight temp
offsets); [pipeline](../docs/pipeline.md#light-map-and-3-way-cc-zones). Profiles are unchanged.

**Validation** (settled headless captures; [`analyze_r3.py`](2026-11-11_look_target/analyze_r3.py),
images `captures/look_fit_20261111/r3/`, grid `gated_grid.png`):
- Identity: the production profile on the new code matches the old production capture exactly on 6
  scenes (0 codes, 0 px changed).
- Indirect cue readback, Oklab Δb (production + `KEY_WARMTH` 1 minus production) in the brighter
  half:

  | Frame | Δb |
  |---|---|
  | GZW sun 172413 | +.019 |
  | Arc sun 210958 | +.010 |
  | GZW warm title 133932 | +.009 |
  | Arc sun 211131 | 0 (miss: its sparse cue is 1.6%, below the ramp) |
  | GZW overcast 133729, overcast 133831, interior 133444, menu 133912 | exactly 0 |

  This is from output images; it is not a GPU readback of `sun_key`.

**Gated profiles** (H minus its global warmth: `MID_TEMP` .0875, `HIGHLIGHT_TEMP` .10, printer
lights 0; plus `KEY_WARMTH`):
- H2 (`KEY_WARMTH` 1.0): sunny wall 184 180 145, too yellow.
- H3 (H2 + `SAT_GREEN` −.10, `SATURATION` 0): overcast mean sat back at source (133729
  .301 vs source .300; 133831 .250 vs .248); R−B +2.8/−2.9 vs H +5.9/+1.7. No brown cast.
  Menu .216 (production .430).
- **H4** (H3 with `KEY_WARMTH` .5): sunny wall **180 180 154** (target 182 182 159), shade
  wall .34 sat (target .30), sky .26 (H .24, target .32), jungle .34 (target .28). On frames
  where the cue reads 0, H4 equals H3 (inferred from the gating; not captured separately).

Remaining gaps are the same as before: far-hill haze, sky vs shade chroma, dark-foliage lift.
One capture per profile; no pan or motion check of the cue (sparse sampling + 1.5 s smoothing
is meant to prevent pumping, untested in motion).

### Pan and cut check of the cue (2026-11-11)

Profile: production + `KEY_WARMTH` 1.0 (twice H4's strength). Script:
[`analyze_pan_r3.py`](2026-11-11_look_target/analyze_pan_r3.py); captures in
`captures/look_fit_20261111/pan/`.

- **8-phase static pan** (still shifted 0–7 px, shifted back, compared with shift 0; right 24 px,
  marker and last row masked):
  - GZW sun 172413, cue saturated: bright-half b is stable at phases 0–5 and drops .0015 at
    phases 6–7 (cue about 1.0 → .92).
  - Warm title 133932, cue mid-ramp, so the most sensitive: worst at phase 6, bright-half b
    −.0022, px ΔE(×100) > 1 1.42% vs 0.155% for production at the same shift; mean ΔE
    .34 vs .27. Production's own ≈ .27 mean is the screen-space dither shifting against
    the content.
  - Reading: sparse 16×16 sampling makes the cue phase-dependent by up to ~25% of the warmth
    on frames in the ramp. At H4's `KEY_WARMTH` .5 that is about Δb .001. The 1.5 s smoothing
    averages normal pans (one 8-px phase cycle per ~8 frames at 1 px/frame); only very slow
    drifts (≥ 8 s per 8 px) could show it as slow breathing. Denser sampling (e.g. 32×18
    points) is the fix if it shows in play.
- **Cut** (`--transition`, sun 172413 → overcast 133729 → sun; 0 dropped/delayed frames):
  0.5 s after each cut, bright-half b already equals the settled value of the new scene
  (.00946 overcast, .02351 sun), with no lag or overshoot. The cut reset works.

## Red Dead Redemption 2 as a nature reference (2026-11-11, desk research)

Sources: [SIGGRAPH 2019 Advances course, Bauer (Rockstar), "Creating the Atmospheric World of
RDR2"](https://advances.realtimerendering.com/s2019/index.htm) (abstract only; slides are a 232 MB
PPTX, not read); [graphics study of an RDR2 frame](https://imgeself.github.io/posts/2020-06-19-graphics-study-rdr2);
[TechRadar on its HDR output](https://www.techradar.com/news/red-dead-redemption-2-is-faking-its-hdr-output).

What carries RDR2's nature look, according to these sources:
- Engine-side atmosphere: raymarched volumetric fog and clouds over a voxelised scene, scattering
  and transmittance shared between systems, physically based but art-directable per mission and mood.
- An ambient model that approximates indirect light from the sky (shade lit by the actual sky).
- Baked large-scale AO plus SSAO; cascaded sun shadows.
- Non-thresholded bloom whose intensity rises with distance (more glow in foggy depth).
- Tonemapping/grading are not documented; reports describe a warm yellow/orange grade.

Mapping to this pipeline:
- **Not portable:** volumetric fog, aerial perspective and distance-weighted bloom all need
  depth, and depth is unavailable (anti-cheat). Diffusion/bloom is also excluded by AGENTS. So
  the haze gap stays engine-side.
- **Already consistent:** "physically grounded, art-controllable", i.e. look parameters driven
  by measured light rather than fixed. `KEY_WARMTH` gated by the warm-key cue follows that model.
- **Candidate (from the sky-ambient idea):** the shadow CC currently pushes a fixed cool colour
  (`SHADOW_TEMP` × `SHADOW_CC_STRENGTH`) into every dark zone, including menus and interiors
  (the teal cast found in the scene review). RDR2 lights shade with the measured sky. The
  equivalent here: scale or orient the shadow CC by the frame's measured fill colour. The light
  map's `LLDirections` already computes lit and dark chromaticities, then normalises away the
  magnitude; the warm-key cue is a related measure. Overcast and menus (no cool fill) would get
  little shadow CC; sunny frames keep it. Not built; this is item 2 of the earlier gap list.

## Fill-following shadow CC (round 5, 2026-11-11)

Idea from the RDR2 sky-ambient review: shade colour should follow measured fill, not a fixed tint.
A global lit/shade chroma split was already ruled out (sky is lit and blue; `sun_cue_screen.py`),
so the shadow CC reuses the sun-edge cue: `shadow_cc = SHADOW_CC_STRENGTH · lerp(1, sun_key,
SHADOW_FILL_FOLLOW)` in `grade.fx`. No new taps, passes or history. Default 0 = production.

Captures `captures/look_fit_20261111/r5/` (profiles r5_cur, r5_curF1, r5_H5, r5_H5s = H5 with
SHADOW_CC 1.25; plus r4_H4 on the remaining scenes); `analyze_r5.py`; grid `fill_follow_grid.png`.

- Identity: follow 0 is bit-identical to r3_cur on all 7 scenes.
- Sun (172413, title 133932): curF1 = cur exactly (sun_key saturated), cool shade kept.
- Arc 210958 (partial cue): darker-half b −3.19 → −2.40 (source −1.72), half the push kept.
- Overcast 133729 / 133831: darker-half b +0.28 → +1.36, +0.42 → +1.53 (source +1.26, +1.42).
- Interior 133444: +0.66 → +1.50 (source +1.33).
- Menu 133912: darker-20% C 1.58 → 0.47 (source 0.19); darker-half b −1.45 → +0.10 (source
  +0.04). Visible teal UI cast gone; residual 0.28 C comes from other stages.
- H5 vs H4: overcast and menu shade return to source; sun unchanged. H5s (CC 1.25) adds back cool
  shade only on sun frames (172413 darker-half b −0.06 → −0.41).
- Not checked: pan breathing of shade colour (same cue and 1.5 s smoothing as KEY_WARMTH; at
  production 2.25 strength the mid-ramp cue wobble of ~25% maps to ≈ .005 Oklab b in shade), live play.
