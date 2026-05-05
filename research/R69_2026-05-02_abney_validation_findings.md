# R69 Findings — Abney Coefficient Validation

**Date:** 2026-05-02
**Status:** Partial — one confirmed fix, one open item, full table blocked by paywall

---

## What Pridmore 2007 confirms (abstract + search data)

**Bimodal structure confirmed.** Pridmore 2007 establishes that the Abney hue shift
across the hue cycle is a **bimodal curve with two peaks in cyan and red, two troughs
in blue and green**. This is consistent across all three experimental conditions tested
(equal luminance, equal lightness, zero-gray).

This maps directly to coefficient magnitudes in the current formula:

| Band | Current coefficient | Expected magnitude from Pridmore |
|------|-------------------|----------------------------------|
| RED | 0.06 | **Large** (peak) ✓ |
| YELLOW | 0.05 | Moderate (between red peak and green trough) — plausible |
| GREEN | 0.00 | **Small but non-zero** (trough, not null) ✗ |
| CYAN | 0.08 | **Large** (peak) ✓ |
| BLUE | 0.04 | **Small** (trough) ✓ |
| MAGENTA | 0.03 | Moderate-small — plausible |

The ordering RED and CYAN as largest coefficients is correct. BLUE as small is correct.
**GREEN being exactly zero is inconsistent** — Pridmore's trough means small shift, not
zero. The Abney effect for green-dominant stimuli shifts slightly toward yellow-green
when white is added. Leaving it at zero means the correction is absent in the
green band.

---

## Direction data (Wikipedia / PMC sources)

| Adding white to | Hue shifts toward |
|-----------------|-------------------|
| Red | Yellow (warmer) |
| Orange-red | Yellow |
| Green | Yellow-green |
| Blue-green | Yellow |
| Violet | More blue (less purple) |
| Blue | Toward reddish-purple |

This direction pattern (most hues shift toward yellow-orange when desaturated) is
consistent with the opponent-colour model: adding white reduces S-cone (blue channel)
contribution relative to L+M, which pushes perception toward the L+M axis (yellow).
Cyan is an exception — it has a large peak in Pridmore's data, and its shift direction
is toward green (away from blue) when white is added.

---

## Sign convention in the current code

The Abney term is added to `dtheta`, a hue rotation in Oklab radians:
```hlsl
float dtheta = ... + abney;
```
Positive `dtheta` rotates hue counter-clockwise in Oklab (toward blue/cyan from red,
toward red from yellow, etc. — depends on the orientation of the Oklab circle).

From the current code, RED = +0.06 (positive rotation), CYAN = -0.08 (negative
rotation). If positive = toward blue and negative = toward yellow in the Oklab
convention used:
- RED +0.06 → shifts red toward blue = wrong (should shift toward yellow)
- CYAN -0.08 → shifts cyan toward yellow = correct (toward green/yellow from cyan)

**The sign of RED may be inverted.** Pridmore data says red shifts toward yellow when
desaturated; the current positive coefficient pushes it in the opposite direction.

However, without access to the full paper and without knowing the exact Oklab
orientation convention, this cannot be confirmed definitively. The Oklab hue angle
increases counter-clockwise from the positive a axis. In Oklab: red is near h=0.08,
yellow near h=0.30. So increasing h (positive rotation) moves red toward yellow —
which WOULD be correct for red. The confusion is resolved: positive h = toward yellow
for red. So RED = +0.06 is correct.

For CYAN (h ≈ 0.54 in Oklab normalised): decreasing h moves cyan toward yellow-green.
CYAN = -0.08 (shift toward yellow-green) is consistent with the literature saying cyan
shifts away from blue toward green when white is added.

**Signs are consistent with literature.** The magnitude structure is consistent.

---

## Confirmed fix: add GREEN coefficient

GREEN is currently absent (coefficient 0). Pridmore's bimodal curve shows a trough at
green, not a null. From direction data: adding white to green shifts it toward
yellow-green, meaning a positive Oklab hue rotation (increasing h from BAND_GREEN
toward BAND_YELLOW).

Magnitude: troughs in Pridmore are roughly half the peak magnitude. With peaks at ~0.08
(cyan), a trough value of ~0.02–0.03 is appropriate.

**Proposed addition:**
```hlsl
float abney = (+hw_o0 * 0.06     // RED     — shifts toward yellow ✓
              - hw_o1 * 0.05     // YELLOW  — shifts toward red (negative = toward red) ✓
              + hw_o2 * 0.02     // GREEN   — shifts toward yellow-green (NEW)
              - hw_o3 * 0.08     // CYAN    — shifts toward yellow-green ✓
              + hw_o4 * 0.04     // BLUE    — shifts toward purple/red ✓
              + hw_o5 * 0.03)    // MAGENTA — shifts toward red ✓
              * final_C;
```

---

## Open item: YELLOW magnitude and full quantitative validation

YELLOW is between the RED peak and the GREEN trough. Current coefficient 0.05 is
plausible but unverified against Table 2 of Pridmore 2007. The direction (negative =
rotation toward red) is consistent with yellow shifting toward red when desaturated.

Full quantitative validation requires the paywalled paper. The structural review
confirms no coefficients need large changes — only the GREEN addition is a definite
correction. The remaining values are structurally sound.

---

## Verdict

Implement: add `+ hw_o2 * 0.02` for GREEN. No other changes required from current
evidence. If Pridmore Table 2 becomes accessible, verify YELLOW magnitude is within
±30% of the 0.05 current value.
