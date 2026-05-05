# R90 — Adaptive Inverse Tone Mapping (2026-05-04)

## Motivation

R86 (`inverse_grade_aces.fx`) requires ACES-specific math and a confidence gate that fails on
flat midtone scenes. Goal: replace with a game-agnostic inverse that works on any S-curve
tonemapper, using only the p25/p50/p75 data already on the highway.

## Approach

### Log-normal scene model

Natural scene luminance follows a log-normal distribution (established in HDR photography
research; Reinhard 2002, Ward 1994). For outdoor scenes, the p25–p75 IQR in scene-linear space
is typically 2–4 stops. Rather than a fixed guess, the IQR reference is derived from ACES math.

### ACES-derived IQR reference

The ACES Hill 2016 forward transform applied to log-normal scene percentiles (0.18 ± 1.5 stops)
gives the expected display IQR for a naturally-exposed ACES scene:

    ACES(0.18 / exp2(1.5)) ≈ 0.0644   (display p25)
    ACES(0.18 * exp2(1.5)) ≈ 0.6222   (display p75)
    log2(0.6222) - log2(0.0644) = 3.28 stops

This 3.28-stop constant replaces a guess. It is computed from ACES mathematics and anchored
to the well-established 0.18 mid-grey and log-normal ±1.5-stop scene IQR.

From ACES documentation: "log-log slope through 18% mid-grey < 1.55" — consistent with our
formula producing slope ≈ 1.5–1.6 for typical ACES outdoor content.

### Compression slope

Any S-curve tonemapper compresses the log-space IQR. The ratio of the ACES reference to
the observed display IQR gives the expansion factor:

    slope = 3.28 / (log2(p75) - log2(p25))

For pure ACES outdoor scene: slope ≈ 1.0 (already at reference — no correction needed).
For more compressed tonemapper: slope > 1.0 (expands to match ACES reference IQR).
For uncompressed/linear: display IQR > 3.28 → slope < 1.0 → clamped to 1.0 (no-op).
Self-limiting. No gate needed.

### Inversion formula

Log-linear expansion per-channel, pivoted at p50:

    log_anchor = log2(p50) * (1 - slope)
    expanded   = exp2(log2(col.rgb) * slope + log_anchor)

Equivalent to `col^slope * K` where K keeps p50 mapped to p50.
Shadows pulled darker; highlights pushed brighter. Per-channel increases colour
separation — "more colours." Midtone brightness preserved (EXPOSURE handles absolute level).

### Literature alignment

The APSIPA "Fully-automatic inverse tone mapping" (2023) uses median luminance + contrast
statistics as primary parameters — matching our p50-anchor + IQR-slope design. No neural
network or tonemapper knowledge required.

## Parameters

| Parameter | Value | Rationale |
|-----------|-------|-----------|
| `LOG_IQR_ACES` | 3.28 stops | Derived from ACES forward transform on 0.18±1.5-stop scene |
| `slope` clamp | [1.0, 2.5] | 1.0 = no-op; 2.5 = hard cap for flat/uniform scenes |
| `log_disp_IQR` floor | 0.5 stops | Prevents slope explosion on near-uniform histograms |
| Pivot | p50 | Midtone anchor; EXPOSURE knob handles absolute level |

## Risks

- **3-stop assumption wrong for indoor/UI scenes**: slope over-expands. Mitigated by 2.5 cap.
- **Flat histogram (uniform grass)**: slope → 2.5, applies maximum expansion. Downstream
  grade corrects. Acceptable since the expansion is bounded.
- **Per-channel hue shift at extremes**: minor; absorbed by downstream Oklab corrections.
- **Clipped highlights unrecoverable**: values at 1.0 stay at 1.0. Inherent SDR limitation.

## Replaces

`inverse_grade_aces.fx` + `aces_debug.fx` in the chain.
New file: `general/inverse-grade/inverse_grade.fx`
Knob: `INVERSE_STRENGTH` in `creative_values.fx`.
