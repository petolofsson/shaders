# Cost reduction — 2026-11-11

User request: reduce the FPS cost of the pipeline. GPU profiling is excluded (AGENTS), so the
work used a static cost model and user-read in-game FPS (GZW, same spot, shader on vs off via
Home). GPU: RX 9070 XT (RADV), 2560×1440.

## Result

| Build | FPS on / off | Shader cost |
|---|---|---|
| Start | 92 / 115 | 2.17 ms |
| After steps 1–4 | about the same | – |
| After step 5 (`OklabToSDR` fast path) | ~100 / 113 | ~1.15 ms |

Steps 1–4 each saved under ~0.1 ms (below FPS readout noise). Step 5 saved ~1.0 ms, more than
its 0.6 ms estimate, probably because removing two inlined copies of the projection from the
common path also lowered register pressure (higher occupancy).

## Steps (validation: settled headless captures, 7 GZW scenes with the production profile copy
`r5_cur`, plus Arc 210958 with the Arc profile; marker and last row masked)

1. **Trims:** inverse-grade gamut bisection 14 → 10 steps; `NativeGuideLogTex` R32F → R16F.
   ≤ 1 code, 0.22–0.89% px changed.
2. **Bit-identical restructuring** (0 codes changed):
   - compile-time skips of exact no-op stages: luma contrast (all `LUMA_CONTRAST_*` 0), hue
     rotation (all `HUE_*` 0), Retinex (`RETINEX_STRENGTH` 0); guided passes write zero when no
     consumer is active;
   - NearClip, MeanChroma, HistEntropy, CDFWalk, CDFWalkMode merged into `AnalysisStatsPS`
     (SceneCut stays separate: its RGBA16F output is read back rounded);
   - `AnalysisLaneSamples` (32×18) and `LLPoints` (16×16) cache lane samples for the
     single-texel loops;
   - one highway copy instead of three; the combined inverse grade reads `NeutralIllumTex`
     directly (same one-frame delay; stills cannot test timing).
   44 → 40 passes. The Arc check compared against a reconstructed copy of the previous tree.
3. **Analytic inverse-grade gamut limit** (`GamutMaxChroma`, Ottosson cusp with two Halley
   steps plus one upper-half Halley step, branch-free). Offline vs exact (300k colours): mean
   error 3e-6 (10-step bisection 2.3e-4); ~.016% of colours near the blue cusp (hue ≈ −96°,
   L ≈ .45) get a limit up to .047 C too high. Captures: ≤ 1 code on ≤ .004% px.
4. Static model (below) found `OklabToSDR` was the largest single cost.
5. **`OklabToSDR` early return** for in-gamut colours. The former code computed the full
   projection (10-step bisection, 5 Newton steps for blue, ~6 conversions) and then discarded it
   via `lerp(mapped, original, valid)`. Output-preserving pixel branch, authorized by the user and
   recorded in CODE_RULES. 0 codes changed. The projection still catches step 3's blue overshoot.

## Static model (before step 5)

Instruction count per pixel, transcendentals weighted 4×, ~12 T ops/s single-issue, 3.69 M px.

| Part | Ops/px | Est. ms |
|---|---|---|
| Fixed: vkBasalt copies, ~40 pass launches/barriers, serial 1×1 loops, full-res traffic | – | 0.4–0.6 |
| ColorTransform | ~3,050 | 0.9–1.0 |
| ↳ `OklabToSDR` | ~1,000 | 0.30 |
| ↳ 25-tap tonal neighbourhood | ~500 + 25 taps | 0.15–0.2 |
| ↳ surround-tint lightness math | ~320 | 0.10 |
| InverseGrade (incl. `OklabToSDR` ~1,000) | ~1,550 | 0.45 |
| Total | | ≈ 2.0–2.2 (measured 2.17) |

## Follow-up (same day, user: "minimal changes")

6. **Rounding-only bundle (done):** the chroma stage returns Oklab and, at `CHROMA_STRENGTH` 100
   (compile-time switch `GRADE_CHROMA_FULL`), goes straight to `OklabToSDR` without the RGB → Oklab
   round trip; the output dither stays sRGB-encoded (`DitherSDREncoded`) and is written directly
   instead of decode + re-encode. Static estimate ~0.04–0.05 ms. Validation (settled headless,
   marker/last row/right 24 px masked): 6 GZW scenes (133729, 133932, 172413, 210201, 224513,
   224557) ≤ 1 code on .01% px; Arc 210958 and a synthetic black/white/ramp frame ≤ 1 code on
   .01% px against the previous code (temporary stash). CC → tonal merge skipped (the RGB value is
   reused between, not minimal).
7. **`FILM_CURVE` 0 (rejected):** not inert. Same 6 scenes: five at noise (≤ .46% px); 133932
   (low sun) 1.2% px up to 38 codes: near-white highlights lose their colour (changed px
   max − min channel 40 → 33; sun disc 252 247 214 → 252 252 252). The film curve's luma-only
   shoulder keeps highlight hue; print's per-channel shoulder converges to white. Kept.

## Remaining options (not done)

- 25-tap tonal neighbourhood from a 1/8 copy: ~0.1–0.15 ms; changes the image, needs a pan check
  (a similar shortcut shimmered before).
- Surround-tint skip on lit pixels (~0.05–0.08 ms; not strictly output-identical, so outside the
  branch exception as written). CC → tonal Oklab merge (~0.02 ms, needs value threading).


8. **One highlight shoulder (done):** print stock's per-channel shoulder came after the SDR
   projection and, with the film curve on, contributed almost nothing (it relaxed by the film
   curve's share). Removed with its relief plumbing; the film curve (adaptive knee, luma-only,
   before the projection) is the only shoulder and `FILM_CURVE` now acts directly. Change vs the
   previous build: GZW 6 scenes ≤ 3 codes (133932 4.0% px, others ≤ .9%; bright L +0…+.17);
   Arc 210958 ≤ 5 codes, 10.5% px, .24% > 1 code. Merged build = test hook (0 codes).
- More pass/loop merges: < 0.03 ms total.
- Not possible: removing the full-res native-guide pass (ReShade FX cannot target the back
  buffer and a texture in one pass).
