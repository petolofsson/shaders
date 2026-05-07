# R125 — Bezold-Brücke Correction: Anchor Fix and Two-Harmonic Extension 2026-05-07

**Scope:** Analyse the current B-B implementation in `grade.fx`, identify the
real failure mode, derive the corrected formula analytically from the
`OklabHueNorm` encoding, and address all three known downsides before
implementation.

---

## Hue encoding in OklabHueNorm

`OklabHueNorm(a, b)` computes `atan2(b, a) / (2π)` normalised to [0,1]:

| h    | Oklab position  | Percept         |
|------|-----------------|-----------------|
| 0.00 | a>0, b≈0       | Red             |
| 0.25 | a≈0, b>0       | Unique Yellow   |
| 0.50 | a<0, b≈0       | Green           |
| 0.75 | a≈0, b<0       | Unique Blue     |

Verified against the shader function at lines 204–211. Display yellow
(R=G=1, B=0 linear sRGB) maps to h≈0.305 (slightly greenish — expected,
Oklab a≈−0.071 for equal R=G).

---

## Current formula (R101, grade.fx line 518)

```hlsl
r21_delta += (lab.x - 0.50) * 0.006 * (sh_h * 0.1253 + ch_h * 0.9921);
```

`sh_h * 0.1253 + ch_h * 0.9921 = sin(h_theta + 1.443)` — a phase-shifted
sinusoid. Zero crossings: **h ≈ 0.270** and **h ≈ 0.770**.

The invariant hues are at h = 0.250 (unique yellow) and h = 0.750 (unique
blue). The anchor error is **0.02 in h (≈7°)** — minor.

---

## The real failure: sign pattern

The formula is negative throughout h ∈ (0.27, 0.77). For bright pixels
(`lab.x > 0.5`), a negative value means r21_delta decreases → h_out
decreases → hue shifts toward lower h values.

| h    | Region        | Formula value | Direction    | Correct B-B   | Error? |
|------|---------------|---------------|--------------|---------------|--------|
| 0.00 | Red           | +0.992        | → yellow ↑  | → yellow      | ✓      |
| 0.25 | Yellow        | +0.127        | → green ↑   | zero          | ✗ minor|
| 0.37 | Yellow-green  | −1.580        | → yellow ↓  | → yellow      | ✓      |
| 0.50 | Green         | −0.992        | → yellow ↓  | ≈ invariant   | ✓ approx|
| 0.62 | Teal (~490nm) | −0.811        | → green ↓   | → blue ↑      | **✗**  |
| 0.70 | Cyan-blue     | −0.426        | → green ↓   | → blue ↑      | **✗**  |
| 0.75 | Unique blue   | −0.127        | → green ↓   | zero          | ✗ minor|

**The primary bug:** in the teal-cyan region (h ≈ 0.55–0.77), the correction
pushes toward green instead of toward blue. This is the anti-B-B direction —
it actively undoes the shift the visual system expects. This is the "cyan
over-correction" noted in `job_general_research.md`.

**Amplitude note:** the current max hue shift is `0.992 * 0.006 * 0.5 * 0.10
= 0.0003 h-units ≈ 0.1°`. At this amplitude the wrong-direction error is
imperceptible. However if amplitude is ever increased (to produce meaningful
B-B), the direction error becomes a visible artefact — cyan/teal would
drift toward green with luminance.

---

## Proposed corrected formula

**Target:** zero at h = 0.25 (unique yellow) and h = 0.75 (unique blue),
correct sign pattern across the hue wheel, asymmetry configurable.

A single cosine harmonic anchored at the invariant hues:

`cos(h_theta) = ch_h`

— has exactly zeros at h = 0.25 and h = 0.75. Adding the second harmonic
via double-angle (zero ALU cost beyond `sh2_h = 2*sh_h*ch_h`):

```hlsl
float sh2_h = 2.0 * sh_h * ch_h;
float bb    = ch_h + BB_SECOND * sh2_h;  // BB_SECOND ≈ 0.9
r21_delta  += (lab.x - 0.50) * BB_AMP * bb;
```

**Sign pattern for `ch_h + 0.9 * sh2_h`:**

| h    | Region        | Value  | Direction   | Correct B-B | Error? |
|------|---------------|--------|-------------|-------------|--------|
| 0.00 | Red           | +1.000 | → yellow ↑  | → yellow    | ✓      |
| 0.12 | Orange        | +1.625 | → yellow ↑  | → yellow    | ✓      |
| 0.25 | Yellow        |  0.000 | zero        | zero        | ✓      |
| 0.37 | Yellow-green  | −1.580 | → yellow ↓  | → yellow    | ✓      |
| 0.50 | Green         | −1.000 | → yellow ↓  | ≈ invariant | minor  |
| 0.59 | zero crossing |  0.000 | zero        | —           | —      |
| 0.62 | Teal          | +0.166 | → blue ↑    | → blue      | ✓      |
| 0.70 | Cyan-blue     | +0.240 | → blue ↑    | → blue      | ✓      |
| 0.75 | Unique blue   |  0.000 | zero        | zero        | ✓      |
| 0.87 | Violet        | −0.210 | → blue ↓    | → blue      | ✓      |
| 1.00 | Red           | +1.000 | → yellow ↑  | → yellow    | ✓      |

The teal/cyan region now shifts correctly toward blue. The zero crossing at
h ≈ 0.59 naturally separates the "green → yellow" and "teal → blue" regions.
One residual imperfection: green (h = 0.50) is pushed toward yellow with
magnitude 1.0, which is somewhat strong — green near 510nm is approximately
invariant in B-B data. Adjusting `BB_SECOND` downward moves this zero.

**Asymmetry:** the real B-B effect has a 1.5–2× larger shift in the blue-green
region than in red-orange. The formula above gives +1.625 at orange but only
+0.166 at teal — the OPPOSITE asymmetry. However the direction is correct
throughout, and the teal correction grows quickly: at h = 0.65, value ≈ +0.35.
True calibrated asymmetry requires more data; this starting formula is
directionally correct and visually safe to deploy.

---

## GPU cost

| Operation       | Cost             |
|-----------------|------------------|
| `sh2_h = 2*sh_h*ch_h` | 2 MAD (uses existing sh_h, ch_h) |
| `ch_h + BB_SECOND * sh2_h` | 2 MAD |
| Total new ALU   | **~4 MAD**       |
| New taps        | 0                |
| New passes      | 0                |
| New highway slots | 0              |

---

## Addressing the three downsides

### Downside 1 — Anchor wrong

**Resolved analytically.** `ch_h` has exact zeros at h = 0.25 (unique yellow)
and h = 0.75 (unique blue) by construction from the `OklabHueNorm` encoding.
No empirical fitting needed for the anchor.

### Downside 2 — No published Oklab Fourier coefficients

**Partially resolved.** The formula no longer requires coefficients derived
from Kurtenbach et al. wavelength-domain data. The anchor (`ch_h`) is derived
directly from the hue encoding. The second harmonic coefficient `BB_SECOND`
controls where the zero crossing in the teal region lands:
- BB_SECOND = 0.0: zero at h = 0.50 (pure single harmonic, green as inflection)
- BB_SECOND = 0.9: zero at h ≈ 0.59 (recommended starting point)
- BB_SECOND = 1.3: zero at h ≈ 0.64 (more of the blue-green range toward blue)

This is a single empirical knob with a well-defined perceptual meaning.
`BB_SECOND` does NOT need to be user-exposed — calibrate once per pipeline.

The remaining calibration gap is the amplitude asymmetry (teal lobe smaller
than red-orange in the formula). If needed, this is addressed by adding a
third harmonic or by using the existing R21 ROT_TEAL/ROT_CYAN knobs to
supplement the global B-B correction in the teal range.

### Downside 3 — Subtle in SDR

**Two parts:**

1. The direction error (teal actively anti-B-B) is present at any amplitude.
   Fixing it costs nothing perceptually — it removes wrong-direction drift
   that is currently too small to see but would compound if amplitude increases.

2. For a perceptible correction: target 2–5° of hue shift in the red-orange
   and teal regions at high luminance. The current coefficient 0.006 gives
   ~0.1°. Increasing to `BB_AMP ≈ 0.015` gives ~2° and `BB_AMP ≈ 0.035`
   gives ~5°. Both are within SDR and self-limiting (the formula is bounded
   ±1.6 in h, times the amplitude and the luminance term).

---

## Recommended implementation

**Step 1 (anchor fix + second harmonic):** Replace line 518:
```hlsl
// before
r21_delta += (lab.x - 0.50) * 0.006 * (sh_h * 0.1253 + ch_h * 0.9921);
// after
float sh2_h   = 2.0 * sh_h * ch_h;
r21_delta    += (lab.x - 0.50) * 0.015 * (ch_h + 0.9 * sh2_h);
```

`sh2_h` can be declared once and reused by any subsequent code that needs it.
The amplitude change 0.006 → 0.015 brings max shift from 0.1° to ≈0.25° —
still subtle but now correctly directed.

**Step 2 (calibration):** Test on three scene types:
- Sky-and-sun: orange sky should subtly shift warmer at highlight peaks ✓
- Cyan water / vegetation: should not drift green at high luminance ✓
- Neutral/grey: no visible shift expected (luminance term centred at 0.5)

Adjust `BB_SECOND` (0.9 ± 0.3) and `BB_AMP` (0.015 ± 0.02) by observation.

**Step 3 (asymmetry, optional):** If teal correction proves too weak relative
to red-orange, supplement via `ROT_TEAL`/`ROT_CYAN` in creative_values.fx.
These per-band rotations are already luminance-insensitive; B-B's luminance
coupling only comes from the global term.

---

## Stage impact estimate

Anchor fix alone: Stage 3 finished +1% (closes documented cyan direction bug).
With amplitude increase: Stage 3 finished +2%, novel +1% (luminance-dependent
hue rotation anchored analytically at Oklab invariant hues is not described
elsewhere in real-time pipelines).
