# R183 — Tone Mapping & Film Sensitometry — 2026-05-11

## Domain
Monday rotation: Tone mapping & film sensitometry (2023–2026 literature sweep).

---

## Primary finding: ACES 2.0 highlight chroma compression in Oklab

### Source
ACES 2.0 Output Transform (released 2024), chroma-compression design documents:
- https://docs.acescentral.com/system-components/output-transforms/technical-details/chroma-compression/
- https://community.acescentral.com/t/chroma-compression-explained/5083

### What it is
ACES 2.0 introduces a hue-preserving, lightness-dependent colorfulness compression as a
mandatory stage of its display rendering transform. Operating in Hellwig 2022 JMh space:

- **J and h are frozen**; only M (colorfulness / chroma magnitude) is compressed.
- Compression is a monotonically increasing function of J: shadows unchanged, highlights
  progressively desaturated.
- A "toe on the M axis" means *less-saturated* colours are compressed *more* aggressively
  than highly-saturated ones. The effect: near-neutral highlights bleach toward white first,
  while a pure scarlet or cyan resists much longer.
- Mathematically: M_scaled = M·(J_t/J)^(1/cz); then an invertible toe function is applied
  whose steepness scales with (1 − J_t/J_max).

### Physical motivation (film sensitometry)
In colour negative film the three emulsion records (cyan, magenta, yellow) each follow an
H&D characteristic curve with a finite shoulder. As scene luminance climbs into the exposure
shoulder, all three records approach their D-max simultaneously and at converging rates. The
differential colour information collapses — highlights desaturate toward neutral grey or
paper-white regardless of original hue. This is the physical basis of ACES 2.0's M-axis toe:
more desaturated highlight colours are already closer to the neutral axis, so they complete
the collapse first.

### Gap in current pipeline
The CHROMA stage currently has (in order):
1. R22 sat-by-luma — **shadow arm only** (highlight arm was removed; comment at grade.fx:507
   states "R133 HueBandRollN() owns highlight desaturation").
2. R133 Munsell per-hue rolloff — per-band amplitude ceiling, 12 discrete hue bands.
3. Chroma attraction (complementary to R73 ceilings).
4. R73 HueCeil hard ceilings — hue-specific hard maximum.
5. R68B gamut pre-knee → R78 gclip.

**Neither R133 nor R73 models the hue-agnostic, continuously progressive lightness→chroma
compression of ACES 2.0.** R133 manages *which hues roll off and at what amplitude* (based
on Munsell empirical data); R73 sets *hard per-hue ceilings*. Neither applies a smooth
global desaturation that grows with L and targets near-neutral highlights first.

The removed R22 highlight arm left this space empty. The ACES 2.0 design, adapted to
Oklab, fills it with physical backing.

### Oklab adaptation (SDR-only, no HDR machinery needed)
The ACES 2.0 formula uses Hellwig J and AP1-gamut-cusp lookups for HDR peak-luminance
scaling. For this pipeline (SDR, display-referred, Oklab throughout) those drop out:

- Replace J with Oklab **L** (0 = black, 1 = white). The monotonic rise is equivalent.
- Replace M with Oklab **C** = `length(a, b)`. Hue angle is automatically preserved when
  a and b are scaled uniformly.
- The AP1 gamut cusp and L_peak terms are HDR-only; remove them.
- The "toe on M" becomes a Michaelis-Menten factor on C: `C_ref / (C + C_ref)`, where
  C_ref ≈ 0.20 (typical scene chroma in Oklab for sRGB-gamut content). This factor → 1
  for near-neutral pixels (C ≪ C_ref) and → 0 for deeply saturated pixels (C ≫ C_ref).

### Implementation sketch

```hlsl
// R183: ACES 2.0-inspired highlight chroma rolloff — film shoulder desaturation
// Hue-agnostic; preserves hue angle; acts only in highlights, grows with L.
// Insert in ColorTransformPS, CHROMA stage, after R73 HueCeil and before gamut pre-knee.

float L_ok   = col_oklab.x;             // Oklab L ∈ [0..1]
float C      = length(col_oklab.yz);    // chroma magnitude
float C_ref  = 0.20;                    // knee of the "toe on C" — tune if needed

// Lightness factor: smooth quadratic, 0 at black, 1 at white (no hard threshold).
float lf     = L_ok * L_ok;

// Toe on the chroma axis: desaturated highlights compressed more than saturated ones.
float c_toe  = C_ref / max(C + C_ref, 1e-5);

// Net suppression ∈ [0, HCHROMA_ROLLOFF]: highlights × near-neutral = most compressed.
float suppress = lf * c_toe * HCHROMA_ROLLOFF;   // knob 0..1, default 0

// Scale a and b, preserving hue angle.
col_oklab.yz *= max(0.0, 1.0 - suppress);
```

**Knob:** `HCHROMA_ROLLOFF` (float, 0.0–1.0, default 0.0) in `creative_values.fx`.

**Insertion point:** `general/grade/grade.fx`, ColorTransformPS, between the R73 ceiling
block (~line 578) and the gamut pre-knee block (~line 639). At this position, R73's hard
per-hue ceilings have already run — the new compression smoothly reduces whatever chroma
remains in the highlights before gclip finalises the gamut boundary.

### GPU cost
- 2 ALU: `L_ok * L_ok`, `length(a,b)`.
- 1 RCP/div: `C_ref / (C + C_ref)`.
- 2 MUL, 1 saturate-like max, 1 vec2 scale.
- **Total: ~7 scalar ALU, 0 texture taps.** Negligible.

### Conflict check
| Rule | Status |
|------|--------|
| No hard conditionals / smoothstep gates | ✓ — `L²` and Michaelis-Menten are continuous |
| SDR by construction | ✓ — suppress ∈ [0,1], C only decreases |
| No auto-exposure | ✓ |
| creative_values.fx only tuning surface | ✓ — one knob `HCHROMA_ROLLOFF` |
| No HDR-only technique | ✓ — J/M → L/C substitution removes all HDR terms |
| Doesn't conflict with R133 Munsell | ✓ — R133 fires earlier; this is a second pass |
| Doesn't conflict with R73 ceilings | ✓ — R73 fires before this; no ordering hazard |
| Highway row y=0 guard | n/a — no BackBuffer write |

### Suggested default tuning
At `HCHROMA_ROLLOFF = 0.35`:
- L=0.5, C=0.04 (pastel mid-tone): suppress ≈ 0.25 × 0.83 × 0.35 ≈ 0.073 → −7% chroma.
- L=0.85, C=0.04 (bright near-neutral): suppress ≈ 0.72 × 0.83 × 0.35 ≈ 0.209 → −21% chroma.
- L=0.85, C=0.35 (bright saturated): suppress ≈ 0.72 × 0.36 × 0.35 ≈ 0.091 → −9% chroma.
- L=0.95, C=0.02 (near-white): suppress ≈ 0.90 × 0.91 × 0.35 ≈ 0.287 → −29% chroma.

Near-neutral highlights bleed toward white (film-accurate); deeply saturated highlights
retain most of their chroma (preserving the original look intent).

---

## Secondary finding: spektrafilm masking coupler model (reference for R85 future work)

### Source
- https://github.com/andreavolpato/spektrafilm (active dev; last commit ≈2026-05)
- https://discuss.pixls.us/t/spectral-film-simulations-from-scratch/48209

### What it is
A fully spectral simulation of the negative+print pipeline, including masking couplers:
"Masking couplers give the typical orange color to unexposed developed film and are consumed
locally where density is formed to reduce the effect of cross-talk in layer absorption, thus
increasing saturation." The model represents this as a **negative absorption contribution**
in each dye's isolated spectral curve — local to the exposure region that formed density.

### Relevance
R85 implements inter-channel dye masking as fixed linear cross-feeds (cyan→green 2.0%,
magenta→blue 2.2%). The spektrafilm model shows that real masking couplers are density-
proportional and produce negative (anti-masking) contributions outside the primary layer.
A fuller model could be a 3×3 log-density cross-channel matrix with both positive and
negative off-diagonal terms, driven by the per-channel log-density values from R84's curve.

### Pipeline feasibility
A 3×3 log-density matrix is ~18 ALU at 0 tex taps. The coupling strengths would need
calibration against published Kodak Vision3 / Fuji Eterna masking data (not trivially
available, but the chookindustries.com Kodak Film Essentials PDF contains partial data).

### Recommendation
**File as future work** pending density data acquisition. Not proposing implementation now —
R85 is adequate, and the gain is incremental relative to the calibration effort required.

---

## Exclusions verified (nothing in this session re-proposes excluded items)
- No clarity/sharpening, no grain, no LCA, no HDR-only, no CIECAM02 surround.
- OPT-2/3 not touched.
- R22 highlight arm: not re-proposing the removed arm — R183 is a different mechanism
  (J-dependent desaturation, not a luma–saturation lookup).
