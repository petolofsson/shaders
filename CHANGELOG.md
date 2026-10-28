# Changelog

Recent implementation changes. Measurements and rejected candidates remain in
versioned research reports; older implementation history is in git.

## 1.0 — 2026-10-28

- Stable checkpoint of the combined SDR pipeline, including the adopted
  inverse-luma restraint, Retinex material preservation and current user-tuned
  Arc Raiders/GZW profiles. Validation scope and accepted costs remain as
  documented in the reports below; this version adds no new effectiveness claim.
- Shadow depth and material separation are the next requested assessment;
  no shadow experiment is included in this release.

## 2026-10-27

- Adopted [Retinex material preservation](research/2026-10-27_retinex_material_preservation.md):
  a gentler native luminance response retains the original guided/native spatial
  gain ratio and ±0.35-stop limits. Selected paint/paving separation improves;
  native boundary protection remains. Seven real cases, two-profile boundaries,
  repeats, independent GPU contracts, same-update cut controls, bypass and actual
  active configs pass. Shadow/cloud/sky and small daylight timing costs remain.
  Profiles/configs, history rates, resources and eight passes are preserved.
  Direct-curve candidates are rejected and this finite decision is closed.
- Adopted [current-source inverse-luma restraint](research/2026-10-27_tonal_selectivity.md)
  as the first bounded tonal-cooperation enhancement. Broad trimmed source spans
  reduce inverse strength to half its manual ceiling; Retinex/lift remain.
  Six held cases/repeats, new p75 GPU probes, two-profile cut controls and actual
  active-config comparisons pass. Interior separation gains are modest; cloud/
  warm-floor costs remain. New p75 uses spare cache B and slot 218, with no added
  history, pass, rate or tuning control. Profiles/configs and headers are preserved.
  Lift taper and joint/history-driven restraint candidates are rejected and closed.
- Closed the [current-source lift repair and combined-chain activation](research/2026-10-27_lift_transition_repair.md).
  Native material checks, six production held identities, source/state GPU probes
  and independent controls pass. Existing statistics and rates remain; grade stays
  eight passes. Both active configs now exactly match their tested combined trials
  after the user's explicit approval, fixing resource sharing. Actual active full/
  repeats are pixel-identical in both games. Profiles remain unchanged. The known
  technical repair pass is closed; broader coverage is confidence work, not a new
  mandatory repair queue. Material/color and dark quantization costs are retained.
- Completed a [current-observation lift-consumer screen](research/2026-10-27_lift_consumer_screen.md):
  four two-profile replays, 192 exact full controls and 960 frozen point images.
  Filtering the complete current-observation lift product reduces night peaks
  ~0.64–0.65→0.12–0.16 ΔE, but changes incoming images ~3.49 ΔE. Return/daylight
  controls remain identical. No lift candidate was adopted at that stage;
  native material, held-scene and noncut checks subsequently closed the decision
  in the lift/activation report above.
- Applied [direct cut-gate recovery](research/2026-10-27_gate_recovery.md) using
  existing adaptive coefficients. Native first-return steps fall ~1.44→0.76 ΔE,
  with larger subsequent recovery. Six motion and six held runs preserve exact
  controls; all three held repeats are identical. Two RGBA32F adaptive records
  retain eight grade passes. Independent packed-state and synthetic cadence/hitch
  probes pass. Raw p25/mode settling still drives early night lift targets;
  producers, profiles, detector, headers and existing rates remain unchanged.
- Screened [complete lift-product and direct cut-gate transitions](research/2026-10-27_transition_screen.md)
  in four private two-profile replays using existing adaptive coefficients.
  Product filtering retains the early night peak and extends later settling;
  it is rejected as a complete repair. Gate recovery reduces the return step
  from about 1.48 to 0.78–0.79 ΔE but spreads change to subsequent updates.
  All 192 full-output controls match exactly; daylight 1428/1432 candidates
  remain identical to full. No production change was adopted at that stage;
  subsequent gate and lift reports above close the follow-up checks.
- Completed [night-settling attribution](research/2026-10-27_night_settling_attribution.md)
  through ten private same-update replays: early lift-strength growth, later
  specular-protection release, smaller zone settling and the ambient cut gate.
  All 320 full-output controls match exactly; 2,560 point images and 3,274
  artifacts verify. Profiles, production shaders, configs and rates remain.
  Diagnostic holds/bypasses were not adopted. The subsequent transition repairs
  above retain steady-state and daylight rejection controls.
- Broadened [consecutive cut coverage](research/2026-10-27_temporal_cut_coverage.md)
  with six two-profile replays and two full-route observation traces. Explicit
  GPU phases cover 372 original-clip frozen images; tail frames and readback-tag
  footprints are excluded. Eight runs have zero dropped/delayed frames; 1,058
  artifacts verify. Return handoff/night settling remain above repeat variation.
  Rejected a raw-median detector shortcut for new noncut triggers. Production
  shaders, profiles, configs and rates remain unchanged in this continuation.
- Fixed [filter-kernel spacing](research/2026-10-27_filter_kernel_resolution.md)
  at truncated dimensions. Two low-frequency downscales and both guided passes
  now derive taps from allocated integer texture sizes. Nine GPU probes across
  four resolutions and fifteen held captures across both profiles verify the
  correction. All five repeats and native controls are identical; odd-resolution
  scenes change 48–144 pixels by one code, without new black/white clipping.
  Three shared-path captures match candidates exactly; 105 artifacts pass audit.
  Profiles, shader headers, filter formulas, pass counts and timing remain.
- Fixed the [disconnected blue-cusp projection](research/2026-10-27_gamut_continuity_repair.md)
  in shared `common.fxh`. A bounded lightness-preserving path permits localized
  hue adjustment for out-of-gamut blue; valid-input identity, existing face
  tolerance and SDR bounds remain. Both inverse and grade consume the helper.
  1,410 GPU records, two-profile ramps, eight held repeats, fourteen measured
  motion phases and four final shared/active controls support the scoped repair.
  The selected GZW blue step falls 3.031499→0.112662 ΔE; finite quantized-gradient
  amplification and extreme-blue hue/separation costs remain.
- Completed [wall/sky attribution](research/2026-10-27_wall_sky_attribution.md):
  eleven captures and two 1,326-record GPU traces isolate inverse-luma/Retinex
  wall normalization and broad shadow-lift sky eligibility. Equations match;
  no global bypass, profile retuning or additional production repair is promoted.
- Completed [material/highlight coverage](research/2026-10-27_material_highlight_coverage.md)
  for the current two-game set. Twenty fresh captures over four new views,
  eight verified prior views and retained two-phase uniform-boundary controls
  document dark structure, colored highlights, daylight restraint and remaining
  normalization/core/hue/blue costs. Twelve held full/repeat pairs are identical;
  all twenty fresh runs report zero dropped/delayed frames. Artifact audit passes.
- Synchronized the root/tool/Babylon docs, evidence index, handoff and sole
  `startup-prompt-latest`. It records the applied spacing change, completed
  temporal/night attribution, rejected detector shortcut, newest local artifacts
  and six-item remaining work order. Conservative lift/control and cut-gate
  transition assessment is next. All 22 diagnostic tooling tests pass. Profiles,
  shader headers and active configs remain. Overall acceptance, additional games
  and active-chain integration remain open; no effectiveness re-score follows.

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
