# Research 03 Findings — Zone S-curve shape

## Summary
**Found:** Zone S-curve is `PivotedSCurve` written inline — identical to the chroma
formulation in the same pass. Maximum gain at the pivot, rolling off to linear at the
luma extremes. Off-centre asymmetry is real but already mitigated by R02's IQR scaling.
**Implemented:** Nothing — current shape is fit for purpose and consistent.

---

## 1. Transfer function — median = 0.5, ZONE_STRENGTH = 30

The curve (`grade.fx:403–405`) is:
```
bent = dt + s * dt * (1 - sat(|dt|)),  s = 0.30,  dt = luma - 0.5
new_luma = sat(0.5 + bent)
```

**Gain** (slope, d(new_luma)/d(luma)) = `1 + s*(1 - 2|dt|)`:
- At pivot (dt=0):       gain = 1.30 — maximum contrast boost
- At |dt| = 0.5 (extremes): gain = 1.00 — back to linear
- At |dt| > 0.5:         gain < 1.0 — sub-linear (compression)

For median=0.5, |dt| is bounded by 0.5 in SDR [0,1], so gain never drops below 1.0.
The curve is a soft contrast expander, maximum slope at the pivot, rolling off to linear
at the clipping boundary. Peak correction magnitude: `s/4 = 0.075` at luma = 0.0 and 1.0.

This is NOT a classic S-curve with toe and shoulder tapers. It is maximum-gain-at-pivot
with continuous rolloff — closer to a soft linear contrast boost than a sigmoidal shape.

**Identity with PivotedSCurve**: the formula is exactly `PivotedSCurve(luma, zone_median,
ZONE_STRENGTH/100)` written inline (`grade.fx:349–354`). Same function used for chroma
pivoting in the same pass. The inline version is a copy, not a different design.

## 2. Off-centre pivots

**Low pivot (median = 0.15, dark zone):**
- dt ranges from −0.15 to +0.85.
- At luma = 1.0 (dt = 0.85): gain = 1 + s*(1−1.7) = 0.79 — sub-linear but still positive.
  Correction = 0.3 × 0.85 × 0.15 = +0.038 (highlights pushed up, as expected).
- Peak correction (+0.075) occurs at dt = 0.5 → luma = 0.65. Correct behaviour.

**High pivot (median = 0.80, bright zone):**
- dt ranges from −0.80 to +0.20.
- At luma = 0.0 (dt = −0.80): gain = 1 + s*(1−1.6) = 0.82. Sub-linear.
  Correction = 0.3 × (−0.80) × 0.20 = −0.048 (shadows pushed darker, as expected).
- Peak correction (−0.075) occurs at dt = −0.5 → luma = 0.30 — well inside SDR range.
  Shadows down to luma = 0.30 get the full bend; below that the correction decreases.

**Asymmetry:** for off-centre pivots the peak correction lands inside SDR on one side and
outside on the other. High pivot → shadows get the full parabolic bend; highlights don't
reach the peak. Low pivot → vice versa. Corrections always have the correct sign (darks
pushed darker, lights pushed lighter), but strength is unbalanced across the pivot.

**Mitigation from R02:** off-centre zones (bright sky, dark floor) tend to be low-IQR.
IQR scaling already reduces effective strength for those zones, which attenuates the
asymmetry in practice. Not eliminated, but sub-perceptual at ZONE_STRENGTH 30.

## 3. Interaction with clarity and shadow lift

**Clarity** operates on `detail = luma - low_luma` (high-frequency residual) with a
midtone mask. Orthogonal to zone S-curve: zone works on the per-zone global luma level,
clarity on local fine structure. No conflict.

**Shadow lift** adds `(SHADOW_LIFT/100 * 0.15) * lift_w` after the zone S-curve, where
`lift_w = smoothstep(0.4, 0.0, new_luma)`. For a dark zone (low median), both zone
S-curve and shadow lift push shadows up — they're additive. At SHADOW_LIFT 12 and
ZONE_STRENGTH 30 the combined shadow push is modest (~0.018 + 0.075), but it's worth
knowing they don't cancel in any tonal region.

## 4. ZONE_STRENGTH linearity

Peak correction = `ZONE_STRENGTH / 400`. Linear in strength, approximately linear in
perceived effect (linear light space). At 30: peak = 0.075. At 60: peak = 0.15. The
knob becomes aggressive above ~50 — noticeable tonal shift rather than a gentle local
contrast boost. Current value of 30 is in the well-behaved region.

## 5. Comparison with alternatives

**smoothstep S-curve**: proper toe and shoulder taper by construction. Requires explicit
range parameters (toe, shoulder), which would need to come from p25/p75. More classical
"S" shape. More complex to parameterize adaptively. No clear perceptual advantage over
the current form at moderate strength.

**Normalized current formula**: divide dt by available headroom before the bell
correction — `(1 - median)` above pivot, `median` below — then scale back. Makes peak
correction symmetric regardless of pivot position. Eliminates the off-centre asymmetry
identified above. Adds two divisions per pixel. Low priority given IQR mitigation.

**Cubic Hermite with IQR-derived range**: use p25/p75 as toe/shoulder for a smoothstep
that is calibrated to the actual scene distribution. Would be the most "correct" form
but requires reading p25/p75 from ZoneHistoryTex and running a smoothstep instead of
the current bell — more computation, harder to reason about.

## Verdict

The current shape is adequate and internally consistent. No change recommended.

The formula is identical to `PivotedSCurve` — used in both the zone and chroma sections.
The maximum gain at the pivot (not the extremes) is the right behaviour for scene-adaptive
contrast: the S-curve boosts contrast most where the zone's tonal mass is concentrated,
and rolls off approaching the clipping boundaries.

The off-centre asymmetry is real but already partially addressed by IQR scaling (R02).
At ZONE_STRENGTH 30 and typical IQR-modulated effective strengths, the asymmetric peak
is sub-perceptual.

One low-priority option if asymmetry ever becomes visible: normalize dt by available
headroom before the bell correction. Two divisions per pixel, no other changes.
