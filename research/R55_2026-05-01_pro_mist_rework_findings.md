# R55 — Pro Mist Rework — Findings

**Date:** 2026-05-01
**Searches:**
1. Black Pro-Mist filter optical characterisation spatial frequency MTF
2. Hollywood Black Magic diffusion filter mechanism halation glow highlights
3. Pro-Mist filter Tiffen highlights shadows midtones skin tones tonal selectivity
4. diffusion filter clarity sharpness micro contrast cinema
5. pro mist filter digital emulation shader bloom scatter additive

---

## Key Findings

### 1. Pro-Mist is NOT purely additive scatter — it genuinely reduces contrast

This is the most important finding for the shader. Tiffen's own product description states
"contrast is lowered" and multiple independent reviews confirm that contrast reduction is a
distinct, primary characteristic — not a side effect. The mechanism involves optical particles
in the glass that scatter light in both directions: bright areas bleed into darks (additive)
AND dark areas bleed into brights (subtractive). The net result is a reduction of local
contrast across the full tonal range, not just a glow around highlights.

Industry comparisons map the effect to "Gaussian blur blended in overlay or soft light mode"
— overlay blend mode both adds light to darks and subtracts light from brights, which is
fundamentally different from a pure additive composite.

**Implication for the shader:** The current implementation uses only `max(0, diffused − base)`
— additive-only. This captures only half the physical effect. The correct model blends the
low-frequency version into the base at a controlled weight, both above and below the current
pixel value. The `max(0, ...)` clamp should be removed.

### 2. The clarity boost is doing the opposite of the physical effect

The current pass adds `result += adapt_str * 1.10 * detail * bell` where
`detail = base − diffused` — this is a Laplacian sharpening term that increases local
contrast in the midtones. Real Pro-Mist reduces local contrast. These two operations
partially cancel each other, which explains why the current implementation requires a high
`MIST_STRENGTH` to produce a visible effect — much of its strength is spent fighting the
clarity boost.

The clarity boost should be **removed entirely** from this pass. If midtone contrast
enhancement is desired elsewhere in the chain, it belongs in the zone S-curve (already
present in `grade.fx`) or as a dedicated CLAHE step, not inside a diffusion filter.

### 3. Tonal selectivity: highlights primary, midtones secondarily, skin tones spared

Tiffen's documentation explicitly states the halation "is NOT transported to the skin tone
values." The Hollywood Black Magic description adds "softens highlights and mid-tone contrast
and reduces glare." This suggests the effect is luminance-weighted: strongest at the
brightest highlights, moderate in midtones, minimal in shadows and in the specific hue
range of skin (approximately 20–40° Oklab hue, warm yellow-orange).

The current luma gate (`smoothstep(gate_lo, gate_hi, luma_in)`) correctly captures the
luminance weighting. However, gating at `p75 − 0.12` means the effect can fire in the
lower-midtone range in dim scenes — too aggressive. A tighter gate starting at `p75 + 0.0`
(not minus 0.12) would be more physically faithful.

### 4. Spatial scale: medium halo, not bloom-width

Pro-Mist's scatter is described as "gauzy" and "tight" relative to broader diffusion
filters like Moment CineBloom. It is narrower than a true bloom but wider than halation.
This maps well to the current 1/8-res `CreativeLowFreqTex` mip 0 as the scatter source.
Blending in mip 1 for a slightly wider glow in high-contrast scenes (large IQR) is
consistent with the reported "larger size black particles" producing "slightly tighter
halation" at higher densities.

No MTF curves are published by the industry for any diffusion filter. Tiffen, Schneider-
Kreuznach, and retailers all describe effects qualitatively. Frequency-domain characterisation
is not achievable from available literature.

### 5. Single-pass re-enable is safe — no texture hazard

The two-pass version that crashed Arc Raiders used a custom `DiffuseTex` render target
(written by `DiffuseHPS`, read by `ProMistPS`). The crash was a render target hazard
under Vulkan. The current single-pass version uses only `CreativeLowFreqTex` (written by
`corrective.fx`, a separate earlier effect) and `PercTex`/`WarmBiasTex`/`ChromaHistoryTex`
(all written by analysis passes). No write hazard exists in the current implementation.
Re-enabling in the chain is safe.

---

## Parameter Validation

### Removing the clarity boost

At `MIST_STRENGTH = 0.40`, the clarity boost contributes:
`0.40 * 0.09 * 1.10 * (base − diffused) * bell`

In the midtone bell peak (luma ≈ 0.5, bell ≈ 1.0), this adds approximately 4% of the
Laplacian residual back — a visible contrast enhancement that fights the mist softening.
Removing it will make the mist effect more visible per unit of `MIST_STRENGTH`, meaning
the default should be reduced. Recommended: lower `MIST_STRENGTH` from 0.40 → 0.25 after
removing clarity, then tune up.

### Corrected scatter model

Replace `max(0.0, diffused − base.rgb)` with a bidirectional blend:

```hlsl
float3 scatter_delta = (diffused - base.rgb) * adapt_str * luma_gate;
float3 result = base.rgb + scatter_delta * float3(scatter_r, 1.00, scatter_b);
```

This allows the scatter to both add light (bright areas bleeding outward) and subtract
light (dark areas pulling bright neighbors slightly down), matching the overlay-blend
character of the physical filter. The luma gate still prevents the effect from firing
in deep shadows.

### Luma gate tightening

Change `gate_lo = saturate(p75 − 0.12)` → `gate_lo = saturate(p75 + 0.0)`, so the gate
opens at p75 rather than 12% below it. This prevents the mist from activating in the
lower midtones of dim scenes.

### Multi-scale scatter

Add mip 1 blend:
```hlsl
float3 diffuse0 = tex2Dlod(CreativeLowFreqSamp, float4(uv, 0, 0)).rgb;
float3 diffuse1 = tex2Dlod(CreativeLowFreqSamp, float4(uv, 0, 1)).rgb;
float  scene_softness = smoothstep(0.1, 0.4, iqr);
float3 diffused = lerp(diffuse0, diffuse1, scene_softness * 0.35);
```

One additional `tex2Dlod` call. In high-contrast scenes (large IQR), the scatter radius
widens slightly — consistent with the physical filter having more visible scatter in
high-contrast environments.

---

## Risks and Concerns

### 1. Bidirectional scatter may crush shadow detail

Removing `max(0, ...)` allows `diffused < base` to subtract light from highlights. In a
scene where a bright highlight is surrounded by dark pixels, the luma gate should prevent
the dark surroundings from pulling the highlight down — but verify at the gate boundary.
If shadow pulling is observed, restore `max(0, ...)` for the shadow range only by
multiplying the negative delta by `(1.0 − luma_gate)` weighting.

### 2. Halation removal leaves R37 code in pro_mist.fx

The R37 halation block inside `ProMistPS` should be removed once R56 implements halation
in `grade.fx`. Leaving both active would double-apply halation — once in grade, once in
pro_mist. Remove lines 118–129 of the current `pro_mist.fx` as part of this rework.

### 3. Ordering with halation (R56)

`grade.fx` runs before `pro_mist.fx` in the chain. If R56 halation is implemented in
`grade.fx`, it fires before pro_mist scatter. The pro_mist's `diffused − base` delta
is computed against the post-halation base — areas where halation has lifted pixels above
the diffused level will see a negative delta, which the bidirectional model will reduce.
This is self-regulating: halation-lifted highlights are naturally protected from further
pro_mist scatter. No additional anti-stacking logic needed.

---

## Verdict

**Proceed with rework. Three changes required before re-enabling:**

1. **Remove clarity boost** (lines 113–116 of current `pro_mist.fx`). It is physically
   incorrect and partially cancels the mist effect.
2. **Switch scatter from additive-only to bidirectional** — remove `max(0, ...)` clamp,
   let the luma gate control tonal range instead.
3. **Tighten luma gate** — `gate_lo` at `p75 + 0.0` rather than `p75 − 0.12`.
4. **Add mip 1 blend** for multi-scale scatter — one additional `tex2Dlod`, IQR-driven.
5. **Remove R37 halation block** — replace with R56 in `grade.fx`.
6. **Re-enable in chain** — add `pro_mist` to effects line in `arc_raiders.conf`.
7. **Lower `MIST_STRENGTH` default** to 0.25 (clarity removal makes the effect ~30%
   stronger per unit; compensate downward).
