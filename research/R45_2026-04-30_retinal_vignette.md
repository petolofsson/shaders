# R45 — Retinal Vignette

**Date:** 2026-04-30
**Status:** Proposal

---

## Motivation

A standard radial vignette (simple power-law darkening toward corners) was considered and
rejected — it reads as a post-process artifact rather than a natural optical effect.
The intended replacement is a *retinal vignette*: a luminance- and chrominance-aware
peripheral attenuation that mirrors how the human visual system actually loses sensitivity
away from the fovea. This was never built.

---

## Biological basis

The retina has three distinct sensitivity gradients relevant here:

**1. Spatial acuity falloff**
Cone density drops sharply outside the foveal pit (~1–2° of arc). Perceived contrast
and detail fall off roughly as a Gaussian in eccentricity. This is what a vignette
approximates spatially.

**2. Stiles–Crawford effect (SCE)**
Light entering the pupil obliquely (as from peripheral screen area) stimulates
photoreceptors less effectively. The SCE is strongest in photopic (bright) conditions
and nearly absent in scotopic (dark) conditions. Consequence: peripheral darkening
should be scene-luminance-dependent — stronger in bright scenes, weaker in dark ones.
The scene's p50 (median luminance from PercTex) is already available in grade.fx and
pro_mist.fx.

**3. Peripheral chrominance loss**
Rod density increases toward the periphery; rods carry no color information. The
periphery is effectively less saturated perceptually. A retinal vignette should
optionally desaturate toward the edges in addition to darkening.

---

## Behavioral differences from vignette.fx

| Property | Standard vignette | Retinal vignette |
|----------|------------------|-----------------|
| Strength | Fixed knob | Adapts to scene luminance (p50) |
| Chrominance | None | Optional chroma rolloff at periphery |
| Math | pow(r, n) | Gaussian or cos⁴ with scene modulation |
| Self-limiting | No (crushes highlights) | Yes — darkening bounded by headroom |
| SDR safe | Depends | By construction via multiplicative form |

---

## Constraints checklist

- SDR by construction: use multiplicative form (output = pixel × vignette_weight);
  weight ∈ [v_min, 1.0], never boosts, never clips
- No gates: the radial falloff must be smooth everywhere; no threshold on radius
- No auto-exposure: vignette strength may adapt to p50 but must not override EXPOSURE
- creative_values.fx is the only tuning surface
- GPU budget: UE5 saturates the GPU — must be either (a) merged into an existing pass
  or (b) a trivially cheap standalone pass (no texture reads beyond BackBuffer + PercTex)
- SPIR-V: no `static const float[]`, no variable named `out`
- BackBuffer guard: if standalone pass writes BackBuffer, guard `if (pos.y < 1.0) return col;`

---

## Candidate approaches

### A. Merged into pro_mist.fx (preferred)
Pro_mist already reads PercTex for `auto_hal`. Adding a radial weight computation
costs ~5 ALU ops and zero extra texture reads. Apply as a final multiplicative blend
before the pro_mist output write. Keeps pass count unchanged.

**Risk:** pro_mist diffusion already softens the image; vignette on top may look
over-cooked. Need to assess interaction.

### B. Separate lightweight pass (after pro_mist)
A new effect with one pass: reads BackBuffer + PercTex (already bound), writes
BackBuffer with radial weight applied. No render targets needed. ~10 ALU ops.
Arc_raiders.conf would gain one entry.

**Risk:** one more 8-bit UNORM round-trip on BackBuffer (~0.2% max error).
For a multiplicative operation the quantization error is negligible in dark corners.

### C. Merged into grade.fx / ColorTransformPS
ColorTransformPS already reads PercTex. UV coordinates available via TEXCOORD.
But register pressure in ColorTransformPS is already near the 128-scalar spill
threshold (R25/R26). Adding even 3 floats risks a spill.

**Risk:** register pressure. Not recommended unless R45 findings show headroom.

---

## Proposed math

```hlsl
// Screen UV centered at (0.5, 0.5), aspect-corrected
float2 uv_c   = texcoord - 0.5;
uv_c.x       *= BUFFER_WIDTH / (float)BUFFER_HEIGHT;
float  r2     = dot(uv_c, uv_c);               // [0, ~0.3] for 16:9

// Gaussian falloff — self-limiting, no threshold
// VIGN_RADIUS controls the e⁻¹ point; VIGN_STRENGTH is max darkening
float  gauss  = exp(-r2 / (VIGN_RADIUS * VIGN_RADIUS));
float  weight = lerp(1.0 - VIGN_STRENGTH, 1.0, gauss);   // ∈ [1-str, 1]

// Stiles-Crawford: adapt strength to scene luminance (photopic vs scotopic)
// p50 from PercTex — already available
float  sc_att = lerp(0.6, 1.0, smoothstep(0.15, 0.55, perc.g));
weight        = lerp(1.0, weight, sc_att);                 // dim scenes get less vignette

// Multiplicative apply — SDR safe by construction (weight ≤ 1)
float3 col_out = col * weight;

// Optional: chroma rolloff — reduce saturation at periphery in Oklab
// Blend factor 1 - gauss (maximum desaturation at corners)
// float3 lab = RGBtoOklab(col_out);
// lab.yz *= lerp(1.0 - VIGN_CHROMA, 1.0, gauss);
// col_out = OklabToRGB(lab);
```

**Proposed knobs** (creative_values.fx):
- `VIGN_STRENGTH` — max darkening at corners, range [0.0, 0.45], default ~0.25
- `VIGN_RADIUS` — Gaussian σ in aspect-corrected UV space, range [0.2, 0.6], default ~0.38
- `VIGN_CHROMA` — optional chroma rolloff at periphery, range [0.0, 0.30], default 0.0
  (off by default; the luminance effect alone is the primary value)

---

## Open research questions

1. **Cos⁴ vs Gaussian vs r²-polynomial** — natural lens vignetting follows cos⁴(θ)
   (cos⁴ law of illumination). For game footage (no real lens) Gaussian is perceptually
   cleaner. Research: which matches the retinal sensitivity curve more accurately?

2. **Correct SCE attenuation curve** — the Stiles–Crawford function is approximately
   `η(ρ) = 10^(−0.05 ρ²)` where ρ is entrance pupil position in mm. Mapping from
   scene luminance (p50) to effective eccentricity is non-trivial. What simplification
   preserves the perceptual intent?

3. **Chroma rolloff — Oklab vs luma-only** — doing the chroma rolloff in Oklab requires
   a full RGBtoOklab + OklabToRGB round-trip. Is there a good linear-space approximation
   that reduces saturation without the full conversion? (E.g., blend toward luma-only.)

4. **Chain position** — before or after pro_mist? Pro_mist adds glow that bleeds into
   corners; vignette after pro_mist would suppress that glow at edges (more natural).
   But vignette before pro_mist means the diffusion halo from vignetted edges looks
   correct. Which is more filmic?

5. **Aspect ratio and screen resolution** — the aspect-corrected UV must account for
   BUFFER_WIDTH / BUFFER_HEIGHT at shader compile time (these are ReShade built-ins).
   Verify they are available in the vkBasalt SPIR-V compilation path.

---

## Implementation plan (pending findings)

1. Resolve open questions via literature search + first-principles derivation
2. Choose chain position (likely: standalone pass after pro_mist, or merged into pro_mist)
3. If standalone: add entry to arc_raiders.conf and new .fx file
4. Add three knobs to creative_values.fx
5. Test on Arc Raiders: bright outdoor scene, dark interior, high-contrast mixed scene
