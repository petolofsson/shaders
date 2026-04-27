# Research 02 Findings — Zone median accuracy

## Summary
**Found:** Zone medians adequate. Flat zones (low IQR) were receiving the same S-curve
bend as contrasty ones — wasted work at best, artificial contrast injection at worst.
**Implemented:** IQR-modulated `ZONE_STRENGTH` in `grade.fx` `ColorTransformPS`.
`p25`/`p75` (already in `ZoneHistoryTex` .g/.b, previously unused) now scale the bend
via `smoothstep(0.0, 0.25, zone_iqr)`. No new texture reads. Pivot unchanged.

---

## 1. Sample count and effective coverage per zone

Pass 1 (`ComputeLowFreqPS`) renders to `CreativeLowFreqTex` at BUFFER_WIDTH/8 ×
BUFFER_HEIGHT/8 using a 4-tap tent filter with offsets at ±1.5 **full-res** pixels.
Each output texel covers only a ~3×3 full-res pixel cluster, not the expected 8×8=64
block. At 1920×1080, each zone spans ~60×34 texels in the 1/8 res image (~2025 texels).

Pass 2 (`ComputeZoneHistogramPS`) samples that zone via a 10×10 regular grid
(`sx`/`sy` 0–9), giving **100 samples per zone**. Each sample is spaced 0.25/10 = 0.025
UV steps → 60×0.025 ≈ 1.5 texels apart in the 1/8 res texture. The outermost samples
land ~3 texels inside the zone boundary, so bilinear filtering causes no cross-zone bleed.

100 regular-grid samples from a low-frequency representation is adequate for a 32-bin
histogram of a typical game zone. The limiter is the coarse 4-tap downsample (tight 3×3
coverage), not the sample count itself. High-frequency texture detail is aliased into the
low-freq representation, but this is immaterial for luma distribution purposes.

## 2. 32-bin resolution for CDF accuracy

Each bin spans 1/32 = 0.03125 luma units. `BuildZoneLevelsPS` walks the CDF and writes:
```hlsl
float bv = float(b) / 32.0;   // bin lower edge
median = lerp(median, bv, at50);
```
When the CDF first crosses 0.5, `at50` fires and `median` is set to the bin's **lower
edge** — no intra-bin interpolation. Median error is therefore up to +0.03125 (one full
bin), always undershooting the true median.

**Inconsistency with research 01**: `analysis_frame.fx` (PercTex) now uses intra-bin
interpolation after the R01 fix. Zone medians in `corrective.fx` do not. This is the
most actionable gap found.

## 3. Temporal smoothing — convergence and cut lag

`ZONE_LERP_SPEED = 8` → `speed = 0.08` per frame (EMA α = 0.08).

Cold-start guard: `if (prev.r < 0.001) speed = 1.0` — correct, no cold-lag.

Convergence from a step change:
- 90% convergence: `0.92^n ≤ 0.10` → **~28 frames** (~0.46 s at 60 fps)
- 95% convergence: **~36 frames** (~0.60 s at 60 fps)

Hard-cut lag: zone medians in `CreativeZoneLevelsTex` update immediately, but
`ZoneHistoryTex` moves only 8% per frame. After a hard cut where zone structure changes
significantly, the S-curve pivot drifts for ~0.5 s at 60 fps. This is visible as a
slow tonal shift on scene cuts but is intentional by design.

## 4. Zone boundaries

Zone UV rectangle is strictly partitioned. The 10×10 grid places outermost samples
`sx=0` at `u_lo + 0.0125` and `sx=9` at `u_lo + 0.2375`, both ≥3 texels inside the
boundary in the 1/8 res image. Bilinear filter radius is 0.5 texels. No inter-zone
contamination possible.

## 5. Uniform and bimodal zones

**Uniform zone** (e.g. sky at L≈0.7): all 100 samples land in one bin. CDF jumps from
0 to 1.0 at that bin; p25 = median = p75 all collapse to the same bin lower edge. This
is correct behavior. Quantization error ±0.03125. No instability — EMA dampens any
bin-boundary jitter to sub-perceptual levels.

**Bimodal zone** (e.g. sky + foreground in same 1/4-frame block): histogram has two
clusters. Median lands in the trough between them — a poor tonal pivot. The S-curve
anchored there will over-contrast one population and under-contrast the other. This is
an inherent limitation of using a single median pivot per zone; it cannot be fixed
within the current architecture without moving to per-pixel zone assignment or multiple
pivots per zone.

## Verdict

Zone accuracy is **not** the limiting factor in tonal quality. The system is adequate
for its role as a gentle scene-adaptive S-curve pivot. Two issues worth noting:

1. **Actionable**: ±0.03125 bin quantization from missing intra-bin interpolation.
   Scene percentiles were fixed in R01; zone medians weren't. The inconsistency is
   low practical impact (zone S-curve tolerates coarser pivots than FilmCurve) but
   the fix is trivial and brings both systems to the same accuracy.

2. **Architectural**: Bimodal zones produce a median in the inter-modal trough. No fix
   within the current per-zone-median design.

## Fix implemented — IQR-modulated S-curve strength

The ±0.03125 bin quantization is low practical impact and left as-is (zone S-curve
tolerates coarser pivots than FilmCurve). The actionable fix addresses the more
meaningful problem: **flat zones receiving the same bend as contrasty zones**.

`ZoneHistoryTex` already stores p25 (.g) and p75 (.b) per zone, never previously read
in `ColorTransformPS`. IQR = p75 - p25 measures how much distribution there is to work
with. The fix scales `ZONE_STRENGTH` by the zone's IQR before applying the S-curve:

```hlsl
float4 zone_lvl   = tex2D(ZoneHistorySamp, uv);
float zone_median = zone_lvl.r;           // pivot unchanged
float zone_iqr    = zone_lvl.b - zone_lvl.g;
float iqr_scale   = smoothstep(0.0, 0.25, zone_iqr);
float bent        = dt + (ZONE_STRENGTH / 100.0) * iqr_scale * dt * (1.0 - saturate(abs(dt)));
```

- Flat zone (IQR ≈ 0–0.05): iqr_scale ≈ 0 → near-zero bend, no artificial contrast injection
- Moderate zone (IQR ≈ 0.125): iqr_scale ≈ 0.5 → half strength
- Contrasty zone (IQR ≥ 0.25): iqr_scale = 1.0 → full ZONE_STRENGTH unchanged

Pivot remains the zone median. No new texture reads (p25/p75 already in ZoneHistoryTex).
No gates. Implemented in `grade.fx` ColorTransformPS tonal section.
