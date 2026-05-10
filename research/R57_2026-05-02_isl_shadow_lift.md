# R57 — ISL Shadow Lift

**Date:** 2026-05-02
**Status:** Proposal — needs findings before implementation.

---

## Motivation

The current shadow lift term in `ColorTransformPS` (`grade.fx`) uses an exponential
falloff driven by local illumination:

```hlsl
float shadow_lift = SHADOW_LIFT * 25.19 * exp(-5.776 * illum_s0) * local_range_att;
```

The exponential `exp(-k·illum)` decays smoothly but has no physical basis — it was
tuned empirically. The inverse square law offers a physically grounded alternative:
light intensity falls as `1/r²` from a source, so pixels at luminance `L` are
implicitly "at distance" proportional to `1/√L` from the nearest light. Shadow lift
applied proportionally to that distance would then scale as `1/L`:

```
lift ∝ 1 / (illum² + ε)
```

For jungle/canopy scenes this distinction matters. Dappled canopy light creates pools
of bright patches separated by deep shadow. The exponential treats a shadow at luma
0.05 and one at luma 0.12 relatively similarly; ISL applies roughly 5× more lift to
the darker shadow. This better matches the actual perceptual need — deep inter-patch
shadows need aggressive detail recovery, penumbra pixels near a bright patch need much
less.

---

## Physics note

ISL (`1/r²`) describes point-source falloff in free space. It is not the right model
for atmospheric extinction (Beer-Lambert exponential) or for participating media like
fog or jungle haze. However, as a proxy for "how far is this pixel from a light
source" it is coherent: if we treat scene luminance as a linear measure of received
irradiance, then ISL says irradiance ∝ 1/r² → r ∝ 1/√L → lift ∝ r² ∝ 1/L. The
`1/(illum²)` form follows directly.

---

## Proposed implementation

Replace the exponential factor in the shadow lift term inside `ColorTransformPS`:

**Current (`grade.fx`, shadow lift block):**
```hlsl
float shadow_lift = SHADOW_LIFT * 25.19 * exp(-5.776 * illum_s0) * local_range_att;
```

**Proposed:**
```hlsl
float isl_lift    = 1.0 / (illum_s0 * illum_s0 + ISL_EPS);
float shadow_lift = SHADOW_LIFT * ISL_K * isl_lift * local_range_att;
```

Where:
- `ISL_EPS` — regularisation constant preventing divergence as `illum_s0 → 0`.
  Determines how aggressively lift fires in absolute black. Candidate range: 0.002–0.02.
- `ISL_K` — normalisation scalar. Must be chosen so that the lift magnitude at a
  reference shadow level (p25 ≈ 0.08 in a typical scene) is comparable to today's
  output, preserving the calibrated `SHADOW_LIFT` scale. Candidate: derive from
  `25.19 * exp(-5.776 * 0.08) / (1 / (0.08² + ISL_EPS))` at the reference point.

Both constants are internal — not exposed in `creative_values.fx`. `SHADOW_LIFT`
remains the single user knob.

---

## Risk: clipping at the toe

`1/(illum²)` diverges as illumination approaches zero. Pixels at exactly 0 (after
`FILM_FLOOR` is applied, the floor is 0.005, so true zero should not exist) could
still receive very large lift values. The result must pass through `saturate()` before
it reaches the output, which is already the case in the current stage. Verify that
`ISL_EPS` is tuned so that at `illum = FILM_FLOOR (0.005)` the lift does not push a
near-black pixel above the shadow midtone range (~0.15).

---

## Research tasks

1. Read the current shadow lift block in `grade.fx` in full — identify exact line
   numbers, what `illum_s0` is (which texture, which channel), and what
   `local_range_att` is doing.
2. Compute the exponential curve vs ISL curve numerically at representative shadow
   levels (0.01, 0.03, 0.05, 0.08, 0.12, 0.18) to confirm ISL gives meaningfully
   different shape and not just a rescaled version of the same falloff.
3. Find `ISL_K` and `ISL_EPS` values that preserve the reference lift magnitude at
   p25 ≈ 0.08 under a typical scene.
4. Assess whether the steeper ISL rolloff causes any visible step artefact at the
   shadow/midtone boundary — the current exponential is very smooth; ISL is smooth
   but steeper.
5. Test in a jungle/canopy scene (GZW) and a neutral interior (Arc Raiders) — confirm
   the ISL lift helps dappled shadows in GZW without over-lifting AR's indoor shadows.
