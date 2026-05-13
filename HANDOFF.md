# Handoff — 2026-05-13

> **Purpose (for AI context):** Current session state. Read at session start to orient. Update at session end. Changelog entries go in CHANGELOG.md.

## Active chain (testbed)

```
analysis_frame : inverse_grade : corrective : grade
```

grade is a **10-pass technique**: LFDownscale1 → LFDownscale2 → NeutralIllum → BilateralLogH → BilateralLogV → ColorTransform → DiffusionDownsample → DiffusionBlurH → DiffusionBlurV → Diffusion

## Pipeline state

See PLAN.md for authoritative scores and reasoning.

## Known state

- No known compile errors. Debug log: `/tmp/vkbasalt.log`
- **Data highway** lives in `HighwayTex` (256×1 R16F, declared in `highway.fxh`). BackBuffer is a pure image surface — no y=0 data, no guards needed. `ReadHWY` reads from `HighwaySamp` via `tex2Dlod`. Write passes (`HighwayWritePS`, `RenderTarget=HighwayTex`) are last in `analysis_frame` and `corrective` techniques. `inverse_grade` reads `illum_warm` from `NeutralIllumTex` directly.
- **Highway slots renamed:** `HWY_CHROMA_SLOPE` (was `HWY_SLOPE`), `HWY_MEDIAN_C` (was `HWY_MEAN_CHROMA`). `HWY_STEVENS` removed (dead slot).
- **inverse_grade actual state**: R187 + R189 complete. **Single-pass** (InverseGradePS only). LocalLumaDownH/V passes, LocalLumaHTex/LocalLumaTex, L_local, BILATERAL_ZONE_DEBUG all removed. Bell curve zone weight applied: `zone_w = 4.0 * lab.x * (1.0 - lab.x)` — peaks at midtone, zero at black/white. Matches ACES compression profile and cinema chroma zone research.
- **inverse_grade lerp_t**: `saturate(INVERSE_STRENGTH * zone_w * c_weight * dir_scale)` where `zone_w = 4.0 * lab.x * (1.0 - lab.x)` (midtone bell, research-grounded).
- **HWY_CHROMA_SLOPE** (slot 197): replaced IQR+Bowley (broken in linear luma space — always clamped to 1.15) with `lerp(1.8, 1.15, saturate(median_C / 0.15))`. Low scene chroma → slope 1.8 (max expansion); vivid scene → slope 1.15. Encode/decode unchanged.
- **Luma-gated EXPOSURE** in grade.fx: `gain = lerp(E, 1.0, smoothstep(0.55, 0.85, lum))` — highlights preserved, no white-out from stops-based multiplication on pre-tonemapped SDR.
- **EXPOSURE** stops-based `rgb * pow(2, EXPOSURE)`. Testbed at 0.17 EV (recalibrated post-R187).
- **FilmCurve** rational shoulder + toe. Asymptotically SDR-bounded by construction.
- **CHROMA_SHOULDER** (renamed from HCHROMA_ROLLOFF) — ACES 2.0-inspired L²-weighted Michaelis-Menten toe. Default 0.0 in both profiles.
- **VIBRANCE** first in CHROMA section (lift-only, reach for this first). **SATURATION** below it (global, uniform).
- **Skin tone fix** in testbed: ROT_RED 0.00, SAT_RED −0.10, SAT_YELLOW −0.10. R156 warm-hue bias compresses orange/skin more than neutral hues — reducing chroma in those bands restores skin character.
- **Illuminant-adaptive halation** — `ApplyHalation` G weights modulated by `ctx.illum_warm`. `g_mod = 1 − (illum_warm − 0.39) × 0.25`. G weights corrected to emulsion physics R:G:B ≈ 30:3:1 (was ~4× too high). D65 neutral = no change.
- **Scene-adaptive HK + Abney** — `hk_coeff = lerp(0.32, 0.18, zone_log_key / 0.50)` — direction corrected (H-K stronger at low luminance per Hellwig 2022 + Nayatani 1997). HK gate inverted: fades above L=0.55, not below. Abney scale `1 + ctx.median_C × 0.25`. Abney per-hue corrected per Pridmore 2007 (YELLOW near-null, CYAN largest).
- **Physics audit complete (2026-05-13)** — all stages (0–3, Output) audited. No direction bugs in Stages 0, 1, 2, Output. Stage 3 bugs were corrected in prior session. All physics-direction constants sourced from literature; calibration amplitudes empirically tuned (standard practice). One doc correction: grain envelope `sqrt(1−L_gamma)` peaks mathematically at pure black, not L≈0.50 — perceived peak is upper shadows (grain at pure black is invisible).
- **Current creative_values** — read live from `creative_values.fx` files; do not cache here. GZW profile tuned for jungle movie aesthetic (teal-green shadows, green mids, golden highlights) — separate from arc_raiders testbed.
- **Halation stage fix** — `ApplyHalation` moved to pre-FilmCurve in `ApplyCorrective`. All three signals (pixel, lf_mip1, lf_mip2) now pre-corrective. Physically correct: halation is a camera-negative phenomenon.
- **Retinex stage fix** — `nl_safe * zk_safe / illum_s0` → `new_luma * zk_safe / illum_s0`. Both `zk_safe` and `illum_s0` are pre-corrective; `new_luma` is current post-zone value being corrected multiplicatively — no mixed-stage absolute target.
- **Mid-shadow off-color** — unverified post R127/R130. Likely resolved. Re-test before marking closed.

- **R189 bilateral tonemapper** — `BilateralLogH/V` passes at 1/8-res (σ_s=2 texels=16px, σ_r=0.4 log10). `BILATERAL_STRENGTH` blends local illumination toward global key. `CLARITY_STRENGTH` scales detail layer (>0 = punch, <0 = soften). Both no-op at 0. Testbed: BILATERAL_STRENGTH 0.30, CLARITY_STRENGTH 0.25.
- **Bilateral Retinex improvement** — evaluated and deferred. Swapping LowFreqMip1 for bilateral base in shadow lift/Retinex is zero extra cost but marginal improvement (only visible near hard luminance edges). Code complexity not worth it now.

## Next candidates

- **ApplyChroma** still ~80 lines — over Rule 4 limit. Split into ApplyChromaLift + ApplyChromaFinish deferred.
- **CHROMA_SHOULDER calibration** — default 0.0; try 0.35 as starting point when evaluating highlight rolloff character.
- **vk-colorist Phase 0** — Rust/Vulkan layer infrastructure is independent of shader quality; can start when ready.
- **Re-test mid-shadow off-color** — confirm resolved before vk-colorist Phase 2.
