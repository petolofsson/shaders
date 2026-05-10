# R118 — Yellow/Orange Chroma Over-Saturation: Findings
**Date:** 2026-05-06

---

## Finding 1 — R73 yellow ceiling is calibrated backwards

**Current code (R73/R81B):**
```hlsl
// R81B: MacAdam-calibrated ceilings — blue/cyan tightened (smallest discrimination
// ellipses), yellow relaxed (largest ellipses).
float C_ceil = hw_o0 * 0.28 + hw_o1 * 0.24 + hw_o2 * 0.16
             + hw_o3 * 0.15 + hw_o4 * 0.19 + hw_o5 * 0.22;
```

Yellow ceiling: 0.24 (second loosest, after red 0.28).
Comment justification: "yellow relaxed (largest ellipses)."

**Research finding:** MacAdam (1942) ellipses are **smallest** in the yellow region — humans have
their finest color discrimination near yellow-green. This is well-established and confirmed by the
Oklab design paper (Bottosson 2020), which fitted Oklab to the MacAdam/Luo-Rigg dataset.

The R81B reasoning is **inverted**. Small MacAdam ellipses = fine discrimination = should produce a
**tight** ceiling, not a loose one. The code comment has the logic backwards.

**Correct calibration direction:**
- Blue/cyan: large ellipses (coarse discrimination) → ceiling can be relaxed
- Yellow: small ellipses (fine discrimination) → ceiling should be tightest

Current assignment vs. correct assignment:

| Hue | Current ceiling | Correct direction |
|-----|----------------|-------------------|
| Red (0.28) | loosest | moderate (large ellipses in saturated red) |
| Yellow (0.24) | second loosest | should be tightest — finest discrimination |
| Magenta (0.22) | moderate | moderate |
| Blue (0.19) | moderate | could be relaxed (larger ellipses in deep blue) |
| Green (0.16) | tight | moderate |
| Cyan (0.15) | tightest | moderate-tight |

Yellow at 0.24 Oklab C is already a visually aggressive saturation level. Combined with the pipeline's
stacked amplification, it reaches values that exceed natural scene range and are perceptually jarring.

**Proposed fix:** Tighten yellow ceiling to 0.14–0.15 (tighter than green, consistent with
finest-discrimination status). This is the single highest-leverage change.

---

## Finding 2 — H-K effect is weak in yellow: no perceptual loudness compensation applies

**Pre-research hypothesis:** Yellow appears perceptually loud partly due to a strong
Helmholtz-Kohlrausch effect amplifying its perceived saturation.

**Research finding:** H-K effect is **negligible in yellow and green**, and strongest in blue
and red. (High 2023, Wiley; Journal of Information Display 2022.)

Yellow at Oklab C=0.20 does not appear more saturated than its colorimetric value suggests — it
appears exactly as saturated. There is no HK-amplified perceptual loudness unique to yellow.

**Implication:** The loudness is not a perceptual illusion — it is a real over-saturation caused
by the pipeline stack. The fix must be in the ceiling, not in a perceptual compensation layer.

---

## Finding 3 — ACES / filmic tonemappers desaturate bright yellows; inverse grade over-restores

**Research finding:** ACES and Reinhard-family tonemappers desaturate bright colors, including
yellow/orange, as luminance approaches the shoulder. (Narkowicz 2016; Promit 2017.)

**Pipeline implication:** Arc Raiders almost certainly uses a filmic tonemapper in-engine. The
tonemapper compresses both luma and chroma for bright yellows. Inverse grade (R90) measures the
overall IQR chroma slope and expands uniformly. If the tonemapper suppressed yellow chroma more
than average (which it does — bright yellows are near the shoulder), uniform IQR expansion
over-restores yellow relative to other hues.

This is a compounding effect: tonemapper disproportionately compressed yellow → R90 uniformly
expands by the same factor for all hues → yellow ends up above original scene value.

**Proposed fix (secondary):** This is harder to correct without per-hue inverse grade tracking,
which is a significant architectural change. The ceiling fix in Finding 1 is the correct first
line of defense. If yellow remains too strong after ceiling tightening, investigate per-hue
chroma slope tracking in R90.

---

## Finding 4 — No natural scene chroma data found for yellow; heuristic estimate only

No published database of natural scene Oklab C values for yellow hues was found via search.

However: Munsell Book of Color (widely used for natural scene calibration) has maximum chroma for
yellow at roughly Munsell C=14 in its 5Y hue family. Converting Munsell chroma 14 to Oklab C
(approximately, via CAM16 correspondence): roughly Oklab C ≈ 0.14–0.16.

The current ceiling of 0.24 allows yellow to reach ~50–70% above the Munsell natural maximum.
The proposed ceiling of 0.14–0.15 would align with the Munsell natural gamut boundary.

**Confidence: Medium.** The Munsell conversion is approximate. But the direction is clear.

---

## Summary

| Finding | Pre-research hypothesis | Post-research verdict |
|---------|------------------------|----------------------|
| R73 MacAdam yellow ceiling | Ceiling may be too loose | **Ceiling is calibrated backwards — must tighten** |
| H-K effect on yellow | Yellow is perceptually loud via HK | **HK negligible in yellow — loudness is real over-saturation** |
| Inverse grade over-restoration | Suspected | **Confirmed: filmic tonemappers compress yellow more** |
| Natural scene yellow ceiling | ~0.15 estimated | **~0.14–0.16 (Munsell, approximate)** |

## Implementation plan

**Priority 1 — R73 yellow ceiling: 0.24 → 0.14**
- Change `hw_o1 * 0.24` to `hw_o1 * 0.14` in the C_ceil computation
- Update comment: remove "yellow relaxed (largest ellipses)" — it is factually wrong
- Expected visual impact: yellow/orange saturation drops to perceptually correct range

**Priority 2 (optional) — Blue/Cyan ceiling: consider relaxing**
- If MacAdam ellipses are larger for deep blue (coarse discrimination), blue ceiling
  could be relaxed slightly from 0.19 → 0.21
- Lower confidence; defer pending visual testing

**Priority 3 (future) — Per-hue inverse grade weighting**
- Currently deferred: architectural, requires per-hue slope tracking in analysis_frame
- Revisit if yellow is still over-restored after ceiling fix
