# Changelog

Recent implementation changes. Measurements and rejected candidates remain in
versioned research reports; older implementation history is in git.

## 2026-10-25

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
