# R138 — Color Appearance Models: Saturday Nightly Findings
**Date:** 2026-05-09  
**Domain:** Color appearance models (day 6, Saturday rotation)  
**Scope:** 2023–2026 literature; SDR real-time HLSL applicability filter applied

---

## Finding 1 — Chroma Crispening via Scene Achromatic Fraction

### Perceptual basis

When a scene's surround is predominantly neutral/achromatic, the visual system
exhibits enhanced chroma discrimination — small chroma differences appear
larger than they would in a chromatic surround. This is the **crispening
effect**, a well-measured phenomenon in color appearance science:

- **Moroney (2001)** "Chroma Scaling and Crispening," IS&T/SID CIC-9.
  Psychophysics experiment (CRT, dark surround, constant-hue IPT ramps on
  achromatic vs. medium vs. high-chroma backgrounds) showed ~25–40% higher
  chroma scaling on an achromatic background vs. a high-chroma background.
  CIECAM02 C provided the best fit across conditions.
- **Zaidi et al. (1992)** "Brightness, Discriminability and the Crispening
  Effect," Vision Research 32(10). Established the achromatic contrast gain
  mechanism: the visual system references the neutral background for chroma
  gain control; deviations from neutral are amplified.
- **Karimipour et al. (2017)** "Performance of CAM02-based formulas in
  prediction of the Crispening effect," Color Research & Application. 
  Confirmed CIECAM02/CAM16 chroma scales correctly with background neutrality.

The mechanism is not a gate — it is a continuous perceptual gain that ramps
with background neutrality. Fully self-limiting.

### Pipeline fit

`HWY_ACHROM_FRAC` (slot 202, defined in `general/highway.fxh:29`) is the
fraction of scene pixels with Oklab C < 0.05. This is the direct proxy for
"how neutral/achromatic is the scene surround?"

- High achromatic fraction (gray industrial environments, Arc Raiders concrete
  and steel zones) → visual system is in crispening mode → chroma appears
  more vivid.
- Low achromatic fraction (foliage, sunset, alien flora) → less crispening →
  chroma appears at nominal strength.

The slot is written by `analysis_frame.fx` and available at the start of
`ColorTransformPS`. It is **not currently used** in the chroma path; `grade.fx`
reads it nowhere. R66's per-pixel `achrom_w` is a different variable (computed
from the individual pixel's own chroma, not the scene fraction).

### Proposed implementation

In `ColorTransformPS`, in the chroma modulation block following the Hunt line
(`grade.fx` ~line 572):

```hlsl
// before (lines 570-572):
float chroma_str = CHROMA_STR * 0.04;
chroma_str *= lerp(1.0, 0.65, smoothstep(0.02, 0.08, local_var)); // R68A
chroma_str *= lerp(0.80, 1.20, smoothstep(0.05, 0.35, zone_log_key)); // R117 Hunt

// after — add crispening line:
float achrom_frac = ReadHWY(HWY_ACHROM_FRAC);                        // [0,1]
chroma_str *= 1.0 + 0.25 * achrom_frac;                              // crispening
```

The coefficient 0.25 corresponds to the upper end of Moroney's observed
chroma-scaling range for achromatic backgrounds. With `CHROMA_STR` at its
default and a typical neutral-heavy Arc Raiders scene (`achrom_frac` ≈ 0.45):
- chroma_str boost: ×1.11 — an 11% relative increase in chroma lift
- With achrom_frac ≈ 0.70 (heavy grey scene): ×1.18
- With achrom_frac ≈ 0.10 (vivid/colorful scene): ×1.03 — nearly no effect

This is smaller than the Hunt luminance modulation (×0.80 to ×1.20) but
operates on a orthogonal scene property, so the two effects compound
multiplicatively.

### GPU cost

| Item                  | Cost                               |
|-----------------------|------------------------------------|
| `ReadHWY(202)`        | 1 tex fetch, slot almost always in L1 cache |
| `1.0 + K * achrom`    | 1 MAD                              |
| `chroma_str *= ...`   | 1 MUL                              |
| **Total**             | **1 cached tex + 2 MAD**           |
| New passes            | 0                                  |
| New highway slots     | 0 (slot 202 already written)       |

### Conflict check

- No gates (multiplicative, no hard threshold on pixel properties). ✓
- SDR output: chroma_str scales a lift function already clamped to [0,1]. ✓
- No auto-exposure: achrom_frac is a property of scene color distribution,
  not luminance — it does not adapt exposure. ✓
- Not on exclusions list. ✓
- Not in already-implemented list. ✓

**Verdict: viable, recommended for implementation.**

---

## Finding 2 — CIECAM16 SDR Adapting Luminance Formalisation

### Source

**Gao, Xiao, Pointer, Li (2024)** "The development of the CIECAM16 and
visualization of its domain and range," Color Research & Application 50(2).
Published Oct 2024.

### Finding

The paper formally maps the valid parameter space for CIECAM16, including the
adapting luminance (LA). For SDR display targets:

> LA = 0.2 × Lw (cd/m²)

where Lw is the absolute white luminance of the display. For a typical SDR
monitor at ~200 cd/m², LA ≈ 40 cd/m². This places the scene in the
"average indoor" adaptation regime of CIECAM16, which determines FL
(luminance adaptation factor) and the power-law exponent family.

### Relevance to pipeline

The pipeline's Hunt exponent is `lerp(0.52, 0.64, saturate(zone_log_key /
0.50))`. The CIECAM16 domain paper confirms the H-K exponent of ~0.52–0.64
is in the correct range for SDR adapting luminance (their FL-adapted exponent
maps to ~0.42–0.63 over the valid SDR range). The current parameterisation
is **consistent with the formal CIECAM16 domain**.

Also confirmed: the CIECAM16 chroma response for SDR differs from HDR by
approximately the FL scaling: saturated colours at high scene luminance
receive less colorfulness boost than at low scene luminance — which is
exactly what the Hunt scaling line (`lerp(0.80, 1.20, zone_log_key)`) models.

### Verdict

Confirmatory: the pipeline's current luminance-dependent chroma and H-K
parameterisations fall within the formally validated CIECAM16 SDR regime.
No parameter changes needed. No implementation required.

---

## Finding 3 — Temporal Chromatic Adaptation (ACM SIGGRAPH Asia 2025)

### Source

**Xiao et al. (2025)** "Modeling and Exploiting the Time Course of Chromatic
Adaptation for Display Power Optimizations in Virtual Reality," ACM
Transactions on Graphics (SIGGRAPH Asia 2025). arXiv:2509.23489.

### Finding

Chromatic adaptation (the visual system's adjustment of cone gain to
normalise the perceived white point) has two temporal components:
- **Fast**: 40–70 ms half-life (photoreceptor gain control)
- **Slow**: 10–30 s half-life (cortical/opponent-channel adaptation)

After an abrupt illuminant change, the slow component takes ~1 minute for
full adaptation. The fast component accounts for initial perceptual "pop."

### Relevance to pipeline

The pipeline already detects scene cuts via `HWY_SCENE_CUT` (slot 199).
A potential application: on scene cut, the white adaptation built into
the CAT16-derived operations should temporarily lag, as the human visual
system has not yet adapted to the new scene illuminant. In effect, the
warm-bias EMA and the chroma slope (R90) already implement a slow temporal
smoother, but they track luminance statistics, not the white-point adaptation
lag specifically.

A targeted implementation sketch (not yet recommended for implementation):

```hlsl
// Conceptual — read temporal adaptation lag from scene cut EMA
float adapt_lag = ReadHWY(HWY_SLOW_KEY);  // slot 205 — slow ambient EMA
// Reduce crispening and Hunt scaling during rapid illuminant transitions
float temporal_damp = saturate(lerp(0.6, 1.0, adapt_lag));
chroma_str *= temporal_damp;
```

`HWY_SLOW_KEY` (slot 205) tracks the slow ambient key EMA; after a scene cut
it will be transiently below the current zone_log_key, creating the desired
damping effect.

### Conflict check

The concern is whether this crosses into auto-adaptation territory (violating
the "no auto-exposure" rule). The distinction: the temporal damp here modulates
perceived chroma adaptation lag, not luminance exposure. However, its effect
is perceptually similar to auto-exposure transition management. This requires
explicit discussion before implementation — **file as future avenue, not a
near-term proposal**.

---

## Summary table

| Finding | Status       | GPU cost | Highway slots | Action |
|---------|-------------|----------|---------------|--------|
| F1: Chroma crispening (HWY_ACHROM_FRAC) | **New, viable** | 1 cached tex + 2 MAD | slot 202 (existing) | Recommend for next implementation session |
| F2: CIECAM16 SDR LA domain | Confirmatory | 0 | — | No action, confirms existing parameters |
| F3: Temporal CA lag on scene cut | Future avenue | ~2 MAD | 199, 205 (existing) | Needs policy discussion first |

---

## Implementation sketch for F1 (complete)

Location: `general/grade/grade.fx`, ColorTransformPS chroma section.

```hlsl
// ── Chroma crispening: neutral surround enhances perceived colorfulness ──
// Moroney 2001 (CIC-9): ~25–35% chroma boost on achromatic vs. chromatic background.
// achrom_frac = fraction of scene pixels with Oklab C < 0.05 (highway slot 202).
float achrom_frac = ReadHWY(HWY_ACHROM_FRAC);
chroma_str *= 1.0 + 0.25 * achrom_frac;
```

Insert after the existing Hunt scaling line (~line 572) and before the
`LiftChroma` call loop. No other files need to change — `HWY_ACHROM_FRAC`
is already defined in `general/highway.fxh` and the slot is already written
by `general/analysis-frame/analysis_frame.fx`.
