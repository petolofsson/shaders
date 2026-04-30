# Research 05 — Rank-based zone contrast — Findings

## Investigation answers

### 1. Is CreativeZoneHistTex available in grade.fx?

Yes. Chain order is `corrective : grade`. `corrective.fx` Pass 2 (`ComputeZoneHistogramPS`)
populates `CreativeZoneHistTex` before grade.fx runs. The texture is declared in corrective.fx as:
```
texture2D CreativeZoneHistTex { Width = 32; Height = 16; Format = R16F; MipLevels = 1; }
```
To read it in grade.fx, declare an identical texture with the same name — vkBasalt/ReShade shares
textures by name across effects. Precedent: `ZoneHistoryTex` and `ChromaHistoryTex` are already
declared in both corrective.fx and grade.fx this way.

Zone index from UV: `int zone = int(uv.y * 4) * 4 + int(uv.x * 4)` — same integer math used in
`BuildZoneLevelsPS`. CDF walk per pixel: 32 POINT fetches from row `(zone + 0.5) / 16.0`. All
pixels within a zone read the same row; at 1/16th of screen pixels per zone, these 32 values
stay L1 resident. Cost is low relative to the Oklab path already in the shader.

### 2. What blend fraction preserves film aesthetic?

Rank-based at full weight is histogram equalization — the rank maps each pixel to its CDF
position, fully flattening the zone histogram. That looks over-processed (HDR/video-game
grading, not film).

A blend parameter — `RANK_CONTRAST_STRENGTH` in `creative_values.fx` (0–100, default ~30) —
would blend between the rank-mapped luma and the current median-S-curve output. The current
IQR-modulated S-curve already provides the film-like baseline; rank replaces the S-curve shape
rather than blending with identity. Practically, the useful range is 20–50% rank weight.

Requires a new knob in `creative_values.fx`. Cannot derive a fixed fraction analytically —
needs a visual tuning session.

### 3. How does rank interact with IQR scaling (R02)?

IQR scaling is **not made redundant** by rank — it becomes more important.

Rank always spans [0, 1] regardless of zone spread. A zone where all pixels cluster between
0.48 and 0.52 (near-flat) maps them to full [0, 1] rank space and would apply full contrast
expansion. That is the opposite of the desired behavior for flat zones. IQR scaling (or an
equivalent zone-spread gate) is still needed to suppress contrast when the zone has low dynamic
range. If anything, rank-based contrast is more aggressive on flat zones than the current system,
so the IQR suppression term from R02 must be retained.

### 4. Is the 32-bin CDF walk affordable?

Likely yes. The 32-bin histogram row for a zone fits in 64 bytes (32 × R16F). GPU L1 is
wavefront-local — all threads in a wavefront mapping to the same zone share those cache lines.
At 64 threads per wavefront and a 4×4 zone grid, same-zone threads are spatially clustered.
In practice this is ~32 sequential POINT fetches from a nearly-always-cached row, comparable
in cost to a single bilinear texture sample from an uncached large texture. No profiling needed
before a prototype; only revisit if frame time regresses visibly.

## Structural verdict

The concept is sound and buildable with modest changes:

- Declare `CreativeZoneHistTex` in grade.fx (shared texture, matching declaration)
- Add CDF walk in Stage 2 to compute per-pixel rank within its zone
- Replace `dt = luma - zone_median` with `dt = rank - 0.5` (rank centered at 0.5)
- Retain IQR scaling — multiply rank-based displacement by `iqr_scale` as now
- Expose `RANK_CONTRAST_STRENGTH` in `creative_values.fx`; blend with current output or with identity

---

## Implementation outcome — REJECTED (2026-04-29)

Implemented, bugfixed (rank-space / luma-space type error; unsaturated negative lerp), and evaluated in Arc Raiders. Result: overall image darkening and a grayish cast at any non-zero strength. No perceptual improvement over `ZONE_STRENGTH` alone.

Root cause is inherent to histogram equalization: in Arc Raiders' typical zone histograms (dense darks/mids, sparse highlights), equalization always compresses highlights toward the zone median and expands the dense shadow mass — reading as darker and flatter, not as increased contrast.

`ZONE_STRENGTH`'s S-curve approach is strictly better for this content: it amplifies existing contrast rather than redistributing the histogram. The rank approach would theoretically help zones with pathologically asymmetric distributions, but Arc Raiders does not exhibit that problem at a perceptually relevant scale.

**Decision:** removed from `grade.fx` and `creative_values.fx`. Do not revisit unless a specific scene pathology is identified where `ZONE_STRENGTH` demonstrably misfires.

## Bimodal zone claim — scrutiny

The paper states rank handles bimodal zones better. This is partially true but subtler than
stated. For a clean bimodal zone (half pixels at 0.2, half at 0.7), ranks are:
- Lower cluster → ranks 0–0.5, median rank 0.25
- Upper cluster → ranks 0.5–1.0, median rank 0.75

With rank S-curve pivoted at 0.5, the lower cluster is pushed downward (rank 0.25 → further
negative) and upper pushed upward — expanding the split. The current median S-curve with pivot
at the trough (~0.45) does essentially the same thing. The advantage of rank is not primarily
bimodal handling — it is **asymmetric distribution handling**. When a zone has a long upper
tail (most pixels dark, a few bright highlights), the median is pulled up by the tail, causing
the S-curve to treat most pixels as below-median and compress them. Rank is immune to this:
each pixel sees only its own percentile position, not the distortion from outliers.

## Chroma rank footnote

`SatHistTex` in analysis_frame.fx: 64 bins × 6 hue bands, R32F. Same CDF walk approach applies.
Since analysis_frame runs before grade, the texture is available. Practical gain is smaller —
chroma distributions within a hue band are rarely asymmetric enough to matter. Log for later.
