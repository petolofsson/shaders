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

## R14 — Temporal Stability (2026-04-28)
**Files:** `research/R14_temporal_stability.md` (spec), `research/R14_temporal_stability_findings.md`
**Status:** Research complete — simple adaptive formula found

Key findings:
- F1: Magnitude-adaptive zone speed: `speed = saturate(base * (1.0 + 10.0 * abs(current.r - prev.r)))` — replaces fixed lerp and first-frame gate, self-initialises
- F2: Same pattern for chroma history
- F3: Optional asymmetric adaptation (+30% speed brightening, −30% darkening) via sign(delta)
- Narkowicz 2016 frame-rate-independent formula noted; deferred (not needed at fixed 60 fps)
