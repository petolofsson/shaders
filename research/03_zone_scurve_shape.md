# Research 03 — Zone S-curve shape

## Question
Is the current zone S-curve shape the best choice for organic tonal contrast, or is
there a better mathematical form that behaves more predictably at extremes and produces
a more film-like response?

## Context
The zone S-curve in `general/grade/grade.fx` (ColorTransformPS tonal section) works as:

    dt   = luma - zone_median
    bent = dt + (ZONE_STRENGTH / 100.0) * dt * (1.0 - saturate(abs(dt)))
    new_luma = saturate(zone_median + bent)

This is a quadratic bend: the correction is zero at the pivot (luma == zone_median),
peaks somewhere in the midrange, and tapers off as luma approaches 0 or 1. It is
self-limiting (saturate keeps output in [0,1]).

The question is whether this specific shape is the right one — whether it produces
contrast that feels organic and film-like, or whether it has a characteristic "look"
that could be improved with a different formulation.

## What to read
- `general/grade/grade.fx` — the full TONAL section of ColorTransformPS (zone S-curve,
  clarity, shadow lift all interact — read them together)

## What to investigate
1. Plot the transfer function of the current curve at ZONE_STRENGTH 30 for a mid-grey
   pivot (zone_median = 0.5). What is the shape? Where is the inflection? What is the
   maximum lift/compression and at what luma value does it occur?
2. How does the curve behave when zone_median is very low (dark zone, median = 0.15)
   or very high (bright zone, median = 0.80)? Does it remain well-behaved?
3. Compare to known S-curve formulations: cubic Hermite, Reinhard, ASC CDL power,
   smoothstep. What are the perceptual differences?
4. Does the current shape interact well with clarity and shadow lift, or do they
   pull in conflicting directions in any tonal region?
5. Is the ZONE_STRENGTH knob linear in perceptual effect, or does it become
   unpredictable at high values?

## Output expected
- Mathematical description of the current curve shape with transfer function analysis
- Behaviour at edge cases (low pivot, high pivot, high strength)
- Comparison against 1–2 alternative formulations with their trade-offs
- Verdict: is the current shape a good choice, or is there a clearly better one?
- If alternative is better: describe it precisely (one paragraph, no implementation)
