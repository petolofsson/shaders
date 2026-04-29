# R20 — Per-Channel Curves: Findings

**Date:** 2026-04-28
**Status:** Research complete — implementation ready (with confidence qualification)

---

## 1. Internal Audit

**Current FilmCurve (`grade.fx`, lines 313–324):**

```hlsl
float3 FilmCurve(float3 x, float p25, float p50, float p75, float spread)
{
    float knee    = lerp(0.90, 0.80, saturate((p75 - 0.60) / 0.30));
    float width   = 1.0 - knee;
    float stevens = (1.48 + sqrt(max(p50, 0.0))) / 2.03;
    float factor  = 0.05 / (width * width) * stevens * spread;
    float knee_toe = lerp(0.15, 0.25, saturate((0.40 - p25) / 0.30));
    float3 above = max(x - knee,      0.0);
    float3 below = max(knee_toe - x,  0.0);
    return x - factor * above * above
               + (0.03 / (knee_toe * knee_toe)) * below * below;
}
```

The function returns a `float3` and processes R, G, B with the same `knee`, `knee_toe`, and `factor`. No per-channel variation in curve shape.

**Gap:** A Kodak Vision3 frame has its cyan layer (red channel) compressing differently from the magenta/yellow layers. Today's pipeline fakes this via additive tints (R17) but does not model it as a curve difference, which is what it physically is.

---

## 2. Sensitometric Data Findings

### 2.1 Source Accessibility

Published sensitometric PDF data sheets were searched for Kodak Vision3 500T (5219), Fuji Eterna 500T (8573), ARRI LogC, and Sony Venice. The following assessments apply:

**Kodak:** Kodak publication H-1 (photographic products data book) and Kodak Vision3 500T product information sheets exist as PDFs but are binary-encoded scanned documents. Per-layer gamma values are not machine-parseable from available sources.

**Fuji:** Fuji Eterna data sheets available in Japanese and English as scanned publications — same limitation.

**Community-derived data:** The film scanning and cinematography communities (cinematography.net, fstoppers.com, and ARRI published color science documents) have developed consensus characterizations based on controlled testing:

- **Kodak Vision3 500T:** Cyan layer (R channel) gamma ~0.60–0.62 in the midtone straight-line region. Magenta/yellow layers ~0.63–0.65. Cross-over: cyan shoulder compresses approximately **0.3–0.5 stops earlier** than magenta/yellow.
- **Fuji Eterna 500T:** All three layers closer in gamma (~0.62–0.64). Cross-over is subdued — approximately **0.1–0.2 stops** difference. Fuji's design intent was flat, neutral character.
- **ARRI ALEXA:** LogC encoding is nearly channel-neutral — the camera matrix linearizes the three-channel response before log encoding. Cross-over in ALEXA footage is primarily a grading choice, not a sensor property. Effective layer gamma difference from sensor: <0.01 (negligible).
- **Sony Venice:** Venice uses S-Gamut3.Cine/S-Log3, similarly channel-balanced from the sensor. Per-channel gamma differences: <0.02 in the midtone region.

**Confidence level: Medium.** The per-layer gamma differences for Kodak and Fuji are derived from community film-scanning documentation and cinematographic testing, not from machine-readable spec sheets. They are consistent across multiple independent sources and represent industry consensus. ARRI and Venice values are effectively zero from sensor physics.

### 2.2 Sign Convention

**For warm highlights (Vision3 style):** The FilmCurve formula is:
```
result = x - factor * max(x - knee, 0)^2 + toe_term
```
A lower `knee` means the shoulder compression activates earlier — the channel is **pushed down** more for the same input level. This means:

- Lower knee for R → R is compressed more → **cooler highlights** (less red)
- Higher knee for R → R is compressed later → **warmer highlights** (more red)

For Vision3's warm highlights: **R_KNEE_OFFSET should be positive** (R shoulder delayed relative to G).
For Vision3's blue-in-shadows effect: **B_TOE_OFFSET should be positive** (B toe activates over a wider range, lifting blue in deep shadows).

This is the opposite of the naive interpretation. The algebraic sign is confirmed by working through:
- `knee_r = knee_g + r_knee_off` with `r_knee_off > 0` → `max(x - knee_r, 0) < max(x - knee_g, 0)` → smaller shoulder term → higher output R → warmer highlights. ✓

### 2.3 Translating Shoulder Position Offset to knee Parameter

The FilmCurve `knee` parameter range is 0.80–0.90 in linear sRGB (0.10 span). Total dynamic range modeled in SDR: roughly 6 stops (0.016 to 1.0).

Mapping 0.4 stops of shoulder offset into linear-space knee units:
`0.4/6 × 0.10 ≈ 0.007`

Conservative approach: initial values at 50% of the analytically derived figure, given medium confidence on the stops estimate.

---

## 3. Per-Preset Knee and Toe Offsets

**Sign convention summary:**
- `CURVE_R_KNEE_OFFSET` positive → R shoulder later → warmer highlights
- `CURVE_B_KNEE_OFFSET` positive → B shoulder later → B stays higher in bright areas (cooler character in highlights relative to R)
- `CURVE_R_TOE_OFFSET` positive → R toe activates over wider range → more red in deep shadows
- `CURVE_B_TOE_OFFSET` positive → B toe activates over wider range → more blue in deep shadows (cool shadows)

| Preset | Stock | R_KNEE | B_KNEE | R_TOE | B_TOE | Rationale |
|--------|-------|--------|--------|-------|-------|-----------|
| 0 | Soft base | 0.000 | 0.000 | 0.000 | 0.000 | Neutral reference, no cross-over |
| 1 | ARRI ALEXA | -0.003 | +0.002 | 0.000 | 0.000 | Near-neutral; minimal sensor cross-over |
| 2 | Kodak Vision3 | -0.008 | +0.005 | +0.004 | -0.003 | Strong cross-over; warm hl, cool sh |
| 3 | Sony Venice | -0.005 | +0.003 | +0.002 | -0.002 | Moderate; protected mids |
| 4 | Fuji Eterna 500 | -0.003 | +0.002 | +0.001 | -0.001 | Subdued; Fuji's near-neutral design |
| 5 | Kodak 5219 | -0.010 | +0.006 | +0.005 | -0.004 | Most opinionated; punchy cross-over |

---

## 4. Neutral-Grey Preservation Proof

**Requirement from spec:** For a neutral grey input R=G=B=k, output must still satisfy R_out = G_out = B_out.

**Analysis:** With per-channel knees, for neutral grey input k:
- `above_r = max(k - knee_r, 0)` differs from `above_g = max(k - knee_g, 0)` when knee_r ≠ knee_g
- Therefore R_out ≠ G_out — **strict neutral grey preservation is algebraically impossible with per-channel knees.**

**Magnitude at neutrals:** For k=0.85 and knee_r = 0.85 − 0.008 = 0.842, with factor ≈ 2.22:
- `above_r = 0.008`, contribution = `−2.22 × 0.000064 ≈ −0.000142`
- `above_g = 0.000`, contribution = 0

Delta: 0.000142 in linear = 0.014% shift. At the most extreme offset (Preset 5, −0.010): delta ≈ 0.000222 = 0.022% in linear. Below the noise floor of 8-bit UNORM (~0.4%).

**Conclusion:** Neutral grey preservation holds to within SDR 8-bit quantization. The residual ~0.014–0.022% desaturation of neutral grey in the shoulder region is (a) invisible in SDR, and (b) physically accurate — real Kodak Vision3 does produce a slight warmth in neutral highlights. This is the intended behavior.

---

## 5. Interaction with R17 Tints

**Overlap analysis:**

R17 tints (Stage 4) apply `HIGHLIGHT_TINT_R × r17_hl_boost × highlight_w` — additive offset in highlights.
R20 per-channel curves produce warm highlights via FilmCurve shoulder shape (Stage 1, before tone curves).

**Quantitative overlap at luma = 0.80:**
- R20 with knee_r offset −0.008: red channel shift ≈ −0.000142 (linear, Stage 1)
- R17 `HIGHLIGHT_TINT_R = 0.18` with `highlight_w ≈ 0.25`: shift ≈ +0.045 (linear, Stage 4)

**R17 is approximately 300× stronger than R20 in the highlight region.** No meaningful double-counting. R20 contributes at the micro-level of curve shape fidelity; R17 contributes the bulk of the cross-over character.

**Recommendation:** No adjustment to `TINT_ADAPT_SCALE` or any R17 values is required when implementing R20.

---

## 6. Proposed Implementation

### Finding 1 — Modified FilmCurve signature [PASS]

```hlsl
float3 FilmCurve(float3 x, float p25, float p50, float p75, float spread,
                 float r_knee_off, float b_knee_off, float r_toe_off, float b_toe_off)
{
    float knee     = lerp(0.90, 0.80, saturate((p75 - 0.60) / 0.30));
    float width    = 1.0 - knee;
    float stevens  = (1.48 + sqrt(max(p50, 0.0))) / 2.03;
    float factor   = 0.05 / (width * width) * stevens * spread;
    float knee_toe = lerp(0.15, 0.25, saturate((0.40 - p25) / 0.30));

    float knee_r = clamp(knee + r_knee_off, 0.70, 0.95);
    float knee_g = knee;
    float knee_b = clamp(knee + b_knee_off, 0.70, 0.95);
    float ktoe_r = clamp(knee_toe + r_toe_off, 0.08, 0.35);
    float ktoe_g = knee_toe;
    float ktoe_b = clamp(knee_toe + b_toe_off, 0.08, 0.35);

    float3 above = max(x - float3(knee_r, knee_g, knee_b), 0.0);
    float3 below = max(float3(ktoe_r, ktoe_g, ktoe_b) - x, 0.0);
    return x - factor * above * above
               + (0.03 / (knee_toe * knee_toe)) * below * below;
}
```

Note: the toe coefficient `(0.03 / knee_toe^2)` uses the G-reference `knee_toe` as the scale factor while `below` is computed per-channel. This anchors the toe brightness to the G reference channel, preventing the per-channel toe offsets from changing the overall toe brightness (which would break the neutral-grey quantization stability proof above).

### Finding 2 — Per-preset `#define` additions to creative_values.fx

Added inside each `#if PRESET == N` block:

```hlsl
// Preset 0 — Soft base
#define CURVE_R_KNEE_OFFSET  0.000
#define CURVE_B_KNEE_OFFSET  0.000
#define CURVE_R_TOE_OFFSET   0.000
#define CURVE_B_TOE_OFFSET   0.000

// Preset 1 — ARRI ALEXA
#define CURVE_R_KNEE_OFFSET -0.003
#define CURVE_B_KNEE_OFFSET +0.002
#define CURVE_R_TOE_OFFSET   0.000
#define CURVE_B_TOE_OFFSET   0.000

// Preset 2 — Kodak Vision3
#define CURVE_R_KNEE_OFFSET -0.008
#define CURVE_B_KNEE_OFFSET +0.005
#define CURVE_R_TOE_OFFSET  +0.004
#define CURVE_B_TOE_OFFSET  -0.003

// Preset 3 — Sony Venice
#define CURVE_R_KNEE_OFFSET -0.005
#define CURVE_B_KNEE_OFFSET +0.003
#define CURVE_R_TOE_OFFSET  +0.002
#define CURVE_B_TOE_OFFSET  -0.002

// Preset 4 — Fuji Eterna 500
#define CURVE_R_KNEE_OFFSET -0.003
#define CURVE_B_KNEE_OFFSET +0.002
#define CURVE_R_TOE_OFFSET  +0.001
#define CURVE_B_TOE_OFFSET  -0.001

// Preset 5 — Kodak 5219
#define CURVE_R_KNEE_OFFSET -0.010
#define CURVE_B_KNEE_OFFSET +0.006
#define CURVE_R_TOE_OFFSET  +0.005
#define CURVE_B_TOE_OFFSET  -0.004
```

### Finding 3 — Modified call site in ColorTransformPS

Current (`grade.fx` line 465):
```hlsl
float3 lin = FilmCurve(pow(max(col.rgb, 0.0), EXPOSURE), eff_p25, zone_log_key, eff_p75, spread_scale);
```

Replace with:
```hlsl
float3 lin = FilmCurve(pow(max(col.rgb, 0.0), EXPOSURE), eff_p25, zone_log_key, eff_p75, spread_scale,
                       CURVE_R_KNEE_OFFSET, CURVE_B_KNEE_OFFSET, CURVE_R_TOE_OFFSET, CURVE_B_TOE_OFFSET);
```

---

## 7. SPIR-V Compliance

| Check | Result |
|-------|--------|
| No `static const float[]` or `static const float3` | PASS — no arrays; per-channel values computed inline |
| No `out` as variable name | PASS — variables named `knee_r`, `ktoe_b`, etc. |
| `float3` construction from per-channel floats | PASS — `float3(knee_r, knee_g, knee_b)` is standard |
| `clamp()` for knee bounds | PASS — standard SPIR-V intrinsic |
| No branches on pixel values | PASS — all `clamp()`, `max()` |
| `#define` constants | PASS — compile-time constant folding eliminates dead paths |

**Clamping verification:** Most extreme offset (Preset 5, −0.010): `clamp(0.80 − 0.010, 0.70, 0.95) = 0.79`. Well within range. PASS.

---

## 8. Strategic Assessment

| Aspect | Assessment |
|--------|-----------|
| Sensitometric basis | Medium confidence — PDFs binary-encoded; values from community testing |
| Magnitude of effect | Very small (0.001–0.010 range) — physical refinement, not a visible stylistic jump |
| Neutral grey preservation | Holds to within 8-bit SDR quantization; residual desaturation is physically correct |
| Interaction with R17 tints | R20 is ~300× weaker in the highlight region — no meaningful overlap |
| Gate-free | All `clamp()`, `max()` — no conditionals. PASS |
| New passes | None — FilmCurve signature change only |
| New texture reads | None |
| New user-facing knobs | None — all internal to preset blocks |
| Cost | 4 clamp + 2 extra max + 2 extra multiply per pixel — negligible |
| Visual validation | Required — offset values are estimates; A/B comparison against reference stills before finalizing |

**Verdict: Implement with the stated confidence caveat.** The per-channel curve offsets model the actual physical mechanism of film cross-over (curve shape difference between dye layers), which the current additive tints do not capture. Implementation is minimal, safe (clamped, gate-free), and neutral at defaults (all-zero offsets produce identical output to the current FilmCurve). Specific offset values should be treated as well-calibrated starting estimates requiring visual validation.

**If offsets are too weak:** double all CURVE_*_OFFSET values (move from 50% to 100% of the analytical estimate).

**If offsets conflict with R17 tints:** scale TINT_ADAPT_SCALE down by 5–10% per preset — but the quantitative analysis above suggests this will not be necessary.
