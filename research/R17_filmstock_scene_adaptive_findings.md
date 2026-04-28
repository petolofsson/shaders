# R17 — Film Stock Presets: Scene-Adaptive Tint Balance

**Date:** 2026-04-28  
**Status:** Research complete — implementation ready

---

## 1. Internal Audit

**Current film grade (stage 4, grade.fx lines 536–588):**

```hlsl
// Fixed-strength tinting — amounts per preset are hardcoded #defines
result.r += HIGHLIGHT_TINT_R * highlight_w;
// ...
result += SHADOW_TINT * g_shadow;
result.r += TOE_TINT_R * toe_bell * tt_gate;
```

All tint contributions are **fixed-scale** relative to each preset's `#define` values. The same
highlight boost and shadow tint applies regardless of whether the scene is dark or bright.

---

## 2. Literature & Physical Basis

### 2.1 Film characteristic curve cross-over behavior

**Standard sensitometric description** (Kodak Tech Pubs, universally documented across
manufacturers):

A film stock's characteristic curve (D-log E) has **per-layer gammas** for cyan (controls red),
magenta (controls green), and yellow (controls blue) dye layers. For Kodak Vision3-family stocks:

- **Cyan layer (red channel):** lower gamma in the highlight shoulder than magenta/yellow
- At high exposure (highlights): cyan layer compresses first → less red blocked → warm output
- At low exposure (shadows): all layers approach similar slope → neutral/cool output
- Result: warm highlights, cool shadows — the "Kodak cross-over"

**Fuji Eterna family:** designed for flat/cool character. Green (magenta layer) has minimal
divergence from other channels — muted cross-over effect by design.

**ARRI ALEXA:** log-encoded with minimal color latitude effects — near-neutral cross-over.

### 2.2 Cross-over shift with exposure rating

**Physical mechanism:** The cross-over point (where shadows become cool, highlights become warm)
is defined by the toe-shoulder transition in the characteristic curve. When a scene is:
- **Over-exposed** (bright key, zone_log_key >> 0.18): more of the image sits in the shoulder
  region → more of the frame takes on the warm highlight character
- **Under-exposed** (dark key, zone_log_key << 0.18): more image sits in the toe region →
  more of the frame takes on the shadow/cool character

This is universally documented behavior for all negative film stocks. The cross-over is calibrated
at "normal" exposure (18% grey = zone V).

### 2.3 Sensitometric data accessibility

Kodak Vision3, Fuji Eterna, and Sony color negative data sheets were found in PDF form but are
binary-encoded and cannot be parsed to extract exact gamma slopes. The per-layer gamma differences
(typically 0.03–0.08 difference between red and green/blue channels) are not available in
text-accessible format from current sources.

**Consequence:** The TINT_ADAPT_SCALE constants below are derived from qualitative stock
descriptions (industry-standard characterizations), not raw sensitometric measurements.
They represent well-calibrated estimates with medium confidence. Visual validation required.

---

## 3. Proposed Implementation

### Finding 1 — Exposure-adaptive tint scale [PASS, medium confidence]

Use `zone_log_key` (computed in R16, available as a shader variable in stage 4) to scale
highlight and shadow tint intensities. Normal key is 0.18 (zone V / middle grey).

```hlsl
// R17: scene-adaptive tint balance — cross-over shifts with scene exposure
float r17_stops      = log2(max(zone_log_key, 0.001) / 0.18);   // stops above/below normal
float r17_hl_boost   = 1.0 + TINT_ADAPT_SCALE * saturate( r17_stops);  // bright → more highlight tint
float r17_sh_boost   = 1.0 + TINT_ADAPT_SCALE * saturate(-r17_stops);  // dark  → more shadow tint
```

**Range:**
- zone_log_key = 0.09 (1 stop under): `r17_stops = -1.0` → r17_sh_boost = 1 + SCALE, r17_hl_boost = 1.0
- zone_log_key = 0.18 (normal): `r17_stops = 0.0` → both = 1.0 (no change)
- zone_log_key = 0.36 (1 stop over): `r17_stops = +1.0` → r17_hl_boost = 1 + SCALE, r17_sh_boost = 1.0

The `saturate()` clamps at 1 stop in each direction — prevents extreme tint shifts for unusual scenes
(night scenes at 0.03 key, or overexposed outdoor at 0.50+).

### Finding 2 — Per-preset TINT_ADAPT_SCALE constants [medium confidence]

Define per-preset scale factors matching each stock's cross-over strength:

| Preset | Stock | TINT_ADAPT_SCALE | Rationale |
|--------|-------|-----------------|-----------|
| 0 | Soft base | 0.00 | Neutral by definition |
| 1 | ARRI ALEXA | 0.15 | Clean stock, minimal cross-over |
| 2 | Kodak Vision3 | 0.35 | Strong warm/cool cross-over — defining characteristic |
| 3 | Sony Venice | 0.25 | Moderate, protected mids character |
| 4 | Fuji Eterna 500 | 0.10 | Flat, desaturated — minimal tint shift by design |
| 5 | Kodak 5219 | 0.40 | Punchy, most opinionated cross-over behavior |

**Confidence:** Medium — derived from qualitative stock descriptions. These may need
upward or downward tuning based on visual validation.

### Implementation — Modified stage 4 tint operations

Apply `r17_hl_boost` to highlight tint, `r17_sh_boost` to shadow/toe tints:

```hlsl
// Toe tint — scale by shadow boost
result.r += TOE_TINT_R * toe_bell * tt_gate * r17_sh_boost;
result.g += TOE_TINT_G * toe_bell * tt_gate * r17_sh_boost;
result.b += TOE_TINT_B * toe_bell * tt_gate * r17_sh_boost;
// ...

// Shadow tint — scale by shadow boost
result = saturate(result + float3(SHADOW_TINT_R, SHADOW_TINT_G, SHADOW_TINT_B) * g_shadow * r17_sh_boost);

// Highlight tint — scale by highlight boost
result += float3(HIGHLIGHT_TINT_R, HIGHLIGHT_TINT_G, HIGHLIGHT_TINT_B) * highlight_w * r17_hl_boost;
```

`zone_log_key` is already a live variable from the R16 block at the top of ColorTransformPS.
No additional texture reads. Cost: 1 `log2` + 2 `saturate` + ~6 multiplications.

---

## 4. Strategic Assessment

| Aspect | Assessment |
|--------|-----------|
| Physical basis | Clear — cross-over shift with exposure is standard sensitometric knowledge |
| Source data | Qualitative (PDFs inaccessible) — TINT_ADAPT_SCALE needs visual calibration |
| SPIR-V compliance | `log2()` is standard intrinsic. PASS |
| Gate-free | `saturate()` only, no if statements. PASS |
| Cost | ~1 log2 + 6 MAD per pixel — negligible |
| Interaction with R16 | Uses zone_log_key from R16 — zero extra passes |
| Risk | Conservative scale range (0.0–0.40) limits worst-case deviation from static behavior |

**Verdict: Implement.** The cross-over shift is the most scene-specific behavior of each
film stock and is currently completely absent (fixed tints). The implementation is conservative.
TINT_ADAPT_SCALE values are best-effort estimates; visual comparison with real stock reference
images should inform final tuning.

**Note on per-channel gamma (not implemented):** The true sensitometric cross-over is caused by
per-layer gamma differences, which would require per-channel curve offsets at the log-space stage.
This is a more faithful model but requires raw gamma data (R≈0.60, G≈0.65, B≈0.63 for Vision3 —
from community film-scanning documentation, unverified). Deferred pending accessible source.
