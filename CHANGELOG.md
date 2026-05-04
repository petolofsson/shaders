# Changelog

## 2026-05-04 — session (F1–F3 film sensitometry + Stevens)

### Implemented
- **F1 — Print stock bell tracks FilmCurve** (`grade.fx` line 296)
  - `desat_w` bounds replaced with `fc_knee_toe` / `fc_knee` (already in scope).
  - Desaturation window now widens/narrows with scene exposure like real Kodak 2383.
  - Bright outdoor: midtone window opens. Dark interior: shadow zone tightens.
  - Source: Žaganeli et al. 2026, arXiv 2604.06276.
- **F2 — Midtone saturation expansion in R22** (`grade.fx` line 420)
  - +6% chroma bell peaking at Oklab L≈0.47 (smoothstep [0.22–0.40] × [0.55–0.70]).
  - Cinema SDR masters actively push midtone saturation — we only modelled suppression.
  - Net output ~+3–4% after vibrance mask and memory color ceilings.
  - Source: Žaganeli et al. 2026, arXiv 2604.06276.
- **F3 — Stevens exponent sqrt→cbrt** (`grade.fx` line 274)
  - `fc_stevens`: `sqrt(zone_log_key)` → `exp2(log2(key)*(1/3))`. Denominator 2.03→2.04.
  - Cube root matches psychophysical data across dark→bright luminance range.
  - Dark scenes: +6–8% shoulder compression. Bright outdoor: unchanged.
  - Source: Nayatani et al. 1997 + JoV 2025.

### Key findings
- Fixed luma bounds in print stock desaturation caused incorrect zone widths across scenes.
- Cinema SDR masters have a measurable midtone saturation bump absent from our model.
- Stevens effect follows L^(1/3), not L^(1/2), across the full photopic adaptation range.

---

## 2026-05-04 — session (R90 adaptive inverse — chroma edition)

### Implemented
- **R90** — `general/inverse-grade/inverse_grade.fx` replaces R86 ACES-specific inverse.
  - Game-agnostic: measures display IQR, infers compression ratio vs. 2.5-stop reference.
  - **Oklab chroma-only expansion** — luma unchanged, hue preserved, brightness neutral.
    `lab.yz *= lerp(1.0, slope, INVERSE_STRENGTH * mid_weight * c_weight)`
  - `mid_weight = L*(1-L)*4` — bell curve, zero at black/white, peak at L=0.5.
  - `c_weight = saturate((C-0.10)/0.15)` — zero for near-neutral (warm whites, greys),
    full for clearly coloured pixels (C > 0.25). D65 neutral by construction.
  - Slope pre-computed in `analysis_frame` from float16 PercTex, encoded at highway x=197.
    Kalman-smoothed, no flicker. Clamp `[1.15, 1.8]` — always fires, never overexpands.
  - `inverse_grade_debug.fx` — slope colour box: blue=no-op, green=healthy, red=capped.
  - `INVERSE_STRENGTH 0.50` in `creative_values.fx` (Arc Raiders).
- **Data highway extended** — x=197 carries Kalman-smoothed slope (normalised [0,1]).
- **R86 retired** — `inverse_grade_aces.fx`, `aces_debug.fx` removed from chain.
- **Arc Raiders tuning** — `HAL_STRENGTH 0.00`, `VEIL_STRENGTH 0.00` (both compete with
  inverse grade highlights). `EXPOSURE 0.90`.

### Key findings
- Luma expansion causes net brightness lift (p50 anchor below 0.5 pushes most pixels up).
  Chroma-only expansion is brightness-neutral by construction.
- Wrong Oklab b-row (`0.4784341246, -0.4043461455`) maps white to b≈0.1 (yellow).
  Correct values from grade.fx: `0.7827717662, -0.8086757660` — white maps to b=0.
- C gate relative to D65 neutral protects warm whites without scene illuminant sampling.
- Three-zone confidence gate (R86) was a workaround for a bad detector; R90 needs none.

---

## 2026-05-04 — session (R86 prototype)

### Implemented
- **R86 prototype** — `inverse_grade_aces.fx` + `aces_debug.fx` in Arc Raiders chain.
  - Analytical ACES inverse (quadratic formula, 4 ALU) + per-hue Oklab correction.
  - Scene normalization: `scene_ceil = max(ACESInverse(p75), 1.0)` prevents highlight
    clipping. Only activates for high-exposure scenes where p75 > ~0.85.
  - Confidence gate: `blend = ACES_BLEND * aces_conf`. Direct multiplication — no
    smoothstep threshold, no flicker at boundaries.
  - `ACES_BLEND` knob in `creative_values.fx` (Arc Raiders). Current value: 0.30.
  - `LCA_STRENGTH` set to 0.0 (Arc Raiders) — disabling for R86 validation.
- **Data highway extension** — `analysis_frame.fx` DebugOverlay now encodes PercTex
  p25/p50/p75 into BackBuffer at y=0, x=194/195/196. Proven cross-effect sharing
  mechanism (PercTex `pooled = true` silently ignored by vkBasalt — confirmed dead end).
- **`tools/aces_calib.py`** — calibration tool. Periodic screenshots, reads highway
  pixels, computes ACESConfidence in Python, tracks stability.
- **`aces_debug.fx`** — live debug overlay. Box top-right corner: red→green confidence.
  Bottom half: three columns showing raw p25/p50/p75 from highway (diagnostic mode).
- **Arc Raiders chain reordered** — `aces_debug` moved before `analysis_scope` so it
  reads highway before scope visualization overwrites x=194-196.
- **GZW tuning** — exposure 0.80→1.00, floor/ceiling reset to 0/1, zone_strength 1.30→1.35,
  film curve values tightened, print_stock 0.50→0.30.

### Key findings
- `pooled = true` ignored by vkBasalt. BackBuffer data highway is the only cross-effect
  sharing mechanism.
- `bright_gate` removed from ACESConfidence — caused false negatives in hazy outdoor
  scenes. `highs_norm` already handles truly dark scenes.
- smoothstep blend gate replaced with direct `conf * ACES_BLEND` multiplication to
  eliminate flicker.

### Open
- Debug box shows red in bright outdoor scenes. 3-column p25/p50/p75 diagnostic added.
  Root cause not yet confirmed (PercTex values vs. formula vs. highway encoding).

---

## 2026-05-03 — session (R83–R89 + LCA tuning)

### Implemented
- **R83** Chromatic FILM_FLOOR (`grade.fx`): per-channel black pedestal from Kodak 2383
  D-min ratios (1.02/1.00/0.97), modulated by CAT16 `lms_illum_norm`. Zero new taps.
- **R84** Log-density FilmCurve (`grade.fx`): `CURVE_*` knobs reinterpreted as log₂-density
  offsets (`fc_knee * exp2(CURVE_R_KNEE)`). exp2 folds at compile time. CURVE_* values
  recalibrated for both Arc Raiders and GZW.
- **R85** Inter-channel dye masking (`grade.fx`): cyan→green 2.0% and magenta→blue 2.2%
  bleed inside Beer-Lambert block. First real-time implementation of inter-channel dye coupling.
- **R88** Sage-Husa Q adaptation (`corrective.fx`): Kalman Q in `SmoothZoneLevelsPS` and
  `UpdateHistoryPS` now driven by posterior P (accumulated uncertainty) rather than
  instantaneous innovation. Single-frame flashes no longer spike the filter gain.
- **R89** IGN blue-noise dither (`grade.fx`): Jimenez IGN replaces `sin(dot)·43758` white
  noise. Spectrally blue — banding in gradients reduced.
- **LCA** displacement halved (base scale 0.004→0.002); Arc Raiders `LCA_STRENGTH` 0.4→0.8.

### Research committed
- **R86** ACES analytical inverse — exact quadratic formula (4 ALU, float32 epsilon).
  Microsoft MiniEngine formula bug identified (wrong root). ACES confidence fingerprint
  designed from PercTex (zero new taps). Empirical calibration still needed.
- **R87** Lateral research (Telecommunications domain) — Sage-Husa Q and IGN dither
  identified as high-ROI candidates.

---

## 2026-05-03 — session (R78 + R79 + R80 + R76 + brightness fix)

### Implemented
- **R78** Constant-hue gamut projection (`grade.fx`): `gclip` now applied to Oklab
  `(f_oka, f_okb)` before `OklabToRGB` instead of projecting `chroma_rgb` toward grey
  in RGB space. Same formula, same cost, hue-accurate. Uses existing `rgb_probe` —
  one fewer float in registers. Note: correctness improvement, not a novelty gain.
- **R79** Halation dual-PSF + gate + warm wing (`grade.fx`): gate onset `0.80→0.70`
  (R79A); mip 2 extended wing tap added, 70% core / 30% wing per channel (R79B);
  green wing blend reduced to 20% for warm bias — red penetrates deeper in emulsion
  (R79C). +1 tex tap total.
- **R80** Pro-Mist spectral scatter model (`pro_mist.fx`): warm scatter tint
  `[1.05, 1.0, 0.92]` folded into existing R46 channel weights (R80A); scene-key
  adaptive `lerp(1.30, 0.80, smoothstep(0.05, 0.25, zone_log_key))` on `adapt_str`
  (R80B); aperture proxy `lerp(1.10, 0.90, ...)` via `EXPOSURE` (R80C). No new taps.

---

## 2026-05-03 — session (brightness fix + R76)

### Fixed
- **Brightness regression** diagnosed and resolved. Root cause: R72 clarity coefficient
  (`0.10`) created a systematic net brightness lift — `log_R` is positive for any pixel
  brighter than its local illuminant (the common case on lit surfaces), so the effect
  was one-sided upward. R72 removed entirely: game engines bake in sharpening/clarity,
  making it redundant.
- **FILM_CEILING** restored to `1.00` (passthrough). Ceiling/floor are now both
  passthrough (`FILM_FLOOR 0.000`, `FILM_CEILING 1.00`). Brightness is correct without
  requiring input headroom clamping.

### Implemented
- **R76A** CAT16 chromatic adaptation — normalises scene illuminant toward D65 using
  `CreativeLowFreqTex` mip 2 as illuminant estimate. Implemented as purely chromatic:
  adapted pixel is re-normalised to its original luma (`cat16 *= luma_in / Luma(cat16)`)
  before the 60% blend. Zero luminance impact — shadow lift, Retinex, zone contrast all
  see the same luma as without R76A. Illuminant normalised to unit luminance before gain
  computation, preventing absolute-brightness lift from scene-darker-than-D65 illuminants.
- **R76B** CIECAM02 surround compensation — `VIEWING_SURROUND` knob added to
  `creative_values.fx`. Default `1.00` = off. `dim→dark` (gaming): `1.123`.
  Applied as `pow(col.rgb, VIEWING_SURROUND)` before FilmCurve.

### Removed
- **R72** Reflectance local contrast (`new_luma += coeff * log_R * clarity_gate * (1-new_luma)`).
  Redundant with game sharpening. Net brightness bias regardless of coefficient sign.

---

## 2026-05-03 — commit `50c1cc4`

### Implemented
- **R47** Shadow warm bias (scene-adaptive shadow temperature): enabled with `zone_std`
  gate `smoothstep(0.06, 0.15, zone_std)` to suppress in flat/UI scenes. Was fully
  implemented in corrective.fx but never sampled in grade.fx; the ShadowBiasSamp tap
  and gated `sh_temp_auto` computation added to the R19 block.
- **R71** Vibrance self-masking: `vib_mask = saturate(1 - C / 0.22)` attenuates chroma
  lift delta on already-saturated pixels. Prevents over-saturating primaries while
  lifting flat naturals.
- **R72** Reflectance local contrast: `new_luma += 0.10 * log_R * clarity_gate * (1 - new_luma)`
  after Retinex normalisation. `log_R = log2(luma / illum_s0)` is illumination-free,
  so this sharpens surface detail without illuminant bleed (the fault that killed R30).
- **R73** Memory color protection: per-band Oklab C ceiling interpolated from
  `hw_o0–hw_o5` band weights (0.28 red / 0.22 yellow / 0.16 green / 0.18 cyan /
  0.26 blue / 0.22 magenta). `final_C = min(vib_C, max(C_ceil, C))` — never pushes
  below the input chroma.
- **R74** Munsell-calibrated highlight desaturation: R22 highlight arm coefficient
  `0.25 → 0.45`. Munsell data shows 50–60% chroma reduction at Value 9 for most hues;
  25% was ~2× too gentle.
- **R75** Hue-by-luminance (2383 tonal): `r21_delta += lerp(-0.003, +0.003, lab.x)`.
  ±1.1° hue rotation — cool shadows, warm highlights. Primarily affects neutral axis
  (achromatic pixels); below perceptual threshold on saturated colors.
- **creative_values.fx**: EXPOSURE 1.03→1.00, FILM_FLOOR 0.005→0.000, FILM_CEILING 0.95→1.00

### Research committed
R65–R80: 32 research documents (proposals + findings) covering Hunt chroma coupling,
ambient shadow tint, pipeline gap analysis, gamut knee, Abney validation, film pipeline
gap, vibrance, reflectance contrast, memory color, highlight desaturation, hue-by-luminance,
perceptual input normalization (CAT16 + CIECAM02), Stage 2 calibration validation, constant-hue
gamut projection, halation dual-PSF, and Pro-Mist spectral scatter.

### Removed
- `research/CHANGELOG_2026-05-01_session.md` — replaced by this file

---

## 2026-05-02 — commit `ceeb214`

- **R60** Temporal context: `context_lift = exp2(log2(slow_key / zk_safe) * 0.4)`
  boosts shadow lift during dark scene transitions, suppresses on re-entry.
- **R62 OPT-3** Chroma-stable tonal: zone S-curve applied in Oklab L space
  (`lab_t.x *= exp2(log2(r_tonal) / 3)`) to prevent S-curve from shifting chroma.
- HELMLAB Fourier hue correction: 2-harmonic correction
  `h_perc = h + (0.008 sin θ + 0.004 sin 2θ) / 2π` aligns Oklab hue toward perceptual.
- Shadow lift auto-range widened: max 1.30 → 1.50.
- SHADOW_LIFT / CHROMA_STRENGTH automation (R63).
- OPT-1/2/3: zero-error perf wins in ColorTransformPS.

---

## Attempted and reverted (no commit)

### 2026-05-03 — R76 first attempt (all-white failure, then fixed)
R76A first attempt caused all-white screen — root cause was R72's net brightness lift
inflating LMS values before the CAT16 gain calculation, spiking the blue gain channel.
Fixed in same session: R72 removed, R76A re-implemented with per-pixel luma
re-normalization for guaranteed luminance neutrality. Stable.
