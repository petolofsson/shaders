# Job — Shader Research Nightly

**Trigger ID:** trig_01X6LEJt3G5xvjUqGiaokRFh
**Schedule:** 0 1 * * * (1 AM UTC)
**Output:** `research/R{next}_{YYYY-MM-DD}_{slug}.md`

## Summary

Domain-rotation literature search. Finds novel findings from adjacent fields and
filters them for architectural viability. Writes a dated findings file to alpha.

## Domain rotation (date +%u)
1 Mon — Tone mapping & film sensitometry
2 Tue — Perceptual chroma (HK, Hunt, Abney)
3 Wed — Temporal filtering & state estimation
4 Thu — Zone/histogram analysis
5 Fri — Film stock spectral emulation
6 Sat — Color appearance models
7 Sun — Wild card

## Key exclusions (permanent, no exceptions)
- Clarity / sharpening / local contrast / mid-frequency boost / CLARITY_STRENGTH
- Film grain
- Lateral chromatic aberration
- Any HDR-only technique

## Last updated
2026-05-04 — Updated for R90/R61 chain, fixed R-number filename convention,
added clarity permanent exclusion, replaced hardcoded implemented list with
HANDOFF.md reference.
