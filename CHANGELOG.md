# Changelog

Adopted changes only. Dated reports retain validation, rejected variants and
tradeoffs; their profile values describe their own evidence epochs. Current
profiles and scores are in [HANDOFF.md](HANDOFF.md). The former detailed ledger
is preserved in [research](research/2026-11-06_root_document_history.md).

## 2026-11-11 — Light-aware CC; cost reduction

Look target (user): mock `mix_tsb`, naturalistic film daylight ([look target](research/2026-11-11_look_target.md)).
- **`KEY_WARMTH`:** `LLAnchorPS` counts sun edges (lane steps > 1 stop whose darker side is
  > .1 bluer along `LL_SKY`) at its 16×16 points; the share ramps 1.5–3.0% into `sun_key`
  (1.5 s symmetric half-life, reset at cuts, adaptive record 0 G). Adds `KEY_WARMTH·sun_key`
  to highlight temperature and half to mid. Default 0.
- **`SHADOW_FILL_FOLLOW`:** scales shadow CC by lerp(1, `sun_key`, follow), so overcast,
  interior and menu shade keeps source colour (menu dark-20% chroma 1.58 → .47, source .19).
  Default 0.
- **`SHADOW_NEUTRALIZE`:** `LLAnchorPS` measures fill colour relative to the key at sun edges
  (`LLFillTex`); 3-way CC removes that share from shade before the shadow CC, toward neutral
  only. Default 0 (bit-identical on 172413). GZW profile 1 (user accepted the recommendation):
  172413 shade wall Oklab b −2.7 → −1.8 (target −1.5); golden 133932 and overcast 133729 unchanged.
- Defaults are bit-identical to the previous production on 7 scenes. GZW profile (user, live
  play): `KEY_WARMTH` .5, `SHADOW_FILL_FOLLOW` 1, `SHADOW_CC_STRENGTH` 1.25, `RETINEX_STRENGTH` 0.

Cost ([report](research/2026-11-11_cost_reduction.md)): GZW shader cost ~2.2 → ~1.15 ms.
`OklabToSDR` returns in-gamut colours directly (user-authorized output-preserving branch;
CODE_RULES exception); compile-time skips of zero-knob stages; five 1×1 analysis passes merged;
lane-sample caches; one highway copy; analytic inverse-grade gamut limit; native guide R16F.
44 → 40 passes. Bit-identical except the trims and analytic limit (≤ 1 code, ≤ .9% px).

## 2026-11-10 — Retinex strength .4

The user chose `RETINEX_STRENGTH` .4 in both profiles after a settled review of 0–1.0. At 1.0 settled
Retinex pulled daylight mids/highlights down by up to 7–8 codes; .4 keeps about 40% of that, close
to what earlier unsettled reviews showed as production
([recheck](research/2026-11-10_settled_capture_recheck.md)).

## 2026-11-10 — Bug analysis fixes; settled captures

From a code review, with the user's approval:
- **Scene cuts:** the brightness trigger compares the current frame's mean log2 luma with the
  previous frame (0.6–1.1 stops). It formerly compared a doubly smoothed p50 and almost never
  fired; a raw p50 jumped on camera flicks ([recheck](research/2026-11-10_settled_capture_recheck.md)).
- **Slow key:** a cut resets it in proportion to cut confidence. The former 67 ms rate met a
  one-frame pulse and moved it ~16%, so the key lagged ~20 s and over-lifted dark scenes after a
  bright interlude.
- **Scene context once per frame:** new `SceneContext` pass (grade 24 passes); ColorTransform
  reads 6 texels instead of rebuilding the context per pixel. AdaptiveHistory copies those
  texels, so no pass reads another texel of its own target (rule added to CODE_RULES).
- Reversed `smoothstep` edges rewritten; unused parameters and dead values removed.
- **Captures:** `compare_frame.py` single-PNG mode plays a looping lossless clip; a still PNG
  never settled frame-time histories (gate ~.4, entropy ~.1 at capture; run-to-run noise).

Static stills equal the previous build (≤ 1 code, ≤ .013% px); repeats bit-identical. Cut
probes: dark↔bright and a 1.15-stop brightness-only cut reset fully; a fast flick does not cut.
Settled recapture: Retinex acts about twice as strongly in game as earlier stills showed, shadow
lift about a third less in foliage; FILM_CURVE stays inert. Leftover configs (cs2, trials) removed. GZW profile:
`SHADOW_CC_STRENGTH` 2.0, `HIGHLIGHT_TEMP` .10 (user).

## 2026-11-10 — Warm restraint

At the user's request ("a natural look"): new knob `WARM_RESTRAINT`. Red through yellow (full
weight ~20–105°, fading to zero by ~128°) keep only (1 − value) of the chroma the chroma stage adds,
and are never cut below that stage's input. Greens, blues and luminance are unchanged. Set to 1.0 in
both profiles: warm bands go from 1.02–1.25× source to about .95–1.07×
([report](research/2026-11-09_warm_hue_research.md)). Both profiles now also list the
existing per-band `SAT_*` controls at 0.

## 2026-11-10 — Full-area spatial lane; light map cleanup

From the [light map review](research/2026-11-10_light_map_review.md), with the user's approval:
- The shared 1/8 spatial lane is now a full 8×8 mean (16 taps) instead of a 4-tap box that
  covered 16 of 64 px. GZW pan shimmer went from .042% to .000% of pixels; game stills
  changed on ≤ .03% of pixels, and Arc menus show soft changes around UI panels (≤ 1.4%).
  The light map reads this lane, so its own lane pass is gone (one pass fewer).
- The light map's paint step is now a smooth ramp (.30–.40) instead of a hard .35 step.
  It has no measurable effect.
- Removed an unused 256-sample sum from `LLAnchorPS`; output unchanged.

## 2026-11-09 — 3-way CC zones from the light map

3-way CC shadow colour is now placed by an estimated light map instead of pixel
brightness, so dark materials in light are not cooled. Dim frames keep some shadow
colour through a low-absolute-light term. Highlight colour stays brightness-based
inside the lit share ([report](research/2026-11-09_cc_light_map_placement.md),
variant G; the user approved the look).
- New `light_map.fxh`: a 1/8 material-veto light estimate. It has its own full-area
  input lane, and per-pixel light is native luma plus a bilinear correction. Pan
  shimmer on Arc 211202 went from .37% (bilateral upsample) to .03% of pixels.
- 12 new passes (1 lane + 11 map, all at 1/8 or 1×1) and one map read per pixel in
  `ColorTransform`.
- New profile knob `SHADOW_CC_STRENGTH`: 2.5 in both profiles, at the user's request
  (Arc is visibly cooler on 2–19% of pixels; GZW stays below one just-noticeable step).

## 2026-11-09 — Cheaper shadow surround tint

[Optimized the tint](research/2026-11-09_tint_optimization.md) with no intended
change to output:
- Merged the two gather passes into one two-target pass.
- Made both environment blurs separable, with 32F intermediates (exact for the
  square Gaussian kernels).
- Replaced `atan2`/`sin` in the H-K hue term with an exact identity.

Tint passes went from 5 to 4 and blur fetches from 530 to 64 per 1/16 texel.

## 2026-11-09 — Warmth 1.75×

User screenshots (shader on vs off) showed red chroma +20–35% and orange/yellow
+13–26%, mainly from warmth. The user eased mid/highlight warmth from 3.5× to
1.75×: GZW .0875/.175, Arc .0875/.0875. Profile change only.

## 2026-11-09 — Saturation .075, shadow CC ×3

After the [effect-visibility check](research/2026-11-09_effect_visibility.md),
the user set `SATURATION` .15 and shadow temp/tint ×4, then eased both to
`SATURATION` .075 and ×3 (GZW −.15/−.030, Arc −.225) in both profiles.
`FILM_CURVE` is marked inert: print's shoulder compensates for it. Profile
changes only.

## 2026-11-08–09 — Print stock 0.5, warmth 3.5×

The user set `PRINT_STOCK` to 0.5 in both profiles after a
[print-strength comparison](research/2026-11-08_cool_chroma_print_strength.md).
Print was the main cause of cool-hue chroma loss and the overall darkening;
0.5 roughly halves both. The user then raised mid/highlight warmth 3.5×. The old
values were below visibility. GZW is now .175/.35 and Arc .175/.175. Profile
changes only.

## 2026-11-08 — Shadow surround tint

Adopted the [shadow surround tint](research/2026-11-08_shadow_tint_candidate.md):
shaded areas take a slight tint of the surrounding surface colour. It uses one
equal-perceived Oklch+ step and a Helmholtz–Kohlrausch darkening, computed on
the regional colour so pixel noise is not amplified. The darkening fades out near
emitters and on lit spots. Five low-resolution grade passes were added. The new
`SHADOW_SURROUND_TINT` control is set to 1.0 in both profiles. Known limitation:
dark background behind bright foreground objects can receive a tinted halo
(colour-only; depth is unavailable).

## 2026-11-08 — Review fixes

Applied all six findings of the [full-shader review](research/2026-11-08_ultrareview_fixes.md):
bounded the R60 shadow-lift context ratio, removed the unreachable fallback lift and
unused per-hue chroma Kalman, gave each optional color control its own default,
shared one clamped spatial-lane read, and retired the standalone inverse-grade debug
overlay that could not read the combined pipeline's highway.

## 2026-11-06 — Documentation

Shortened root guides, separated rules/priorities/state, moved technical contracts
to [the pipeline reference](docs/pipeline.md), and archived duplicated history.
No production change. November 4–6 shadow experiments remain unadopted.

## 2026-11-03

Adopted [shared-component CC](research/2026-11-03_neutral_component_cc_adoption.md):
retain gray correction while reducing colored-material hue steering.

## 2026-11-02

Adopted [one guarded tonal base](research/2026-11-02_tonal_architecture.md) for
Retinex, zone shaping and lift, retaining corrected-pixel detail and source-range
protection. The [requested review](research/2026-11-02_effect_ratings.md) estimates
chain/grade 78 and joint tonal behavior 80, provisionally.

## 2026-11-01

The user set BLACKS=.0025 in both profiles. The
[Arc trial](research/2026-11-01_arc_black_trial.md) supports its Arc scope;
post-edit actual-config verification completed November 2.

## 2026-10-29–31

- [Weak-material color preservation](research/2026-10-31_weak_material_colors.md):
  protect subtle lower-tone print colors while retaining bright palette behavior.
- [Highlight cooperation](research/2026-10-31_highlight_cooperation.md): relieve
  overlapping FilmCurve/print shoulders while retaining the print toe.
- [Print/inverse color preservation](research/2026-10-31_print_inverse_color_preservation.md):
  preserve print color ratios above deep shadows; bound added inverse chroma
  with per-pixel SDR headroom.
- [Inverse chroma restraint](research/2026-10-31_inverse_chroma.md): preserve
  incoming chroma and abstain above the reconstruction budget.
- [Three-way CC profile tuning](research/2026-10-31_three_way_cc.md): user-authorized
  half-strength shadow correction; later external GZW choices supersede its values.
- [Gentler print shoulder](research/2026-10-30_print_look_preservation.md).
- [Guarded inverse shadow reconstruction](research/2026-10-29_shadow_stage_preservation.md).

## 2026-10-28 — v1.0

Stable combined SDR checkpoint, `1724bb6`. Later changes are listed above.

## 2026-10-24–27 — Technical foundation

- [Retinex material preservation](research/2026-10-27_retinex_material_preservation.md)
  and [source-aware inverse restraint](research/2026-10-27_tonal_selectivity.md).
- [Current-source lift and combined-chain activation](research/2026-10-27_lift_transition_repair.md),
  following [cut-gate recovery](research/2026-10-27_gate_recovery.md).
- [Integer-dimension filter spacing](research/2026-10-27_filter_kernel_resolution.md)
  and [continuous blue-cusp projection](research/2026-10-27_gamut_continuity_repair.md).
- [Original-source Retinex guide](research/2026-10-26_retinex_sky.md),
  [zone scene pivot/black tail](research/2026-10-26_zone_scene_pivot.md), and strict
  [render-phase matching](research/2026-10-26_return_cut_alignment.md).
- [Statistics/gamut contracts](research/2026-10-25_signal_contracts.md),
  [live-history precision](research/2026-10-25_remaining_histories.md),
  [slow-key precision](research/2026-10-25_slow_key_precision.md), metadata,
  percentile initialization and median-chroma corrections.
- Retinex halo, zone precision and shadow-tail repairs. Earlier sRGB, signed
  Oklab, reconstruction, dither and adaptation work is recorded in the
  [implementation report](research/2026-10-23_fidelity_implementation.md).
  Diffusion, temporal grain and golden-image testing were removed.
