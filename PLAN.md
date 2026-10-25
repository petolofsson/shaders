# Pipeline Plan

Tracks implementation and validation toward the agreed [visual goal](GOAL.md):
a game-agnostic SDR tool that gives colors fullness and dimension, shadows depth
and nuance, and highlights convincing light while preserving each game's visual
identity. The effect should feel like a considerably better image with an
unobtrusive treatment. Richness is not a saturation or darkness target.

Automatic restraint across games is the product direction; existing profiles
remain unchanged while evidence is gathered. Earlier completion/novelty
percentages were subjective estimates, not measured fidelity scores.

Current [provisional ratings](research/2026-10-25_effect_ratings.md) distinguish
technical working, effectiveness and importance. Combined-chain effectiveness
is estimated at 75/100, with palette/print and temporal coverage gaps; this is
not accepted achievement of the 75+ target or a rating of the active broken
cross-effect chain. Novelty has not been re-scored.

| Stage | Implemented | Remaining validation |
|-------|-------------|----------------------|
| Input / inverse-grade | Local max-channel protection plus global near-clip history; bounded chroma expansion; inverse chroma changed a bright real-game stress input by 0.15 ΔE | GZW-specific vivid objects, reconstruction assumptions, small emitters |
| Corrective / FilmCurve | Explicit linear processing, internal range retention, zero-preserving DIR/tint, corrected shoulder; fixed-endpoint GZW corrective gate 2.38 ΔE, Arc bright-cloud FilmCurve 0.15 ΔE | GZW broad highlights and empirical strength calibration |
| Tonal | Corrected Retinex reconstruction, bounded shadow contrast toe, more precise zone statistics near black, independent gates, spatial confidence, time-based selective adaptation; GZW tonal gate 1.51 ΔE and dark shadow lift 2.35 ΔE | Other moving shadow/illumination edges, dark-surface depth and longer recovery |
| Color | Corrected chroma normalization and two-sided Oklab gamut projection; GZW chroma gate 0.97 ΔE | Color distinctions across brightness levels, hue continuity and gamut transitions |
| Look | Print stock and dye/masking controls; GZW look gate 2.94 ΔE | Palette/neutral preservation, dimensionality and automatic print restraint across games |
| Output | Explicit sRGB encode, endpoint-preserving code-domain dither, marker; runtime endpoints and marker checked | Display quantization and gradients in-game; noise-floor measurement |
| Diagnostics | Continuous lossless RGB playback, private IPC/logs, serial access, equal gates, repeat baseline, source hashes, cut probe | Broader motion coverage and live cross-game visual review; explicit diagnostic readback is available |

## Current Priorities

Work in this order toward [GOAL.md](GOAL.md). Preserve creative values, shader
headers and existing changes. Use the combined trial for GZW assessment;
`gzw.conf` stays unchanged. All runtime testing remains private and headless.

The current assessment pass and its remaining preference/coverage decisions
are summarized in the [review pack](research/2026-10-25_review_pack.md). Shelf,
sunset, overcast and emitter attribution is completed for the retained inputs;
the verified inverse-luma gain-units correction is adopted. Earlier effect-size
numbers predate that correction and are historical, not current acceptance scores.

1. **Establish a visual baseline for richness and depth.** Review matched raw,
   current full and unchanged-repeat captures from existing GZW/Arc references
   and the Babylon course. Include dark, bright, vivid and muted material.
   Identify where colored surfaces lose shade distinctions, shadows flatten or
   crush, and highlights wash out. Separate source limitations from processing
   damage. Select regions from the source and record repeat uncertainty.
   Deliver a short prioritized list of demonstrated gaps with visual crops;
   do not add effects or retune profiles on assumptions.
2. **Deep, nuanced shadows.** Inspect dark-surface color and texture, black
   anchors, and illumination edges in fixed scenes and matched motion. Attribute
   Retinex/zone/lift interactions. Preserve separation while avoiding gray
   pedestals, clipping and halos. Assess slow-key transitions by their visible
   contribution; the measured settling tail alone does not justify faster rates.
3. **Fuller colors across the tonal range.** Assess inverse reconstruction,
   three-way correction, luminance/chroma coupling, compression and gamut
   projection together. Preserve distinctions within colored materials, credible
   neutrals and stable hues in shadows, midtones and highlights. Inspect whether
   saturation or compression flattens those differences; higher chroma or more
   occupied color bins is not the objective. Preserve intentionally muted scenes.
4. **Convincing highlights and light.** Check broad clouds, bright colored
   surfaces and small emitters for retained shape, hue and smooth rolloff.
   Judge their relationship to midtones and shadows within SDR headroom. Do not
   infer recoverable information from already-clipped input or promise HDR output.
5. **Coordinate automatic intervention.** Use matched bypasses to assess tonal,
   color and print interactions against the goal. Check print-induced depth
   against lost color distinctions, neutral shifts or palette homogenization.
   Develop bounded automatic restraint only for demonstrated needs, with stable
   behavior through motion/cuts and smooth fallback when confidence is weak.
   Prioritize existing stages; sharpening, debanding and other new effects stay
   deferred until a relevant gap is demonstrated.
6. **Cross-game acceptance and live review.** Check any candidate across varied
   games/scenes, including already well-balanced and deliberately muted inputs.
   Use the same candidate logic for cross-game checks and disclose profile
   differences; do not optimize each test frame with separate settings. Prepare
   matched before/after/bypass evidence and tradeoffs for user review of the
   overall impression. The long-term target needs no per-game/effect tuning;
   current profiles remain intact during assessment. Switching `gzw.conf` still
   requires the user's explicit request.

Change one demonstrated issue at a time. Shared shader changes need Arc
regressions, fresh processes, unchanged repeats and 20-second settling for small
effects. Do not block on new user recordings. Visual benefit decides direction;
measurements explain it and expose costs.

## Completed Foundations and Evidence

These support the current priorities; they are not pending tooling tasks.

- **Inverse-luma units — corrected and checked on active/combined chains.** A
  GPU function probe confirms the previous Oklab scaling cubed a linear-light
  gain. Applying that gain in RGB restores sunset ground median L 38.82→41.46
  and group separation 27.46→30.70 L with unchanged black coverage in six held
  cases. Twelve fresh candidate/repeats, two matched motion replays, six active
  config captures and four applied-path checks pass scoped validation. Blue-sky
  group separation decreases 9.61→6.94 L; retain that print/tonal tradeoff for
  visual review. Profiles and configs remain intact; twenty diagnostics pass.
  [Evidence](research/2026-10-25_inverse_luma_units.md).
- **Shadow/color/print/highlight attribution — initial pass complete.** Eighteen
  fresh captures attribute shelf warmth loss chiefly to the current cool CC,
  sunset density to inverse luma/print, and added colorfulness chiefly to chroma.
  Overcast and compact real lamps broaden coverage. Keep tuning intact pending
  palette/print review; no new effect is justified by these inputs.
  [Review](research/2026-10-25_stage_review.md), [pack](research/2026-10-25_review_pack.md).
- **Zone confidence rims — corrected conservatively.** Independent confidence
  and fixed-field interventions isolate the rim to coarse-edge strength fading.
  Uniform use of the existing 0.65 lower confidence budget reduces held purple
  spread 1.07→0.34 L and edge gap 0.73→0.00 L. Ten fresh candidate/repeats and
  five motion processes pass scoped checks; fifteen exact assessment matches
  cover foliage/clearing/corridor. The stronger candidate was rejected for its
  shadow cost. Remaining work is shelf color, sunset/stage interactions, muted
  inputs and small emitters; coarse-zone interior gradients remain.
  [Evidence](research/2026-10-25_zone_confidence.md).
- **Flat-face Retinex shading — attributed and corrected.** Native-resolution
  guide reconstruction reduces held orange's edge gap +2.63→−0.30 L and
  magenta interior spread 1.71→0.73 L. Twelve GZW/Arc held captures and two
  candidate motion replays pass scoped checks with repeats; ten exact motion
  matches cover foliage, clearing and corridor. Purple zone shading remains,
  with a modest boundary regression on two poses; attribute that next, then
  shelf shadow color and sunset interactions. Profiles/configs stay intact.
  [Evidence and limits](research/2026-10-25_flat_face_attribution.md).
- **First color/shadow baseline — reviewed from retained captures.** Four held
  GZW/Arc cases and three exact Babylon poses identify residual flat-face shading,
  reduced shelf shadow color, and strong sunset/sky redistribution. On a uniform
  magenta face, L95−L5 is 0.187 in the matched shader-disabled replay and 1.763
  in both full/repeat. Attribute that spatial shading first, then shelf and
  sunset interactions; retain useful cloud separation. Profiles remain intact.
  This is initial coverage, not cross-game acceptance or a 75+ rating.
  [Evidence and crops](research/2026-10-25_visual_baseline.md).
- **Background matched motion — validated, with sparse coverage limits.** Private
   Babylon source export and lossless replay now produce exact identity matches
   in foliage, clearing, corridor and both sides of both cuts. Two fresh passes
   yielded 17 shared identities, zero mpv dropped/delayed frames, and 0.010 ΔE
   mean trial/repeat variation (foliage maximum 0.085). Keep repeat uncertainty
   explicit; 15 source poses/sec duplicated at 30 fps is not native 60 fps.
   [Evidence](research/2026-10-24_background_motion_resume.md).
- **Shadow settling — residual isolated on the fixed dark/sunset pair.**
   Explicit GPU readback shows local zone histories have settled by return
   +0.5 seconds; slow key carries the long tail. Holding only its grade consumer
   at the initial dark value reduces +6.5-second residual from 0.341 ΔE to
   0.000024. Do not blindly change the intentional slow adaptation rate.
   Check motion and other cuts before changing behavior.
   [Evidence](research/2026-10-24_shadow_history_readback.md).
- **Moving shadow detail and halos — Retinex outline fixed.** A coarse-edge
   strength fade painted borders into uniform sky. Removing that fade from
   Retinex (retaining bounded gain and global confidence) reduced four matched
   moving-pose gaps from 3.50–3.61 to 0.37–0.88 L. GZW dark/sunset/vivid and Arc
   combined/active regressions passed with repeats and unchanged tuning.
   Continue other shadow/illumination edges and zone/lift interactions.
   [Evidence](research/2026-10-24_retinex_edge_halo.md).

GPU cost remains deprioritized. Use `tools/noise_floor.py` when a dither or
quantization change warrants it. No golden-image suite is to be restored.
Latest workflow evidence: [background capture](research/2026-10-24_background_capture.md).
Latest shader evidence: [inverse-luma units correction](research/2026-10-25_inverse_luma_units.md),
[zone confidence correction](research/2026-10-25_zone_confidence.md),
[Retinex flat-face correction](research/2026-10-25_flat_face_attribution.md),
[earlier halo correction](research/2026-10-24_retinex_edge_halo.md);
[shadow zone precision](research/2026-10-24_shadow_zone_precision.md) remains preserved.

## Scoring Discipline

- Target **75+ effectiveness** for the complete chain and each retained effect
  in its intended role, using the [acceptance definition](GOAL.md#effectiveness-target-75).
  Require evidence and visual review; current scores remain provisional. Novelty
  and improvement potential have no minimum. Effects may be simplified, merged
  or removed, and should back off automatically when unnecessary.
- Success means fuller color relationships, nuanced shadow depth, convincing
  light and unobtrusive processing across games, as defined in [GOAL.md](GOAL.md).
- Saturation, darkness, delta-E, entropy and occupied color bins are diagnostic
  quantities, not objectives to maximize. Preserve the game's visual identity.
- Directional constants should be literature-backed where possible.
- Amplitudes and blend endpoints are allowed to be empirical, but must be tested.
- Do not inflate novelty for standard concepts such as exposure, saturation,
  bloom, LUT-like color shifts, or removed optical finishing effects.
- Prefer effect-attribution data over theoretical confidence when stages interact.
