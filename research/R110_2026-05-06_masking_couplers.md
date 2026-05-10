# Research Findings — Masking Couplers as Luminance-Dependent Chromatic Floor — 2026-05-06

## Status: Implemented. PRINT_STOCK * 0.008 * (1 − L/0.75)² shadow warm shift. R51 unchanged.

## Motivation

Spektrafilm models masking couplers as **negative dye absorption** in the unexposed film
base. They are not a fixed offset; they are consumed during development proportional to
local dye formation. In unexposed areas (shadows), the full masking coupler remains,
producing maximum orange-mask absorption. In fully exposed areas (highlights), coupler
is consumed by density formation, reducing the orange cast toward neutral.

This creates a **luminance-dependent warm bias**: shadows are warmest (full coupler),
highlights are neutral (coupler consumed). Currently our pipeline handles this with:
- **R83** — chromatic FILM_FLOOR: per-channel D-min pedestal `[1.02, 1.00, 0.97]`.
  This models the *minimum density* (unexposed processed base), not coupler consumption.
- **PRINT_STOCK** — global warm cast. Applied uniformly across all tones. Does not
  scale with local exposure.

Neither captures the luminance-dependent character of masking couplers. PRINT_STOCK
warm cast is identical in shadows and highlights; in reality the orange cast should
fade as highlights are reached.

---

## Physical model

Color negative film contains DIR masking couplers that form an orange-absorbing
compound throughout the emulsion before development. In chemistry terms:

- Unexposed, undeveloped: masking coupler intact → orange absorption present → film
  appears warm-orange when light passes through.
- Exposed + developed: silver development consumes coupler → proportionally to local
  dye density → orange absorption reduced in high-density (shadow) areas of the *print*
  (which correspond to highlight areas of the *negative*).

For a **print stock** (Kodak 2383), the relationship is inverted relative to the
negative. The print is an optical positive: bright scene → dense negative → thin print
dye → print pixel is bright. The masking coupler in the print stock (if present) would
affect thin-dye (bright highlight) regions. However, 2383 is a *print* stock and does
not necessarily carry masking couplers in the same way as camera negative. The warm
character of 2383 in practice comes from:

1. The cumulative orange mask of the *negative* (e.g. Vision3 500T) transmitted through
   the optical printing process.
2. The spectral sensitivity of the 2383 paper and its dye characteristics.
3. Dye absorption overlap (R85 inter-channel bleed: cyan→green, magenta→blue).

**In our pipeline context:** The *effective* masking coupler of the full negative+print
chain produces a warm-shadow effect. Bright highlights of the final rendered image
correspond to heavily exposed print areas where little coupler remains → neutral.
Shadows of the final image correspond to lightly exposed print → full coupler → warm.

This is exactly the opposite of PRINT_STOCK's current behavior: PRINT_STOCK shifts
uniformly, equally affecting shadows and highlights.

---

## Proposed implementation

Add a luminance-modulated warm shift in the **CORRECTIVE** block, after CAT16 and
FilmCurve, before R19 3-way CC. It should:
- Be strongest in shadows (low `lab.x`)
- Fade to zero in highlights (high `lab.x`)
- Use PRINT_STOCK as its scaling knob (already the film stock character knob)
- Replace part of the current uniform PRINT_STOCK shift with this tonal version

```hlsl
// Masking coupler: shadow warm bias, fades in highlights
// physical source: unexposed coupler absorbs orange in low-density areas
float coupler_weight = saturate(1.0 - lab.x / 0.75);   // full in shadows, zero above L=0.75
float coupler_weight = coupler_weight * coupler_weight;  // square for faster fade at highlights

// Warm shift in Oklab (a = green-red axis, b = blue-yellow)
// Orange direction ≈ Oklab a: +0.01, b: +0.015 (warm orange quadrant)
// Scale by PRINT_STOCK (0.0–1.0 range) and a small physical constant
float coupler_str = PRINT_STOCK * 0.018;
lab.yz += float2(coupler_str * coupler_weight,           // a-channel: red push
                 coupler_str * 0.6 * coupler_weight);   // b-channel: yellow push (weaker)
```

Alternatively, if the shift is implemented in RGB space (simpler, after OklabToRGB):
```hlsl
float coupler_weight = saturate(1.0 - lab_x / 0.75);
coupler_weight *= coupler_weight;
// Direct RGB lift in shadows: warm lift (R+ B-)
lin.r += PRINT_STOCK * 0.015 * coupler_weight;
lin.b -= PRINT_STOCK * 0.010 * coupler_weight;
```

This separates masking coupler (tonal, shadow-biased) from PRINT_STOCK's current
uniform role. The question of rebalancing is critical: if we add coupler_weight without
reducing the uniform PRINT_STOCK contribution, the total warm cast will increase.

**Rebalancing strategy:** Keep PRINT_STOCK at its current value. The uniform shift
that PRINT_STOCK currently applies should be reduced by an amount equal to the
shadow-weighted average of coupler_weight (roughly 0.4 at current knob 0.40). In
practice: leave the uniform PRINT_STOCK term at ~60% of current weight, add the
tonal term for the remaining 40%. This keeps the overall scene-average warm cast
constant while re-shaping it tonally.

---

## Interaction with existing terms

| Term | Current behavior | After R110 |
|------|-----------------|------------|
| PRINT_STOCK | Uniform warm shift all tones | ~60% weight, remainder redistributed to tonal |
| R83 FILM_FLOOR | Per-channel shadow pedestal (D-min) | Unchanged |
| R85 dye masking | Fixed %: cyan→green, magenta→blue | Unchanged |
| R19 3-way CC | SHADOW/MID/HIGHLIGHT_TEMP | Unchanged |

There is an overlap risk with R19 SHADOW_TEMP (currently -5): both shift shadow
temperature. Confirm that the masking coupler term at PRINT_STOCK=0.40 with the
rebalanced PRINT_STOCK does not double-shift shadows excessively. Zero-everything
diagnostic (zero R110, zero R19) may be needed.

---

## Calibration targets

From Kodak 2383 spectral data (spektrafilm R110 ref): at D-min (unexposed base),
the transmission spectrum peaks warm by ~8–12% in red vs. blue. At D-max (full
density), this disappears (dye absorption dominates). In our SDR pipeline, shadows
sit at `lab.x ≈ 0.1–0.3`, highlights at `0.8–1.0`. The `coupler_weight` ramp from
1.0 to 0.0 between L=0.0 and L=0.75 correctly spans this range.

At PRINT_STOCK=0.40: maximum shadow warm shift would be `0.40 × 0.018 ≈ 0.007` in
Oklab a (roughly +1.5% red gain in shadows). Perceptually subtle but consistent with
the real photochemical difference.

---

## Risks

1. **Zero-everything diagnostic required.** Before enabling, confirm with all knobs
   zeroed (PRINT_STOCK=0, SHADOW_TEMP=0) that the tonal term produces a clean warm-
   shadow shift with no unexpected hue rotation at other tonal zones.
2. **Interaction with R47 (removed):** R47 (shadow auto-temp) was removed because it
   fought the explicit grade. This proposal is a *fixed* (non-adaptive) shadow warm
   bias, not scene-adaptive. Ensure the distinction is maintained — coupler_weight
   must not use any histogram or scene stats.
3. **PRINT_STOCK rebalancing calibration.** The 60%/40% split is approximate. Measure
   p50 and warm_bias at MIST_STRENGTH=0, VEIL_STRENGTH=0 before and after to verify
   scene-average warm cast is unchanged.

---

## GPU cost

| Item | Cost |
|------|------|
| `coupler_weight` derivation (1 sub, 1 sat, 1 mul) | 3 ALU |
| Oklab shift (2 fma) | 2 ALU |
| Total | ~5 ALU |

Zero new taps. Runs inside ColorTransformPS before OklabToRGB.

---

## Targets

- Stage 1 finished: +3% (physically derived tonal warm-shadow model vs. flat shift)
- Stage 1 novel: +4% (first real-time implementation of exposure-dependent masking
  coupler warm bias in post-process — no published game post-process does this)

---

## References

- Spektrafilm couplers.py — `compute_density_curves_before_dir_couplers()`,
  `compute_dir_couplers_matrix()` — separation of masking vs DIR couplers. Dev 2026.
- Spektrafilm README — masking coupler description: "negative absorption contribution
  in isolated dye absorption spectra."
- Hunt, R.W.G. *The Reproduction of Colour* 6th ed., Ch. 15 — masking coupler
  chemistry: coupler consumed proportional to silver development.
- Giorgianni & Madden, *Digital Color Management* 2nd ed. §6.3 — color negative
  spectral transmission and orange mask origin.
- R83 (2026-05-03): chromatic FILM_FLOOR per D-min ratios `[1.02, 1.00, 0.97]`.
- R85 (2026-05-03): inter-channel dye masking (cyan→green 2.0%, magenta→blue 2.2%).
- PLAN.md — R47 removed (shadow auto-temp, scene-adaptive, caused orange feedback loop).
  R110 is intentionally non-adaptive to avoid that failure mode.
