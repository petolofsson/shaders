# R43 — Energy-Normalised Wavelet Packet Clarity Weights
**Date:** 2026-04-30
**Type:** Proposal
**Source:** R42 lateral research — Telecommunications (wavelet packet best-basis theory)
**ROI:** Medium — ~5 ALU, zero new passes, better clarity behaviour on mixed-content
scenes (sharp edges + smooth gradients in the same frame)

---

## Problem

The current clarity wavelet decomposition uses fixed weights:

```hlsl
float detail = D1 * 0.50 + D2 * 0.30 + D3 * 0.20;
```

These weights are fine-biased regardless of local signal content:
- On sharp edges, D1 (full-res → 1/8-res residual) is large and the 0.50 weight
  is appropriate — fine detail is dominant.
- On smooth gradients or soft surfaces, D1 is small (no fine texture), D2 and D3
  carry the meaningful signal — but 0.30/0.20 still under-weight them.
- In uniform areas (sky, walls), all three bands are near zero and the fixed weights
  do not matter — but the composition is still incorrect relative to what the signal
  actually contains.

The Retinex illumination weights in the same pass are correctly **coarse-biased**
(0.20/0.30/0.50) because coarse scale is the better illumination estimate. Clarity
should be locally adaptive — fine-biased where fine detail exists, coarse-biased
where it does not.

---

## Solution — Wavelet Packet Best-Basis energy normalisation

In telecom subband coding (wavelet packet decomposition), the best-basis algorithm
selects subbands by their signal energy fraction. Applied per-pixel, this gives a
locally adaptive weighting that requires no lookup, no texture tap, and no knob:

```hlsl
float e1    = D1 * D1;
float e2    = D2 * D2;
float e3    = D3 * D3;
float e_sum = max(e1 + e2 + e3, 1e-6);
float detail_wp = D1 * (e1 / e_sum) + D2 * (e2 / e_sum) + D3 * (e3 / e_sum);
```

The energy fraction `ei/e_sum` acts as the per-band weight. Properties:
- **Sharp edge pixel:** D1 >> D2 >> D3 → e1 dominates → weight ≈ (1, 0, 0) → detail_wp ≈ D1. Fine-biased, same as current.
- **Soft surface pixel:** D1 ≈ D2 ≈ D3 → weights ≈ (0.33, 0.33, 0.33) → blended. More coarse weight than fixed 0.50/0.30/0.20.
- **Smooth gradient:** D3 >> D1, D2 → weight ≈ (0, 0, 1) → detail_wp ≈ D3. Coarse signal only — prevents amplifying nothing as if it were texture.
- **Uniform area:** all near 0 → e_sum clamped, weights arbitrary → detail_wp ≈ 0. Correct: no signal to sharpen.

---

## Implementation

`grade.fx` — lines 261–264:

**Current:**
```hlsl
float D1     = luma - illum_s0;
float D2     = illum_s0 - illum_s1;
float D3     = illum_s1 - illum_s2;
float detail = D1 * 0.50 + D2 * 0.30 + D3 * 0.20;
```

**Replacement:**
```hlsl
float D1     = luma - illum_s0;
float D2     = illum_s0 - illum_s1;
float D3     = illum_s1 - illum_s2;
float e1     = D1 * D1;
float e2     = D2 * D2;
float e3     = D3 * D3;
float e_sum  = max(e1 + e2 + e3, 1e-6);
float detail = D1 * (e1 / e_sum) + D2 * (e2 / e_sum) + D3 * (e3 / e_sum);
```

All downstream uses of `detail` (line 270 luma clarity, line 326 chroma co-boost)
consume this value unchanged — no other edits required.

---

## Risk

**Sign preservation:** `detail_wp` preserves the sign of the dominant band. If D1
is positive (pixel brighter than local base), `detail_wp` is positive → clarity
adds brightness. If D1 is negative (pixel darker), `detail_wp` is negative →
clarity subtracts. Correct behaviour in both cases.

**Uniform-area numerical safety:** `e_sum` clamped to 1e-6. At e_sum = 1e-6 and
D1 = D2 = D3 = 0, `detail_wp = 0`. Safe.

**Range:** In the worst case (all energy in one band), `detail_wp = Di`. Maximum
magnitude equals the maximum single-band residual — same range as the current
`detail` variable. No clipping risk.

**Interaction with R44 (bell replacement):** These two proposals are designed to
compose. R44 replaces the bell function using `detail_wp` as input. Implementing
R43 alone (with the existing bell) is valid and produces no regression.

---

## Success criteria

- Fixed weights `0.50 / 0.30 / 0.20` replaced with energy-normalised per-pixel weights
- Sharp edge content: clarity behaviour unchanged (D1-dominant → same fine boost)
- Smooth surface content: clarity draws more from coarse bands → less false fine-grain noise
- Uniform areas: detail ≈ 0 → clarity ≈ 0 → no noise amplification
- No new passes, no new taps, no new knobs
- Net ALU delta: +5 (3 multiplies, 1 add, 1 max, 3 divides via multiply-reciprocal)
