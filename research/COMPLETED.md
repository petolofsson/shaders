# Completed Research Jobs

## R01–R07 — Formal research (job spec + findings pairs)

| Number | Topic | Status |
|--------|-------|--------|
| R01 | FilmCurve anchor quality | Implemented |
| R02 | Zone median accuracy | Implemented |
| R03 | Zone S-curve shape | Implemented |
| R04 | FilmCurve / zone interaction | Implemented |
| R05 | Rank-based zone contrast | Pending implementation |
| R07 | Shadow lift redesign | Implemented |

---

## R08N — HK Effect (2026-04-28)
**File:** `research/R08N_2026-04-28_chroma_hk.md`
**Implemented:** Finding 2 — Seong & Kwak 2025 saturation-primary HK model
- `grade.fx`: replaced ratio-of-boost HK block with `1/(1 + HK_STRENGTH/100 * final_C)` correction
- `creative_values.fx`: added `HK_STRENGTH 20` knob

## R09N — Clarity / Local Contrast (2026-04-28)
**File:** `research/R09N_2026-04-28_clarity_local_contrast.md`
**Implemented:** All three findings
- F1: `edge_w` gate replaced with Cauchy bell `1/(1 + detail²/0.0144)` — gate-free edge suppression
- F2: Multi-scale Laplacian via mipmap chain — `MipLevels 1→3` in corrective.fx, two-band detail in grade.fx
- F3: Chroma co-enhancement — `final_C` scaled by `abs(detail) * CLARITY_STRENGTH * 0.25`

## R10N — Optimization (2026-04-28)
**File:** `research/R10N_2026-04-28_optimization.md`
**Implemented:** All four findings
- F1: `atan2` → Volkansalma polynomial in `OklabHueNorm` (both grade.fx + corrective.fx)
- F2: Chilliant gamma — encode: sqrt-chain; decode: MAD chain (grade.fx)
- F3: Small-angle sin/cos for Abney/green rotation (grade.fx)
- F4: `[unroll]` on 6-band chroma loop (grade.fx)

---

## R11 — Stevens + Hunt Effects (2026-04-28)
**Files:** `research/R11_stevens_hunt_effects.md` (spec), `research/R11_stevens_hunt_effects_findings.md`
**Status:** Research complete, pending implementation

Key findings:
- F1 Stevens: replace linear lerp with `(1.48 + sqrt(p50)) / 2.03` — CIECAM02 sqrt curve (low ROI, range barely changes)
- F2 Hunt: replace linear lerp with FL^(1/4) from CIECAM02 — corrects 3× over-amplification at bright scenes (current upper bound 1.3 vs. literature 1.05)
- Hellwig 2022 H-K hue formula `J_HK = J + f(h)*C^0.587` noted for future R08N refinement (non-trivial hue remapping required)

## R12 — Abney Hue Shift (2026-04-28)
**Files:** `research/R12_abney_hue_shift.md` (spec), `research/R12_abney_hue_shift_findings.md`
**Status:** Research complete — partial improvement viable; Oklab-native data not yet publicly available

Key findings:
- Pridmore 2007: bimodal curve — PEAKS at Cyan & Red, TROUGHS at Blue & Green. Current shader has magnitudes **inverted** (Blue=0.08 is trough; Cyan=0.05 is peak).
- F1: Swap Cyan↑ (−0.05→−0.08) and Blue↓ (−0.08→−0.04) — well-supported
- F2: Add Red band (+0.06) — missing peak (medium confidence)
- F3: Add Magenta band (−0.03) — conservative (low confidence)

## R13 — Gamut Compression (2026-04-28)
**Files:** `research/R13_gamut_compression.md` (spec), `research/R13_gamut_compression_findings.md`
**Status:** Research complete — trivial fix found

Key findings:
- F1: Remove `if (rmax > 1.0)` gate by wrapping gclip in `saturate()` — 3-line change, mathematically equivalent
- F2: Replace grey-point desaturation with hue-preserving `(a,b)` axis scale using `rmax_probe` (already computed)
- F3: Optional Reinhard pre-compression at rmax=0.85 threshold
- ACES powerP formula (industry standard) has a hard conditional — not gate-free
- Ottosson adaptive-L₀ is gate-free but requires `find_cusp()` — not pursued

## R15 — Hellwig 2022 H-K Hue (2026-04-28)
**Files:** `research/R15_hellwig_hk_hue.md` (spec), `research/R15_hellwig_hk_hue_findings.md`
**Implemented:** Full Hellwig 2022 upgrade
- `grade.fx`: Seong linear model → `f(h)*C^0.587` using sincos + double-angle identities (1 sincos + 1 pow)
- Oklab hue usable directly — offset vs. CIECAM02 < 7° across sRGB primaries, error < 3% in f(h)
- f(h) range: cyan 1.21 (peak), yellow 0.31 (trough) — 4× hue variation the old model was blind to
- `creative_values.fx`: HK_STRENGTH 20 → 12 (parity at average saturation; tune upward for stronger)

---

## R14 — Temporal Stability (2026-04-28)
**Files:** `research/R14_temporal_stability.md` (spec), `research/R14_temporal_stability_findings.md`
**Status:** Research complete — simple adaptive formula found

Key findings:
- F1: Magnitude-adaptive zone speed: `speed = saturate(base * (1.0 + 10.0 * abs(current.r - prev.r)))` — replaces fixed lerp and first-frame gate, self-initialises
- F2: Same pattern for chroma history
- F3: Optional asymmetric adaptation (+30% speed brightening, −30% darkening) via sign(delta)
- Narkowicz 2016 frame-rate-independent formula noted; deferred (not needed at fixed 60 fps)

---

## R16 — FilmCurve: Zone-Informed Scene Key (2026-04-28)
**Files:** `research/R16_filmcurve_zone_key.md` (spec), `research/R16_filmcurve_zone_key_findings.md`
**Implemented:** All three findings

- F1: Zone geometric mean key replaces p50 — `zone_log_key = exp(mean(log(0.001 + z_i)))` over 16 zone medians (Reinhard 2002 log-average formula). Spatially-unbiased scene key, immune to large flat areas dominating the pixel histogram.
- F2: Zone min/max blend with histogram p25/p75 as toe/knee anchors — `eff_p25 = lerp(perc.r, z_min, 0.4)`, `eff_p75 = lerp(perc.b, z_max, 0.4)`. 40% zone weight, 60% histogram.
- F3: Zone std dev modulates FilmCurve factor — `spread_scale = lerp(0.7, 1.1, smoothstep(0.08, 0.25, zone_std))`. Compact scenes get gentler compression; high-contrast scenes slightly stronger.
- All 16 zone reads share one pass — 16 tex2D reads + log/exp/sqrt chain.

---

## R17 — Film Stock Presets: Scene-Adaptive Tint Balance (2026-04-28)
**Files:** `research/R17_filmstock_scene_adaptive.md` (spec), `research/R17_filmstock_scene_adaptive_findings.md`
**Implemented:** Both findings

- F1: Exposure-adaptive tint scale — `r17_stops = log2(zone_log_key / 0.18)` (stops above/below normal). `r17_hl_boost = 1 + TINT_ADAPT_SCALE * saturate(+stops)`, `r17_sh_boost = 1 + TINT_ADAPT_SCALE * saturate(-stops)`. Bright scene → warm highlights amplified; dark scene → cool shadows amplified. Cross-over shifts with actual scene key.
- F2: Per-preset TINT_ADAPT_SCALE constants: P0=0.00, P1=0.15, P2=0.35, P3=0.25, P4=0.10, P5=0.40. Derived from qualitative stock descriptions — visual calibration recommended.
- Uses zone_log_key from R16 — no extra texture reads. Cost: 1 log2 + 6 MAD.

---

## R18 — Spatial Adaptation: Zone Luminance Normalization (2026-04-28)
**Files:** `research/R18_spatial_adaptation.md` (spec), `research/R18_spatial_adaptation_findings.md`
**Implemented:** Both findings

- F1: Zone luminance normalization — `r18_norm = pow(zone_log_key / zone_median, strength * 0.4)`. Multiplicative correction: dark zones gently brightened, bright zones gently darkened, zones at global key unchanged. Monotone, bounded.
- F2: No new pass needed — ZoneHistoryTex LINEAR sampler at full-res UV already provides bilinear spatial interpolation of zone medians (~25% screen-width transitions). Zero halo risk, no separate blending kernel required.
- Added `SPATIAL_NORM_STRENGTH 20` knob to creative_values.fx. Grade.fx cost: 1 pow + 2 divisions.
- Three-tier spatial system: zone normalization (between zones) + zone S-curve (within zones) + clarity (pixel-level detail).
