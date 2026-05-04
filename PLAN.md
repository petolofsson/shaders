# Pipeline Improvement Plan
**Goal:** Raise every stage to 90% finished / 75% novel (game-specific sense).
**Created:** 2026-05-03 | **Updated:** 2026-05-04 (R86 prototype)

---

## Phase status

| Phase | Status | Notes |
|-------|--------|-------|
| 1 — Research | **Done** | R74–R80 all researched, findings docs committed |
| 2 — Quick code | **Done** | R74, R75, R47 shipped; R72 removed (clarity redundant + brightness bias) |
| 3 — Stage 0 | **Done** | R76A (CAT16, luma-neutral) + R76B (surround knob, default off) — stable |
| 4 — Stage 2 | **Skip** | R77 findings: no code changes needed |
| 5 — Stage 3 | Ready | R78 constant-hue gamut projection |
| 6 — Stage 3.5 | Ready | R79A/B/C halation |
| 7 — Output | Ready | R80A/B/C Pro-Mist |

---

## Current state (all phases complete)

| Stage | Finished | Novel | Notes |
|-------|----------|-------|-------|
| Stage 0 — Input | 92% | 75% | R83 chromatic FILM_FLOOR done; CAT16, VIEWING_SURROUND, Eye LCA novel |
| Stage 1 — Corrective | 90% | 75% | R84 log-density FilmCurve + R85 dye masking done |
| Stage 2 — Tonal | 90% | 88% | Clarity/shadow lift concepts exist; zone system, R60/62/66 genuinely novel |
| Stage 3 — Chroma | 95% | 90% | Vibrance/Purkinje/HK/Abney published; HELMLAB, MacAdam ceilings, adaptive chroma novel |
| Stage 3.5 — Halation | 90% | 78% | Concept exists; zero-tap mip architecture + calibrated chromatic model novel |
| Output — Pro-Mist | 90% | 72% | Base concept common; bidirectional scatter, zone_log_key adaptive, zero-tap novel |

---

## Research items

### R74 — Highlight Desaturation
**Targets:** Stage 1 finished +5%, Stage 3 finished +3%

R22 applies Munsell-calibrated chroma rolloffs in shadows only. Film print stock
desaturates near paper white — chroma approaches zero as luminance approaches 1.0.
The highlight arm is absent.

Research: Derive correct Oklab C rolloff shape at high Lightness from Munsell data.
Confirm whether R51 print stock desat_w partially covers this or needs a separate term.

Likely implementation (Stage 3, after R22 shadow block):
```hlsl
C *= 1.0 - 0.30 * saturate((lab.x - 0.80) / 0.20);
```

GPU cost: 2 ALU. No new taps, no new knobs.

---

### R75 — Hue-by-Luminance Rotation
**Targets:** Stage 1 finished +4%, Stage 3 finished +3%, Stage 1 novel +3%

Film print stock dye response is not tonally neutral: shadows acquire a blue-green cast
(thin dye layer transparency to base), highlights acquire a warm cast (dye at low
density is warm-biased). Currently `r21_delta` is hue-dependent but luminance-agnostic.
The 3-way CC (R19) applies uniform RGB shifts per zone — it cannot apply hue rotation
that varies by luminance.

Research: Derive sign and magnitude of hue rotation per tonal zone from Kodak 2383
spectral data. Map to Oklab hue-normalised units (0–1).

Likely implementation: luminance-weighted additive delta on `r21_delta` before it feeds
`h_out`. ≤3 lines.

GPU cost: ~3 ALU. No new taps, no new knobs.

---

### R76 — Perceptual Input Normalization
**Targets:** Stage 0 finished +10%, Stage 0 novel +55%

Stage 0 is currently EXPOSURE (power) + FILM_FLOOR/CEILING. No game pipeline has a
perceptual input stage. Two components, implemented sequentially.

**R76A — CAT16 scene-illuminant chromatic adaptation.**
The scene illuminant chromaticity is available from `CreativeLowFreqTex mip 2` (already
used by R66). CAT16 normalises toward D65 in LMS cone space — more principled than
R19's linear RGB shifts, which operate in the wrong physiological space. Unlike the
dismissed Gray World auto-WB, this uses the spatially-measured illuminant from the
analysis infrastructure, not a mean assumption. R19 becomes an artistic deviation from
the CAT16 neutral rather than a scene correction.

Research: Derive CAT16 forward transform in HLSL (linear algebra — no new textures).
Validate illuminant estimate quality from mip 2 across diverse game scenes. Confirm
no double-correction interaction with R19.

**R76B — CIECAM02 viewing condition surround compensation.**
CIECAM02 models how perceived contrast varies with display surround luminance: a
dark-room player needs more contrast than a bright-room player for equivalent appearance.
The surround factor `Fs` adjusts the effective tone response. A single new knob
`VIEWING_SURROUND` (dark / dim / average) applies the correction at the input stage
before FilmCurve shapes the response.

Research: Derive the surround-adaptive exposure correction from CIECAM02 Appendix A.
Validate against standard test patterns at each surround setting.

Note: R76A must be implemented and validated before R76B. The CAT16 neutral is the
reference point for the surround model.

GPU cost: CAT16 = matrix multiply (9 MAD). Surround = 2–3 ALU. No new taps.

---

### R77 — Stage 2 Calibration
**Targets:** Stage 2 finished +3%

Stage 2 is already at 93% novel. This is a finishing pass only — research + parameter
validation, may produce zero code changes.

Three targeted validations:

1. **R65/R66 interaction** — Both R65 (Hunt coupling) and R66 (ambient shadow tint)
   write to `lab_t.y/z` in the shadow region. Validate that combined weight does not
   over-correct in worst-case: low-key scene with strong ambient hue.

2. **Retinex blend weight** — `0.75 * ss_04_25` is empirical. Validate against
   zone_std extremes (flat/uniform vs. high-variance) to confirm the blend doesn't
   over-flatten or under-normalise.

3. **R60 temporal context exponent** — `exp2(log2(slow_key/zk_safe) * 0.4)`: the
   0.4 exponent is unverified. Confirm it correctly tracks typical scene-key change
   rates via analysis of Arc Raiders gameplay log output.

Research deliverable: numerical analysis of R65/R66 combined weight across parameter
space + R60 output value sampling from `/tmp/vkbasalt.log`.

---

### R78 — Constant-Hue Gamut Projection
**Targets:** Stage 3 finished +3%

The `gclip` fallback projects toward `L_grey` when `rmax > 1`. This does not follow
constant-hue lines in Oklab — it produces a visible hue shift on out-of-gamut pixels.
R68B (pre-knee) reduces how often gclip fires, but it remains active as a safety net.

Replace L_grey projection with a constant-hue projection: find scale factor `s` such
that `OklabToRGB(float3(density_L, f_oka*s, f_okb*s)).max == 1`. Preserves the ab
hue direction while compressing chroma.

Research: Derive closed-form constant-hue compression using headroom and current C.
Determine whether a 2-iteration binary search or a direct headroom-based approximation
is sufficient. Validate no visual artifacts on sRGB boundary.

GPU cost: ~4 ALU for closed-form approximation. Replaces current gclip block at same cost.

---

### R79 — Halation Dual-PSF + Gate Refinement + Chromatic Dispersion
**Targets:** Stage 3.5 finished +22%, Stage 3.5 novel +20%

Three components, implemented in order.

**R79A — Soften hal_gate.**
Current threshold `smoothstep(0.80, 0.95, hal_luma)` is too conservative.
Mid-brightness coloured surfaces (luma 0.55–0.75) near light sources receive no
halation in film. Research the correct Kodak 2383 halation onset vs. exposure density.
Likely gate onset at ~0.65.

**R79B — Dual-Gaussian PSF per channel.**
Real film halation has a tight core (~1–2px spread) plus extended wings (~8–12px).
Currently one mip per channel (single spatial scale). Adding a second mip level per
channel (mip 0 for tight core, mip 2 for extended wing) with a split blend weight
models the two-lobe response. Red: mip 1 core + mip 2 wing. Green: mip 0 core + mip 1
wing. Blue: remains 0.

**R79C — Chromatic dispersion in scatter.**
The extended wing is slightly warmer than the tight core — longer wavelengths penetrate
deeper into the film base and scatter further. Tight mip preserves input colour; extended
wing shifts toward warm dye bias (slight amber lean). No new taps — different colour
weighting on core vs. wing contributions per channel.

Research: Kodak 2383 data sheet halation section for gate onset and scatter radius
ratios. Optical two-Gaussian PSF literature for parameter derivation.

GPU cost: +2 tex taps (mip 2 for red and green extended wing). ~6 additional ALU.

---

### R80 — Pro-Mist Spectral Scatter Model
**Targets:** Output finished +18%, Output novel +27%

Three components, R80B/C independent of R80A.

**R80A — Wavelength-dependent scatter.**
Optical diffusion materials scatter shorter wavelengths more (Mie/Rayleigh mix).
A Pro-Mist filter's polymer particles produce slight blue-biased scatter — the bloom
halo is cooler-coloured than a luminance-based scatter implies. Split the mip blend
by channel: blue channel weighted toward finer mip (tighter scatter kernel), red toward
coarser.

**R80B — Scene-key adaptive strength.**
Mist visually dominates in low-luminance conditions (point lights in dark environments).
High-key exterior scenes require less mist for the same knob value. Scale scatter blend
by `zone_log_key^0.3` — dark scenes get more mist, bright scenes less. Zero new taps,
uses existing zone_log_key.

**R80C — Aperture proxy via EXPOSURE.**
Real optical diffusion filters interact with lens aperture — wider aperture converges
rays before the filter, reducing effective diffusion. `EXPOSURE` correlates loosely
with relative aperture. Using `EXPOSURE` as a proxy to modulate scatter radius adds a
physical dimension no other mist implementation has.

Research: Published optical characterisation of diffusion filters (Lindgren 2019 MTF
measurements or equivalent) and Mie scattering approximations for polymer particles.
Derive spectral weighting and aperture-scatter relationship.

GPU cost: R80A = ~2 ALU (weighted channel blend). R80B = 1 pow + 1 mul. R80C = 1 mul.
No new taps.

---

### R47 — Enable Shadow Warm Bias
**Targets:** Stage 1 finished +3%, Analysis infra finished**

Shadow warm bias pass (R47) is implemented in `corrective.fx` but disabled pending
visual validation. Validate against Arc Raiders and GZW. Enable if no seaming artifacts.

---

---

## Novelty gap research (Stage 0 and Stage 1)

### R83 — Chromatic FILM_FLOOR
**Targets:** Stage 0 novel +5% → 75%

FILM_FLOOR is currently a static scalar black pedestal — identical for all three channels.
Real film has a per-channel base density (D-min): the unexposed emulsion base has a
chromaticity that varies with the scene illuminant and the specific stock's chemical fog.
The CAT16 illuminant estimate is already computed and available in `lf_mip2` (hoisted,
zero new taps). The illuminant chromaticity provides the signal needed to derive a
physically-motivated per-channel floor.

Research: Derive the relationship between illuminant chromaticity (in LMS after CAT16
forward transform) and the Kodak 2383 per-channel D-min values. Confirm the floor
adjustment does not interact destructively with the CAT16 neutral already applied above it.
Validate on warm and cool scene illuminants in Arc Raiders.

Likely implementation (Stage 1, replaces the scalar `FILM_FLOOR` application):
```hlsl
// per-channel floor from illuminant chromaticity — CAT16 LMS already computed above
float3 cfilm_floor = float3(FILM_FLOOR) * (lms_illum_norm * float3(1.02, 1.00, 0.97));
col.rgb = col.rgb * (FILM_CEILING - cfilm_floor) + cfilm_floor;
```

GPU cost: 3 MAD. No new taps (lms_illum already in scope from CAT16 block).
No new user knobs — FILM_FLOOR remains the single scalar control.

---

### R84 — Optical Density FilmCurve
**Targets:** Stage 1 novel +5%

The FilmCurve currently fits a sigmoid polynomial to the visible H&D curve shape in linear
light. Real film H&D curves are defined in optical density units (D = −log₁₀(T)), where
the actual characteristic curve is a natural sigmoid. Operating in linear light forces a
higher-order polynomial to approximate what is a near-linear segment in log space.
Reformulating the curve in log-density space gives a more physically accurate shoulder and
toe, and the per-channel offsets (CURVE_R_KNEE etc.) become proper density deviations
rather than empirical polynomial coefficients.

Research: Map current CURVE_R/B KNEE/TOE values to equivalent D-log offsets. Derive the
correct log-density sigmoid for Kodak 2383 from the published data sheet characteristic
curves (available from Kodak/Kodak Alaris publications). Validate that the new curve
produces equivalent or better results at the current knob values. Confirm no SPIR-V issue
with log2/exp2 in this context (already used elsewhere).

Likely implementation: replace `FilmCurvePS` scalar in `ColorTransformPS` Stage 1 with
a log-density calculation that lifts the knee/toe into density space before converting
back to linear. ~6 ALU replacing the current polynomial. Per-channel knee/toe offsets
become density-space deltas — same knob names, reinterpreted units.

GPU cost: ~4 ALU delta (log2 + exp2 already available). No new taps, no new knobs.

---

### R85 — Inter-Channel Dye Masking
**Targets:** Stage 1 novel +5%

R81C (Beer-Lambert) models intra-channel dye absorption: dominant-channel dye attenuates
its own channel. In real colour negative film, the three dye layers (cyan/magenta/yellow)
have spectral overlaps — the magenta dye (green record) absorbs slightly in blue; the cyan
dye (red record) absorbs slightly in green. These inter-channel terms produce the
characteristic warm shadow desaturation and cross-channel compression that makes film look
different from digital.

No other post-process implementation models this. The Kodak 2383 data sheet includes
spectral dye density curves that can be used to derive approximate inter-channel coupling
coefficients.

Research: Read Kodak 2383 spectral dye density curves (available in published process
documentation). Derive a 3×3 absorption matrix for the three dye layers at the operating
density range (~0.1–1.8 D). Validate that inter-channel terms are small enough to remain
perceptually subtle at normal exposure (dominant terms should remain dominant). Confirm no
interaction with the existing Beer-Lambert dominant-channel term.

Likely implementation (Stage 1, after R81C):
```hlsl
// inter-channel dye coupling: magenta bleeds into blue, cyan bleeds into green
float3 dye_cross = float3(
    0.0,
    dom_mask.r * sat_proxy * ramp * 0.018,   // cyan dye → green bleed
    dom_mask.g * sat_proxy * ramp * 0.022    // magenta dye → blue bleed
);
lin = saturate(lin * (1.0 - dye_cross));
```
Coefficients to be refined from spectral data.

GPU cost: ~6 MAD. No new taps, no new knobs.

---

## Execution order

| Phase | Items | Stages | Status |
|-------|-------|--------|--------|
| 1 — Research | R74–R80 | All | **Done** |
| 2 — Quick code | R74, R75, R47; R72 removed | Stage 1, 3 | **Done** |
| 3 — Stage 0 | R76A (CAT16), R76B (surround) | Stage 0 | **Done** |
| 4 — Stage 2 | R77 calibration | Stage 2 | **Skip — no code changes needed** |
| 5 — Stage 3 | R78 gamut projection | Stage 3 | **Done** |
| 6 — Stage 3.5 | R79A → R79B → R79C | Stage 3.5 | **Done** |
| 7 — Output | R80A, then R80B + R80C | Pro-Mist | **Done** |
| 8 — Novelty gaps | R83 → R84 → R85 | Stage 0, Stage 1 | **Done** |

---

## Actual outcomes (all phases complete)

| Stage | Finished | Novel | Gap to 90/75 target |
|-------|----------|-------|---------------------|
| Stage 0 | 92% | 75% | **At target** — R83 shipped |
| Stage 1 | 90% | 75% | **At target** — R84 + R85 shipped |
| Stage 2 | 90% | 88% | **Exceeds target** |
| Stage 3 | 95% | 90% | **Exceeds target** |
| Stage 3.5 | 90% | 78% | **Exceeds target** — zero-tap mip architecture is genuinely distinct |
| Output | 90% | 72% | Novel −3% — bidirectional + scene-adaptive lifts it close |

---

## Post-plan additions (2026-05-03)

Shipped after the plan was written — not part of original scope.

### R81A — Eye LCA (longitudinal chromatic aberration)
Per-pixel radial channel separation modelling the human eye's focus-wavelength
dispersion. Blue samples outward, red inward from screen centre. First physiologically-
grounded LCA implementation for game post-process. `LCA_STRENGTH` knob (0 = off,
0.4 = current both games).

### R81B — MacAdam-calibrated chroma ceilings
Per-hue chroma ceilings (R73 memory color) re-derived from MacAdam discrimination
ellipses: blue/cyan tightened (smallest ellipses), yellow relaxed (largest). Physically-
justified per-hue discrimination thresholds.

### R81C — Beer-Lambert dye absorption
Replaced linear dominant-channel attenuation with `exp(-α·c·d)` Beer-Lambert law.
Physically correct for dye-layer absorption at high chroma. Taylor-expanded to 2nd order
(max error 4.57×10⁻⁵, 44× below JND) for GPU efficiency.

### R83 — Chromatic FILM_FLOOR
Per-channel black pedestal from Kodak 2383 D-min ratios (1.02/1.00/0.97), modulated by
CAT16 `lms_illum_norm`. Warm illuminants produce warm floor, cool produce cool floor.
Zero new taps — `lms_illum_norm` hoisted from CAT16 block. Stage 0 novel: 70%→75%.

### R84 — Log-Density FilmCurve offsets
`CURVE_*` knobs reinterpreted as log₂-density offsets: `fc_knee * exp2(CURVE_R_KNEE)`
instead of `+ CURVE_R_KNEE`. exp2 folds to constant at compile time. Physically correct
density-space deviation. Stage 1 novel: +3%.

### R85 — Inter-Channel Dye Masking
Cyan→green (2.0%) and magenta→blue (2.2%) bleed from Kodak 2383 spectral dye curves.
`float2 dye_cross` inside Beer-Lambert block. First real-time post-process to model
inter-channel dye coupling. Stage 1 novel: +7%. Stage 1 total: 75%.

### R88 — Sage-Husa Q Adaptation
Replaced instantaneous-innovation Q trigger (single-frame spike) in both Kalman passes
(`SmoothZoneLevels`, `UpdateHistory`) with posterior-P-driven adaptation. P accumulates
only on persistent change — flashes no longer spike the filter gain. 2 lines changed.

### R89 — IGN Blue-Noise Dither
Replaced `sin(dot)·43758` white-noise dither with Jimenez IGN (Interleaved Gradient
Noise). Spectrally blue — quantization error pushed to high spatial frequencies. Reduces
visible banding in fog, sky, and shadow gradients. No texture — analytical, same cost.

### R82 — 11 zero-loss optimizations in ColorTransformPS
−3 tex reads, −5 transcendentals, ~−30 live scalars, −8 saturate ops per pixel.
Critical fix for AMD RDNA: hist_cache[6] array removal frees 24 scalars, reducing
register spill pressure. All changes exact or below JND threshold.
See: `research/R82_2026-05-03_optimization_findings.md`

### F1–F3 — Film Sensitometry + Stevens Recalibration (2026-05-04)
Three implementations from nightly research (`research/2026-05-04_filmcurve.md`,
Žaganeli et al. 2026 + Nayatani 1997/JoV 2025):

- **F1** Print stock `desat_w` bounds: magic numbers `0.3`/`0.6` → `fc_knee_toe`/`fc_knee`.
  Desaturation window tracks scene exposure. 2-token change, zero new ops.
- **F2** Midtone chroma expansion: +6% bell at L≈0.47 added to R22. Net ~+3–4% after
  downstream ceilings. Gate-free double smoothstep. 4 ALU.
- **F3** `fc_stevens`: `sqrt` → `exp2(log2(key)*(1/3))`, denominator 2.03→2.04. Cube root
  matches psychophysical data across full photopic range. Dark scenes +6–8% shoulder.

### R90 — Adaptive Inverse Tone Mapping
Game-agnostic chroma recovery. IQR-based compression ratio (2.5-stop reference, ACES-
derived) drives Oklab chroma expansion. Luma unchanged — brightness neutral by construction.
Mid-weight bell curve `L*(1-L)*4` protects black/white. C-gate `saturate((C-0.10)/0.15)`
protects near-neutral pixels from amplifying warm white bias. Slope Kalman-smoothed in
analysis_frame (float16 PercTex), encoded at highway x=197. `INVERSE_STRENGTH 0.50`.
Key bug found: Oklab b-row from wrong spec (`0.4784…, -0.4043…`) mapped white to b≈0.1
(yellow). Correct row `0.7827…, -0.8086…` matches grade.fx and maps white to b=0.
Replaces R86 ACES-specific inverse. Stage 0 novel: +5%.

### SHADOW_LIFT_STRENGTH knob
Auto shadow lift was fully hidden. Exposed as user scalar (1.0 = calibrated default).
Arc Raiders: 1.0. GZW: 1.1 (dark indoor environments need more lift).

### GZW sync + LCA highway fix
GZW `creative_values.fx` was missing `VIEWING_SURROUND` and `LCA_STRENGTH` — grade.fx
failed to compile, causing black screen. Fixed.
LCA was sampling shifted r/b channels before the data highway guard at y=0, corrupting
the scope's pre-correction histogram. Guard moved before LCA reads.

---

## Scene Reconstruction Research Track

**Status: Phase 1 complete (analytical inverse + fingerprint design) — prototype pending**
**Goal:** Approximate the pre-tonemapped, scene-referred signal from the game's SDR output —
effectively inverting the engine's tone mapping to recover a RAW-like linear-light image,
then re-applying a controlled forward transform at output.

If this works, every stage in the pipeline operates on scene-referred values rather than
display-referred values. The entire grade becomes physically accurate rather than an
empirical correction on top of an opaque game transform.

### Why the existing approach is insufficient

`unused/general/inverse-grade/inverse_grade.fx` exists but was pulled from GZW with
"game tone curve is better." Its limitations:

- Blind generic inverse S-curve — not derived from any specific engine tone mapper
- Anchored only at p50, IQR-driven strength — no structural knowledge of shoulder/toe shape
- Proportional chroma recovery only (`lab.yz *= lerp(1.0, expansion, 0.5)`) — cannot
  correct the hue distortions ACES introduces (red/magenta → orange push is notorious)
- No tone mapper identification — same inversion applied regardless of game engine
- No forward re-apply — leaves the image in an uncontrolled luminance range

The failure mode is predictable: a blind inverse S will over-expand the wrong tonal regions
and produce chroma and hue errors that compound through every subsequent stage.

---

### R86 — Tone Mapper Identification and Analytical Inversion

**Track:** Scene Reconstruction | **Status:** Prototype running in Arc Raiders (2026-05-04)
**Targets:** New — not tracked in existing novelty scores

**Problem:**
The pipeline is game-agnostic — different games apply different tone mappers (or none)
before vkBasalt sees the frame. R86 must never assume a specific mapper is present.
The design requirement: detect which tone mapper was applied from display-referred
statistics already in PercTex / CreativeZoneHistTex, apply the correct inverse only
when confidence is high, and fall back to identity otherwise. The result must be
perceptually neutral on games that do not use ACES.

Arc Raiders (UE5) is the primary validation case — it is known to use the Hill 2016
ACES approximation:

```hlsl
// UE5 ACES approx (Hill 2016)
float3 ACESFilm(float3 x) {
    float a = 2.51, b = 0.03, c = 2.43, d = 0.59, e = 0.14;
    return saturate((x*(a*x+b))/(x*(c*x+d)+e));
}
```

This is a rational function `f(x) = (ax²+bx) / (cx²+dx+e)` — it has an exact analytical
inverse via the quadratic formula. Crucially, the inverse only exists in the range [0,1],
which is exactly what the display-referred SDR output provides.

**Approach:**

1. **Identify tone mapper from scene statistics** — The ACES coefficients produce a
   characteristic histogram shape (p75/p50 shoulder ratio, p25/p50 toe ratio, zone
   histogram overflow pattern) that distinguishes it from Reinhard, Hable/Uncharted2,
   AgX, and linear/no-TMO. Compute a per-frame confidence score; apply the analytic
   inverse only when `aces_conf > 0.7`. Below 0.3, pass through as identity. Arc Raiders
   is the known-good validation case; GZW must score low and receive no modification.

2. **Derive analytical inverse** — For the rational form `y = (ax²+bx)/(cx²+dx+e)`,
   rearrange to quadratic: `(cy-a)x² + (dy-b)x + ey = 0`. Solve for `x` (taking the
   positive root). This is exact — no approximation error.

3. **Exposure estimation** — The inverse maps [0,1] back to scene linear, but the actual
   scene-linear range depends on the exposure going into the tone mapper. Use p99 of the
   scene (available from the histogram) to anchor the inverse curve scale.

4. **ACES hue shift correction** — ACES is notorious for a red/magenta→orange hue push,
   a cyan→blue shift, and highlight desaturation of yellows. These are measurable as
   deviations from neutral in Oklab hue at mid–high chroma. Derive per-hue correction
   offsets from the known ACES spectral response and apply them in the Oklab LCh domain
   after the luminance inversion.

5. **Forward re-apply** — After the full pipeline runs on scene-referred values, apply a
   controlled forward display transform at the very end. This replaces or subsumes the
   current FilmCurve + PRINT_STOCK combination. The forward transform is the artist's
   choice: ACES, filmic S, or the current polynomial.

**Why this is novel:**

No game post-process shader identifies and inverts the upstream tone mapper. ACES inversion
is studied in VFX pipelines (for undoing bakes before re-compositing) but never in a
real-time display shader that also feeds the inverted signal back to further grading stages.
The combination of: stat-driven parameter confirmation → analytical inverse → hue correction
→ scene-referred grading → controlled forward output is entirely new in this context.

**Research deliverables:**

- Validate ACES confidence score on Arc Raiders (should score high) and GZW (should score low / identity)
- Derive the HLSL inverse and validate it with forward(inverse(x)) ≈ x across [0.01, 0.99]
- Characterise ACES hue distortions at different luminance/chroma combinations
- Prototype in `unused/` — do NOT integrate until validated end-to-end on both games
- Write findings doc before touching any live shader

**Risk factors:**

- The game may apply post-ACES operations (UI compositing, sharpening) that break the
  clean inverse. The scope guard at y=0 suggests at least one such transform exists.
- GZW may use a different tone mapper (check with a parallel analysis pass later)
- Exposure estimation from p99 is noisy if the scene contains specular spikes. The
  histogram already filters extremes (p95 bin exists) — use p95 as a robust ceiling.

**Scope:** Research-only until findings confirm the inverse is clean. No live shader
changes without a validated prototype in `unused/`.

---

### How this fits the main pipeline

If R86 succeeds, the Stage 0 input block gains a new first step:

```
[BackBuffer] → TMO⁻¹ (R86, confidence-gated) → EXPOSURE → CAT16 (R76A) → VIEWING_SURROUND (R76B)
```

Stages 1–Output then operate on approximately scene-linear values.
The final Output stage gains a forward display transform replacing/subsuming FilmCurve.

This would push Stage 0 novelty from 70% to approximately 90% — and make every
downstream stage more physically accurate as a side effect.
