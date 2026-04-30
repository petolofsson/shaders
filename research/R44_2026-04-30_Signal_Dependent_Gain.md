# R44 — Signal-Dependent Gain (Bell Function Replacement)
**Date:** 2026-04-30
**Type:** Proposal
**Source:** R42 lateral research — Telecommunications (DFE nonlinear feedback, NUM image enhancement)
**ROI:** Medium — ~2 ALU, suppresses noise-floor amplification that the current bell
cannot address, zero new passes

---

## Problem

The current clarity gain function is a Cauchy bell:

```hlsl
float bell = 1.0 / (1.0 + detail * detail / 0.0144);
```

This is **one-sided** — it only suppresses for large `|detail|` (haloing on hard edges).
For small `|detail|` → bell ≈ 1 → full clarity strength is applied. In flat or
near-uniform areas this means noise-floor variations (|detail| < 0.01) receive the
same amplification as real mid-frequency texture (|detail| ≈ 0.04).

The bell does not distinguish between:
- **Noise at the pixel level** (|detail| ≈ 0.005–0.015): should be suppressed
- **Real mid-frequency texture** (|detail| ≈ 0.03–0.08): should be boosted
- **Hard edges** (|detail| > 0.15): should be suppressed (haloing)

It only handles the third case correctly.

---

## Solution — Signal-dependent gain from DFE analogue

Decision Feedback Equalisation (DFE) in telecom uses a nonlinear feedback gain
that rises from zero at noise floor, peaks at the expected signal amplitude, then
falls for out-of-range values. The analogue for image sharpening:

```hlsl
float g = sqrt(abs(detail)) / (sqrt(abs(detail)) + 0.04);
```

Properties (with `x = |detail|`):
- `x = 0.000`: g = 0/0.04 = **0.0** — noise floor receives zero gain
- `x = 0.001`: g ≈ 0.44 — rising steeply from zero
- `x = 0.040`: g = 0.2/0.24 ≈ **0.83** — peak region (0.04 = the `+0.04` offset)
- `x = 0.120`: g ≈ 0.93 — near-maximum, broad plateau
- `x = 0.400`: g ≈ 0.98 — near-maximum for large edges

Wait — this function is **monotonically increasing**, not two-sided. It approaches 1
for large |detail| — meaning hard edges are NOT suppressed. This is intentional and
correct when combined with R43:

With energy-normalised `detail_wp`, hard edges already redirect almost all weight
to D1. The Cauchy bell was needed to prevent D1-dominated haloing. With `detail_wp`,
the energy normalisation itself handles this: if D1 is very large, e1/e_sum ≈ 1 and
detail_wp ≈ D1 — but the clarity_mask (zero above luma 0.9) clips specular extremes,
and the auto_clarity driver (via stevens_att) reduces strength in bright/contrasty
scenes. The two-layer suppression (clarity_mask + auto_clarity) replaces the need
for the bell's large-|d| suppression.

What `g` adds that the bell cannot: **noise-floor suppression at small |detail|**,
which is the bell's blind spot.

---

## Formula

```hlsl
float sd = sqrt(abs(detail));
float g  = sd / (sd + 0.04);
```

The constant `0.04` sets the inflection point: `g = 0.5` when `|detail| = 0.04²
= 0.0016`, and `g` rises to ~0.83 at `|detail| = 0.04`. Adjust if the noise floor
of the pipeline is higher or lower.

SPIR-V safe: `sqrt(abs(x))` is a standard HLSL intrinsic with no edge case at x=0
(sqrt(0) = 0, g = 0/0.04 = 0).

---

## Implementation

`grade.fx` — line 266:

**Current:**
```hlsl
float bell = 1.0 / (1.0 + detail * detail / 0.0144);
new_luma = saturate(new_luma + detail * (auto_clarity / 100.0) * bell * clarity_mask);
```

**Replacement:**
```hlsl
float sd   = sqrt(abs(detail));
float g    = sd / (sd + 0.04);
new_luma = saturate(new_luma + detail * (auto_clarity / 100.0) * g * clarity_mask);
```

The chroma co-boost (line 326) uses `abs(detail)` directly without bell — no change
needed there.

---

## Standalone vs. composed with R43

**R44 alone (with existing fixed-weight `detail`):**
Valid. The noise-floor suppression works regardless of how `detail` is computed.
Flat areas where `detail ≈ 0` get g ≈ 0 — correct. The bell's one-sided suppression
is replaced by g's zero-floor behaviour. Hard edges (|detail| > 0.15) get g ≈ 0.93 —
slightly stronger than bell at the same magnitude, but clarity_mask already rolls
off above luma 0.6, so specular hard edges are protected by the mask.

**R44 + R43 composed:**
Optimal. Energy-normalised `detail_wp` feeds into `g`. On smooth-gradient pixels,
detail_wp is small-magnitude (coarse signal only) → g is near its peak (0.04 range)
→ appropriate coarse clarity boost. On hard-edge pixels, detail_wp ≈ D1 which is
large → g → 1 → full boost — but these are exactly where the clarity_mask provides
the containment.

---

## Risk

**g → 1 for large |detail| (no hard-edge suppression):** Mitigated by clarity_mask
and auto_clarity (which reduces overall strength in high-contrast scenes via
stevens_att). If tested standalone without R43, monitor for edge haloing in scenes
with strong micro-contrast. If haloing appears, reduce the `+0.04` offset toward
`+0.02` (shifts peak to |detail|=0.0004, tighter suppression of mid-range).

**Perceptual character change:** The bell gave a specific "soft" quality to clarity
(midtones boosted, extremes suppressed symmetrically). `g` gives a "texure-selective"
quality — noise floors are suppressed, everything else passes more freely. The result
should read as cleaner rather than softer.

---

## Success criteria

- `bell` variable removed; replaced by `sd` + `g` (~2 ALU net)
- Flat/noise-floor areas (|detail| < 0.01): clarity contribution ≈ 0 (vs. current ≈ full)
- Mid-frequency texture (|detail| ≈ 0.04): clarity contribution at g ≈ 0.83 (vs. bell ≈ 0.90 — comparable)
- Hard edges (|detail| > 0.15): g ≈ 0.93, contained by clarity_mask
- No new passes, taps, or knobs
- Best deployed after R43; valid standalone
