# Research 02 — Zone median accuracy

## Question
Are the per-zone medians accurate and stable enough to be trusted as tonal pivots?
Is the sample count (100 samples per zone at 1/8 res) sufficient, and does the temporal
smoothing help or mask underlying instability?

## Context
`general/corrective/corrective.fx` computes a 4×4 grid of zone medians:
- Pass 1 downsamples BackBuffer to 1/8 res (CreativeLowFreqTex)
- Pass 2 builds a 32-bin luma histogram per zone (100 samples each)
- Pass 3 walks the CDF to extract median, p25, p75 per zone
- Pass 4 lerps the result into ZoneHistoryTex at ZONE_LERP_SPEED/100 per frame

ZoneHistoryTex is then read by ColorTransformPS in grade.fx to drive the zone S-curve.

The risk: 100 samples from a 1/8 res downsample may not characterise a zone reliably,
especially for zones with bimodal distributions (e.g. a zone containing both sky and
foreground). Temporal smoothing may hide per-frame noise but also slow adaptation.

## What to read
- `general/corrective/corrective.fx` — passes 1–4 in full
- `general/grade/grade.fx` — how ZoneHistoryTex.r (zone_median) is used in the tonal section

## What to investigate
1. What is the effective sample count per zone after the 1/8 res downsample? How many
   unique source pixels does one zone sample actually represent?
2. Is 32 bins enough resolution for a CDF walk to produce accurate medians?
3. What does the temporal smoothing (ZONE_LERP_SPEED 8 = 8% per frame) mean in practice?
   How many frames to converge on a new scene? How many frames of lag on a hard cut?
4. Are zone boundaries hard or soft? Can a bright edge pixel in one zone bleed into
   the adjacent zone's histogram?
5. What happens to zones that are largely uniform (sky, flat wall)? Does the CDF
   produce a stable median or does it jump between bins?

## Output expected
- Precise accounting of sample count and effective coverage per zone
- Analysis of temporal smoothing lag (frames to converge, frames to recover from cut)
- Identified weak cases (bimodal zones, uniform zones, hard cuts)
- Verdict: is zone accuracy the limiting factor in tonal quality, or is it good enough?
- If weakness found: what would a fix look like (one paragraph, no implementation)
