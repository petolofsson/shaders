# R187 — Zero-anchored chroma expansion + principled zone weights

**Date:** 2026-05-12
**Status:** Proposal — awaiting approval before implementation

---

## Problem statement

`InverseGradePS` has two related bugs in how it expands chroma:

### Bug 1 — Wrong expansion anchor

Current formula (line 163):
```hlsl
float new_C = mean_C + (C - mean_C) * factor;
```

This is a *chroma contrast stretch around the scene median*. When `factor > 1`:
- Pixels with `C > mean_C` → expanded (more saturated) ✓
- Pixels with `C < mean_C` → contracted (less saturated) ✗

Highlights are specifically desaturated by the game tonemapper → they cluster *below* `mean_C`. So the formula applies chroma *reduction* to exactly the pixels most in need of recovery.

Example: `C = 0.04`, `mean_C = 0.08`, `factor = 1.15`
→ `new_C = 0.08 + (0.04 − 0.08) × 1.15 = 0.034` — pixel became *more* neutral.

### Bug 2 — Wrong zone weights

```hlsl
float zone_weight = w_shadow * 0.4 + w_mid * 1.0 + w_highlight * 0.8;
```

Empirically calibrated during R186 with no principled basis. Highlight weight 0.8 is substantially too high per all literature sources.

---

## Research findings

### Source 1 — ACES 2.0 chroma compression (official documentation)

ACES 2.0 operates in JMh (perceptual lightness / colorfulness / hue) space. Tone mapping modifies J only. Chroma compression is a *separate* subsequent step modifying M only. They are independent operators.

Chroma compression uses an invertible toe function:

**Forward (compress):**
```
toe(x, limit, c₁, c₂) = (k₃x − k₁ + √((k₃x − k₁)² + 4k₂k₃x)) / 2
```

**Inverse (expand / recover):**
```
toe_inv(x, limit, c₁, c₂) = (x² + k₁x) / (k₃(x + k₂))
```

Where k₁ = √(c₁² + k₂²), k₂ = max(c₂, 0.001), k₃ = (limit + k₁) / (limit + k₂)

Critical property: `toe_inv(0) = 0`. **Zero-anchored.** C = 0 stays 0; expansion is proportional to existing chroma.

**Zone treatment per ACES:**
- Compression affects *highlights and mid-tones*
- Compression *does not affect shadows*
- Expansion increases saturation in *shadows and mid-tones only*
- **No expansion in highlights** — confirmed explicitly
- Higher J (lightness) → more compression. Higher M (colorfulness) → less compression (saturated colors resist more than near-neutral ones).

**Expansion parameter scales with display peak luminance:**
```
saturation = max(0.2, 1.3 − 1.3 × 0.69 × log₁₀(L_peak / 100))
```

For SDR displays (100 cd/m²): `saturation = max(0.2, 1.3 − 0) = 1.3`. Significant expansion.

---

### Source 2 — Cinema SDR→HDR mastering study (arxiv 2604.06276, April 2026)

Pixel-wise analysis of professional mastering across ASC StEM2 content. Measures chroma change from SDR master to HDR master — the forward direction of what we're inverting.

| Zone | Luminance | Mean ΔC | % pixels gaining chroma |
|------|-----------|---------|--------------------------|
| Shadow | < 20 cd/m² | −0.039 | 30.8% |
| Midtone | 20–100 cd/m² | +0.003 | 66.9% |
| Highlight | > 100 cd/m² | −0.008 | 34.4% |

Reading these for our inverse direction (game SDR → inverse): what the tonemapper *added* to chroma going HDR→SDR is what we should *remove* going SDR→inverse:
- Highlights: tonemapper added −0.008 to chroma (desaturated). We should add some back. But mean is nearly zero and gamut constraint prevents much.
- Midtones: tonemapper added +0.003 to chroma (slightly boosted — surprising, but small). Our expansion here is still justified to undo luminance-compression-induced apparent desaturation.
- Shadows: tonemapper added −0.039 chroma (strongly desaturated). We should add some back.

Conclusion: **midtones are the primary zone, shadows secondary, highlights minimal** — consistent with ACES.

---

### Source 3 — Mantiuk et al. "Color Correction for Tone Mapping" (Cambridge)

Proposes a luminance-ratio saturation correction for inverse tone mapping:

```
C_HDR = ((C_LDR / L_LDR − 1) × s + 1) × L_HDR
```

Where s ≥ 1 is a saturation gain parameter. Key property: expansion is **anchored at the white point** (C = L → neutral), not at zero or the mean. The deviation of a pixel's chroma from neutrality is amplified by s.

In the limit where L_LDR ≈ L_HDR (shadows, where luminance mapping is near-linear), this collapses to approximately `C_HDR ≈ C_LDR × s` — multiplicative from zero. In highlights where luminance is heavily compressed, the formula applies less expansion.

**Practical implication:** This is a continuous alternative to a zone system. The expansion magnitude is automatically modulated by luminance — highlights naturally get less because L is high and the deviation from neutrality is small.

---

### Source 4 — BT.2446 Method A (via lilium ReShade implementation)

```hlsl
hdr = sdr * (y_Hdr / y_Sdr);  // luminance-ratio scaling
```

Pure multiplicative scaling by the luminance expansion ratio. Zero-anchored (sdr=0 → hdr=0). No dedicated chroma recovery beyond what the luminance scaling provides. Simplest possible implementation of zero-anchored expansion.

### Source 5 — BT.2446 Method C (via lilium ReShade implementation)

Uses crosstalk matrix with alpha parameter. In the reference implementation, dedicated chroma recovery code is **commented out** — the implementation relies on the luminance mapping alone to handle chroma. This is simpler and avoids overcorrection.

---

## Synthesis: what the literature agrees on

| Claim | ACES | Cinema study | Mantiuk | BT.2446 |
|-------|------|--------------|---------|---------|
| Zero/proportional anchor | ✓ | — | approx ✓ | ✓ |
| Highlights get minimal/no expansion | ✓ | ✓ | ✓ (implicit) | ✓ |
| Midtones are primary recovery zone | ✓ | ✓ | ✓ | ✓ |
| Shadows get moderate expansion | ✓ | partial | ✓ | ✓ |

No source supports mean-anchored expansion. All sources converge on zero-anchored (or luminance-ratio-anchored, which approximates zero-anchor in practice).

---

## Proposed changes

### Change 1 — Formula: zero-anchored expansion

Remove `mean_C` entirely. Replace line 163:

```hlsl
// Before
float  mean_C      = tex2Dlod(MeanChromaSamp, float4(0.5, 0.5, 0, 0)).r;
// ...
float  new_C       = mean_C + (C - mean_C) * factor;

// After
float  new_C       = C * factor;
```

- Drops the `MeanChromaSamp` texture read
- `C = 0` → stays 0 (neutral pixels stay neutral)
- All colored pixels expand proportionally when `factor > 1`
- No pixel can be contracted when `factor > 1`

### Change 2 — Zone weights: literature-derived

```hlsl
// Before
float zone_weight = w_shadow * 0.4 + w_mid * 1.0 + w_highlight * 0.8;

// After
float zone_weight = w_shadow * 0.5 + w_mid * 1.0 + w_highlight * 0.05;
```

Rationale:
- **Shadow × 0.5**: Cinema study shows shadows desaturated −0.039 in forward TM; ACES adds shadow expansion to counteract desaturation. Moderate weight justified.
- **Mid × 1.0**: Unanimous — primary recovery zone.
- **Highlight × 0.05**: Near-zero. Gamut geometry prevents chroma recovery above L≈0.85. The 0.05 preserves a small amount to avoid a hard boundary at the mid/highlight transition.

### Alternative — Continuous luminance-driven weighting (Mantiuk-inspired)

Instead of the zone partition, replace `zone_weight × luma_env` with a single continuous term:

```hlsl
float lerp_t = saturate(float(INVERSE_STRENGTH) * (1.0 - lab.x) * c_weight * dir_scale);
```

`(1 − lab.x)` is the simplest possible continuous weighting: full expansion at L=0, zero at L=1. No zone system, no bilateral passes needed for the weighting function. The bilateral `L_base` texture would still exist but only used to define the zones if we keep them.

Tradeoff: loses the asymmetric zone-specific calibration (shadow = different from mid = different from highlight) in exchange for simplicity and physical correctness. Bilateral passes become dead weight if zones are dropped.

---

## Open questions

1. **Shadow weight 0.5 or lower?** The mastering data shows professional HDR masters desaturate shadows on average. An argument exists for shadow weight closer to 0.2–0.3 — "don't fight the professional colorist's intent." Counter-argument: game tonemappers are cruder than professional mastering; game shadows are legitimately too desaturated.

2. **Keep bilateral zones or switch to continuous `(1 − lab.x)` weighting?** If zones are dropped, the two bilateral passes (H + V) become unnecessary — saves two passes and two 1/8-res textures. Significant GPU savings. The `luma_env` bell already provides smooth L-based rolloff; the zone system adds spatial context but at high cost.

3. **`MeanChromaSamp` descriptor removal:** After switching to `C * factor`, `MeanChromaSamp` in `inverse_grade.fx` becomes dead. But the texture (`MeanChromaTex`) may be shared with `analysis_frame.fx`. Audit before removing descriptor.

4. **INVERSE_STRENGTH recalibration:** With zero anchor, `C * factor` expands all pixels rather than only those above `mean_C`. Effective expansion magnitude increases. `INVERSE_STRENGTH` will need pulling down — start recalibration at 0.20–0.25.

---

## Recommended implementation order

1. Change formula to `C * factor` (low risk, high correctness gain)
2. Change zone weights to `shadow×0.5, mid×1.0, highlight×0.05`
3. Recalibrate `INVERSE_STRENGTH`
4. Evaluate whether bilateral zone system is still earning its GPU cost (two passes) or should be replaced with continuous `(1 − lab.x)` weighting
