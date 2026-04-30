# Pipeline Changelog

Session history extracted from HANDOFF.md. Most recent first.

---

## 2026-04-30 (session 5)

### R29 — Multi-Scale Retinex implemented (`grade.fx`)
Replaced R18 zone-normalization (4×4 step function) with pixel-local Multi-Scale Retinex
using `CreativeLowFreqTex` mip levels 0/1/2 (already computed free by corrective Pass 1):
```hlsl
float log_R = 0.20 * log(luma_s / illum_s0)
            + 0.30 * log(luma_s / illum_s1)
            + 0.50 * log(luma_s / illum_s2);
float retinex_luma = saturate(exp(log_R + log(max(zone_log_key, 0.001))));
new_luma = lerp(new_luma, retinex_luma, smoothstep(0.04, 0.25, zone_std));
```
Coarse-biased weights (0.20/0.30/0.50) from research findings. Blend fully automated via
`zone_std` — flat scenes get no correction, contrasty scenes get full correction.
Mip 1 tap is shared with the R30 wavelet clarity block (no redundant reads).

### R28 — Kalman temporal filter implemented (`corrective.fx`)
Replaced heuristic adaptive EMA (`1 + 10 * abs(delta)`) in both history passes:
- `SmoothZoneLevelsPS`: Kalman on zone median (.r), EMA K_inf=0.095 on p25/p75
- `UpdateHistoryPS`: Kalman on chroma mean (.r), EMA K_inf=0.095 on std/wsum
- Kalman P (error variance) stored in `.a` channel of both history textures
- Cold-start: P initialized to 1.0 → K≈1 → immediate lock-on; converges in ~10 frames
- `ZONE_LERP_SPEED` and `LERP_SPEED` defines retired; replaced by `KALMAN_Q=0.0001`,
  `KALMAN_R=0.01`, `KALMAN_K_INF=0.095`

### R30 — Wavelet clarity implemented (`grade.fx`)
Replaced 2-level Laplacian pyramid with 3-band Haar decomposition:
```hlsl
float D1 = luma - illum_s0;       // fine:   full-res → 1/8-res
float D2 = illum_s0 - illum_s1;   // mid:    1/8-res  → 1/16-res
float D3 = illum_s1 - illum_s2;   // coarse: 1/16-res → 1/32-res
float detail = D1 * 0.50 + D2 * 0.30 + D3 * 0.20;
```
Eliminates the empirical `lerp(..., 0.6)` blend. Each band is orthogonal; weights from
satellite imagery literature (fine-biased: 0.50/0.30/0.20). No extra texture taps —
illum_s1 (mip 1) shared with R29 Retinex.

### R31 — Nyquist sampling analysis (no change)
Research confirmed: 8 samples/frame + Kalman α=0.095 ≈ 160 effective accumulated samples
(p95 accuracy). 16 zones slightly above Reinhard (8) / Ansel Adams (11) reference but
harmless. Current design is theoretically justified.

### R32 — Zone stats pre-computed in ChromaHistoryTex col 6 (`corrective.fx`, `grade.fx`)
`UpdateHistoryPS` now handles `band_idx == 6` as a zone-stats gather:
- Reads all 16 zone medians from `ZoneHistoryTex`
- Writes `float4(zone_log_key, zone_std, zmin, zmax)` to ChromaHistoryTex column 6, row 0
`grade.fx ColorTransformPS` replaces the 16-tap zone gather + 16 `log()` calls with 1 read
from `ChromaHistory` column 6. Eliminates ~33M `log()` calls/frame at 1080p.
Uses free pixels in an existing texture — no new textures, no new passes.

### Pro_mist strength reduced
`adapt_str` base: `0.36 → 0.09` (÷4). IQR-adaptive range now 0.063–0.117.

### Alpha highway extension — reverted
Attempted BackBuffer alpha as data channel for zone stats — discarded. Game framebuffer
alpha at row y=0 is not stable between frames. R32 via ChromaHistoryTex is the clean solution.

---

## 2026-04-30 (session 4)

### Lateral domain research — nightly job restructured
`job_general_research.md` rewritten from scratch. New approach:
- 7-domain weekly rotation (radio astronomy, seismic, medical imaging, remote sensing,
  telecoms, climate science, sonar) determined from ISO week number
- Math-first search terms — never search "shader", "game", "rendering"
- Every finding assessed against 6 pipeline mathematical problems
- HIGH PRIORITY flag for High visual impact + Low/Medium GPU cost findings

### New proposals filed
- `R28_2026-04-30_Kalman_Temporal_History.md` — replace adaptive EMA heuristic in
  SmoothZoneLevels + UpdateHistory with scalar Kalman filter; P stored in unused .a
  channel; zero new passes
- `R29_2026-04-30_Retinex_Illumination.md` — replace R18 zone normalization with
  Multi-Scale Retinex using CreativeLowFreqTex mip levels 0/1/2 (already computed);
  pixel-local illumination estimate vs. current 4×4 zone step function

---

## 2026-04-30 (session 3)

### Naming convention unified — RXX_DATE_TITLE.md
All research documents now follow `RXX_DATE_TITLE.md` regardless of origin (CLI or nightly job).
The `N` suffix is retired. Renamed all files in `research/`:
- R01–R07: date `2026-04-27` added
- R08N–R10N, R23N–R27N: `N` stripped; dates already present
- R11–R22: date `2026-04-28` added
Job files updated: output paths, `ls` glob, git add patterns.
`overnight_research_area.md` renamed to `job_general_research.md`.

### R27 — Data highway integrity audit
Static code audit of all BackBuffer-writing passes in the active chain. Confirmed:
all active BB-writing passes after `analysis_scope_pre` have the row-y=0 guard.
Two open items (scope display only, no color-grade impact):
1. `analysis_frame` DebugOverlay missing guard — latent risk if chain order changes
2. Pixel-129 post-mean smoothing broken — `analysis_scope` reads game content as prior
   (vkBasalt confirmed no cross-frame BackBuffer persistence via source review)

---

## 2026-04-30 (session 2)

### Nightly job spec fixes
- Output naming: both jobs now use `R{next}N_{YYYY-MM-DD}_{topic}.md` convention
- Both jobs commit and push output to `alpha` branch
- `SPATIAL_NORM_STRENGTH` removed from automation job candidates (already done)

### Stability audit — R25N (local, alpha branch)
- Previous R25N (nightly run on wrong branch) deleted and re-run locally
- No CRASH or CORRUPT findings on actual alpha codebase
- Register pressure: `ColorTransformPS` ~129 scalars, at 128-scalar spilling threshold
- All BackBuffer row-0 guards correct; all EMA coefficients in range; R19–R22 safe

### Shader fixes (from R25N findings)
- X3206 warnings suppressed: all 8 `DrawLabel` call sites now pass `pos.xy` (was `pos`)
  — analysis_frame.fx, analysis_scope_pre.fx, analysis_scope.fx, corrective.fx (×3),
    grade.fx, pro_mist.fx
- Histogram textures: LumHistRaw, SatHistRaw, LumHist, SatHist — R32F → R16F
  in analysis_frame.fx (values are [0,1] fractions; R32F was unnecessary)

### Research filed
- `R25_2026-04-30_Nightly_Stability_Audit.md` — full stability audit on alpha
- `R26_2026-04-30_Register_Pressure_Research_Proposal.md` — research proposal:
  does `[unroll]` loop restructure of 16 zone reads actually reduce SPIR-V register
  pressure, or is it compiler-dependent? Pending execution next session.

---

## 2026-04-30

### SPATIAL_NORM_STRENGTH automated
`SPATIAL_NORM_STRENGTH` removed from `creative_values.fx` (arc_raiders + gzw).
`grade.fx:284` now derives r18_str from zone_std:
```hlsl
float r18_str = lerp(10.0, 30.0, smoothstep(0.08, 0.25, zone_std)) / 100.0 * 0.4;
```
Complementary to existing zone_str automation — contrasty scenes get stronger
normalization while getting a gentler S-curve, preventing double-amplification.
23 knobs remain.

### Nightly job fixes
- All three triggers: `git config user.email/name` + `git push origin HEAD:alpha`
- Stability audit + Automation research: `git checkout alpha` added at job start
  (jobs were running against `main` — wrong codebase)
- Automation research: Brave curl + arxiv search pattern added

### Research filed
- `R24_2026-04-30_Nightly_Automation_Research.md` — 5-knob automation formulas

---

## 2026-04-29 (night)

### GZW fully configured
- Rewrote `gzw.conf` to mirror arc_raiders structure
- Created `gamespecific/gzw/shaders/creative_values.fx` and `debug_text.fxh`
- GZW chain: `analysis_frame:analysis_scope_pre:corrective:grade:pro_mist:analysis_scope`

### Debug label system extended
- Added '8' glyph to both `debug_text.fxh`: `if (ch == 56u) return 34287u;`
- Slots: 1ANL / 2SCP / 3COR+4ZON+5CHR (passthrough) / 6GRA / 7PMS / 8SCO
- analysis_scope moved from slot 7 (y=58) to slot 8 (y=66)

### pro_mist — new effect (R23N)
Physical model: Black Pro-Mist glass filter. Additive chromatic scatter (R>G>B).
Single pass, reads `CreativeLowFreqTex` as scatter source.
- `adapt_str = 0.36 * lerp(0.7, 1.3, saturate(iqr / 0.5))` — IQR-adaptive
- Gate onset from p75: `smoothstep(p75-0.12, p75+0.06, luma_in)`
- Additive: `base + max(0, diffused-base) * float3(1.15, 1.00, 0.75) * adapt_str * gate`
- Clarity component: `base - diffused` × bell × adapt_str × 1.10
**Constraint:** Must stay single-pass — see arc_raiders game-specific notes in HANDOFF.

### Bug fixes
1. `corrective.fx` kHalton — `static const float2 kHalton[256]` replaced with
   procedural `Halton2(uint)` / `Halton3(uint)` (SPIR-V-safe). Chroma stats now correct.
2. `analysis_scope_pre.fx` SCOPE_S — 16→8 (matches analysis_scope.fx).
3. Stage 4 (FILM GRADE) removed — dead code at GRADE_STRENGTH=0.
