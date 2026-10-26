# Changelog

Recent implementation changes. Measurements and rejected candidates remain in
versioned research reports; older implementation history is in git.

## 2026-10-26

- Fixed [Retinex sky compression](research/2026-10-26_retinex_sky.md): evaluate the
  guide in original-source log-luma, condition its residual and normalize bounded
  gain by key plus illuminant. A native R32F observation precedes inverse work;
  profiles, strengths, histories/rates and grade's eight passes remain.
  Sky separation recovers 7.376501→9.646211 against source 9.708699, without
  restored measured held rims, selected lighting-gap loss or added clipping.
  Six held repeats, two GPU probes, 14 measured-phase motion samples and five
  final shared/active checks pass. Zero-strength bypass is pixel-identical;
  all 22 diagnostic tests pass. Broader motion/visual acceptance remains open.
- Resolved the [return-cut repeat uncertainty](research/2026-10-26_return_cut_alignment.md):
  retained captures mixed the first/second GPU updates of a duplicated source pose.
  Native frozen output/state readback reproduces their 1.588 ΔE separation;
  aligned phases repeat within 0.000426. Retinex-only bypass attributes the main
  deterministic handoff. Production shaders, profiles and rates stay unchanged.
- Added strict measured render-phase matching and explicit source-only report
  labels to the motion tooling. Two regression tests reject mixed phases and
  host-time-only records; all 22 diagnostic tests pass.
- [Attributed spatial/color behavior](research/2026-10-26_spatial_color_attribution.md):
  coarse median interpolation shades uniform materials, Retinex compresses broad
  sky separation, and the overcast green shift chiefly follows existing three-way CC.
- Applied [bounded scene-adaptive zone contrast](research/2026-10-26_zone_scene_pivot.md):
  a live scene pivot/span removes interpolated zone gradients, and pivot-relative
  shadow debt retains a linear black tail. Rejected two simpler candidates for
  shadow costs. Profiles, shader headers, histories/rates and active configs remain.
- Verified GPU curves, six held scenes, 25 exact motion matches across seven
  windows and five final shared/active-path captures. Held cases and matched
  motion add no clipping; final captures match their references pixel-for-pixel.
  Twenty diagnostic tests passed for that repair. Local separation/halo costs
  remain explicit; its apparent return-cut outlier is resolved above. Dense cut
  acceptance stays open.
- Active-chain data sharing remains unresolved; active configurations are preserved.

## 2026-10-25

- Completed the [history-consumer audit](research/2026-10-25_history_consumers.md):
  six per-hue records have no ordinary image consumer and remain untouched.
- Fixed [scene-chroma feedback precision](research/2026-10-25_scene_chroma_precision.md)
  and [eight remaining live accumulators](research/2026-10-25_remaining_histories.md)
  with independently GPU-verified 32-bit histories. Existing formulas, rates,
  initialization and half-float publications remain; one-frame cut storage stays
  half-float after a separate bounded-error check.
- Fixed [statistical and gamut contracts](research/2026-10-25_signal_contracts.md):
  recover exact counts from raw global/zone histogram fractions, compute stable
  weighted zone variance, and prevent matrix roundoff from contracting valid SDR
  boundary colors. Smoothed histograms remain continuous and output stays bounded.
- Verified signed/color/film/dither helpers, two-profile 768-patch neutral bypass,
  held-scene repeats and matched motion using private headless GPU runs. Twenty
  diagnostic tooling tests pass. Reports retain small one-code shadow costs and
  convergence/coverage limits; these are not effectiveness-score increases.
- Closed PLAN priorities 1 and 2 for this audit; spatial/color attribution is next.
  Profiles, active configs and shader headers remain unchanged. Active separate
  effects still lack shared analysis resources; combined trials remain the valid
  assessment path.
- Fixed [slow-key feedback precision](research/2026-10-25_slow_key_precision.md):
  RGBA32F authoritative history and direct feedback retain the intended response
  at simulated 30/60/144 updates/sec. Publications and 20-second/67-ms half-lives
  remain unchanged; real-chain readback verifies retained precision.
- Fixed [metadata coordinates](research/2026-10-25_highway_resolution.md): integer
  allocated texture width prevents cross-field blending at non-divisible widths.
  Five-resolution GPU probes recover all 40 metadata slots.
- Fixed [percentile initialization](research/2026-10-25_percentile_initialization.md):
  valid covariance no longer causes six-update cold-start cycles. Controlled
  cuts retain innovation response and scene detection.
- Fixed [scene median chroma](research/2026-10-25_chroma_median_contract.md): all
  576 samples count; neutral scenes no longer return C=0.10. Colored hue-centroid
  filtering and achromatic fraction remain separate and unchanged.
- Earlier same-day fixes: [inverse-luma gain units](research/2026-10-25_inverse_luma_units.md),
  [zone confidence](research/2026-10-25_zone_confidence.md) and
  [Retinex guide reconstruction](research/2026-10-25_flat_face_attribution.md).
- Made technical correctness and robust intended behavior the current priority.
  Preserved profiles/configs and shader headers; personal taste is not a blocker.
- Reconciled root documentation, removed obsolete task/profile narratives and
  recreated one fresh `startup-prompt-latest`. Historical reports remain evidence.

## 2026-10-24

- Established [the SDR visual goal](GOAL.md) and cross-game restraint direction.
- Made runtime capture private/headless, with fresh processes, continuous
  playback, exact source identities and unchanged repeats.
  [Workflow](research/2026-10-24_background_motion_resume.md).
- Fixed [Retinex halos](research/2026-10-24_retinex_edge_halo.md),
  [zone precision](research/2026-10-24_shadow_zone_precision.md) and
  [shadow contrast](research/2026-10-24_contrast_shadow_toe.md).
- Attributed the fixed dark-return tail to slow key rather than zone lag.
  [Historical readback](research/2026-10-24_shadow_history_readback.md).

## Earlier foundations

Explicit sRGB boundaries, signed high-range internal Oklab, two-sided SDR gamut
projection, reconstruction fixes, endpoint-safe dither, selective time-based
adaptation and the combined pipeline are documented in
[the implementation record](research/2026-10-23_fidelity_implementation.md).
Diffusion, temporal grain and the golden-image system were removed. Superseded
profile values and retired-effect tuning are not repeated here; use current
profiles and git history when investigating older behavior.
