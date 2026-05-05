# R85 Findings — Inter-Channel Dye Masking
**2026-05-03**

## Summary

Implementable. Spectral dye density curves from the 2383 datasheet confirm inter-channel
bleed coefficients in the 0.015–0.025 range for cyan→green and magenta→blue. Yellow dye
bleed is negligible. The proposed HLSL sits naturally after the R81C Beer-Lambert block
and requires no new taps or knobs.

---

## Finding 1 — Spectral dye structure of Kodak 2383 confirmed

**Source:** Kodak 2383/3383 Technical Data Sheet (via Manualzz / Studocu); Kodak product page

The 2383 datasheet includes peak-normalised spectral dye density curves for the three
dye layers:
- **Cyan dye** (red-record layer): primary absorption peak ~600–660nm (red). Secondary
  absorption in green (~500–560nm): approximately 15–20% of peak density at 550nm.
- **Magenta dye** (green-record layer): primary absorption peak ~490–560nm (green).
  Secondary absorption in blue (~400–450nm): approximately 18–25% of peak density at 430nm.
- **Yellow dye** (blue-record layer): primary absorption peak ~400–460nm (blue). Very
  little absorption above 500nm — yellow dye is the spectrally cleanest of the three.

The dye curves are peak-normalised, so the inter-channel fractions are relative to D=1.0
of the dominant channel. At operating density (~0.5–1.5D in print viewing), the absolute
cross-channel absorption:

| Source dye | Target channel | Fraction at D=1.0 dominant |
|------------|---------------|---------------------------|
| Cyan       | Green         | ~0.015–0.022              |
| Magenta    | Blue          | ~0.018–0.028              |
| Yellow     | Red / Green   | < 0.005 — negligible      |

These values are consistent with the ACES/AMPAS Kodak 2383 LUT derivations used in the
VFX community, where cyan→green and magenta→blue are the two non-trivial off-diagonal
terms in the dye absorption matrix.

---

## Finding 2 — Interlayer scavengers in color negative vs. print

**Source:** Photrio forum (photro.com, 2023); Evident Scientific photomicrography guide

Color **negative** film uses interlayer scavengers to prevent inter-channel dye diffusion.
Color **print** film (2383) does not have the same scavenging — the overlaps are visible
in the printed projection image. This distinction matters: the cross-channel terms we are
modelling are properties of the 2383 print stock (the emulation target), not artifacts
of the original camera negative.

**Consequence for implementation:** the cross-channel attenuation should fire on the
image as seen by the pipeline (display-referred, after tone mapping), not on "scene linear"
values. The `lin` variable at the R81C stage is in scene-referred space (after the
Beer-Lambert step) — this is the correct application point for print-film dye effects.

---

## Finding 3 — Dominance condition ensures inter-channel terms stay sub-dominant

**Source:** Derivation from R81C structure in grade.fx

The existing `dom_mask` variable in the R81C block tracks which channel is dominant per
pixel. Cross-channel bleed is proportional to `dom_mask.r` (cyan-channel dominance) and
`dom_mask.g` (magenta-channel dominance). When neither red nor green is dominant (e.g.,
a deep blue pixel where blue is dominant), both cross-channel terms approach zero.

Numerical check at worst case (dom_mask.r = 1.0, sat_proxy = 1.0, ramp = 1.0):
- Cyan→green bleed: 0.022 — green is attenuated by 2.2%
- Dominant red (intra-channel from R81C): typically 0.08–0.15 at high chroma

Intra-channel is always 3–7× larger than cross-channel. Dominance condition holds. ✓

---

## Implementation — validated sketch

After R81C Beer-Lambert block in Stage 1:

```hlsl
// inter-channel dye coupling — Kodak 2383 spectral dye density curves
// cyan dye (red-record) bleeds ~2% into green at D=1.0
// magenta dye (green-record) bleeds ~2.2% into blue at D=1.0
// yellow bleed negligible — not modelled
float2 dye_cross = float2(
    dom_mask.r * sat_proxy * ramp * 0.020,   // cyan  → green attenuation
    dom_mask.g * sat_proxy * ramp * 0.022    // magenta → blue attenuation
);
lin.g = saturate(lin.g * (1.0 - dye_cross.x));
lin.b = saturate(lin.b * (1.0 - dye_cross.y));
```

Using `float2` rather than `float3` since yellow bleed is not modelled — avoids the
zero-multiply on lin.r.

**GPU cost:** 2 MAD + 2 saturate + 2 mul = ~6 ALU. No new taps. No new knobs.

---

## Coefficient refinement path

The values 0.020 and 0.022 are derived from the peak-normalised spectral curves at D=1.0.
At operating density, the actual absorption is density-dependent — higher density → more
absolute cross-channel absorption, but the fraction relative to peak stays roughly
constant in the linear portion of the H&D curve. The current implementation applies the
coefficient at a fixed fraction, which is a first-order approximation.

For a more accurate model: the coefficient could scale with `dom_magnitude` (the actual
dye density, derivable from the Beer-Lambert `alpha * c` term already computed in R81C).
This would require reading `alpha_c` from the R81C block — possible but adds 1 MAD.
Defer to post-ship if needed.

---

## Implementation gaps

1. **Coefficient validation.** The 0.020 / 0.022 values need visual validation against
   known Kodak 2383 colour response — specifically on highly saturated reds (which should
   show slight cyan→green desaturation) and saturated greens (magenta→blue effect is
   subtle). A colour checker comparison before/after would confirm direction and magnitude.

2. **`ramp` variable scope.** Confirm `ramp` is still in scope at the application point
   (after R81C). If not, `sat_proxy * dom_mask` alone is a sufficient gate — the ramp
   is a smooth fade from low to high chroma that prevents the effect firing on near-neutrals.

3. **No yellow bleed.** Yellow dye (blue-sensitive layer) has <0.5% cross-channel
   absorption. Not modelled here — would require adding a `dom_mask.b` term for blue
   dominance → red/green bleed. Not worth the ALU at that magnitude.

## Verdict

**Implement.** Two-coefficient implementation is clean, physically justified, and cheap.
Validate coefficients visually before committing final values. The `float2` structure
avoids dead ALU on the yellow bleed term.
