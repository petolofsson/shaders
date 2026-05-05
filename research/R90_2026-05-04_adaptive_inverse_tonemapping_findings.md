# R90 Findings — Adaptive Inverse Tone Mapping (2026-05-04)

## Status: Implemented

## What was built

`general/inverse-grade/inverse_grade.fx` — replaces `inverse_grade_aces.fx`.
`general/inverse-grade/inverse_grade_debug.fx` — slope debug overlay.

## Final formula

    slope = clamp(3.28 / log_iqr_obs, 1.0, 2.5)   — computed in analysis_frame from float16 PercTex
    luma_out = exp2(log2(luma_in) * slope + log2(p50) * (1 - slope))
    col.rgb  = col.rgb * (luma_out / luma_in)       — uniform channel scale, hue preserved

## Key decisions and why

**Luma-driven, not per-channel**: per-channel expansion caused blue clipping (blue channel
typically lower than luma p50 in outdoor scenes → pushed harder → blows out). Luma-driven
uniform scale preserves hue exactly.

**Slope encoded at highway x=197 from analysis_frame**: computing slope as a ratio of two
8-bit highway values caused flicker (ratio amplifies quantization noise). Computing from
float16 PercTex inside analysis_frame, then encoding as a single normalized float, gives
Kalman-smooth slope with no frame-to-frame jitter.

**3.28-stop reference**: derived from ACES forward transform on log-normal scene percentiles
(0.18 ± 1.5 stops). Replaces the arbitrary 3.0 assumption in the original R90 proposal.

**No confidence gate**: slope naturally approaches 1.0 for uncompressed content (no-op).
Gate was needed for R86 (ACES-specific detector); not needed here.

## Tuned values

- `INVERSE_STRENGTH = 0.10` (Arc Raiders) — conservative; visible color improvement without
  overblow. Higher values overblown.
- `slope` cap 2.5 — not hitting in normal outdoor scenes (blue/green box on debug overlay).

## Chain

    analysis_frame : inverse_grade : inverse_grade_debug : analysis_scope_pre : corrective : grade : pro_mist : analysis_scope

## Discarded approaches

- **R86 ACES-specific inverse**: required confidence gate with three zone discriminants
  (shadow/midtone/highs) that kept failing on flat-histogram scenes.
- **Per-channel log expansion**: blue channel blows out due to luma p50 anchor mismatch.
- **Slope computed from 8-bit highway values**: ratio of two noisy values flickers.
