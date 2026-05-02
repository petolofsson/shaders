# R79 — Halation Dual-PSF + Gate Refinement + Chromatic Dispersion

**Date:** 2026-05-03
**Status:** Proposed

## Problem

The current halation block (R56) has three limitations:

1. **hal_gate too conservative.** `smoothstep(0.80, 0.95, hal_luma)` only fires above
   luma 0.80. Mid-brightness coloured surfaces (luma 0.55–0.75) near light sources
   should receive some halation in film.

2. **Single spatial scale per channel.** One mip per channel (mip 1 for red, mip 0
   for green) gives a single Gaussian PSF. Real film halation has a tight core plus
   extended wings — a two-Gaussian model with a narrow lobe and a wide low-amplitude
   lobe.

3. **No chromatic dispersion in the wings.** The extended scatter wing should be
   slightly warmer than the tight core — longer wavelengths penetrate deeper into the
   film base and scatter further spatially.

## Research tasks

### R79A — Gate onset
Find the halation onset in Kodak 2383 (or equivalent print stock) as a function of
exposure density. Convert to linear light luma threshold. Published data source:
Kodak 2383 data sheet, or film halation characterisation papers (Hunt, Colour
Reproduction in Photography, or equivalent).

### R79B — Two-Gaussian PSF
Find published optical measurements or models for film halation PSF. Identify the
ratio of tight-core radius to extended-wing radius, and the amplitude ratio. Map to
mip-level pairs: mip 0 (1/8-res) as core, mip 2 (1/32-res) as wing.

### R79C — Chromatic dispersion
Determine the wavelength-dependent penetration depth in gelatin film base. Longer
wavelengths (red ~700nm) scatter wider than shorter (green ~550nm). Derive whether
the warm bias in the extended wing is measurable at print stock output level, or
is cancelled by the print stock dye response.

## Likely implementation sketch

```hlsl
// R79A: softer gate
float hal_gate = smoothstep(0.65, 0.90, hal_luma);

// R79B: dual-PSF — core (mip 0/1) + wing (mip 2)
float3 hal_core = ...; // existing mip 0/1 reads
float3 hal_wing = tex2Dlod(CreativeLowFreqSamp, float4(uv, 0, 2)).rgb;
float3 hal_delta = hal_core * 0.7 + hal_wing * 0.3 - lin;  // blend ratios TBD

// R79C: warm wing bias
// Extended wing gets slight warm shift — implementation TBD from research
```

## GPU cost

+2 tex taps (mip 2 for red and green extended wing). ~6 ALU.
