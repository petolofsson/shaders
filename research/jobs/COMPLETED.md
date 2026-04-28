# Completed Research Jobs

## HK Effect (2026-04-28)
**File:** `research/2026-04-28_chroma_hk.md`
**Implemented:** Finding 2 — Seong & Kwak 2025 saturation-primary HK model
- `grade.fx`: replaced ratio-of-boost HK block with `1/(1 + HK_STRENGTH/100 * final_C)` correction
- `creative_values.fx`: added `HK_STRENGTH 20` knob

## Clarity / Local Contrast (2026-04-28)
**File:** `research/2026-04-28_clarity_local_contrast.md`
**Implemented:** All three findings
- F1: `edge_w` gate replaced with Cauchy bell `1/(1 + detail²/0.0144)` — gate-free edge suppression
- F2: Multi-scale Laplacian via mipmap chain — `MipLevels 1→3` in corrective.fx, two-band detail in grade.fx
- F3: Chroma co-enhancement — `final_C` scaled by `abs(detail) * CLARITY_STRENGTH * 0.25`

## Optimization (2026-04-28)
**File:** `research/2026-04-28_optimization.md`
**Implemented:** All four findings
- F1: `atan2` → Volkansalma polynomial in `OklabHueNorm` (both grade.fx + corrective.fx)
- F2: Chilliant gamma — encode: sqrt-chain; decode: MAD chain (grade.fx)
- F3: Small-angle sin/cos for Abney/green rotation (grade.fx)
- F4: `[unroll]` on 6-band chroma loop (grade.fx)

---

# Pending Research Jobs

| File | Domain | Priority |
|------|--------|----------|
| `R08_stevens_hunt_effects.md` | Stevens effect (contrast) + Hunt effect (chroma) in FilmCurve and chroma lift | High — affects every pixel |
| `R09_abney_hue_shift.md` | Full 6-band Abney hue shift with measured data | Medium — 3 bands currently uncited |
| `R10_gamut_compression.md` | Perceptual smooth gamut compression replacing hard clamp | Medium — CLAUDE.md gate violation |
| `R11_temporal_stability.md` | Adaptive temporal filtering for zone/chroma histories | Medium — pumping artifact in dynamic scenes |
