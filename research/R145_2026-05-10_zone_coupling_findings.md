# R145 — Zone Coupling: Findings
**Date:** 2026-05-10
**Status:** Implemented (subsequently removed)

## Problem
R144 luma expansion in inverse_grade raised scene luma, reducing zone S-curve effective strength. Zone felt weaker after inverse grade was enabled, prompting a compensation mechanism.

## Solution
Divided ZONE_STRENGTH by inverse-grade slope to compensate: `zone_str_eff = ZONE_STRENGTH / slope`. Later found R144 itself was wrong (cbrt pivot caused texture smoothing). R144 was removed in R159, making R145 a workaround for a bad fix — R145 was therefore also removed.

## Implementation
Was `zone_str_eff = ZONE_STRENGTH / slope` in grade.fx — removed along with R144.

## Result
ZONE_STRENGTH (now CONTRAST) is a clean standalone knob with no hidden coupling.
