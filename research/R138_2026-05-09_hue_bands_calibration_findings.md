# R138 — Hue Bands Calibration: Munsell Mid-Value Ceilings + Luminance-Aware Lower Arm

**Date:** 2026-05-09
**Status:** Complete  
**Source data:** `coloria-dev/color-data` `munsell/real.dat` (2734 chips, Illuminant C, CIE 1931)  
**Conversion chain:** Munsell (x,y,Y) → XYZ Illuminant C → Bradford adapt → XYZ D65 → linear sRGB → Oklab

---

## Summary

- **H1 confirmed** for 6 of 6 intermediate bands. All differ from current estimates by ≥ 0.012 Oklab C.
  - 4 bands lower than estimated (orange, amber, teal, azure)
  - 2 bands higher than estimated (violet, rose)
- **H4 refuted.** Testbed shadow pixels (L < 0.40) have median Oklab C = 0.020. Lower arm deferred.
- **H3 rejected** — smoothstep(0.0, 0.45, L) over-estimates the ramp by 20–50% at V=2–3.
  smoothstep(0.0, 0.60, L) fits much better, but the lower arm itself is deferred.

**Implemented:** 6 intermediate band constants updated in `hue_bands.fxh`.  
**Not implemented:** lower arm, anchor band changes.

---

## Critical observation: Munsell hue ≠ Oklab hue

The Munsell hue system maps non-linearly to Oklab angles. The proposal's named pages
(5YR, 10YR, 5BG, 5PB, 5P, 5RP) were partially correct but several were off by 10–30°.

Key surprises:

| Munsell page | Oklab angle at V=5 max-C chip | Our band at that angle |
|---|---|---|
| 5G ("Green") | 170° | Teal (169°) |
| 5BG ("Blue-Green") | 189° | between Teal and Cyan |
| 5P ("Purple") | 317° | Violet (297°) — 20° off |
| 5B ("Blue") | 211° | Cyan (195°) — not Blue |
| 7.5PB | 269° | Blue (265°) — correct |

The angle-based lookup (find max Oklab hue at V=5 closest to the band center) was used
to select the correct Munsell page for each band.

---

## Critical observation: all V=5 max-chroma chips are outside sRGB gamut

Every Munsell hue page at V=5 has at least one sRGB channel outside [0, 1] at its maximum
chroma. Using the raw Munsell C_max would set ceilings far above what SDR display content
can reach, effectively disabling the ceiling for those hues.

**Correct ceiling = in-gamut C_max**: the highest Oklab C among V=5 chips on the matched
page that are representable in sRGB (all channels in [−0.005, 1.005]).

---

## Task A — Mid-value ceiling calibration

### Intermediate bands (updated)

| Band | Center° | Matched page | Page h° | In-gamut C_max | Old | New | Δ |
|---|---|---|---|---|---|---|---|
| Orange | 65° | 7.5YR | 68° | **0.1303** | 0.16 | 0.13 | −0.03 |
| Amber  | 87° | 2.5Y  | 86° | **0.1159** | 0.15 | 0.12 | −0.03 |
| Teal   | 169° | 5G   | 170° | **0.1233** | 0.15 | 0.12 | −0.03 |
| Azure  | 230° | 2.5PB | 231° | **0.1283** | 0.17 | 0.13 | −0.04 |
| Violet | 297° | 10PB | 290° | **0.2174** | 0.20 | 0.22 | +0.02 |
| Rose   | 359° | 7.5RP | 360° | **0.2422** | 0.22 | 0.24 | +0.02 |

The proposal's named pages (5YR, 10YR, 5BG, 5PB, 5P, 5RP) and the angle-matched pages
agree directionally for Orange, Amber, Violet, Rose. Teal and Azure differ:
- Teal: proposal named 5BG (h=189°, ig_max=0.089), but 5G (170°) is the correct match.
  Using 5BG would have been overly tight (0.089 vs 0.123).
- Azure: proposal named 5PB (h=242°, ig_max=0.147), but 2.5PB (231°) is closer.
  Both are in the same direction (lower), but 2.5PB is more precisely matched.

### Anchor band verification (no changes)

| Band | Matched page | In-gamut C_max | sRGB gamut max | Current | Notes |
|---|---|---|---|---|---|
| Red | 7.5R (28°) | 0.2361 | 0.2577 | 0.28 | Current **above sRGB max** — ceil never fires for SDR red |
| Yellow | 10Y (108°) | 0.1267 | 0.2302 | 0.14 | Consistent — tight by design |
| Green | 10GY (147°) | 0.1591 | 0.2948 | 0.16 | Essentially same |
| Cyan | 7.5BG (194°) | 0.0908 | 0.1616 | 0.15 | Current **significantly above** Munsell ig_max — permits unnatural chroma |
| Blue | 7.5PB (269°) | 0.2072 | 0.3132 | 0.19 | Current below Munsell — conservative (R118 MacAdam rationale) |
| Magenta | 7.5P (327°) | 0.2892 | 0.3225 | 0.22 | Current well below Munsell — very conservative (R118 MacAdam rationale) |

Notable: **HB_CEIL_RED (0.28) never fires** — the sRGB gamut boundary at 30° is 0.258, so no
SDR pixel can reach C=0.28 at the red hue angle. Functionally the same as having no ceiling at red.

Notable: **HB_CEIL_CYAN (0.15) permits more saturation than any Munsell chip at V=5** — the
Munsell in-gamut maximum for cyan-angle hues is only 0.091. Cyan in sRGB can reach C=0.162
at the gamut boundary, so the 0.15 ceiling does prevent some sRGB-gamut saturation but allows
more than natural. This is the opposite problem from the "too conservative" anchor bands.

These observations are for future R118 review, not actionable here.

---

## Task B — Lower arm shape (V=2–5)

Data from 5R, 5Y, 5GY pages at V=2–5 (in-gamut chips only):

| Hue | V | Oklab L | In-gamut C_max | C_norm | ss(0.0,0.45,L) | ss(0.0,0.60,L) |
|---|---|---|---|---|---|---|
| Red | 2 | 0.333 | 0.146 | 0.601 | 0.832 | 0.582 |
| Red | 3 | 0.424 | 0.178 | 0.730 | 0.991 | 0.793 |
| Red | 4 | 0.516 | 0.194 | 0.796 | 1.000 | 0.947 |
| Red | 5 | 0.611 | 0.244 | 1.000 | 1.000 | 1.000 |
| Yellow | 2 | 0.316 | 0.061 | 0.512 | 0.786 | 0.539 |
| Yellow | 3 | 0.404 | 0.085 | 0.714 | 0.971 | 0.750 |
| Yellow | 4 | 0.494 | 0.092 | 0.774 | 1.000 | 0.917 |
| Yellow | 5 | 0.583 | 0.119 | 1.000 | 1.000 | 1.000 |
| Green | 2 | 0.310 | 0.092 | 0.695 | 0.768 | 0.524 |
| Green | 3 | 0.398 | 0.093 | 0.700 | 0.963 | 0.736 |
| Green | 4 | 0.486 | 0.126 | 0.955 | 1.000 | 0.906 |
| Green | 5 | 0.575 | 0.132 | 1.000 | 1.000 | 1.000 |

**smoothstep(0.0, 0.45, L)** overshoots the actual ramp by 20–50% at V=2 and saturates to 1.0
too early (already at V=3 for Red, at V=4 for Yellow/Green). **H3 rejected** as-is.

**smoothstep(0.0, 0.60, L)** fits much better, but remains deferred with the lower arm.

---

## Task C — Testbed shadow chroma (H4)

Capture: `session_20260508_205931_arc_raiders.exr` (2560×1440, 37.8% pixels with L < 0.40)

| L range | Pixel count | C median | C p90 |
|---|---|---|---|
| [0.00, 0.10) | 385 | 0.000 | 0.054 |
| [0.10, 0.20) | 464 463 | 0.006 | 0.016 |
| [0.20, 0.30) | 396 394 | 0.022 | 0.046 |
| [0.30, 0.40) | 532 279 | 0.067 | 0.076 |

Overall shadow (L < 0.40): median C = **0.020**.

**H4 refuted.** Threshold was 0.08; actual is 0.020. Only 0.05% of shadow pixels exceed C=0.12.
The testbed is display-referred SDR from a tonemapper: shadows are near-achromatic by construction.
The lower arm is deferred — it would fire on effectively no pixels.

---

## Implementation

### Changed: `general/hue_bands.fxh`

Six `HB_CEIL_*` constants updated for intermediate bands. All others unchanged.

| Constant | Old | New | Source |
|---|---|---|---|
| `HB_CEIL_ORANGE` | 0.16 | 0.13 | 7.5YR V=5 ig_max=0.1303 |
| `HB_CEIL_AMBER`  | 0.15 | 0.12 | 2.5Y V=5 ig_max=0.1159  |
| `HB_CEIL_TEAL`   | 0.15 | 0.12 | 5G V=5 ig_max=0.1233    |
| `HB_CEIL_AZURE`  | 0.17 | 0.13 | 2.5PB V=5 ig_max=0.1283 |
| `HB_CEIL_VIOLET` | 0.20 | 0.22 | 10PB V=5 ig_max=0.2174  |
| `HB_CEIL_ROSE`   | 0.22 | 0.24 | 7.5RP V=5 ig_max=0.2422 |

### Not changed

- Anchor bands (Red, Yellow, Green, Cyan, Blue, Magenta): have R118/MacAdam rationale, 
  not overridden by Munsell V=5 lookup alone.
- `HueCeil` signature: stays `float HueCeil(float hue)` — no L parameter (H4 refuted).
- Callsites: unchanged.
- `HueBandRollN` and R133 rolloff exponents: unchanged.

---

## Open items for future research

1. **HB_CEIL_RED** (0.28): above sRGB gamut max at red hue angle (0.258) — functionally inert.
   Consider lowering to ~0.26 to match sRGB boundary, or to ~0.24 for Munsell in-gamut max.
   
2. **HB_CEIL_CYAN** (0.15): above Munsell in-gamut max at cyan angle (0.091). The ceiling
   permits more saturation than any naturally occurring cyan-hue object at V=5. R118 rationale
   should be reviewed before changing.

3. **Lower arm**: deferred. If a future testbed or scene has meaningful dark-shadow chroma,
   revisit with smoothstep(0.0, 0.60, L) rather than 0.45.

4. **V=peak vs V=5**: this calibration uses V=5 as the representative mid-value (L≈0.58).
   Some hues peak in chroma at V=6–7. A future pass could take C_max across V=4–7 instead.
