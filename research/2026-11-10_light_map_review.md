# Light map review (2026-11-10)

The user asked for a whole-repo pass for improvements to the adopted light map
(`general/grade/light_map.fxh`, [placement report](2026-11-09_cc_light_map_placement.md)).
Code read: `light_map.fxh`, `grade.fx` consumers, the shared spatial lane and its readers,
and the shadow surround tint's own shade weight. CPU checks are in ignored
`captures/lightmap_review_20261110/` (`score_lightmap_oracle.py`, `score_jbu_vs_native.py`,
`oracle_auc.json`). No shader was changed.

## Accuracy on the cue-map oracle

These use the same synthetic frames, regions, sampling and AUC as the
[cue-map oracle](2026-11-08_cue_map_oracle.md). The CPU form is the material veto at t .35
(global Poisson; the GPU pyramid scored .150 vs .149 on the 7-scene screen) with per-pixel
light = native log luma + bilinear 1/8 correction, as adopted. "Hard" means shaded bright
vs lit dark material.

| Cue | Daylight shaded vs lit | Daylight hard | Interior shaded vs lit | Interior hard |
| --- | ---: | ---: | ---: | ---: |
| pixel darkness | .54 | .08 | 1.00 | 1.00 |
| surround-tint weight (2026-11-08) | .51 | .35 | .77 | .77 |
| light map, −light | .57 | .15 | 1.00 | .99 |
| CC shadow ramp ss(1.25, 2.75) | .70 | .50 | .78 | .78 |

The old bilateral upsample scored .558 / .126 in daylight, so the pan fix cost no accuracy
(.565 / .139 in the same run at 1280×720).

- **Daylight material separation is weak.** The veto fires on .6% of steps. Lit dark
  material gets only about +.7 stop more correction than shaded bright surfaces, and the
  CC ramp gives both full shadow weight (lit dark material .999). The map's gain on game
  frames comes from chromatic paint edges; neutral or low-contrast dark materials stay
  "shade". Earlier screens covered stronger veto rules (hue-angle, caps, flat-fielding,
  colour edges); none beat t .35.
- **Interior:** −light ranks almost perfectly. The CC ramp is lower (.78) by design: the
  absolute term was calibrated so dim rooms keep some shadow colour.

## Findings, ranked

1. **The shadow surround tint could take its shade weight from the light map.** The tint's
   weight is at chance in daylight (.51) and tints lit dark materials beside brighter
   surfaces. The map's CC ramp scores .70 / .50 in daylight and matches it in interiors.
   This is a documented gap. Shade-weight placement would change an accepted look, so it
   needs matched captures and the user's eye.
2. **One shared full-area lane.** The shared spatial lane is a 4-tap box covering 16 of
   64 px. Its readers are the histogram, percentiles, mean chroma, the corrective zone
   histogram, tint gather/region, guided coefficients, neutral illuminant and low-frequency
   mips, and all of them inherit the aliasing the map's pan test exposed. Writing the shared
   lane with the map's 16-tap kernel would let `GradeLLLane` go: one pass fewer, same total
   taps. It changes every lane consumer, so it needs a pan test of production plus matched
   stills. A visible loss is not yet shown for those consumers.
3. **Hard paint threshold.** `LLPaint` is a binary step at .35 on both length and
   perpendicular distance. Chroma steps near .35 flip the correction on and off with camera
   phase and noise. A smoothstep (e.g. .30–.40) would make it continuous. The remaining
   soft patch beside the rifle (Arc 211202 pan) may come partly from this; not verified.
4. **Dead work in `LLAnchorPS`.** `sum_ly` is accumulated (256 lane reads with log2) and
   never used, which breaks the "consume every helper result" rule. The header comment
   ("mean log luminance of the lane minus mean scaled pyramid output") describes the unused
   path. The fix is safe and output-identical.
5. **Serial 1×1 passes.** `LLDirections` makes 768 serial lane reads with logs and
   `LLAnchor` makes 512 (256 after item 4), each on one GPU thread. The cost is latency, not
   throughput, and it cannot be quantified here (no GPU profiling). A 16×16 partial-sum pass
   would parallelise it at the price of a pass. Only worth doing if frame time is in doubt.
6. **Lane decode order.** `LLLanePS` (and the shared lane) average sRGB-encoded values
   bilinearly, then decode. At high-contrast shade edges this biases the 8×8 mean dark. The
   exact form needs 64 point fetches per lane texel (≈1 tap per screen pixel). Low priority.
7. **Native vs lane statistics.** Per-pixel light uses native log luma, while the lit level
   comes from 8×8 means. Across 40 reference stills the native log mean is .02–.20 stop
   below the lane's (median .10). The lit level differs by ≤ .12 stop, and the share of
   pixels > 2 stops below lit rises by a median 1.4% (max 4.3%). This is small and was part
   of the approved look; no action.
8. **Precision.** Pyramid and correction textures are R32F; R16F would be enough (stops,
   ~.004 resolution). The bandwidth saving is negligible at 1/8 resolution; no action.

Not reopened: camera-motion separation, flat-fielding, keep-only-light colour edges and a
frame-level UI gate ([light lift report](2026-11-09_light_lift_candidate.md)).

## Item 1 follow-up: tint shade weight from the map (user: "Start with 1")

Offline only (`score_tint_variants.py`, `tint_t2_game.py`). T1 replaces the tint's
`rel_dark` ramp with the map's CC shadow ramp, keeping the other gates. T2 multiplies the
tint's weight by the map's shadow weight, so it can only remove tint.

| Oracle region mean / AUC | Today | T1 | T2 |
| --- | ---: | ---: | ---: |
| Daylight lit dark material | .31 | .995 | .31 |
| Daylight partial bright | .10 | .996 | .10 |
| Daylight AUC / hard | .51 / .35 | .66 / .51 | .52 / .35 |
| Interior AUC / hard | .77 / .77 | .85 / .85 | .69 / .69 |

- **T1** raises AUC by tinting nearly all dark surfaces in daylight. Lit dark material goes
  from .31 to .995, which makes the tint's documented cost worse, not better.
- **T2** changes nothing in synthetic daylight, because the map also calls lit dark material
  shade. On 8 game stills (map from the adopted G-fixed zone captures) T2 removes 3–15% of the
  tint's weight. Tint weight on pixels the map calls clearly lit is 1–10%, and most of it is on
  210448 and 133058.

Verdict: the ranking in item 1 rested on AUC alone. Region means show that the map does not
separate lit dark material from shade any better than the tint's own cue in daylight, which is
where the tint's cost sits. T2 is safe but removes about a tenth of an already subtle effect,
and a visible change is unlikely. No GPU candidate was built. Item 1 is not supported; the
map's limit is daylight material separation itself (see Accuracy above).

## Items 4, 3, 2 (user: "4 then 3 then 2")

**4, adopted (2026-11-10):** removed the unused `sum_ly` loop from `LLAnchorPS` in
production and updated its comment. A production capture of 133444 matches the pre-change
production capture (max 1 code).

**3 and 2, test copy** `captures/lightmap_review_20261110/general_test` (production + switches),
`run_items32.sh`, 66/66 captures, 0 errors, identities stable, production profiles. `base` =
production's own configs. P3 = `LM_PAINT_SOFT 1`: paint step smoothstep(.30, .40) on chroma
length and perpendicular distance. L2 = `LM_SHARED_LANE 1`: the shared spatial lane is
written with the full-area 16-tap kernel and the map reads it instead of `LLLaneTex`.

Pan (px > .02 ΔE vs shift 0, mean over shifts 1–7):

| | 133444 | 211202 |
| --- | ---: | ---: |
| base | .042% | .030% |
| P3 | .041% | .027% |
| L2 | .000% | .029% |

Stills vs base (8): P3 changes no pixel by > .02 (p99 ≤ .004). L2 changes ≤ .03% of pixels,
except the two Arc menus: 210417 1.4% and 205938 .23% (p99 .029 / .010). Those changes are
soft patches around UI panels (XP bar, buttons), where regional fields now average the whole
8×8 cell.

- **3** has no measurable effect. The Arc soft patch is not caused by the paint threshold.
  It is only a rule-consistency change: continuous instead of a hard step.
- **2** removes production's remaining GZW pan shimmer completely; that shimmer came from
  other lane consumers, not the map. Arc is unchanged: its patch is the map's coarse
  correction. Adopting it drops `GradeLLLane` (one pass, 16 taps per 64 px) and raises the
  shared lane from 4 to 16 taps per 64 px, so the net cost is lower.

**3 and 2, adopted (2026-11-10, user: "Go for 2 and 3"):** production lane kernel is 16 taps;
`LLLaneTex`, `LLLanePS` and the `GradeLLLane` pass are removed, and the map reads
`ReadSpatialLane`; the paint step is smoothstep(.30, .40). Production check
(`stills_prod2`, 5 captures, own configs) vs the L2 test captures: no pixel > .02 (p99 ≤ .004).
The 133444 shift-3 pan pair is .000%.
