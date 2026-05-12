# Handoff — 2026-05-12

> **Purpose (for AI context):** Current session state. Read at session start to orient. Update at session end. Changelog entries go in CHANGELOG.md.

## Active chain (testbed)

```
analysis_frame : inverse_grade : corrective : grade
```

grade is an **8-pass technique**: LFDownscale1 → LFDownscale2 → NeutralIllum → ColorTransform → DiffusionDownsample → DiffusionBlurH → DiffusionBlurV → Diffusion

## Pipeline state

| Stage | Finished | Novel |
|-------|----------|-------|
| Stage 0 — Input | 99% | 92% |
| Stage 1 — Film Stock | 98% | 94% |
| Stage 2 — Tonal | 97% | 91% |
| Stage 3 — Color + Halation | 98% | 90% |
| Output — Diffusion + Grain | 97% | 94% |

## Known state

- No known compile errors. Debug log: `/tmp/vkbasalt.log`
- R187 complete and validated. Inverse grade is **single-pass** — bilateral blur passes (LocalLumaDownH/V), LocalLumaHTex/LocalLumaTex, and MeanChromaTex all removed.
- **R187 formula**: `C * factor` (zero-anchored). `lerp_t = saturate(INVERSE_STRENGTH * (1 - lab.x) * c_weight * dir_scale)`. Full expansion at L=0, zero at L=1. No contraction possible.
- **Luma-gated EXPOSURE** in grade.fx: `gain = lerp(E, 1.0, smoothstep(0.55, 0.85, lum))` — highlights preserved, no white-out from stops-based multiplication on pre-tonemapped SDR.
- **EXPOSURE** stops-based `rgb * pow(2, EXPOSURE)`. Testbed at 0.17 EV (recalibrated post-R187).
- **FilmCurve** rational shoulder + toe. Asymptotically SDR-bounded by construction.
- **CHROMA_SHOULDER** (renamed from HCHROMA_ROLLOFF) — ACES 2.0-inspired L²-weighted Michaelis-Menten toe. Default 0.0 in both profiles.
- **VIBRANCE** first in CHROMA section (lift-only, reach for this first). **SATURATION** below it (global, uniform).
- **Skin tone fix** in testbed: ROT_RED 0.00, SAT_RED −0.10, SAT_YELLOW −0.10. R156 warm-hue bias compresses orange/skin more than neutral hues — reducing chroma in those bands restores skin character.
- **Current creative_values** — read live from `creative_values.fx` files; do not cache here.
- **Mid-shadow off-color** — unverified post R127/R130. Likely resolved. Re-test before marking closed.

## Next candidates

- **ApplyChroma** still ~80 lines — over Rule 4 limit. Split into ApplyChromaLift + ApplyChromaFinish deferred.
- **CHROMA_SHOULDER calibration** — default 0.0; try 0.35 as starting point when evaluating highlight rolloff character.
- **vk-colorist Phase 0** — Rust/Vulkan layer infrastructure is independent of shader quality; can start when ready.
- **Re-test mid-shadow off-color** — confirm resolved before vk-colorist Phase 2.
