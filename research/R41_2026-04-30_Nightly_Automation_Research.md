# Nightly Automation Research — 2026-04-30 (R41)

## Current knob state

Read directly from `creative_values.fx` (verified 2026-04-30). The following
`#define` knobs are present:

| Knob | Value | Stage |
|------|-------|-------|
| `EXPOSURE` | 1.04 | Corrective — `pow(rgb, EXPOSURE)` before FilmCurve |
| `SHADOW_TEMP` | −20 | 3-way corrector — shadow temperature |
| `SHADOW_TINT` | 0 | 3-way corrector — shadow tint |
| `MID_TEMP` | 4 | 3-way corrector — midtone temperature |
| `MID_TINT` | 0 | 3-way corrector — midtone tint |
| `HIGHLIGHT_TEMP` | 30 | 3-way corrector — highlight temperature |
| `HIGHLIGHT_TINT` | −5 | 3-way corrector — highlight tint |
| `CURVE_R_KNEE` | −0.003 | FilmCurve — red channel knee offset |
| `CURVE_B_KNEE` | +0.002 | FilmCurve — blue channel knee offset |
| `CURVE_R_TOE` | 0.000 | FilmCurve — red channel toe offset |
| `CURVE_B_TOE` | 0.000 | FilmCurve — blue channel toe offset |
| `ROT_RED` | 0.25 | Oklab hue rotation — red/skintone band |
| `ROT_YELLOW` | −0.05 | Oklab hue rotation — yellow band |
| `ROT_GREEN` | 0.20 | Oklab hue rotation — green/foliage band |
| `ROT_CYAN` | 0.15 | Oklab hue rotation — cyan band |
| `ROT_BLUE` | −0.12 | Oklab hue rotation — blue/sky band |
| `ROT_MAG` | −0.08 | Oklab hue rotation — magenta band |
| `CORRECTIVE_STRENGTH` | 100 | Stage bypass gate (not a tuning knob) |
| `TONAL_STRENGTH` | 100 | Stage bypass gate (not a tuning knob) |

**Already automated (confirmed removed from `creative_values.fx`):**
- `CLARITY_STRENGTH` — driven by `auto_clarity = lerp(42, 20, …)` from p50 + IQR
- `SHADOW_LIFT` — `lerp(20, 5, smoothstep(0.04, 0.28, p25))`
- `CHROMA_STRENGTH` — `lerp(55, 30, smoothstep(0.05, 0.20, mean_chroma))`
- `DENSITY_STRENGTH` — `lerp(35, 52, smoothstep(0.05, 0.20, mean_chroma))`
- `SPATIAL_NORM_STRENGTH` — driven by zone_std
- Zone S-curve strength — driven by zone_std
- Halation — `lerp(0.0, 0.22, smoothstep(0.55, 0.85, p75))`

19 knobs remain: 2 bypass gates (not tuning knobs), 6 hue rotations, 4 film curve
offsets, 6 3-way corrector values, and 1 EXPOSURE. Effective artistic knob count: 17.

---

## Automation candidates assessed

### 1. EXPOSURE — Scene-key diagnostic hint (NOT auto-exposure)

**What it is:** Applied as `pow(rgb, EXPOSURE)` before all other work. Purely
intentional — it sets the overall tonal placement the artist wants.

**Automation viability:** Zero for the value itself (CLAUDE.md: "No auto-exposure.
EXPOSURE is a deliberate knob set by the user"). However a *diagnostic* is viable:
the pipeline already computes `zone_log_key = exp(mean(log(zone_medians)))` in
`UpdateHistoryPS`, which is the geometric mean of zone medians — identical to
Reinhard's (2002) log-average scene key. If `zone_log_key` deviates significantly
from a target middle-grey (≈ 0.18 in linear), the distance can be expressed as a
suggested EXPOSURE delta for display in the debug overlay only. No shader behaviour
changes.

**Formula sketch:**
```
key_target   = 0.18
key_actual   = zone_log_key   // already in ChromaHistoryTex col 6, .r
key_ratio    = key_target / max(key_actual, 0.001)
// suggested delta = log(key_ratio) / log(2) EV, show in overlay if |delta| > 0.15 EV
```
This mirrors the Reinhard log-average key approach and Knarkowicz (2016) EV
compensation guidance. Risk: zero — it is display-only. Cost: zero — signal already
exists.

**Verdict:** Low-effort, zero-risk overlay-only hint. Viable as a debug readout
addition; outside scope as a behaviour change.

### 2. CURVE_R_KNEE / CURVE_B_KNEE / CURVE_R_TOE / CURVE_B_TOE — Film stock character

**What they are:** Per-channel offsets to the `FilmCurve` knee and toe. Encode the
physical dye-layer spectral cross-over of a particular film stock (e.g. ARRI ALEXA:
red compresses slightly earlier, blue toe lifts). Comments in `creative_values.fx`
are explicit: "Default values match ARRI ALEXA latitude."

**Automation viability:** These are pure aesthetic/stock-character choices, not
scene descriptors. The scene statistics (p25, p50, p75, zone_std) already directly
drive where the *base* knee and toe positions land inside `FilmCurve()` — the
`creative_values.fx` offsets are delta adjustments layered on top. No scene statistic
maps cleanly to "which film stock dye cross-over character is preferred."

Literature search found no psychophysical model linking scene content to preferred
per-channel knee offset. Color.io's film emulation and FilmConvert both treat
these as stock-specific constants, not scene-adaptive parameters.

**Verdict:** Not automatable. These encode artistic identity, not scene description.
Mark as **locked artistic** — no further research needed.

### 3. 3-WAY CORRECTOR (SHADOW_TEMP, MID_TEMP, HIGHLIGHT_TEMP + TINTS) — AWB suggestion

**What they are:** Temperature (R↑B↓) and tint (G) shifts applied per luminance
region after FilmCurve. The current Arc Raiders values (shadow −20, mid +4,
highlight +30) intentionally create a cool-shadow/warm-highlight split — a stylistic
choice, not a neutral correction.

**Automation viability — partial, as a suggestion only:**
The pipeline computes per-band mean chroma in Oklab across 6 hue bands. A grey-world
illuminant estimate could be derived from the mean (a, b) of all sampled pixels
(sum of `lab.yz` weighted by 1, i.e. scene colour cast) — this is already
implicitly available via `ChromaHistoryTex`. If the scene mean (a, b) in Oklab
deviates from (0, 0), a corresponding temperature/tint bias can be computed:
- Oklab a-axis correlates roughly with green-red; b-axis with blue-yellow
- A grey-world AWB offset would be `−mean_a → tint_delta`, `−mean_b → temp_delta`

However:
- The 3-way corrector is explicitly a *stylistic* split (cool shadows, warm
  highlights) — grey-world neutralization would fight the artistic intent.
- The 2025 ICCV workshop paper "Learning Camera-Agnostic White-Balance Preferences"
  (Zhao et al., arXiv 2507.01342) confirms that user WB preference is not the same
  as illuminant neutralization — users prefer slight scene-warmth retention.
- Mixed illuminant scenes (common in UE5/Lumen: warm interior + cool exterior)
  invalidate simple grey-world assumptions (Nafifi's `mixedillWB` GitHub confirms
  this is an open research problem as of 2025).

**Verdict:** A scene-neutral AWB *reference point* (what the temp/tint would be at
grey-world) could be computed from existing ChromaHistoryTex data — no new pass
needed. Cost is ~6 texture taps already in UpdateHistoryPS, or derivable in grade.fx
Stage 1. This is viable as a **debug overlay hint only** (e.g. "neutral WB offset:
TEMP −3, TINT +1") so the user knows the current artistic offset relative to grey-
world. Not suitable for automatic application given the intentional split-toning
design.

**Formula sketch (debug-only):**
```hlsl
// In grade.fx, Stage 3 — after mean_chroma loop, add:
float cm_a = 0.0, cm_b = 0.0, cm_wa = 0.0;
[unroll] for (int bi = 0; bi < 6; bi++) {
    float4 bs = tex2D(ChromaHistory, float2((bi + 0.5)/8.0, 0.5/4.0));
    // bs.r = mean C, bs.b = wsum — recover approximate mean a,b from hue center
    // (approximate only; full a,b mean would need UpdateHistoryPS change)
}
// neutral_temp_hint ≈ -cm_b_scene / 0.030 * 100  (maps Oklab b to temp units)
// neutral_tint_hint ≈ +cm_a_scene / 0.030 * 100  (maps Oklab a to tint units)
```
Full implementation would require storing mean (a, b) alongside mean C in
`UpdateHistoryPS` — currently only mean C (magnitude) is stored, not direction.
This is a small change to ChromaHistoryTex layout (use .g slot currently holding
std, or add a col-7 entry).

**Verdict:** Viable at low cost as a debug overlay hint. Requires a minor
ChromaHistoryTex extension to store directional (a, b) mean rather than scalar C.
No behaviour change to the grade. Candidate for a future R session if debug readout
is wanted.

### 4. ROT_RED … ROT_MAG — Per-band hue rotation

**What they are:** Per-band Oklab LCh hue rotation offsets. Current values encode
Arc Raiders' specific palette intent: skintones → amber, foliage → teal, sky →
cerulean.

**Automation viability:** None. These are entirely aesthetic. No scene statistic
indicates "how much should greens rotate toward teal." Per-band hue rotation is
analogous to choosing a colour grade style — it is the *definition* of artistic
intent, not a scene-descriptive correction.

Literature confirms: per-hue colour grading is purely creative (ColourSpace, DaVinci
Hue vs Hue curves). No 2024–2026 paper attempts to automate creative hue rotation
from scene content.

**Verdict:** Locked artistic. No research needed.

---

## Literature findings

### AWB / Illuminant estimation

1. **Zhao et al. "Learning Camera-Agnostic White-Balance Preferences"** (ICCV 2025
   Workshop, arXiv 2507.01342, Samsung AI Center Toronto) — Key finding: user WB
   preference ≠ grey-world illuminant neutralization. Users retain mild scene-warmth.
   Directly relevant: confirms that applying a computed AWB correction as a default
   would contradict established user preference, supporting the overlay-hint-only
   approach for temp/tint.

2. **"RL-AWB: Deep Reinforcement Learning for AWB in Low-Light Night-time Scenes"**
   (arXiv 2601.05249, 2025) — uses RL to drive AWB in challenging scenes. Uses neural
   features; not directly implementable in HLSL. Confirms grey-world fails in
   non-neutral scenes (UE5/Lumen mixed lighting).

3. **"Advancing WB correction through deep feature statistics and feature distribution
   matching"** (ScienceDirect, JVCI 2025) — EFDM statistical alignment. Too heavy for
   real-time shader; confirms that simple statistical AWB (grey-world, max-RGB) is
   insufficient for complex scenes. Indirectly validates deferring AWB automation.

4. **Nafifi `mixedillWB`** (GitHub, ongoing) — reference implementation for AWB in
   mixed-illuminant scenes. Active research problem as of 2025. Confirms single global
   AWB offset inadequate for UE5 Lumen (multiple dynamic light sources).

### Scene key / Exposure hint

5. **Reinhard et al. (2002) / Knarkowicz (2016) "Automatic Exposure"** — log-average
   luminance as scene key. Knarkowicz explicitly recommends an artist-tweakable EV
   compensation offset rather than blind auto-exposure. The `zone_log_key` value
   already computed in `UpdateHistoryPS` (ChromaHistoryTex col 6, .r) is the geometric
   mean of zone medians — a spatially-stratified variant of log-average, more robust
   than pixel-level log average. Deviation from 0.18 could drive a diagnostic EV hint.

6. **"Managing Camera Exposure With Physical Luminance Workflow"** (Reddit
   r/GraphicsProgramming, 2020 — still the reference for UE5 workflows 2024) —
   confirms exposure compensation curve approach: X = log-average luminance, Y = EV
   adjustment suggestion. Matches what zone_log_key already provides.

### Tone curve / Film emulation

7. **"Filmic Tonemapping Curve"** (Kosobrodov, 2024) — Bézier-based toe/shoulder
   parameterization from scene DR. The `FilmCurve()` in grade.fx already does
   something equivalent by computing knee/toe positions from p25/p75 dynamically.
   The creative_values.fx per-channel offsets are on top of this adaptive base.
   No new automation identified.

8. **HDR Dynamic Tone Mapping with Enhanced Rendering Control** (ResearchGate,
   SID 2024) — Bernstein polynomial with dynamic per-scene knee/toe as metadata.
   HDR-specific; SDR pipeline is already doing per-scene knee placement via PercTex.
   Not applicable.

9. **Color.io Film Emulation Tools** (color.io, 2024) — confirms film emulation tools
   treat per-channel knee/toe as stock-specific constants, not scene-adaptive. Aligns
   with current design: CURVE_R/B_KNEE/TOE are stock identity, not scene response.

### Psychophysical / Appearance models

10. **"Spectral-image-based lighting adaptive color reproduction"** (JOSA A, 2024) —
    CIECAM02-based reproduction with psychophysical validation. Relevant: confirms that
    chromatic adaptation models (CAT02/von Kries) require known illuminant as input,
    which a single-pass shader cannot reliably estimate in a game context (mixed
    dynamic lighting). Supports the overlay-hint-only approach.

11. **CIECAM02 / Color Research & Application 2024 psychophysical magnitude estimation
    study** — luminance-level-dependent colour appearance at 10–10000 cd/m². The
    pipeline already applies Stevens (Hunt-Pointer-Estévez) adaptation through
    `hunt_scale` derived from p50. No new psychophysical automation opportunity
    identified for remaining knobs.

---

## Summary of viable new automation opportunities

| Candidate | Signal available | Implementation | Risk | Priority |
|-----------|-----------------|----------------|------|----------|
| EXPOSURE diagnostic EV hint | `zone_log_key` (existing) | Debug overlay only, ~2 lines | None | Low (QoL) |
| AWB grey-world hint for 3-way temp/tint | Mean Oklab (a,b) — needs minor ChromaHistoryTex extension | Debug overlay only; small UpdateHistoryPS change | None | Low (QoL) |
| CURVE_R/B_KNEE/TOE automation | None identified | N/A | — | Closed/locked |
| ROT_* automation | None identified | N/A | — | Closed/locked |

No new behaviour-changing automation is viable for the remaining knobs. The two
overlay-hint candidates require no shader behaviour changes and carry zero risk of
visual artifacts or artistic override. Both can be addressed in a single small
session when debug readout is wanted.

---

## Searches run

1. `automatic white balance scene-adaptive reference 2024 2025 without user override deep learning`
2. `adaptive tone curve per-channel knee toe scene statistics 2024 2025 film emulation HDR`
3. `scene-adaptive creative grading psychophysical luminance defaults 2024 color appearance model`
4. `grey world von Kries chromatic adaptation scene illuminant estimation real-time shader GLSL HLSL 2024`
5. `log average luminance scene key exposure suggestion p50 median scene-adaptive offset 2024 tone mapping`
6. `per-channel film emulation dye layer cross-over red blue knee offset scene statistics automation 2024`
7. `CCMNet cross-camera color constancy arxiv 2025 illuminant estimation real-time` (supplemental)
8. `log-average luminance scene key exposure bias suggestion real-time Reinhard 2024` (supplemental)
