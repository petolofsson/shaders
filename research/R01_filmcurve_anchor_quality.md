# Research 01 — FilmCurve anchor quality

## Question
Are the percentile anchors (p25/p50/p75) that drive the FilmCurve robust under real
game content? Do specular spikes, near-black areas, or low-variance scenes skew them
in ways that produce a worse tone curve than a fixed anchor would?

## Context
The FilmCurve in `general/grade/grade.fx` (ColorTransformPS stage 1) pivots on three
scene percentiles read from PercTex: p25 (shadows), p50 (midtones), p75 (highlights).
These are computed in `general/analysis-frame/analysis_frame.fx` from a frame-wide
luminance histogram.

The intent: anchor the curve to actual scene content so it adapts shot-to-shot.
The risk: percentiles can be unstable or misleading when scene content is extreme
(specular-heavy frames, dark interiors, flat overcast scenes).

## What to read
- `general/analysis-frame/analysis_frame.fx` — how PercTex is built (histogram → CDF → percentiles)
- `general/grade/grade.fx` — FilmCurve function + how p25/p50/p75 are used in ColorTransformPS

## What to investigate
1. How is the histogram built? Sample count, resolution, temporal smoothing?
2. How are p25/p50/p75 extracted from the histogram? CDF walk, bin interpolation?
3. What happens to the curve when p25 ≈ p50 (flat dark scene) or p75 ≈ 1.0 (specular-heavy)?
4. Is there temporal smoothing on PercTex, or does it update every frame raw?
5. Does the FilmCurve degrade gracefully at extremes or does it invert/collapse?

## Output expected
- Description of the current mechanism (precise, with line references)
- Identified failure modes with concrete scene conditions that trigger them
- Verdict: is the anchor quality sufficient, or is there a specific weakness worth fixing?
- If weakness found: what would a fix look like (one paragraph, no implementation)
