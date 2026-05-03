# R83 — Chromatic FILM_FLOOR
**2026-05-03 | Stage 0 novel +5%**

## Problem

`FILM_FLOOR` is a scalar black pedestal — identical across all three channels. Real print
film has a per-channel base density (D-min): the unexposed emulsion base has a chromaticity
driven by the specific dye-layer chemistry and the scene illuminant under which the print
is viewed.

Kodak 2383 Technical Data confirms the per-channel density asymmetry: Status A density aim
for a visual neutral at D=1.0 is **1.09 red / 1.06 green / 1.03 blue** — the film base
sits warmer than true neutral. A linear scalar floor cannot reproduce this.

The CAT16 illuminant estimate is already computed in `lf_mip2` (hoisted, zero new taps).
The LMS illuminant chromaticity provides the signal to modulate the per-channel floor
physically rather than empirically.

## Targets

Stage 0 novel: 70% → 75%

## Research questions

1. What is the relationship between scene illuminant chromaticity (in CAT16 LMS) and
   per-channel D-min for Kodak 2383? Specifically: warm illuminant → floor shifts warm,
   cool illuminant → shifts cool. What scale factor is appropriate?
2. Does the per-channel floor interact with the CAT16 neutral already applied above it?
   (Expected: no — CAT16 normalises toward D65 before the floor is applied.)
3. What range of per-channel offsets is physically plausible? (D-min ratio implies
   ±2–3% spread across channels, which at FILM_FLOOR=0.01 is ~0.0002–0.0003 absolute.)

## Proposed implementation

Stage 1, replaces scalar `FILM_FLOOR` application:

```hlsl
// per-channel floor from illuminant chromaticity — lms_illum already in scope from CAT16
float3 cfilm_floor = FILM_FLOOR * (lms_illum_norm * float3(1.02, 1.00, 0.97));
col.rgb = col.rgb * (FILM_CEILING - cfilm_floor) + cfilm_floor;
```

GPU cost: 3 MAD. No new taps. No new knobs — FILM_FLOOR remains the scalar control.

## Constraints

- Must not interact destructively with CAT16 neutral (CAT16 runs above this)
- Must be self-limiting: at FILM_FLOOR=0, output is identity regardless of illuminant
- No outer gate — effect must be continuous
