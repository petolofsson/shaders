# Changelog

## 2026-05-08 — session (Diffusion Gaussian blur + vertical oval; shadow lift audit)

### Fixed

- **Diffusion shimmer spots on ground** (`grade.fx DiffusionPS`) — Shimmer was firing on medium-tone ground texture via `max(0, blurred − base)` on a 1/8-res blurred source. Fixed with `src_gate = smoothstep(0.15, 0.45, Luma(blurred))` — suppresses shimmer below blurred luma 0.15, ramps to full above 0.45.

- **Diffusion bloom blockiness** (`grade.fx`) — DiffusionTex was 1/8-res (8px blocks) with a single bilinear tap downsample, producing visible grid artifacts in the shimmer. Replaced with full Gaussian blur chain: DiffusionTex raised to 1/4-res (MipLevels=1), 4-tap box downsample, plus two new 9-tap separable Gaussian passes (DiffusionBlurH → DiffusionHorizTex, DiffusionBlurV → DiffusionTex, σ=2 output texels ≈ 8px at 1080p). DiffusionPS simplified from 3 mip samples to single `diff_blur` from the fully Gaussian-blurred source. Grade is now 8 passes.

- **Diffusion radial — vertical oval** (`grade.fx DiffusionPS`) — Replaced circular `length(uv - 0.5)` with `length(float2(c.x * 1.6, c.y * 0.08))`. Oval extends well past screen top/bottom (boundary at 5.3× screen height — full clarity vertically); horizontal ramp peaks at ~25% screen width at mid-diffusion. Matches large-format lens character: softening on sides, clarity in vertical center strip.

- **Shadow lift: detail_protect** (`grade.fx ColorTransformPS`) — `smoothstep(-0.5, 0.0, log_R)` closed at log_R = −0.5 (pixel only 29% below local illuminant), suppressing lift on actual shadow pixels. Widened to `smoothstep(-2.0, -0.5, log_R)` — shadow pixels up to 1.5 stops below local illuminant now receive lift; genuine dark materials (2+ stops below) still suppressed.

- **Shadow lift: local_range_att removed** (`grade.fx ColorTransformPS`) — Scene-wide `1.0 − smoothstep(0.20, 0.50, zone_iqr)` was cutting lift globally whenever scene IQR > 0.35 — routine in mixed outdoor/indoor content. Per-pixel gates (texture_att, fine_texture_att, detail_protect) already protect where needed. Removed from multiplicative chain.

- **Shadow lift: lift_w ceiling** (`grade.fx ColorTransformPS`) — Bell ceiling raised from `smoothstep(0.25, 0.0, new_luma)` to `smoothstep(0.27, 0.0, new_luma)`. Marginal extension of shadow luma window.

## 2026-05-08 — session (R127 CAT16 removal + chroma pivot fix; R127B FilmCurve body S revised)

### Removed

- **CAT16 pixel correction** (`grade.fx`) — Chromatic adaptation toward D65 removed entirely.
  Game content is display-referred (already in sRGB→D65); CAT16 was treating artistic warm
  lighting (fire, lava, torchlight) as a calibration error and cooling it. `NeutralIllumTex`
  and `lms_illum_norm` kept — still feed R83 (chromatic floor) and R66 (ambient shadow tint).
  Highway slot 216 (cat_blend) removed.

### Fixed

- **Chroma lift pivot bias** (`corrective.fx UpdateHistoryPS`) — `MIN_WEIGHT = 1.0` was adding
  unconditional weight to every pixel regardless of chroma, pulling the per-band pivot toward
  zero. `LiftChroma` uses `t = 1 − C/pivot` — with pivot≈0, t≈0 for all colored pixels,
  making the chroma lift silently inert. Fixed: weight now
  `HueBandWeight(h, center) * smoothstep(0.03, 0.08, C)`. Achromatic pixels contribute zero;
  pivot is the actual mean chroma of colored pixels. Lift now works as designed.
- **FilmCurve body S-curve** (`grade.fx FilmCurveApply`) — R126 formula `x*(1-x)*(1-2x)*0.12`
  lifted shadows (+9% at x≈0.2) and barely touched highlights — net image flattening.
  Replaced with one-sided midrange-weighted S: `max(0, (x*(1-x))²*(2x-1))*0.65`. Shadows
  (x≤0.5) untouched; upper mids lift peaks +1.2% at x≈0.72, zero at x=1.

### Added

- **Highway extension** — Slots 203 (zone_key), 204 (zone_std), 205 (slow_key) written by
  corrective PassthroughPS. Slots 214 (fc_knee), 215 (zone_str), 217 (shadow_lift_str),
  218 (chroma_str), 219 (mist_str) written by grade. All diagnostic-write-only — pipeline
  reads ChromaHistory directly, not via ReadHWY for these slots.
- **NeutralIllumPS pass** (`grade.fx`, R124B) — 144-sample neutral-pixel-weighted illuminant
  estimate (16×9 grid, `CreativeLowFreqSamp` mip0). Replaces flat grey world mean as source
  for `lms_illum_norm`. Pass runs before ColorTransform within-technique.

## 2026-05-07 — session (R124 illuminant, R125–R126 Bezold-Brücke + FilmCurve body)

### Implemented

- **R124A — CAT16 achromatic confidence gate** (`grade.fx`) — When scene has few neutral
  pixels (low `HWY_ACHROM_FRAC`), the grey world illuminant estimate is unreliable. CAT16
  blend now gates via `cat_confidence = smoothstep(0.02, 0.12, achrom_frac)`, scaling blend
  from 0.60–0.80 down proportionally in saturated scenes. Zero passes, ~3 ALU.
- **R124B — Neutral-pixel-weighted illuminant** (`grade.fx`) — New `NeutralIllumPS` pass
  (144-sample 16×9 grid over `CreativeLowFreqSamp` mip0). Weights pixels by
  `1 − smoothstep(0.04, 0.10, C)` (Oklab chroma). Outputs weighted mean to 1×1
  `NeutralIllumTex`, replacing the flat grey world mean as CAT16 illuminant source.
  Falls back to grey world when few neutral pixels present. ~1ms GPU saving observed
  (eliminates spatially-varying per-pixel `lf_mip0` read).
- **R126 — FilmCurve body S-curve** (`grade.fx FilmCurveApply`) — Body of the film curve
  was linear (identity) between toe and knee. Added `body_s = x*(1−x)*(1−2x)*0.12` — an
  S-shaped midtone contrast term that is zero at x=0 and x=1 and peaks at ±1.16% at
  x≈0.21/0.79. Matches the mild S-characteristic of the H&D body in Kodak 2383 print stock.
- **R126 — B-B teal asymmetry** (`grade.fx`) — Previous two-harmonic B-B had orange lobe
  larger than teal (opposite of Kurtenbach 1994 data). Added third harmonic via triple-angle
  identity `ch3_h = ch_h*(4*ch_h²−3)` (3 MAD). Coefficients A=0.10, B=0.50, C=0.30 give
  teal lobe 0.61 vs orange 0.38 — ratio 1.6×, within the 1.5–2× empirical range.
- **R125 — Bezold-Brücke anchor fix + two-harmonic** (`grade.fx`) — Previous formula
  `sh_h * 0.1253 + ch_h * 0.9921` had zeros at h=0.270/0.770 (should be 0.250/0.750)
  and pushed teal/cyan hues toward green instead of toward blue (anti-B-B direction).
  New formula `(lab.x − 0.50) * 0.015 * (ch_h + 0.9 * sh2_h)` anchors exactly at the
  Oklab invariant hues (h=0.25 unique yellow, h=0.75 unique blue). Second harmonic
  `sh2_h = 2*sh_h*ch_h` adds asymmetry via double-angle identity — 4 MAD, zero new taps.
  Amplitude raised 0.006 → 0.015 for ~0.25° max shift.

### Recalibrated

- **Zone_std thresholds** (`grade.fx`) — Post-R116, zone_std measures intra-zone pixel
  variance (peaks ~0.15) not inter-zone median spread (could reach 0.25+). Thresholds
  updated: `smoothstep(0.08, 0.25)` → `(0.06, 0.16)` and `smoothstep(0.04, 0.25)` →
  `(0.03, 0.16)`. Slightly tighter contrast response confirmed.

## 2026-05-06 — session (R114 halation chromatic, R115 Pro-Mist shimmer, R116 pipeline audit)

### Fixed / Improved

- **R114 — Halation chromatic fringe** (`grade.fx`) — Halation previously produced pure red/green
  fringe only (blue=0 was hardcoded). Added `hal_b` component with Lorentzian attenuation from
  `hal_ring.b` via `lerp(0.22, 0.38, hal_lore)`. Gains changed from `float3(1.05, 0.50, 0.0)` to `float3(1.05, 0.45, 0.03)`.
  White surfaces now receive the correct orange/amber fringe. Red dominance preserved (deepest
  dye layer, yellow filter blocks blue emission but passes red/orange).

- **R115 — Pro-Mist shimmer model** (`grade.fx`) — `ProMistPS` changed from symmetric lerp
  diffusion (`lerp(base, blurred, strength)`) to additive unilateral bloom
  (`base + max(0, blurred − base) * strength`). Previous model muted dark areas alongside
  brightening highlights — physically incorrect for scatter optics. New model only adds scatter
  from highlights, shadow/midtone unaffected. `MIST_STRENGTH` recalibrated 5.0 → 1.5.

- **R116 — Color pipeline audit — 9 issues resolved:**
  - **Issue 8 — Chroma ceiling before vibrance** (`grade.fx`): Ceiling applied to `lifted_C`
    before vibrance masking, not after. Ceiling is now a hard guarantee on what enters vibrance.
  - **Issue 9 — HWY_SLOPE minimum clamp** (`inverse_grade.fx`): `max(slope_enc * 1.5 + 1.0, 1.15)`
    enforces minimum valid slope at decode. Cold-start uninit (0) no longer decodes as 1.0 (below
    the valid floor of 1.15).
  - **Issue 5C — Adaptive CAT16 blend** (`grade.fx`): `illum_dev = length(lms_illum_norm − 1)`
    drives blend: 0.80 near-neutral (reliable estimate), 0.60 strongly tinted (safety valve).
    3–5 ALU, zero new taps.
  - **Issue 1 — Chroma median** (`analysis_frame.fx`): `MeanChromaPS` replaced with 32-bin
    histogram CDF-walk p50. Arithmetic mean was outlier-biased (neon, bright primaries) →
    inflated mean → over-expanded shadows. Highway x=198 now carries median Oklab C.
  - **Issue 4 — Pure global percentiles** (`grade.fx`): `eff_p25`/`eff_p75` changed from
    `lerp(global_p25, zone_zmin, 0.4)` to direct `perc.r`/`perc.b`. Previous blend mixed
    a histogram percentile with a spatial zone extreme — incompatible statistics.
  - **Issue 2 — Zone log key linear mean** (`corrective.fx`): `zone_log_key` changed from
    geometric mean to `sum(medians) / 16` (linear mean). Equal weight across all zones;
    eliminates dark-bias in high-contrast (split interior/window) scenes.
  - **Issue 3 — Intra-zone pixel variance** (`corrective.fx`): `zone_std` changed from
    inter-zone std-dev (spread of 16 medians) to mean intra-zone pixel variance
    (histogram moments E[X²] − E[X]² per zone). `ZoneHistoryTex.a` repurposed from
    Kalman P (unused downstream) to smoothed `intra_std`. R88 VFF Kalman Q adaptation
    removed from `SmoothZoneLevelsPS`; replaced with fixed-K EMA (scene-cut reset preserved).

### Tuning (creative_values.fx — Arc Raiders)

- `EXPOSURE` 0.85 → 0.95
- `INVERSE_STRENGTH` 0.40 → 0.55 (chroma median lower than mean → more expansion headroom)
- `COUPLER_STRENGTH` 0.15 → 0.20
- `HAL_STRENGTH` 0.50 → 2.0 (recalibrated for orange/amber fringe on white surfaces)
- `HAL_GAMMA` 0.40 → 2.50 (wider Lorentzian tail for broader diffuse scatter)
- `MIST_STRENGTH` 5.0 → 1.5 (recalibrated after additive shimmer model)
- `PURKINJE_STRENGTH` 1.15 → 1.2

### Research committed

- `research/R116_2026-05-06_color_pipeline_audit.md` — 9 confirmed issues with code evidence
- `research/R116_2026-05-06_color_pipeline_audit_findings.md` — better solutions, priority order, what NOT to fix

---

## 2026-05-06 — session (R113 mip fix, LCA removed, surround removed)

### Removed

- **LCA / R107** — Edge-directional chromatic aberration permanently removed. Revised
  10+ times across multiple sessions (radial → edge-directional → ddx/ddy → 4-tap central
  difference → highlight-gated → tent function). Core problem: no way to exclude UI text
  without a UI mask. `LCA_STRENGTH` knob removed from both `creative_values.fx` files.
- **VIEWING_SURROUND / R76B** — CIECAM02 surround compensation removed. Outside viewing
  environment is not the pipeline's responsibility. `pow(col.rgb, VIEWING_SURROUND)` line
  deleted from `grade.fx`. `VIEWING_SURROUND` knob removed from both `creative_values.fx` files.

### Fixed

- **R113** — vkBasalt cross-technique mip generation bug. `CreativeLowFreqTex` mip1/mip2
  were zero everywhere — vkBasalt only auto-generates mips for render targets written and
  read within the same technique. Fix: two explicit downscale passes (`LFDownscale1PS`,
  `LFDownscale2PS`) within `OlofssonianColorGrade`. `grade.fx` is now a 5-pass technique.
  All downstream effects (Retinex, halation, shadow lift, CAT16, R66) now receive real data.
- **Halation** — Switched from DoG (`mip2 − mip1`, which was always zero) to blur-sharp
  model (`max(0, LowFreqMip1 − col.rgb)`). Fires at dark pixels adjacent to bright sources.

---

## 2026-05-05 — session (R101 chroma refinements + OPT-1/2/3/4)

### Implemented

- **OPT-3/4** — Deleted dead `lin_pre_tonal` register + lerp and `CORRECTIVE_STRENGTH`
  lerp from `ColorTransformPS`. Both `TONAL_STRENGTH` and `CORRECTIVE_STRENGTH` are
  compile-time `#define 100` — `lerp(a, b, 1.0)` is identity. Zero-risk dead code removal.
- **OPT-2** — `tex2D` → `tex2Dlod` for 4 reads in `ColorTransformPS`: `PercSamp`,
  `ChromaHistory` (×2 — zstats row and 6-band pivot loop), `ZoneHistorySamp`. Eliminates
  9 GPU derivative computations per pixel. Consistent with existing `ReadHWY()` usage.
- **R101 F1 — Bezold-Brücke** (`grade.fx`) — Replaces R75 uniform hue-by-luminance lerp
  with unique-yellow-anchored `-sin(2π(h − 0.27))` model. Unique hues are luminance-invariant
  by construction. Reuses `sh_h`/`ch_h` from HELMLAB — zero new trig. Watch cyan in bright
  sky content (single-harmonic slightly over-corrects cyan band).
- **R101 F2 — H-K exponent scene-adaptation** (`grade.fx`) — Hellwig 2022 fixed exponent
  0.587 made scene-adaptive: `lerp(0.52, 0.64, saturate(zone_log_key / 0.50))`. Backed by
  Nayatani 1997 + CIECAM02 F_L. Dim scenes get stronger H-K; bright exteriors get weaker.
- **R101 F3 — Abney C_stim** (`grade.fx`) — Abney per-hue coefficients now scale by
  stimulus chroma `C_stim` (captured before chroma lift) instead of post-lift `final_C`.
  Burns et al. 1984: Abney shift is a stimulus property. Zero ALU.
- **OPT-1** — Eliminated third `sincos` in `ColorTransformPS`. H-K `sh`/`ch` derived via
  small-angle approximation of HELMLAB `dh` (max error 1.28×10⁻⁴) + exact angle-addition
  of R21 rotation using existing `r21_sin`/`r21_cos`. Saves one quarter-rate sincos per pixel.

### Clarified

- **R61 / HUNT_LOCALITY** — Confirmed intentionally removed in commit `e155e6c`
  (2026-05-04, chroma lift simplification). `hunt_la` fed only into `hunt_scale`, which was
  part of a 5-factor pipeline replaced by `chroma_str = CHROMA_STR * R68A`. Not a regression.
  Nightly audits (R102) incorrectly flagged it; explanation added to HANDOFF.

### Automation research verdicts (closed)

INVERSE_STRENGTH base, HAL_STRENGTH auto-enable, and ZONE_STRENGTH inverse scaling all
**rejected** — each case showed the first-order adaptation is already present in the pipeline
(slope encodes inverse-IQR; per-pixel `max(0,blur-sharp)` self-limits halation; inner
`lerp(0.26,0.16,ss_08_25)` already provides 38% inverse scaling with zone_std).

---

## 2026-05-04 — session (R61 Hunt locality + job maintenance)

### Implemented
- **R61 — Per-pixel Hunt adaptation** (`grade.fx` CHROMA block)
  - `hunt_la = max(lerp(zone_log_key, lab.x, HUNT_LOCALITY), 0.001)` replaces
    global `zone_log_key` in Hunt F_L computation. CAM16 local-field specification.
  - Highlights get stronger chroma boost; shadows get less. One lerp, no new passes.
  - `HUNT_LOCALITY 0.35` added to `creative_values.fx`.

### Infrastructure
- **Nightly jobs updated** — all four triggers refreshed for R90/R61 chain state:
  - Correct active chain (includes `inverse_grade : inverse_grade_debug`)
  - R-number filename convention fixed (`R{next}_` prefix, was `YYYY-MM-DD_`)
  - Clarity permanent exclusion added to all jobs
  - Automation job: stale candidates (CLARITY/DENSITY/CHROMA — non-existent knobs)
    replaced with R61/R90 adaptive calibration research
  - Stability audit: targeted review updated from R19–R22 to R88/R89/R90/R61
  - Optimization job: already-implemented list updated (OPT-1, R88, R89)
  - `job_r86_scene_reconstruction.md` deleted
- **Register pressure verified** — RADV shader dump confirms ColorTransformPS uses
  59 VGPRs / 87 SGPRs in hardware (audit estimated 240 scalars from HLSL — compiler
  liveness analysis reduced 4×). No spilling. `scratch_en: false`.

---

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
  - `INVERSE_STRENGTH 0.50` in `creative_values.fx`.
- **Data highway extended** — x=197 carries Kalman-smoothed slope (normalised [0,1]).
- **R86 retired** — `inverse_grade_aces.fx`, `aces_debug.fx` removed from chain.
- **Testbed tuning** — `HAL_STRENGTH 0.00`, `VEIL_STRENGTH 0.00` (both compete with
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
- **R86 prototype** — `inverse_grade_aces.fx` + `aces_debug.fx` in chain.
  - Analytical ACES inverse (quadratic formula, 4 ALU) + per-hue Oklab correction.
  - Scene normalization: `scene_ceil = max(ACESInverse(p75), 1.0)` prevents highlight
    clipping. Only activates for high-exposure scenes where p75 > ~0.85.
  - Confidence gate: `blend = ACES_BLEND * aces_conf`. Direct multiplication — no
    smoothstep threshold, no flicker at boundaries.
  - `ACES_BLEND` knob in `creative_values.fx`. Current value: 0.30.
  - `LCA_STRENGTH` set to 0.0 — disabling for R86 validation.
- **Data highway extension** — `analysis_frame.fx` DebugOverlay now encodes PercTex
  p25/p50/p75 into BackBuffer at y=0, x=194/195/196. Proven cross-effect sharing
  mechanism (PercTex `pooled = true` silently ignored by vkBasalt — confirmed dead end).
- **`tools/aces_calib.py`** — calibration tool. Periodic screenshots, reads highway
  pixels, computes ACESConfidence in Python, tracks stability.
- **`aces_debug.fx`** — live debug overlay. Box top-right corner: red→green confidence.
  Bottom half: three columns showing raw p25/p50/p75 from highway (diagnostic mode).
- **Chain reordered** — `aces_debug` moved before `analysis_scope` so it
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
  recalibrated for both testbed configs.
- **R85** Inter-channel dye masking (`grade.fx`): cyan→green 2.0% and magenta→blue 2.2%
  bleed inside Beer-Lambert block. First real-time implementation of inter-channel dye coupling.
- **R88** Sage-Husa Q adaptation (`corrective.fx`): Kalman Q in `SmoothZoneLevelsPS` and
  `UpdateHistoryPS` now driven by posterior P (accumulated uncertainty) rather than
  instantaneous innovation. Single-frame flashes no longer spike the filter gain.
- **R89** IGN blue-noise dither (`grade.fx`): Jimenez IGN replaces `sin(dot)·43758` white
  noise. Spectrally blue — banding in gradients reduced.
- **LCA** displacement halved (base scale 0.004→0.002); testbed `LCA_STRENGTH` 0.4→0.8.

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
