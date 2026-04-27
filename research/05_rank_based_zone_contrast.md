# Research 05 — Rank-based zone contrast (future)

## Question
Can we replace the median-pivoted S-curve with a rank-based approach that uses the full
per-zone histogram, and does this produce more natural local contrast without the bimodal
zone failure case?

## Concept
Currently `ColorTransformPS` reads only three scalars from `ZoneHistoryTex` (median, p25,
p75) and applies a fixed-pivot S-curve. `CreativeZoneHistTex` (32×16) holds the full
per-zone histogram but is never read downstream — it is discarded after `BuildZoneLevelsPS`
extracts the percentiles.

Rank-based approach: for each pixel, determine its luma percentile rank within its zone
by walking the zone's histogram row in `CreativeZoneHistTex`. Use that rank as the input
to the contrast curve instead of the raw luma. A pixel at the 80th percentile of a dark
zone gets the same contrast treatment as an 80th-percentile pixel in a bright zone.

## Why it's better than the current system
- Bimodal zones: rank is monotonic, so sky pixels and foreground pixels in the same zone
  are treated by their relative position within the zone, not a shared median that falls
  in the trough between them.
- No pivot asymmetry: rank is always in [0,1] regardless of zone median position. The
  S-curve operates in a normalized space that is always symmetric.
- Naturally adaptive to zone width: a narrow distribution and a wide one both map to
  [0,1] rank space — the curve shape is consistent.

## Chroma equivalent
The same principle applies to chroma: replace the per-band mean pivot with each pixel's
chroma rank within its hue band's distribution (from `SatHistTex` in `analysis_frame.fx`).
Practical improvement is smaller than the zone case — bimodal chroma distributions within
a single hue band are uncommon. Log as a footnote when implementing zone rank, not a
separate paper.

## Cost
- `CreativeZoneHistTex` must be declared in `grade.fx` (currently only in `corrective.fx`)
- Per pixel: determine zone index from UV (integer math), walk 32 histogram bins for the
  zone's row to accumulate CDF, find rank of current luma. 32 POINT texture fetches per
  pixel from a 32×16 texture — likely L1 resident since all pixels in a zone read the
  same row.
- Risk: full equalization looks HDR/processed. Must blend rank-mapped output with original,
  not apply 1:1. Tuning surface needed.

## What to investigate
1. Does reading `CreativeZoneHistTex` in grade.fx work correctly — is the texture
   populated before grade runs in the chain?
2. What blend fraction between rank-mapped and original preserves film aesthetic?
3. How does the rank approach interact with IQR scaling (R02)? IQR scaling may be
   redundant if rank naturally handles flat zones (flat zone → all ranks near 0.5 → no
   contrast change needed).
4. Is the 32-bin CDF walk per pixel affordable at full resolution? Profile vs current cost.
