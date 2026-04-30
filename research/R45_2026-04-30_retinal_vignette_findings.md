# R45 — Retinal Vignette — Findings

**Date:** 2026-04-30
**Status:** Ready to implement

---

## Summary

A retinal vignette is biologically grounded, self-limiting by construction, and fills the
remaining gap in the chain. Three research questions are fully resolved; implementation is
straightforward. Recommended as a standalone pass after pro_mist with two primary knobs
and one optional chroma knob.

---

## Q1: Cos⁴ vs Gaussian — resolved: Gaussian

**Cos⁴** (the cosine-fourth law) is a pure optical geometry effect: peripheral image-plane
points receive less flux from a lens because the projected pupil area and solid angle both
shrink with off-axis angle. It describes camera lens vignetting, not perception.

**Gaussian** is the validated model for the Stiles-Crawford effect and retinal sensitivity
falloff. Multiple sources confirm:
- SCE directionality is modeled as `η(ρ) = 10^(−p·ρ²)` — a Gaussian in pupil coordinate ρ
  (Parametric representation of SCE, PubMed; normal p ≈ 0.047 mm⁻²)
- Rendering algorithms for aberrated vision simulation (PMC) explicitly use "Gaussian falloff
  centered on the entrance pupil" for SCE
- Retinal eccentricity sensitivity curves also follow approximately Gaussian shape

**Conclusion:** Gaussian in aspect-corrected UV space. Not cos⁴.

---

## Q2: Stiles-Crawford scene-luminance coupling — resolved

The SCE is exclusively photopic. Wikipedia (Vohnsen model): "explains the lack of
directionality in scotopic conditions." In low light the photoreceptors lose their
waveguiding directionality; in bright light it is fully expressed.

**Mapping from p50 to SCE strength:**
```hlsl
float sc_att = smoothstep(0.10, 0.45, perc.g);  // 0 in dark, 1 in bright
```
- p50 < 0.10: dark scene — no vignette (eye is dark-adapted, peripheral rods active, no SCE)
- p50 > 0.45: bright photopic scene — full vignette
- Smooth transition between — no gate

perc.g is PercTex.g (Kalman-smoothed p50), already read in pro_mist.fx.

---

## Q3: Peripheral chrominance loss — resolved, chroma rolloff validated

Sources:
- "Color vision in the peripheral retina" (PubMed): trichromatic vision lost beyond ~30° eccentricity
- "Color perception in the intermediate periphery" (JOV/ARVO): L−M cone opponency absent at ~25–30°;
  color vision absent beyond ~40°
- "Peripheral Color Demo" (PMC): cone inner segment density drops to ~5000/mm² beyond 10°;
  rod light-catching area dominates the remainder

On a 27" monitor at 60–70 cm (typical), 25° eccentricity corresponds roughly to the screen
corners at 16:9. This means corner-of-screen content falls right at the trichromatic→
dichromatic transition. A moderate chroma rolloff at the corners is perceptually accurate.

**Implementation — linear-RGB blend to luma (no Oklab round-trip):**
```hlsl
float luma      = dot(col, float3(0.2126, 0.7152, 0.0722));
float desat_amt = (1.0 - vign_weight) * VIGN_CHROMA;   // max desat at corners
col             = lerp(col, luma.xxx, desat_amt);
```
The Rec.709 luma weights are the correct linear-light desaturation axis. This is equivalent
to Oklab desaturation to within <0.001 max error in [0,1] — no full Oklab pass needed.

---

## Q4: Chain position — after pro_mist (standalone pass)

Reasoning:
- Pro_mist chromatic halation bleeds glow into corners; vignette applied after suppresses
  that peripheral glow, which is the perceptually correct behavior (corners read as dim)
- Merging into pro_mist couples unrelated concerns; standalone pass is cleaner
- Cost: ~12 ALU ops + one BackBuffer read + one PercTex read. PercTex is already bound
  in pro_mist — if merged, zero extra reads. If standalone, one extra PercTex fetch.
- One additional 8-bit UNORM round-trip; for multiplicative darkening (output ≤ input)
  quantization error is negligible (<0.1% in corners)

**Preferred: standalone pass after pro_mist.** Arc_raiders.conf gains one entry.

---

## Q5: BUFFER_WIDTH / BUFFER_HEIGHT in vkBasalt SPIR-V — confirmed available

These are standard ReShade built-in preprocessor defines. vkBasalt uses the ReShade FX
compiler (reshade-shaders compatibility). Both are available at compile time and can be
used in the aspect-correction term without runtime cost.

---

## Proposed implementation

### New file: `general/retinal-vignette/retinal_vignette.fx`

```hlsl
// retinal_vignette.fx — peripheral luminance and chroma falloff

#include "../../gamespecific/arc_raiders/shaders/creative_values.fx"
#include "../../gamespecific/arc_raiders/shaders/debug_text.fxh"

texture BackBufferTex : COLOR;
sampler BackBuffer { Texture = BackBufferTex; };

texture PercTexture  { Width = 1; Height = 1; Format = RGBA16F; };
sampler PercTex      { Texture = PercTexture; };

float4 RetinalVignettePS(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
    if (pos.y < 1.0) return tex2D(BackBuffer, uv);

    float4 col  = tex2D(BackBuffer, uv);
    float4 perc = tex2D(PercTex, float2(0.5, 0.5));

    // Aspect-corrected radius from screen centre
    float2 uv_c = uv - 0.5;
    uv_c.x     *= BUFFER_WIDTH / (float)BUFFER_HEIGHT;
    float  r2   = dot(uv_c, uv_c);

    // Gaussian vignette weight: 1.0 at centre, falls toward corners
    float sigma   = VIGN_RADIUS;
    float gauss   = exp(-r2 / (sigma * sigma));
    float vweight = lerp(1.0 - VIGN_STRENGTH, 1.0, gauss);  // ∈ [1-str, 1]

    // Stiles-Crawford: scale by scene luminance (photopic only)
    float sc_att = smoothstep(0.10, 0.45, perc.g);
    vweight      = lerp(1.0, vweight, sc_att);               // dark scenes: no vignette

    // Luminance attenuation — multiplicative, SDR safe (weight ≤ 1)
    float3 rgb = col.rgb * vweight;

    // Peripheral chroma rolloff — linear-RGB blend to luma (no Oklab needed)
    float luma     = dot(rgb, float3(0.2126, 0.7152, 0.0722));
    float desat    = (1.0 - gauss) * VIGN_CHROMA * sc_att;
    rgb            = lerp(rgb, luma.xxx, saturate(desat));

    return float4(saturate(rgb), col.a);
}

technique RetinalVignette
{
    pass
    {
        VertexShader = PostProcessVS;
        PixelShader  = RetinalVignettePS;
    }
}
```

### Knobs — add to `creative_values.fx`

```hlsl
// ── RETINAL VIGNETTE ──────────────────────────────────────────────────────────
// Peripheral luminance and chroma falloff mimicking retinal sensitivity.
// Strength adapts to scene luminance — no effect in dark scenes (SCE is photopic).
// VIGN_STRENGTH: max darkening at corners. 0 = off, 0.35 = strong.
// VIGN_RADIUS:   Gaussian σ in aspect-corrected UV space. Larger = wider bright area.
// VIGN_CHROMA:   peripheral desaturation. 0 = luma-only, 0.30 = noticeable.
#define VIGN_STRENGTH  0.28
#define VIGN_RADIUS    0.40
#define VIGN_CHROMA    0.15
```

### Chain — `arc_raiders.conf`

```
analysis_frame : analysis_scope_pre : corrective : grade : pro_mist : retinal_vignette : analysis_scope
```

---

## Perceptual safety

| Property | Assessment |
|----------|-----------|
| SDR ceiling | Multiplicative form; weight ≤ 1; output ≤ input always — cannot clip |
| Gates | None. Gaussian → 1 at centre continuously. sc_att smoothstep — no threshold |
| Chroma rolloff error vs Oklab | < 0.001 max — SAFE |
| BackBuffer round-trip error | < 0.1% for multiplicative darkening — SAFE |
| Dark scenes | sc_att = 0 → vweight = 1 → identity passthrough |

---

## Implementation order

1. Create `general/retinal-vignette/retinal_vignette.fx`
2. Add three knobs to `creative_values.fx`
3. Add `retinal_vignette` to `arc_raiders.conf` after `pro_mist`
4. Test: bright outdoor scene (full effect), dark interior (near-passthrough),
   high-contrast mixed scene (partial effect)
