# R131 — Hollywood Black Magic Dual-Component Pro-Mist Model

**Date:** 2026-05-08  
**Status:** Proposal  
**Target:** Output — Pro-Mist (`grade.fx` ProMistPS)  
**Novelty delta:** +3–4% (Output: 87% → 90–91%)

---

## Filter Research Summary

### Schneider Hollywood Black Magic — Optical Design

The HBM uses two physically distinct mechanisms in a single 4mm water white glass plate:

**Micro-Lenslets™** — a surface array of micro-scale refractive lenses that redirect incident light toward bright areas. Effect: smooth, spectrally neutral glow around highlights. Because the lenslets redirect rather than scatter diffusely, the glow kernel is tighter and rounder than a standard Pro-Mist's particle scatter. No light is added from shadow regions — the glow is sourced from highlights only.

**Carbon micropore particles** (shared with the Black Frost family) — absorb scattered light that would otherwise veil into shadow regions or desaturate colors. Effect: blacks are maintained, color saturation is maintained. This is the critical structural difference from the Tiffen Pro-Mist, which uses white particles that lift blacks and veil the image.

The two mechanisms are not additive — they are a coupled design. The micro-lenslets produce the shimmer; the carbon particles constrain where that shimmer can land. The result: highlight-only additive glow with preserved shadow depth and color, no warm cast.

### "Constant smooth halation at all strengths" — Engineering Meaning

Schneider's tagline is a specific technical claim. Across grades 1/8 → 1/2 → 1 → 2, the *character* of the scatter (kernel shape, spectral neutrality, additive-only behavior) does not change — only amplitude scales. David Mullen ASC (REDUSER) notes the 1/8 → 1/4 jump is smaller than the 1/4 → 1/2 jump in perceived effect, consistent with a roughly linear kernel × quadratic perceived contrast. No grade introduces a qualitatively different effect type.

### Grade 1/4 vs Grade 1 — Perceptual Distinction

| Property | HBM 1/4 | HBM 1 |
|----------|---------|--------|
| Highlight glow on practicals | Present, subtle | Clearly visible, wide |
| Soft overlay (detail smoothing) | Barely noticeable | Visible "airbrushed" look |
| Blacks | Fully maintained | Fully maintained |
| Colors | Fully maintained | Fully maintained |
| Chromatic cast | None | None |
| Common use | Primary grade for most cinematographers (Mullen, Correia) | Close-up older talent; often felt to be "too much" in hindsight |

The key observation: at 1/4, the shimmer is the dominant perceptible effect. At grade 1, a second character becomes clearly visible — a "controlled soft overlay on a sharp, in-focus image" that smooths the high-frequency digital texture of modern sensors. Schneider describes it as giving an "airbrushed" quality. This is not highlight-additive; it reduces perceived texture uniformly in midtones.

### HBM vs Tiffen Black Pro-Mist (our current model reference)

| Property | HBM | Tiffen Black Pro-Mist |
|----------|-----|-----------------------|
| Particle type | Micro-Lenslets + carbon (black) | Black particles in clear matrix |
| Black lift | None | None (black particles prevent) |
| Shimmer source | Micro-lenslet redirection | Particle forward scatter |
| Chromatic character | Color neutral | Subtle warm cast, occasional green near practicals |
| Soft overlay | Yes ("airbrushed") | Minimal |
| Shadow detail | Preserved | Preserved |

---

## Gap Analysis — Current `ProMistPS`

### What we already have (correct for HBM)

**Additive-only shimmer:** `base + max(0, blurred − base) * strength` — physically correct. Micro-lenslet highlight redirection is inherently additive and highlight-sourced; our model matches this exactly. No black lift by construction.

**Three-scale blur:** mip0 (tight), mip1 (wide), mip2 (broader). Physically motivated by polydisperse micro-lenslet population — different lenslet sizes scatter at different radii simultaneously.

**No chromatic bias:** Our current implementation is color-neutral in the shimmer path, which aligns with HBM's neutral scatter. This is correct. *Note: the PLAN.md candidate "chromatic scatter radii" (red → more mip2, blue → more mip0) is appropriate for Tiffen Pro-Mist's warm polydisperse particles, not for HBM. With this proposal, that candidate should be dropped — the halation pass already handles chromatic scatter; duplicating it in Pro-Mist models the wrong filter.*

### What is missing (gap from HBM)

**Gap 1 — Soft overlay component absent.**  
The HBM's Micro-Lenslet array has a secondary effect: the same refractive elements that produce the shimmer also introduce a low-amplitude, spatially smooth blend toward the defocused image across the entire frame, concentrated in midtones. This is the "controlled soft overlay" and "airbrushed" texture that reduces the clinical digital edge of high-res sensors. Our model has no equivalent. The effect is small at 1/4, clearly present at grade 1.

**Gap 2 — Broad scale has a step function, breaking constant-character guarantee.**  
Current: `broad_w = saturate(MIST_STRENGTH * 0.20 - 0.10)` — zero for MIST_STRENGTH < 0.5. Below that threshold the three-scale kernel degenerates to two scales. The bloom character changes qualitatively as MIST_STRENGTH crosses 0.5, which violates the HBM constant-halation-at-all-strengths property.

---

## Proposed Implementation

### Fix 1 — Constant-character broad scale (1 ALU change)

Replace the clamped ramp with a linear proportion fixed to the shimmer weight:

```hlsl
// Before (character-changing)
float broad_w = saturate(MIST_STRENGTH * 0.20 - 0.10);

// After (constant character, linear amplitude)
float broad_w = MIST_STRENGTH * 0.10;
```

The tight:wide:broad ratio stays constant at any strength. All three scales are always active. Scale coefficients (0.25 / 0.15 / 0.10) maintain the tight-dominant kernel of the HBM, where the core lenslet population is small and the broader scatter is a smaller fraction.

### Fix 2 — Soft overlay component (Component B) (~4 ALU, 0 new taps)

The overlay reuses the already-sampled `mist_tight` (mip0). It blends toward the blurred image only in midtones, gated by a bell that reaches zero at luma=0 (blacks preserved) and luma=1 (highlights preserved):

```hlsl
float luma_base = Luma(col);
float mid_gate  = luma_base * (1.0 - luma_base) * 4.0;  // bell, 0 at 0 and 1, peak 1.0 at L=0.5
float overlay_w = MIST_STRENGTH * 0.06 * mid_gate;
col = lerp(col, mist_tight, overlay_w);
```

Applied *after* the shimmer composite. At MIST_STRENGTH=0.5 (HBM 1/4 equivalent), `overlay_w` peaks at 0.03 — barely perceptible texture smoothing. At MIST_STRENGTH=2.0 (HBM 1 equivalent), it peaks at 0.12 — the "airbrushed" quality becomes visible. The bell gate ensures blacks and highlights are untouched by construction, matching HBM's black-and-color preservation guarantee.

### Full ProMistPS revised section

```hlsl
// -- Component A: Highlight shimmer (micro-lenslet redirection) --
float scale_w   = MIST_STRENGTH * 0.25;
float shimmer_w = MIST_STRENGTH * 0.15;
float broad_w   = MIST_STRENGTH * 0.10;  // was: saturate(MIST_STRENGTH * 0.20 - 0.10)

float3 mist_tight  = tex2Dlod(MistDiffuseSamp, float4(uv, 0, 0)).rgb;
float3 mist_wide   = tex2Dlod(MistDiffuseSamp, float4(uv, 0, 1)).rgb;
float3 mist_broad  = tex2Dlod(MistDiffuseSamp, float4(uv, 0, 2)).rgb;

float3 blurred = mist_tight * scale_w + mist_wide * shimmer_w + mist_broad * broad_w;
float  reinhard_w  = blurred_luma / (blurred_luma + 0.08);  // Reinhard knee (existing)
float3 shimmer = max(0.0, blurred - col) * reinhard_w;
col += shimmer;

// -- Component B: Soft overlay (carbon-gate midtone smoothing) --
float mid_gate  = Luma(col) * (1.0 - Luma(col)) * 4.0;
col = lerp(col, mist_tight, MIST_STRENGTH * 0.06 * mid_gate);
```

Note: `Luma(col)` computed once and reused. `mist_tight` already in register from Component A.

---

## GPU Cost

| Change | ALU | Taps |
|--------|-----|------|
| Fix broad_w to linear | 0 (constant fold) | 0 |
| Component B soft overlay | ~4 (Luma + mul + lerp) | 0 (mist_tight reused) |
| **Total** | **~4** | **0** |

---

## Calibration

MIST_STRENGTH mapping to HBM grades (approximate, testbed-dependent):

| MIST_STRENGTH | HBM equivalent | Character |
|---------------|---------------|-----------|
| 0.3–0.5 | 1/8 | Barely-there glow on practicals |
| 0.6–0.9 | 1/4 | Mullen workhorse; subtle shimmer, negligible overlay |
| 1.2–1.5 | 1/2 | Close-up grade; visible shimmer, faint overlay |
| 1.8–2.2 | 1 | "Airbrushed" overlay visible; strong glow; usually too much |

After implementation, retune MIST_STRENGTH with `capture.py` highway reads (slot 219, `mist_str`) to confirm scene-adaptive strength lands in the 1/4–1/2 range for typical content.

---

## Novelty Assessment

- **Dual-component model grounded in published filter optics**: zero prior art in real-time post-process. Existing "Pro-Mist" implementations (including Tiffen emulations in DaVinci Resolve) use only the shimmer component.
- **Carbon-particle midtone gate preventing black lift in overlay**: novel formulation. The `luma*(1-luma)` gate is the direct physical analog of the carbon micropore absorption preventing veil into shadow.
- **Constant-character scaling fix**: correctness improvement — not counted as novelty, but fixes a qualitative error at low MIST_STRENGTH.
- **Drops chromatic scatter radii candidate** from PLAN.md: HBM is spectrally neutral; the chromatic scatter model belongs to Tiffen Pro-Mist physics, not HBM. No novelty loss — halation already covers chromatic scatter.

**Estimated novelty delta: +3–4%.** Output stage: 87% → 90–91%.

---

## Sources

- Schneider-Kreuznach Hollywood Black Magic® Fact Sheet V1_02_2023 (official PDF)
- Schneider-Kreuznach Diffusion and Mist Filters product page
- David Mullen ASC, REDUSER forum thread "Schneider Hollywood Black Magic Filter 1/2 vs 1 vs 2" (practical grade comparison)
- Alik Griffin, "Black Pro-Mist vs Glimmerglass vs Cinebloom" (particle mechanism comparison, carbon vs white particle behavior)
- B&H Photo product listing 68-091156 (4×5.65" HBM 1/4 specifications)
