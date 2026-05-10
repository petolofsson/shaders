# R116 Findings — Color Pipeline Audit — Better Solutions — 2026-05-06

## Status: Research only. No code changes made. Discuss before implementing.

---

## Finding 1 — Replace arithmetic mean chroma with median (Issue 1)

**Current:** Arithmetic mean of Oklab C across C>0.05 pixels — biased by outliers.

**Better solution:** CDF-walk the chroma distribution to find p50 (median).
The pipeline already has a CDF-walk implementation (CDFWalkPS in analysis_frame.fx).
The same approach applied to a histogram of Oklab C values would give a robust median.

**Implementation sketch:**
```hlsl
// In a new pass or piggybacking on existing downsampled frame:
// Build a 32-bin histogram of C values (0–0.30 range, bin width ~0.009)
// Walk CDF to find p50
// Replace mean_C with median_C in MeanChromaPS output
```

**Alternative (simpler, no histogram):** Weighted trimmed mean — exclude pixels with
C > p90 from the mean computation. p90 of chroma can be tracked alongside p90 of luma
(already done). This removes the top 10% of saturated outliers while preserving the
mean character in typical scenes.

**GPU cost:** Negligible if piggybacked on existing downsampling pass. A separate
histogram pass costs one extra render target.

**Risk:** R90 inverse grade was calibrated against the current arithmetic mean. After
changing to median, INVERSE_STRENGTH will likely need reduction — median chroma is
lower than mean in typical game scenes.

---

## Finding 2 — Zone log key: consider arithmetic mean in log space (Issue 2)

**Current:** `exp2(sum(log2(zone_medians)) / 16)` — geometric mean of zone medians.

**What geometric mean gives:** The tone level that best represents multiplicative
relationships — the "exposure center" if all zones were equal-weight exposures.
Physically defensible for exposure-like quantities; deliberately dark-biased.

**What arithmetic mean in log space gives:** `exp2(sum(log2(zone_medians)) / 16)` IS
the geometric mean — these are the same thing. The alternative is a linear mean:
`sum(zone_medians) / 16`.

**Better solution A (linear mean):**
```hlsl
float zone_log_key = m * 0.0625;   // linear mean of zone medians, already computed
```
This gives equal weight to all zones. A split interior/window scene would read the
true average luma rather than the dark-biased geometric mean.

**Better solution B (median-of-medians, no extra cost):**
Sort the 16 zone medians (or approximate: use p50 of the zone histogram). The median
is robust to the single bright-window outlier without over-weighting it.

**Tradeoff:** The current geometric mean behavior has been calibrated across many
scenes. Switching to linear mean raises zone_log_key in high-contrast scenes → zone
contrast fires less aggressively → visible softening of contrast. This is probably
correct but will feel different. Recommend: implement linear mean, zero-everything
diagnostic before enabling.

**GPU cost:** Zero — `m * 0.0625` (linear mean) is already computed on line 325.

---

## Finding 3 — zone_std: per-pixel variance within zones (Issue 3)

**Current:** Standard deviation of the 16 zone medians — measures inter-zone tonal
spread, not intra-zone contrast.

**Better solution:** Compute the mean squared deviation of per-pixel luma from the
zone median within each zone. This is the intra-zone RMS contrast — what actually
drives the sense of local detail and texture.

**Implementation:** During the zone histogram build pass (BuildZoneLevels in
corrective.fx), accumulate sum-of-squared-deviations alongside the histogram bins.
At 32 bins × 4 zones across/down, this adds 16 scalar accumulators.

**Simpler alternative:** Use the zone IQR (already computed: `zone_lvl.b - zone_lvl.g`)
as a per-zone contrast measure. Average zone IQRs would give a frame-wide
texture/contrast signal that responds to per-pixel spread, not zone-to-zone spread.
This requires no new computation — zone IQR data is already available.

```hlsl
// In UpdateHistoryPS, replace zone_std derivation:
float avg_zone_iqr = 0.0;
for each zone: avg_zone_iqr += (zone_p75 - zone_p25);
avg_zone_iqr /= 16.0;
// Use avg_zone_iqr instead of zone_std to drive zone_str
```

**GPU cost:** Near-zero if using existing IQR data. Marginal if computing intra-zone
variance directly.

---

## Finding 4 — eff_p25/p75: separate the statistics or choose one (Issue 4)

**Current:** `lerp(global_p25, zone_zmin, 0.4)` and `lerp(global_p75, zone_zmax, 0.4)`.
Blends a histogram percentile with a spatial extreme.

**The intent seems to be:** FilmCurve adapts to the darkest and brightest spatial
regions, not just the overall histogram. This is a form of local content awareness for
the global curve.

**Better solution A (commit to percentiles only):**
```hlsl
float eff_p25 = perc.r;   // pure global p25
float eff_p75 = perc.b;   // pure global p75
```
Simpler, fully consistent. FilmCurve responds to global histogram only. Loses the
spatial-extreme sensitivity but eliminates the incompatible blend.

**Better solution B (commit to zone extremes):**
```hlsl
float eff_p25 = lerp(perc.r, zstats.b, 0.4);   // keep as-is but document intent
float eff_p75 = lerp(perc.b, zstats.a, 0.4);   // zone zmin/zmax pull the curve
```
Keep the current behaviour but document it as "spatial content-aware knee extension"
rather than a percentile blend.

**Better solution C (zone-weighted percentile):**
Weight each zone's p25/p75 contribution to a composite percentile, rather than using
min/max zone medians. The composite p25 would be the weighted average of zone p25
values (weighted by zone pixel count). This is a true spatial-weighted percentile.

**Recommendation:** Solution A first (audit baseline). If FilmCurve feels less spatially
responsive, reintroduce spatial awareness with Solution C.

---

## Finding 5 — CAT16: improve illuminant estimation (Issue 5)

**Current:** Frame-wide 1/8-res spatial average as the illuminant. Single bright source
dominates after luma normalization.

**Better solution A (trimmed spatial average):**
Before luma-normalization, exclude pixels above p90 luma from the illuminant estimate.
This removes bright specular sources from the average, leaving the mid-scene ambient.
```hlsl
// Weight lf_mip0 pixels by (1 - smoothstep(0.70, 0.95, L)) before averaging
// Requires a separate weighted-average illuminant texture or per-pixel modulation
```

**Better solution B (percentile-based illuminant):**
Use p50 of the scene's chromaticity distribution rather than the mean. The median
chromaticity is the "most common" illuminant colour, robust to outliers.

**Better solution C (increase blend strength selectively):**
Keep lf_mip0 but raise the lerp blend from 0.60 toward 0.80 when the illuminant
estimate is close to neutral (lms_illum_norm ≈ [1,1,1]) — meaning the scene is
already neutral and CAT16 is near-identity. When the illuminant estimate is strongly
tinted (scene has a real cast), the 0.60 blend stays as a safety valve.

```hlsl
float illum_deviation = length(lms_illum_norm - float3(1.0, 1.0, 1.0));
float cat_blend = lerp(0.80, 0.60, smoothstep(0.05, 0.20, illum_deviation));
col.rgb = lerp(col.rgb, saturate(cat16), cat_blend);
```

**Recommendation:** Solution C — zero new texture taps, keeps safety valve, but
corrects more aggressively when the illuminant estimate is reliable (near-neutral).
High-deviation estimates (suspect illuminant) still get 0.60 blend.

**GPU cost:** 3–5 ALU for the deviation check. No new taps.

---

## Finding 6 — Triple highlight compression: decouple or audit (Issue 6)

**Current:** FilmCurve + PrintStock shoulder + gamut density all compress highlights
independently.

**The stacking is not necessarily wrong** — real photochemistry compounds similarly.
Negative FilmCurve → print emulsion PrintStock → gamut constraints. The question is
whether the combined result is calibrated or accidental.

**Better solution A (audit and accept):**
Measure the combined highlight compression by capturing the input→output relationship
for luma 0.70–1.00 at current settings. If the result matches a desired characteristic
curve (e.g., Kodak Vision3 to 2383 combined), the stacking is working correctly and
no change is needed.

**Better solution B (explicit shoulder, disable PrintStock shoulder):**
If the combined result over-compresses, disable the PrintStock shoulder contribution
and rely on FilmCurve alone for highlight rolloff. PrintStock would then provide
toe/midtone character only. Replace:
```hlsl
float3 shoulder = 1.0 - (1.0 - ps) * (1.0 - ps) * 1.8;
// with identity in the shoulder region, knee-limited to fc_knee
```

**Better solution C (unified characteristic curve):**
Derive a single combined target curve that maps what FilmCurve+PrintStock+density
currently produce, then replace all three with one explicit curve function. This gives
full control over the combined result with a single set of parameters.

**Recommendation:** Solution A first — measure the actual combined curve before
changing anything. If it's within tolerance of a real film combined curve, leave it.

---

## Finding 7 — Black lift stacking: acknowledge and document (Issue 7)

**Current:** Four sequential black-lifting stages, none aware of the others.

**The combined lift is probably intentional** for a film look. The concern is:
1. Each stage's "calibrated default" comment assumes it operates alone.
2. The actual combined lift (~0.04–0.08 linear) is not documented anywhere.

**Better solution (documentation only, no code change):**
Add a comment in grade.fx before the first black-lifting stage:
```hlsl
// Note: four black-lifting stages fire in sequence.
// Combined lift at true black (input=0.0) is approximately:
//   FILM_FLOOR=0.01, PRINT_STOCK=0.50, SHADOW_LIFT=1.30 → ~0.05–0.08 linear
//   (sRGB: ~23–29% code value). This is intentional film-print character.
```

**If the combined lift is too high:** Reduce FILM_FLOOR to 0.005 (original ARRI LogC3
value) and reduce PrintStock's hardcoded 0.025 toe offset toward 0.010. These are the
two unconditional lifts; shadow lift and ambient tint are adaptive and self-limiting.

---

## Finding 8 — Chroma ceiling: apply before vibrance (Issue 8)

**Current:** `final_C = min(vib_C, max(C_ceil, C))` — ceiling on post-vibrance value.

**Better solution:**
Apply the ceiling on the *lifted* C before vibrance masking:
```hlsl
float lifted_C_clamped = min(lifted_C, max(C_ceil, C));   // ceiling on raw lift output
float vib_mask = saturate(1.0 - C / 0.22);
float vib_C    = C + max(lifted_C_clamped - C, 0.0) * vib_mask;
float final_C  = vib_C;   // ceiling already applied upstream
```

This makes the ceiling a hard guarantee on *what gets passed to vibrance*, not on
what vibrance produces. Vibrance then masks within the ceiling-bounded range. The
ceiling's meaning becomes unambiguous: "the per-band maximum chroma, period."

**GPU cost:** 1 ALU (move the min earlier in the expression). No structural change.

**Risk:** Low. The ceiling's `max(C_ceil, C)` floor (never reduce below input) is
preserved. In practice the difference is only visible near the ceiling for pixels
whose vibrance mask is non-zero (~C 0.18–0.22 range).

---

## Finding 9 — HWY_SLOPE: initialise to minimum valid value (Issue 9)

**Current:** 8-bit UNORM texture initialized to 0 → decoded slope = 1.0.

**Better solution:**
Write the minimum valid encoded slope on the first highway write, or guard the decode:
```hlsl
// Option A: clamp on decode
float slope = max(slope_enc * 1.5 + 1.0, 1.15);   // enforce minimum at decode site

// Option B: initialise highway x=197 to minimum encoded value on first frame
// (slope=1.15 → encoded = 0.10 → write 0.10 * 255 ≈ 26 as UNORM init value)
```

Option A (clamp at decode) is the safer fix — one line in inverse_grade.fx, zero
cost, eliminates the one-frame identity behaviour.

**GPU cost:** 1 ALU (max op).

---

## Priority order for implementation

| Priority | Issue | Reason |
|----------|-------|--------|
| 1 | Issue 8 (ceiling before vibrance) | One ALU, zero risk, clean semantic |
| 2 | Issue 9 (HWY_SLOPE clamp) | One line, zero risk |
| 3 | Issue 5C (adaptive CAT16 blend) | Low cost, improves neutral scenes |
| 4 | Issue 1 (chroma median) | Needs recalibration of INVERSE_STRENGTH |
| 5 | Issue 6A (measure highlight curve) | Diagnostic before deciding |
| 6 | Issue 2 (linear zone key) | Visible character change; calibrate carefully |
| 7 | Issue 4A (pure percentile curve) | Baseline audit after other fixes |
| 8 | Issue 7 (document black lift) | Comment only |
| 9 | Issue 3 (per-pixel zone_std) | Structural change; last |

---

## What NOT to fix

**Issue 3 (zone_std from medians):** The current behaviour — high zone_std in tonally
varied scenes — is arguably correct for *scene-level* contrast adaptation. Per-pixel
variance would make zone contrast respond to noise and texture, which may produce
undesirable over-sharpening in noisy game footage. Evaluate via A/B before committing.

**Issue 2 (geometric vs linear mean):** The geometric mean's dark-bias has likely been
compensated by calibration of ZONE_STRENGTH, shadow lift strength, etc. Switching to
linear mean will require full recalibration of those downstream parameters. Not urgent.
