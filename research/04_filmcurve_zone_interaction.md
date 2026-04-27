# Research 04 — FilmCurve and zone contrast interaction

## Question
Do the FilmCurve (stage 1) and zone S-curve (stage 2) work together as intended, or
do they partially duplicate effort, fight each other in specific tonal regions, or
produce a combined response that neither was designed for?

## Context
ColorTransformPS in `general/grade/grade.fx` applies two tonal operations in sequence:

Stage 1 — FilmCurve: maps the full tonal range using p25/p50/p75 as anchors.
This is a global operation — same curve applied to every pixel regardless of
where on screen it sits.

Stage 2 — Zone S-curve: applies a per-zone contrast bend around each zone's
local median. This is a spatially-aware operation — different zones get different
pivots.

The intent is complementary: FilmCurve sets the global tonal character, zones
refine local contrast. The risk is interaction: if FilmCurve already compressed
shadows, the zone S-curve may over-compress them further. If FilmCurve lifts
midtones, the zone pivot may be in the wrong place because the median was
computed from the pre-FilmCurve BackBuffer.

## Critical detail
ZoneHistoryTex is computed in corrective.fx from the BackBuffer BEFORE FilmCurve
runs. The zone medians are therefore in pre-FilmCurve tonal space. The zone S-curve
is then applied in post-FilmCurve tonal space. This mismatch may or may not matter
depending on how much the FilmCurve moves values.

## What to read
- `general/corrective/corrective.fx` — when and what BB content the zone histogram reads
- `general/grade/grade.fx` — stage 1 (FilmCurve) and stage 2 (zone S-curve) in full,
  and their order of application in ColorTransformPS

## What to investigate
1. Precisely: what tonal space are the zone medians computed in (pre/post FilmCurve)?
   Does the FilmCurve move values enough that a median of 0.4 pre-curve becomes
   something meaningfully different post-curve?
2. Are there tonal regions where both operations push in the same direction
   (cumulative compression or expansion)? Is this intentional or accidental?
3. Are there tonal regions where they push in opposite directions (one lifts, one bends
   down)? What does that produce visually?
4. Does the Clarity stage (also in stage 2) interact with either FilmCurve or zone
   contrast in any problematic way?
5. Would computing zone medians post-FilmCurve give better results? What would that
   require structurally?

## Output expected
- Clear mapping of what tonal space each operation works in
- Analysis of where the operations are additive, neutral, or conflicting
- Verdict: is the interaction benign, beneficial, or a real problem?
- If problem: describe the correct fix at an architectural level (one paragraph, no implementation)
