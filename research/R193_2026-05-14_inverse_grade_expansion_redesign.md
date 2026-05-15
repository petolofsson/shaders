# R193 — Inverse Grade Expansion Redesign

**Date:** 2026-05-14
**Status:** Research complete — implementation candidate identified

---

## Problem Statement

`INVERSE_STRENGTH` at 3.0 is indistinguishable from 1.5. Identified cause: line 70 in
`inverse_grade.fx`:

```hlsl
float lerp_t = saturate(float(INVERSE_STRENGTH) * zone_w * c_weight * dir_scale);
float factor  = lerp(1.0, slope_eff, lerp_t);
float new_C   = C * factor;
```

`saturate()` hard-clamps `lerp_t` to 1.0. For a typical midtone colored pixel
(zone_w≈1.0, c_weight≈0.5, dir_scale≈1.0), the ceiling is hit at
`INVERSE_STRENGTH ≈ 2.0`. Above that, the knob is a no-op. The maximum expansion is
`slope_eff`, which in vivid scenes (median_C > 0.15) is only **1.15** — a 15% chroma
boost invisible at normal viewing.

---

## Research Findings

### 1. ACES 2.0 Chroma Compression — Inverse (Expansion) Direction
Source: [ACES Documentation — Chroma Compression](https://docs.acescentral.com/system-components/output-transforms/technical-details/chroma-compression/)

ACES 2.0 uses an invertible **toe function** applied directly to colorfulness M, not a
lerp-with-ceiling. The toe_inv function:

```
toe_inv(x, limit, c1, c2):
    k2 = max(c2, 0.001)
    k1 = sqrt(c1² + k2²)
    k3 = (limit + k1) / (limit + k2)
    return (x² + k1·x) / (k3·(x + k2))
```

For the **expansion** direction, parameters are:
- `c1 = saturation × (1.0 - J_t/J_max)` — darker pixels get larger c1 → more expansion
- `c2 = sqrt((J_t/J_max)² + threshold)` — suppresses noise near black
- `saturation = max(0.2, 1.3 - 1.3 × 0.69 × log10(L_peak/100))` — aggressiveness knob

Key properties of toe_inv:
- **No hard ceiling on the strength parameter** — `saturation` (= aggressiveness) is
  unbounded; the function asymptotes to `limit` (gamut cusp), it does not clip
- Less saturated colors (low M/C) expand *more* than already-vivid colors — matches
  physics of tonemapper compression (achromatic axis is most compressed)
- Pure colors (M near limit) resist expansion — correct, they can't go further
- The `(1 - J_t/J_max)` zone weighting means shadows and midtones expand; highlights
  do not — ACES applies this because the tone scale rescaling desaturates mids/shadows

### 2. Cinema SDR-to-HDR Chroma Data
Source: [arxiv:2604.06276 — Structural Regularities of Cinema SDR-to-HDR Mapping](https://arxiv.org/abs/2604.06276)

Quantitative chroma changes between matched SDR and HDR cinema masters (18,580 frames,
ASC StEM2, ACES-based workflow):

| Zone | Luminance | Mean ΔChroma | % Pixels Enhanced |
|------|-----------|-------------|-------------------|
| Shadows | <20 cd/m² | **−0.039** | 30.8% |
| Midtones | 20–100 cd/m² | **+0.003** | 66.9% |
| Highlights | >100 cd/m² | **−0.008** | 34.4% |

Pattern: "shadow suppression, midtone expansion, highlight convergence."

**Interpretation for our use case:** The cinema data describes professional HDR mastering
from an ACES pipeline — not directly the inverse of a game tonemapper. In the cinema
workflow, HDR restores shadow depth (darker blacks), which *reduces* shadow saturation
(gamut near black is small). In game content, the tonemapper primarily compresses upper
midtones and highlights; shadows and lower midtones are minimally affected. The
relevant takeaway: **midtones are the correct expansion zone; highlights are near the
gamut ceiling and self-limit; shadows need little correction.**

This validates the midtone bell `4·L·(1−L)` as approximately correct for game content.
The ACES `(1−J)` zone weighting is not appropriate here — it would over-expand shadows
that weren't compressed by the game tonemapper.

### 3. ACES Chroma Compression Mechanism
Source: [ACES Documentation — Chroma Compression](https://docs.acescentral.com/system-components/output-transforms/technical-details/chroma-compression/)

ACES forward compression makes highlights progressively more desaturated:
- `c1 = compression × (J_t/J_max)` — brighter pixels get larger c1 in compression
- `compression = 2.4 + 2.4 × 3.3 × log10(L_peak/100)` for SDR ≈ 2.4

This confirms that ACES-style game tonemappers compress chroma more in bright highlights
than in shadows. The inverse operation should concentrate expansion in the
upper-midtone-to-highlight range, which our midtone bell addresses partially (peaks
at L=0.5, rolls off by L=0.8: zone_w(0.8) = 0.64, zone_w(0.9) = 0.36).

**Gap identified:** Our bell slightly under-expands the L=0.6–0.8 range where ACES
compression is strongest. A bell centred at L=0.6 rather than L=0.5 would be more
accurate. But this is a secondary concern.

### 4. Why `saturate(lerp_t)` Is Wrong
The lerp architecture `lerp(1.0, slope_eff, saturate(t))` has two coupled defects:

A) **Hard ceiling on t:** Once t ≥ 1.0, no further expansion. `INVERSE_STRENGTH` above
   ~1.5 is dead range. In a vivid scene (slope_eff=1.15), this ceiling is expansion of
   exactly 15% — not useful for poorly-compressed content.

B) **Maximum expansion equals slope_eff:** slope_eff is scene-derived (1.15–2.2) and
   independent of `INVERSE_STRENGTH`. The knob only controls *how fast* you reach the
   ceiling, not *how high* the ceiling is. Both defects mean INVERSE_STRENGTH is not a
   creative knob — it's closer to a threshold gate.

---

## Recommended Solution

### Adopt toe_inv architecture in Oklab

Replace the lerp block with a rational function modelled on ACES toe_inv applied
directly to Oklab C. Key differences from ACES:
- Use Oklab L as J proxy (not Hellwig2022 J — we don't have CAM)
- Use `HueCeil(hue)` as limit (already in the file via hue_bands.fxh)
- Keep midtone bell zone_w (not ACES `(1−J)` — wrong for game compression profile)
- INVERSE_STRENGTH scales c1 directly — no saturate() ceiling

**Proposed formula:**

```hlsl
// Replace lines 70-76 with:
float ceil_C  = max(HueCeil(hue), C + 0.001);  // gamut ceiling, never below C
float k2      = max(0.01, 0.01 + (1.0 - lab.x * lab.x));  // noise gate near black
float c1      = float(INVERSE_STRENGTH) * (slope_eff - 1.0) * zone_w * c_weight * dir_scale;
float k1      = sqrt(c1 * c1 + k2 * k2);
float k3      = (ceil_C + k1) / (ceil_C + k2);
float new_C   = (C * C + k1 * C) / (k3 * (C + k2));
new_C         = max(new_C, C);  // expansion only, never reduce
```

**Why this works:**
- `c1 = INVERSE_STRENGTH × (slope_eff−1) × zone_w × c_weight × dir_scale` — the
  product drives expansion; no saturate() anywhere in the chain
- At c1=0 (IS=0 or slope_eff=1.0): k1=k2, k3=1, toe_inv(C)=C — passthrough
- As c1 increases: near-neutral C values expand strongly; C near ceil_C barely moves
- INVERSE_STRENGTH is now a true linear gain: 2.0 is twice as much expansion as 1.0
- HueCeil is the physical ceiling — same protection as before, but reached
  asymptotically not via saturate()
- The slope signal (slope_eff−1) still uses the highway data as a scene-adaptive
  multiplier — vivid scenes (slope_eff=1.15) get c1 scaled by 0.15; achromatic
  (slope_eff=1.8) by 0.80. Range is now meaningful at all INVERSE_STRENGTH values.

**Calibration starting point:**
- At INVERSE_STRENGTH=0.40 (current), c1 ≈ 0.40×0.80×1.0×0.5×1.0 = 0.16 for achromatic scene, midtone pixel
- At INVERSE_STRENGTH=1.0, c1 ≈ 0.40 — noticeably stronger
- Recalibrate from scratch: start at 0.30–0.50, evaluate chroma richness on vivid objects

### Zone weighting (secondary improvement)

Shift midtone bell peak from L=0.5 toward L=0.6 to better match ACES compression
profile (strongest compression in upper midtones):

```hlsl
// Current:
float zone_w = 4.0 * lab.x * (1.0 - lab.x);   // peaks at L=0.50

// Option: shift peak to L=0.60
float zone_w = (1.0/0.96) * lab.x * (1.0 - lab.x * 0.667);  // peaks at L=0.60, max≈1.0
// or more simply — asymmetric version:
float zone_w = saturate(lab.x / 0.60) * saturate((1.0 - lab.x) / 0.40);  // linear ramps, peak at 0.60
```

This is optional — secondary improvement. The bigger win is the toe_inv architecture.

---

## Implementation Plan

**Files to touch:** `general/inverse-grade/inverse_grade.fx` only.

1. Replace lines 70–76 with the toe_inv block above
2. Remove the separate `min(new_C, max(HueCeil(hue), C))` line — the toe_inv
   function asymptotes to ceil_C by construction (add `max(new_C, C)` safety only)
3. Keep all highway reads, zone_w bell, c_weight gate, dir_scale, slope_eff — unchanged
4. Recalibrate INVERSE_STRENGTH starting at 0.40; expect same visual at ~0.30–0.40

**Risk:** Low. Same inputs, same outputs, no new textures, no new highway reads. The
rational function has more ALU than a lerp (~8 ops vs ~3) but no texture taps. Negligible
GPU cost change.

---

## Sources

- [ACES Documentation — Chroma Compression](https://docs.acescentral.com/system-components/output-transforms/technical-details/chroma-compression/)
- [ACES Documentation — Invertible Gamut Compression](https://docs.acescentral.com/system-components/output-transforms/technical-details/gamut-compression/)
- [arxiv:2604.06276 — Structural Regularities of Cinema SDR-to-HDR Mapping](https://arxiv.org/abs/2604.06276)
- [arxiv:2409.16032 — Deep Chroma Compression of Tone-Mapped Images](https://arxiv.org/html/2409.16032v1)
- [ACESCentral — High light fix and premature desaturate](https://community.acescentral.com/t/high-light-fix-and-premature-desaturate/3041)
- [Tone Mapping — Bruno Opsenica's Blog](https://bruop.github.io/tonemapping/)
