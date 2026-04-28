# R12 — Abney Hue Shift: Findings

**Date:** 2026-04-28  
**Status:** Research complete — partial improvement viable; full data paywalled

---

## 1. Internal Audit

**Current (grade.fx Stage 3, lines 455–458):**
```hlsl
float abney  = (-HueBandWeight(h, BAND_BLUE)   * 0.08
               - HueBandWeight(h, BAND_CYAN)   * 0.05
               + HueBandWeight(h, BAND_YELLOW) * 0.05) * final_C;
float dtheta = -(GREEN_HUE_COOL * 2.0 * 3.14159265) * green_w * final_C + abney;
```

3 of 6 bands have coefficients. Blue carries the largest magnitude (0.08). Red, Green, Magenta are absent.

---

## 2. Literature

### 2.1 Abney Effect Sign Convention

The Abney effect is defined as the hue shift caused by adding white light (desaturation). Since our chroma lift **increases** saturation, the shader-relevant shift is the **inverse**: as C increases, hue shifts opposite to the Abney direction.

**From each source:**

| Source | Band | Abney direction (white added) | Shader direction (C increases) |
|--------|------|-------------------------------|-------------------------------|
| Wikipedia | Red | → Magenta | → Yellow (positive dtheta) |
| Wikipedia | Green | → Cyan | → Yellow (negative dtheta) |
| Wikipedia | Blue | → Violet/Magenta | → Cyan (negative dtheta) |
| Wikipedia | Yellow-green | → Yellow | → Yellow-green (negative dtheta) |
| PMC (Mizokami 2012) | Blue/purple | → Longer wavelengths (red) | → Cyan (negative) |
| PMC | Red/orange | "Less salient" | Small positive |

### 2.2 Pridmore 2007 — Bimodal Distribution

**Source:** Pridmore, R.W. (2007). "Effect of purity on hue (Abney effect) in various conditions." *Color Research & Application* 32(1):25–39.

The Abney shift across the hue cycle follows a **bimodal curve**:
- **Peaks (largest shifts):** Cyan and Red
- **Troughs (smallest shifts):** Blue and Green
- Yellow and Magenta: intermediate magnitudes

This is the most important finding: **the current shader has the magnitudes inverted relative to the literature.** Blue carries the largest coefficient (0.08) but Pridmore identifies Blue as a trough. Cyan carries 0.05 but is identified as a peak.

### 2.3 No Oklab-Native Data Found

Searched arxiv.org, onlinelibrary.wiley.com, opticsinfobase.org for 2020–2026. No paper provides Abney shift coefficients directly in Oklab (a,b) space or in radians-per-unit-chroma format.

The SIGGRAPH Asia 2024 "Hue Distortion Cage" paper remains behind ACM paywall. No preprint found.

Pridmore's data is in wavelength-space (nm), not Oklab. Precise conversion requires psychophysical matching experiments in Oklab, which have not been published in accessible literature as of 2026.

---

## 3. Qualitative Band-by-Band Analysis

Using Pridmore's bimodal pattern + Wikipedia directional data, translated to Oklab hue-normalized (0–1) coordinates:

| Band | h_norm | Pridmore magnitude | Direction with ↑C | Current | Proposed |
|------|--------|--------------------|-------------------|---------|----------|
| Red | 0.083 | **Peak** | +dtheta (toward yellow) | 0 | **+0.06** |
| Yellow | 0.305 | Intermediate | +dtheta (toward green) | +0.05 | +0.05 ✓ |
| Green | 0.396 | Trough | ≈0 (covered by green_cool) | 0 | 0 ✓ |
| Cyan | 0.542 | **Peak** | −dtheta (toward blue) | −0.05 | **−0.08** |
| Blue | 0.735 | Trough | −dtheta (toward cyan) | −0.08 | **−0.04** |
| Magenta | 0.913 | Intermediate | −dtheta (toward red) | 0 | −0.03 |

**Summary of changes:**
- Add Red: +0.06 (currently missing, literature says PEAK)
- Increase Cyan: −0.05 → −0.08 (Pridmore PEAK; current magnitude too small)
- Decrease Blue: −0.08 → −0.04 (Pridmore TROUGH; current magnitude too large)
- Add Magenta: −0.03 (intermediate; small conservative value)
- Yellow, Green: unchanged

### Mathematical Delta

**Current:**
$$\Delta\theta = \left(-0.08 \cdot w_B - 0.05 \cdot w_C + 0.05 \cdot w_Y\right) \cdot C$$

**Proposed:**
$$\Delta\theta = \left(+0.06 \cdot w_R - 0.05 \cdot w_Y - 0.08 \cdot w_C - 0.04 \cdot w_B - 0.03 \cdot w_M\right) \cdot C$$

Note: Yellow sign convention — current shader has +0.05 which shifts *toward green*, consistent with Wikipedia ("yellow-green → yellow" = desaturation → yellow; saturation → yellow-green = positive dtheta). ✓

---

## 4. Small-Angle Approximation Validity Check

The small-angle approximation `cos(dtheta) ≈ 1 - dtheta²/2`, `sin(dtheta) ≈ dtheta` (grade.fx lines 459–460) is valid for `|dtheta| < 0.10 rad`.

For the proposed coefficients, at peak C ≈ 0.40 (high saturation):
- Max |dtheta| ≈ 0.08 * 0.40 = 0.032 rad (Red or Cyan band)

The small-angle approximation remains valid with the new coefficients. No change needed to the rotation code.

---

## 5. Viability

| Finding | SPIR-V safe | Gate-free | Bounded | Confidence |
|---------|-------------|-----------|---------|-----------|
| F1 — Correct magnitudes (Cyan↑, Blue↓) | PASS | PASS | PASS | Medium (Pridmore) |
| F2 — Add Red band | PASS | PASS | PASS | Low-medium (conflicting sources) |
| F3 — Add Magenta band | PASS | PASS | PASS | Low (no direct data) |

**Recommendation:** F1 (Cyan/Blue magnitude swap) is the most well-supported change — Pridmore 2007 is the clearest signal. F2 (Red) and F3 (Magenta) add bands that are currently absent; the values are conservative and directionally consistent with Wikipedia.

**Caveat:** Without Oklab-native measurement data, all proposed magnitudes are calibrated to be reasonable rather than precise. The coefficient range is small enough (≤ 0.08) that worst-case error is a mild over- or under-correction, not an artifact.

**Future work:** Access to the SIGGRAPH Asia 2024 "Hue Distortion Cage" preprint (once available) may provide Oklab-specific per-hue magnitude data that could replace these estimates.
