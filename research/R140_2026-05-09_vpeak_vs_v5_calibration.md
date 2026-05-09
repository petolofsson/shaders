# R140 — V=peak vs V=5 Chroma Ceiling Calibration

**Date:** 2026-05-09
**Status:** Complete — no code changes
**Source data:** `coloria-dev/color-data` `munsell/real.dat` (same dataset as R138)
**Pages used:** Same angle-matched Munsell pages as R138

---

## Question

R138 calibrated `HB_CEIL_*` constants using V=5 (Oklab L ≈ 0.58) as the reference value.
Some hues peak in natural chroma at higher values (warm hues, V=7–9) or lower values
(cool hues, V=4). Should the ceilings use V=5, V=peak, or C_max across a range?

---

## Data: in-gamut Oklab C_max at V=4 through V=9

| Band    | Page   | Cur  | V=4   | V=5   | V=6   | V=7   | V=8   | V=9   | Peak  | Peak V | Δ cur |
|---------|--------|------|-------|-------|-------|-------|-------|-------|-------|--------|-------|
| Red     | 7.5R   | 0.24 | 0.212 | 0.236 | 0.188 | 0.113 | 0.056 | 0.022 | 0.236 | V=5    | −0.004 |
| Orange  | 7.5YR  | 0.13 | 0.107 | 0.130 | 0.137 | 0.159 | 0.093 | 0.035 | 0.159 | V=7    | +0.029 |
| Amber   | 2.5Y   | 0.12 | 0.107 | 0.116 | 0.140 | 0.146 | 0.170 | 0.075 | 0.170 | V=8    | +0.050 |
| Yellow  | 10Y    | 0.14 | 0.098 | 0.127 | 0.134 | 0.162 | 0.166 | 0.196 | 0.196 | V=9    | +0.056 |
| Green   | 10GY   | 0.16 | 0.129 | 0.159 | 0.190 | 0.221 | 0.255 | 0.179 | 0.255 | V=8    | +0.095 |
| Teal    | 5G     | 0.12 | 0.093 | 0.123 | 0.124 | 0.154 | 0.158 | 0.140 | 0.158 | V=8    | +0.038 |
| Cyan    | 7.5BG  | 0.15 | 0.062 | 0.091 | 0.093 | 0.121 | 0.125 | 0.138 | 0.138 | V=9    | −0.012 |
| Azure   | 2.5PB  | 0.13 | 0.105 | 0.128 | 0.157 | 0.127 | 0.072 | 0.017 | 0.157 | V=6    | +0.027 |
| Blue    | 7.5PB  | 0.19 | 0.263 | 0.207 | 0.161 | 0.114 | 0.065 | 0.015 | 0.263 | V=4    | +0.073 |
| Violet  | 10PB   | 0.22 | 0.294 | 0.217 | 0.155 | 0.111 | 0.064 | 0.014 | 0.294 | V=4    | +0.074 |
| Magenta | 7.5P   | 0.22 | 0.249 | 0.289 | 0.297 | 0.218 | 0.118 | 0.043 | 0.297 | V=6    | +0.077 |
| Rose    | 7.5RP  | 0.24 | 0.193 | 0.242 | 0.213 | 0.128 | 0.075 | 0.017 | 0.242 | V=5    | +0.002 |

---

## Key findings

### Two distinct hue families

**Warm hues peak in highlights (high V):**
Yellow, Green, Amber, Orange, Teal all peak at V=7–9. The V=5 ceiling sits well below
their natural maximum. The gap is largest for Green (+0.095) and Yellow (+0.056).

**Cool hues peak in shadows (low V):**
Blue and Violet peak at V=4 with C well above both V=5 and the current ceilings. The
current ceilings for Blue (0.19) and Violet (0.22) are already conservative relative to
both V=5 and V=peak — these ceilings come from the R118/MacAdam rationale, not Munsell V=5.

**Red and Rose peak at V=5:**
The calibration is exact for these two. V=5 is the correct reference.

**Cyan: current ceiling above V=peak:**
Current HB_CEIL_CYAN (0.15) exceeds the V=9 peak (0.138). The ceiling already permits
more saturation than any naturally occurring cyan-hue chip at any value. This reconfirms
the R138 open item — Cyan ceiling should be reviewed against its R118 rationale.

---

## Why V=peak is wrong as a luminance-independent ceiling

Using V=peak would set the Yellow ceiling to 0.196 and Green to 0.255. A
luminance-independent ceiling of 0.255 would permit that chroma at V=5, where the
Munsell data shows the natural maximum is only 0.159. The ceiling would be calibrated
to a condition (extreme highlight green) and applied uniformly at all luminance levels,
which is the opposite of what Munsell data supports.

A luminance-independent ceiling must use a single representative value. V=5 is the
principled choice: it is the mid-point of the perceptual value range and the most
common scene luminance.

---

## Why the upper arm is the correct solution — and why it is deferred

The data reveals an asymmetry in the current architecture:

- **R133 highlight rolloff** handles "chroma decreases in extreme highlights" per hue.
  Yellow's rolloff exponent (n=0.22) correctly keeps yellow chromatic deep into
  highlights because Munsell data shows that is natural.

- **HueCeil** handles "chroma cannot exceed what occurs in nature at this hue." But
  it is currently calibrated to V=5, so it imposes a mid-value constraint at all
  luminance levels.

For a highlight yellow at post-tonemapping L=0.85, the Munsell peak (V=9, C=0.196) is
the natural reference. The V=5 ceiling (0.14) will clip expansion that is in fact
natural at that luminance. The correct fix is a luminance-aware upper arm:
`HueCeil(hue, L)` that permits more chroma at high L for warm hues and more chroma at
low L for cool hues. This is structurally the same architecture as the deferred lower
arm from R138.

**Deferred because:**
1. Whether the ceiling actually fires on highlight warm pixels in practice depends on
   whether R133 has already reduced C below the ceiling before it is applied. This has
   not been measured. If R133 does its job, the upper arm adds no value.
2. The lower arm (shadows) and upper arm (highlights) should be designed and
   implemented together as one `HueCeil(hue, L)` function, not piecemeal.
3. Raising the ceiling via V=peak as a constant would be architecturally wrong
   (too permissive at mid-value), and the full luminance-aware solution is
   out of scope for a single session.

---

## Conclusion

**V=5 is the correct reference for the current single-value ceiling architecture.**
No constants change. The data is filed for future use when the luminance-aware
upper+lower arm is pursued.

If a future testbed measurement shows that HueCeil is firing on highlight warm pixels
at chroma levels where R133 has already done appropriate reduction, that is the trigger
to implement the full luminance-aware architecture. The V=4–9 per-band data above
provides the calibration input for that future pass.

---

## Open items carried forward

1. **HB_CEIL_CYAN** (0.15): above V=peak (0.138). R118 rationale review still pending.
2. **Blue/Violet conservative ceilings**: R118/MacAdam rationale — not addressed here.
3. **Full luminance-aware `HueCeil(hue, L)`**: upper arm (warm highlights) + lower arm
   (cool shadows). Prerequisite: measure empirically whether the ceiling currently fires
   on highlight warm pixels after R133 has run.
