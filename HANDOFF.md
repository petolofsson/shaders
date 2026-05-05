# Handoff — 2026-05-05

## Current branch
`alpha` — active development.

---

## Pipeline state

| Stage | Finished | Novel | Gap |
|-------|----------|-------|-----|
| Stage 0 — Input | 95% | 80% | — |
| Stage 1 — Corrective | 93% | 78% | — |
| Stage 2 — Tonal | 93% | 92% | — |
| Stage 3 — Chroma | 97% | 93% | — |
| Stage 3.5 — Halation | 90% | 78% | — |
| Output — Pro-Mist | 91% | 74% | **1% below 75% target** |

**Next session goal:** Push Output/Pro-Mist novelty from 74% → 76%+.

Two concrete targets:
- **R91** — Mie-correct per-channel scatter radius: blue channel uses mip 0 (tighter, shorter λ scatters more in polymer), red uses mip 1 (wider, longer λ penetrates deeper). 3 ALU, no new taps. Spectral-physically motivated.
- **R92** — Apply IGN blue-noise dither to pro_mist.fx (currently still uses `sin(dot)*43758` white noise). One-line fix.

Combined expected: Output novelty 74% → 76–77%.

---

## Active chain (Arc Raiders)

```
analysis_frame : inverse_grade : inverse_grade_debug : analysis_scope_pre : corrective : grade : pro_mist : analysis_scope
```

---

## What shipped this session (latest first)

### OPT-1 — Eliminate third sincos in ColorTransformPS (grade.fx)

H-K `sincos(h_out * 2π)` eliminated. `sh`/`ch` derived from:
1. Small-angle approximation applied to `(sh_h, ch_h)` for the HELMLAB `dh` perturbation
   (max |dh| = 0.016 rad → max error dh²/2 = 1.28×10⁻⁴, 15× below JND)
2. Exact angle-addition with `r21_sin`/`r21_cos` already computed for R21 vector-space rotation

`dh` hoisted from the HELMLAB line (was implicit, now stored as `float dh`).
Saves one quarter-rate sincos (~16–20 GPU cycles) per pixel.

### R101 — Bezold-Brücke / H-K exponent adaptation / Abney C_stim (grade.fx)

Three Stage 3 Chroma refinements in one commit:

**F1 — Bezold-Brücke (replaces R75):** R75's uniform `lerp(-0.003, +0.003, lab.x)` was
applied identically to all hues. The true Bezold-Brücke effect has unique hues invariant to
luminance (unique yellow ≈ h_perc 0.27 is the most important). Replaced with:
```hlsl
r21_delta += (lab.x - 0.50) * 0.006 * (sh_h * 0.1253 + ch_h * 0.9921);
```
`-sin(2π(h − 0.27))` formulation — zero at unique yellow by construction. Reuses
`sh_h`/`ch_h` from HELMLAB, zero new trig. Watch cyan-heavy content (sky) for
over-rotation: single-harmonic over-corrects cyan band.

**F2 — H-K exponent scene-adaptation:** Hellwig 2022 fixed exponent 0.587 → scene-adaptive:
```hlsl
float hk_exp = lerp(0.52, 0.64, saturate(zone_log_key / 0.50));
float hk_boost = 1.0 + 0.25 * f_hk * pow(final_C, hk_exp);
```
Backed by Nayatani 1997 and CIECAM02 F_L formalism. Dim scenes (low zone_log_key) → 0.52
(stronger H-K), bright exteriors → 0.64 (weaker). 2 ALU, same pow cost.

**F3 — Abney C_stim:** Burns et al. 1984: Abney shift is a stimulus property — should
scale with input chroma, not post-lift chroma. `float C_stim = C` saved before chroma
lift stages; Abney coefficient line changed from `* final_C` → `* C_stim`. Zero ALU.

### OPT-2/3/4 — Dead code removal + tex2Dlod (grade.fx)

- **OPT-3:** `float3 lin_pre_tonal = lin` + `lin = lerp(lin_pre_tonal, lin, TONAL_STRENGTH / 100.0)` deleted.
  `TONAL_STRENGTH` is a compile-time `#define 100` → lerp weight 1.0 → identity.
- **OPT-4:** `lin = lerp(col.rgb, lin, CORRECTIVE_STRENGTH / 100.0)` deleted. Same reason.
- **OPT-2:** 4 `tex2D` → `tex2Dlod` conversions for constant-UV / single-mip reads:
  `PercSamp`, `ChromaHistory` (×2 — zstats and the per-band pivot loop), `ZoneHistorySamp`.
  Eliminates 9 GPU derivative computations per pixel. Zero error (LOD 0 = `tex2D` result
  for constant UV / `MipLevels=1` textures). `ReadHWY()` already used `tex2Dlod` — consistent.

### Automation research verdicts (from R102 nightly)

Investigated four knobs for adaptive derivation. All rejected or deferred:

| Knob | Verdict | Reason |
|------|---------|--------|
| HUNT_LOCALITY | N/A — knob removed | Intentionally removed in e155e6c (chroma simplification). Not a regression. |
| INVERSE_STRENGTH base | REJECT | `slope` already encodes inverse-IQR scaling. Adapting on top double-counts. |
| HAL_STRENGTH auto-enable | REJECT | Per-pixel `max(0, blur−sharp)` evaluates to zero in scenes with no highlights. No scene-level gate needed. |
| ZONE_STRENGTH inverse scaling | REJECT | Inner `lerp(0.26, 0.16, ss_08_25)` already provides 38% inverse scaling with zone_std. |

### Note on R61 / HUNT_LOCALITY

HANDOFF 2026-05-04 listed R61 as shipped. It was removed in commit `e155e6c`
(2026-05-04, "refactor: simplify chroma lift") because `hunt_la` fed only into
`hunt_scale`, which was part of a 5-factor chroma lift pipeline replaced by
`chroma_str = CHROMA_STR * R68A`. The nightly stability and automation audits
(R102) incorrectly flagged this as a regression. It is intentional.

---

## Current creative_values.fx (Arc Raiders)

| Knob | Value |
|------|-------|
| EXPOSURE | 0.90 |
| FILM_FLOOR | 0.01 |
| FILM_CEILING | 0.95 |
| SHADOW_TEMP / MID_TEMP / HIGHLIGHT_TEMP | -5 / +3 / +6 |
| ZONE_STRENGTH | 1.15 |
| SHADOW_LIFT_STRENGTH | 1.25 |
| CURVE_R_KNEE / B_KNEE | -0.0102 / 0.0000 |
| CURVE_R_TOE / B_TOE | +0.0100 / -0.0218 |
| PRINT_STOCK | 0.40 |
| HAL_STRENGTH | 0.40 |
| CHROMA_STR | 1.0 |
| ROT_RED / YELLOW / GREEN / CYAN / BLUE / MAG | +0.03 / -0.015 / -0.02 / +0.015 / -0.03 / 0.00 |
| MIST_STRENGTH | 2.75 |
| VEIL_STRENGTH | 0.15 |
| PURKINJE_STRENGTH | 1.3 |
| VIEWING_SURROUND | 1.123 |
| LCA_STRENGTH | 0.3 |
| INVERSE_STRENGTH | 0.50 |

HUNT_LOCALITY is removed (see note above). CHROMA_STR replaces the former 5-factor
chroma lift pipeline.

---

## Known state

- `inverse_grade_debug.fx` in chain — remove once tuning is stable.
- Register pressure verified via RADV shader dump: 59 VGPRs / 87 SGPRs, no spilling.
  OPT-1/2/3/4 reduced declared scalar count; VGPR count unchanged at hardware level.
- `pro_mist.fx` line 125: still uses `sin(dot)*43758` white-noise dither — R89 IGN not
  applied here (target for R92 next session).
- No known compile errors or visual regressions.
- Stability audit (R102): R88/R89/R90 all pass. BackBuffer guards all present. No NaN/INF
  crash sites.

Debug log: `/tmp/vkbasalt.log` — check first for SPIR-V issues.
