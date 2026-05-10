# Handoff — 2026-05-10

> **Purpose (for AI context):** Current session state. Read at session start to orient. Update at session end. Changelog entries go in CHANGELOG.md.

## Active chain (testbed)

```
analysis_frame : inverse_grade : corrective : grade
```

grade is an **8-pass technique**: LFDownscale1 → LFDownscale2 → NeutralIllum → ColorTransform → DiffusionDownsample → DiffusionBlurH → DiffusionBlurV → Diffusion

## Pipeline state

| Stage | Finished | Novel |
|-------|----------|-------|
| Stage 0 — Input | 98% | 92% |
| Stage 1 — Film Stock | 98% | 94% |
| Stage 2 — Tonal | 97% | 91% |
| Stage 3 — Color + Halation | 98% | 90% |
| Output — Diffusion + Grain | 97% | 94% |

## Known state

- No known compile errors. Debug log: `/tmp/vkbasalt.log`
- R159–R180 complete. R161/R164/R176-autochroma permanently dropped.
- R174: grain rain fixed — fixed luma_scale=2.5, 24fps slot snap, correct 2383 per-channel dye sizing (R×1.15/G×1.00/B×0.85).
- R175: shadow lift gate now (p25+mode)×0.5. Pixel bell `smoothstep(0.23,0,luma)` (tuned from 0.27→0.23 this session).
- R177: MeanChroma EMA ~1s τ, scene-cut reset. Was tracking walls in ~200ms.
- R178: Shadow lift gated on zone_std — `smoothstep(0.05,0.13,zone_std)` suppresses to zero in high-contrast interiors.
- R179: Chroma lift dead zones closed — ±0.14 pivot weight (was ±0.08). All 12 hue regions covered. Confirmed working.
- R180: Eye-shape diffusion — 90°-rotated eye, foci at |dy|=0.70, widest ±12.5% at center. 10% midtone baseline at center. src_gate `smoothstep(0.10,0.40,L)`. adapt_str 0.22, midtone scalar 0.09.
- VIBRANCE: autochroma removed — `chroma_str_base = VIBRANCE × 0.04` directly. CHROMA_STR renamed VIBRANCE everywhere. Lightroom Vibrance semantics (lift-only, self-masked).
- **Current creative_values** — read live from `creative_values.fx` files; do not cache here.
- **Mid-shadow off-color** — unverified post R127/R130. Likely resolved. Re-test before marking closed.

## Next candidates

- **Re-test mid-shadow off-color** — confirm resolved before vk-colorist Phase 2.
- **vk-colorist Phase 0** — Rust/Vulkan layer infrastructure is independent of shader quality; can start now.
- **ApplyChroma** still ~80 lines — over Rule 4 limit. Split into ApplyChromaLift + ApplyChromaFinish deferred.
