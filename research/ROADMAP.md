# Research Roadmap

Priority order agreed 2026-04-28. Goal: elevate the remaining "standard" pipeline elements
into the same psychophysically-grounded, self-calibrating tier as the existing novel work.

---

## Queue

### ~~R16 — FilmCurve: zone-informed tone mapping~~ DONE
**Implemented 2026-04-28** — see `research/R16_filmcurve_zone_key.md` and `research/COMPLETED.md`.
- F1: Zone geometric mean key (Reinhard 2002) replaces pixel histogram p50 in Stevens factor
- F2: Zone min/max blended 40% with histogram p25/p75 as toe/knee anchors
- F3: Zone std dev modulates FilmCurve factor (0.7–1.1 range)

---

### ~~R17 — Film stock presets: scene-adaptive characteristic curves~~ DONE
**Implemented 2026-04-28** — see `research/R17_filmstock_scene_adaptive.md` and `research/COMPLETED.md`.
- Tint cross-over adapts to zone_log_key; per-preset TINT_ADAPT_SCALE (0.00–0.40)

### R17 — Film stock presets: scene-adaptive characteristic curves (archived)
**Priority:** 2 — artistically significant, has sensitometric literature  
**Problem:** Current presets are fixed log-space matrices. Real film stocks (Kodak Vision3,
Fuji Eterna 500, etc.) have characteristic curves where color cross-over shifts with
exposure level — the shadow/highlight color behavior changes depending on how the film is rated.  
**Direction:** Use the scene exposure state (FL from Hunt, zone medians, EXPOSURE knob) to
modulate the preset matrices. Investigate Kodak/Fuji published sensitometric data for
the 6 presets and derive exposure-dependent coefficients.  
**Scope:** grade.fx Stage 4 (film grade block). Likely creative_values.fx additions.

---

### ~~R18 — Spatial adaptation: spatially-varying zone corrections~~ DONE
**Implemented 2026-04-28** — see `research/R18_spatial_adaptation.md` and `research/COMPLETED.md`.
- Key finding: no new pass needed — LINEAR sampler on 4×4 ZoneHistoryTex provides inherent smooth blending
- `pow(zone_log_key / zone_median, strength * 0.4)` normalization after zone S-curve
- SPATIAL_NORM_STRENGTH 20 knob added to creative_values.fx

---

## Deferred (low ROI)

- **Exposure gamma** — `pow(rgb, k)` is fine; it's a deliberate knob, not a computation.
- **Shadow lift** — small operation; psychophysical grounding has marginal gain.
- **Saturation rolloff near white** — minor; current behavior is perceptually reasonable.

---

## Completed (this session: 2026-04-28)

R11 (Stevens + Hunt), R12 (Abney), R13 (Gamut compression + Ottosson), R14 (Temporal stability), R15 (Hellwig H-K)
