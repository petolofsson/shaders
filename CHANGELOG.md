# Changelog

Chronological record of recent code changes. Older detail lives in git history and
research notes.

## 2026-10-24

- Documented the agreed game-agnostic visual goal: fuller SDR color relationships,
  deep nuanced shadows and convincing light with unobtrusive automatic restraint.
  Reordered assessment around that goal; new effects remain deferred until a
  relevant gap is demonstrated. Existing tuning and active configs stay intact.
- Consolidated startup instructions into `startup-prompt-latest`, removed obsolete
  prompts, and synchronized agent, handoff and tool documentation with current
  headless validation, completed evidence and remaining limits.

- Fixed demonstrated Retinex halos from fading normalization strength at coarse
  edges. Keep bounded illuminant gain and global confidence; zone confidence
  stays local. Four matched moving clearing poses reduced sky border gaps from
  3.50–3.61 to 0.37–0.88 Oklab-L. GZW/Arc regression captures and repeats passed;
  profiles and active configs remain unchanged. [Evidence](research/2026-10-24_retinex_edge_halo.md).
- Isolated the long dark-return residual with explicit packed GPU readback and
  a temporary slow-key consumer intervention. Local zones are settled by the
  +0.5-second sample; slow key accounts for the material tail. Its deliberate
  adaptation rate remains unchanged. [Evidence](research/2026-10-24_shadow_history_readback.md).

- Completed private Babylon source export and matched lossless motion replay.
  Validate complementary identity/checksum labels, scene/clip hashes and cached
  protocol; reject missing cut coverage, retry with fresh processes, and retain
  per-attempt playback evidence. Fixed sampling stuck at held EOF. Full course
  yielded 17 three-way identities across all seven windows with zero mpv
  dropped/delayed frames. [Evidence](research/2026-10-24_background_motion_resume.md).

- Made `compare_frame` captures use a private headless Gamescope GPU display by
  default. Capture post-vkBasalt frames without taking desktop focus, retain
  temporal settling and repeats, and fail instead of falling back to the desktop.
  Added a shader-disabled transfer check and private-display cleanup/routing tests.
- Increased local zone-histogram precision near black using 64 bins with squared
  edges and linear-light percentile/moment decoding. GPU median estimates for
  uniform dark patches now differ by at most 2 equivalent 8-bit codes, versus
  a maximum error of 33 previously; creative values remain unchanged. See
  [validation](research/2026-10-24_shadow_zone_precision.md).
- Bound the negative local-contrast arm relative to available luminance so
  positive shadows approach black smoothly instead of collapsing against a
  subtractive clamp. In the matched GZW sunset, source-selected shadows becoming
  exact black fell from 4.31% to 0.11%; the hardest contextual ramp retained
  46 output levels instead of 20. User tuning remains unchanged. See
  [validation](research/2026-10-24_contrast_shadow_toe.md).

## 2026-10-23

- Neutralized GZW MID_TEMP after isolated attribution showed a +4.2° orange-to-yellow
  shift; source-matched high-chroma orange hue drift fell from +3.52° to -0.76°.
  Broader scene validation remains pending.
- Prevented hue-ceiling rolloff and the gamut pre-knee from reducing input chroma
  after luminance/saturation adjustments; final SDR projection still bounds output.
  The current GZW capture compiled; this frame's orange was already in gamut.
- Completed internal range handling through corrective and tonal stages; fixed
  Retinex and saturation-by-luma reconstruction denominators.
- Made SDR sRGB decode/encode explicit on UNORM views, including 10-bit playback.
- Replaced max-only gamut projection with a fixed-iteration Oklab chroma search
  against both RGB bounds; inverse-grade also protects small single-channel emitters.
- Corrected FilmCurve's asymptote; preserved zero in DIR, shadow tint and print toe;
  moved output dither to the sRGB code domain with symmetric endpoint attenuation.
- Made selective hysteresis and zone/slow-key smoothing time-based, removed
  cut-triggered maximum film/print targets, and clamped spatial highway filter taps.
- Repaired capture logs, IPC errors, profile-edit locking, optional-knob handling,
  effect gate consistency, fresh per-image histories, and activity-marker masking.
- Disabled obsolete screenshot telemetry decoding; added diagnostic unit tests.
- At time of the prior capture, GZW was set to `BLACKS=0.05` and `EXPOSURE=0.2`;
  the user later corrected BLACKS to 0.005 and exposure to 0.15.

- Added high-range internal Oklab processing, corrected post-knee gamut probing,
  removed misleading FilmCurve channel-knee controls, and neutralized printer-light defaults.
- Added smoothed near-clip analysis for inverse-grade highlight protection and selective
  rise/fall hysteresis for scene-adaptive controls.
- Added a confidence-weighted local/global blend that reduces Retinex and zone contrast
  near multi-scale illumination edges and during unstable scene transitions.
- Fixed the masking coupler adding colored energy to true black and set GZW's explicit
  black floor to zero.
- Removed the obsolete golden-image regression system and synthetic golden fixtures.

## 2026-10-22

- **Scene automation**: added bounded automation for print-stock strength, soft gamut
  compression, chroma protection, and scene-cut transition damping. Film-curve strength and
  shadow lift also use highlight and shadow-floor statistics; manual creative values remain
  ceilings or bypasses.
- **Diffusion removal**: removed the diffusion downsample, Gaussian blur, bloom pass, and
  profile controls from both game configurations. The 2x2 activity marker remains active.

## 2026-09-03

- **New stable baseline**: synchronized Arc Raiders and GZW profiles with the accepted shared
  values: inverse `0.70`, FilmCurve `0.15`, Contrast/Shadows `1.00`, PrintStock `0.35`,
  Diffusion `0.5`, and Grain `0.60`. Creative hue-band controls remain disabled.
- **Documentation**: marked the simplified shader chain and shared profiles as the current
  stable checkpoint; further changes should be treated as experiments.

## 2026-09-02

- **FilmCurve rebuild**: removed inverse-grade FilmCurve compensation and rebuilt the forward
  transform as a monotonic luminance shoulder applied after spatial tonal processing. Channel
  ratios are preserved and overrange values remain bounded for SDR output.
- **Highlight protection**: Retinex and signed zone contrast now attenuate smoothly in bright
  regions to reduce cloud blooming and preserve highlight texture.
- **Retinex stabilization**: replaced the raw low-frequency/global-key ratio with a bounded
  log-domain gain and multi-scale edge attenuation to reduce halos across broad gradients.
- **Diffusion rewrite**: replaced full-frame blur subtraction and radial eye masking with a
  soft-thresholded bright pass, sharp base preservation, and restrained additive bloom.
- **Adaptive contrast**: changed the zone adjustment from a one-sided upper lift to a signed
  local-median contrast adjustment with a 75% shadow arm.
- **Stage separation**: added independent Retinex, zone-contrast, and shadow-lift gates;
  corrective chroma history now measures original-scene highway samples to avoid feedback.

- **Stable minimal checkpoint**: Arc Raiders now exposes only the core tonal controls;
  removed game-specific hue, saturation, shadow-cast, and perceptual color design knobs.
  The reduced chain passed a one-frame vkBasalt compile/render check.
- **FilmCurve highlight fix**: removed the WHITES taper that bypassed shoulder compression
  for overrange highlights and caused final SDR clipping to white.
- **Inverse/forward coupling fix**: FilmCurve inverse compensation now follows `FILM_CURVE`
  instead of being enabled at full strength by any positive `INVERSE_STRENGTH`.
- **Inverse highlight safety**: protected the FilmCurve inverse asymptote at exact white and
  capped reconstructed values to prevent extreme overrange highlights.
- **Root docs renamed/trimmed**: `CLAUDE.md` renamed to `AGENTS.md`; root docs
  compressed to operational state, current risks, and validation commands.
- **Pipeline correctness**: fixed diffusion zero bypass, exact-white histogram
  binning, and exposure order. The 2x2 red activity marker is intentionally restored.
- **Quality pass**: scene cuts now use p50 plus raw histogram entropy delta;
  guided-filter epsilon is local-variance adaptive.
- **Pipeline reduction**: removed halation, clarity, negative matrix, chromatic
  induction, Bezold-Bruecke, Abney, H-K, HELMLAB, gamut-density darkening, and
  bleach bypass. Rebuilt game profiles around the remaining controls.
- **Testing tools**: `compare_frame --all-effects` no longer references removed
  DIR/toe knobs and fails on missing knobs; added `tools/noise_floor.py`.
- **Validation**: one-frame runtime `compare_frame --all-effects --only FILM_CURVE`
  passed with FilmCurve contribution `DeltaE 32.94`; the legacy image baseline check
  failed against the old `dcc712f` reference set, pending visual review.

## 2026-05-20

- **R205 FilmCurve**: removed display-referred rational toe, reparameterized body
  lift to track `fc_knee`, removed redundant `fc_w`, added WHITES taper, and removed
  `CURVE_R/B_TOE` knobs.
- **BLACKS/WHITES**: replaced separate clips with one linear remap at the top of
  `ColorTransformPS`.
- **Print stock fixes**: gated masking coupler and dye matrix by `PRINT_STOCK`;
  fixed `ApplyPrintStock` midtone desaturation from shadow-only to bell-shaped.

## 2026-05-18

- **3-way CC**: rewritten in Oklab a/b axes; temp and tint are orthogonal and need
  recalibration per profile.
- **Bleach bypass**: moved before print stock and converted to linear-luma
  retained-silver modeling.
- **Temporal dither**: switched from broken `framecount` to `FRAME_TIMER`.
- **Cleanup**: removed unused HSV helper and stale analysis scope/low-frequency docs.

## 2026-05-17

- **INVERSE_LUMA**: replaced flat ACES luma inverse with Mertens bell weighting.
- **Halation**: changed to luma-neutral orange tint with sky suppression.
- **CLARITY**: implemented documented upper highlight rolloff.
- **DIR_COUPLER**: removed user knob; shader uses hardcoded designed strength.
