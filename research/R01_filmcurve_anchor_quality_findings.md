# Findings 01 — FilmCurve anchor quality

## Summary
**Found:** FilmCurve anchors collapse on dark scenes and get hijacked by specular spikes.
**Implemented:** Trimmed percentiles (0.275/0.500/0.725) + intra-bin CDF interpolation
in `analysis_frame.fx` `CDFWalkPS`. Effective anchor resolution raised from 1/64 to ~1/512.

---

## Mechanism (precise)

**Histogram** — `analysis_frame.fx`:
- 32×18 downsample = 576 samples total for the whole frame
- 64 luminance bins, linear light
- Temporal smoothing on the histogram: LERP_SPEED 4.3, frametime-weighted ≈ 7% blend per frame at 60fps → ~160ms decay

**CDF walk** — extracts p25/p50/p75 from histogram:
- Bin-center-only snapping: resolution is 1/64 ≈ 0.016 luma steps
- No interpolation between bins
- No secondary smoothing on the percentiles themselves — PercTex updates raw every frame

**FilmCurve** — `grade.fx`:
- Uses p25 → shadow toe anchor, p50 → midtone reference, p75 → highlight knee
- Squared rolloff on both toe and shoulder (smooth, no hard clip)

---

## Failure modes

### 1. Flat dark scene — p25 ≈ p50 ≈ p75 collapse (HIGH severity)
When most pixels cluster in a narrow dark band, all three percentiles snap to the same
or adjacent bins. Shadow lift denominator (`knee_toe²`) shrinks, causing the lift
amplitude to inflate. Blacks are lifted excessively and asymmetrically. Tonal
separation collapses. Common trigger: dark interiors, night sequences, cinematic shadows.

### 2. Specular-heavy scene — p75 saturates toward 1.0 (HIGH severity)
A small number of specular pixels (window glints, water, metal) push p75 to bin 63
even though 99% of content is mid-range. Highlight knee drops to 0.80, compression
factor inflates to ~1.25×. Result: values in the 0.75–0.95 range are compressed more
aggressively than pure blacks — **tonal order is violated**. Darker input → lighter
output in that range. Common trigger: any outdoor scene, wet surfaces, metallic objects.

### 3. Temporal jitter (MEDIUM severity)
Histogram has 160ms smoothing but percentiles don't. Brief specular spikes or flicker
can shift percentiles by 1–2 bins (0.016–0.032 luma) for a single frame — causing
a visible one-frame tone curve pop.

### 4. Scene cut lag (MEDIUM severity)
160ms histogram decay creates a noticeable lag on hard cuts between interior and
exterior. Percentile jump is not instant — tone curve takes ~10 frames to settle.

---

## Verdict

**Not robust under real game content.** Works well for mid-contrast, well-distributed
scenes. Degrades severely under flat dark scenes and specular-heavy frames — both of
which are common in games. The 64-bin CDF walk with no intra-bin interpolation gives
insufficient anchor precision, and the absence of per-percentile smoothing allows
single-frame spikes to corrupt the curve.

---

## Fix proposal

Two independent improvements:

1. **Intra-bin linear interpolation during CDF walk** — when cumulative mass crosses
   0.25/0.50/0.75, blend between the current and previous bin center proportionally to
   the overshoot. Raises effective resolution from 0.016 to ~0.002 luma. Eliminates
   bin-snap artifacts and the curve inversion at specular extremes.

2. **Secondary exponential smoothing on PercTex values** — apply a separate lerp
   (300ms decay) directly on the p25/p50/p75 output, independent of the histogram
   smoothing. Decouples histogram response time (fast, good for game content) from
   anchor stability (slow, prevents jitter). 300ms lag is imperceptible but absorbs
   single-frame specular spikes entirely.

These two changes together address all four failure modes without altering the
adaptive intent of the system.
