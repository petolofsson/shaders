# GZW Shader Stack — Scene Analysis Notes
# Last updated 2026-04-17 — v0.10

## Known Limitations
- **Night vision**: Blue-channel gate (`smoothstep(0.05, 0.18, col.b)`) on foliage_light extraction, promist scatter extraction, promist diffuse blend, and veil lerp. Halation naturally immune (red-weighted luma, NVG R≈0 → luma_w ≈ 0.083, far below thresh 0.82). Clean.
- **Silver at distance**: Silver rim is edge-detection based — fires on sharp contrast edges. At mid/far distance leaf mass blurs together, nb_contrast stays low. Up close on individual leaves it works well.
- **Scatter on overcast**: No bright highlights to trigger. Diffuse still active. By design.
- **Flickering**: Reduced (LERP_SPEED 0.04, CURVE_STRENGTH 0.28). Watch on high-contrast night scenes.
- **HDR**: GZW HDR is OFF (`bUseHDRDisplayOutput=False`). Stack is SDR [0–1]. Do not enable GZW HDR without full rewrite.

---

## What's working well
- **Foliage separation** — warm/cool luma-weighted gradient on leaves. SAT_GREEN/SAT_SKY luma-weighted — preserves internal leaf gradient instead of uniform boost.
- **Shadow depth** — filmic toe (cubic, TOE_STRENGTH 0.40) + indigo bell-curve tint (peaks mid-shadow luma ≈0.15, fades to black at floor). Deep cinematic shadow density.
- **Indigo shadows** — toe tint R-0.022, G-0.010, B+0.028. Decoupled from cubic, peaks at visible mid-shadow. Saturation-gated — concrete/sky/road skip it. Classic cinematic night blue on chromatic surfaces.
- **Blue→black gradient** — visible transition from blue (shadow entry) to pure black (true black). TOE_RANGE 0.30 stretches gradient wider than original 0.28.
- **Night visibility** — TOE_STRENGTH pulled back to 0.40 + BLACK_LIFT raised. Floor lifted, silhouettes readable. NVG clean.
- **Silver rim** — cool blue-white on lit leaf edges. Fires on leaves, not rocks/concrete. Can reach true white.
- **Shadow rim** — internal leaf gradient, dark core / brighter edge on shadow foliage.
- **Halation** — red-amber bleed around sun and lamps. Quadratic ramp — hottest pixels produce most halation.
- **Veil** — soft atmospheric haze. Mid-distance tree mass dissolves into humid air. White gate prevents glow on buildings.
- **Promist diffuse** — luma-weighted blend (* luma_b). Bright surfaces soften most, darks stay crisp. Merges tree edges into unified canopy mass.
- **Promist scatter** — luma-weighted extraction via pow(). Wide spread (≈4.50px) for atmospheric sun halo.
- **CA** — luma-weighted quadratic radial fringing. Concentrates at bright highlights, invisible in shadows.
- **Highlight tint** — warm amber builds with brightness (quadratic), concentrated at hottest surfaces.
- **Sharpening** — adaptive unsharp mask. Three gates: luma (darks stay soft), contrast (diffused areas untouched), saturation (neutral concrete/sky skipped). Placed after veil so promist diffuse is not sharpened back.
- **Night** — deep shadow density with cinematic indigo rolloff. ~80% vanilla. PVP fair.
- **NVG** — clean. Blue-channel gate (0.05–0.18) on all blur/bloom paths. Halation immune by design.
- **Canopy blending** — promist diffuse at 0.185 merges tree edges into unified canopy mass.
- **Bark/concrete neutrality** — shadow tint + toe tint both saturation-gated: foliage/earth get cool tint, concrete/buildings stay neutral.
- **Green vibrancy** — GRADE_G 1.015 compensates for GRADE_R red pull, warm yellow-green preserved on foliage.

---

## Shader values — v0.9 (final)

### foliage_light
  BLOOM_RADIUS (BUFFER_WIDTH*0.00293), BLOOM_STRENGTH 0.50, EXTRACT_POWER 2.80
  WARM_HUE_LO 0.05, WARM_HUE_HI 0.35
  KELVIN_R 1.06, KELVIN_G 1.00, KELVIN_B 0.78
  SILVER_RADIUS (BUFFER_WIDTH*0.000781)
  SILVER_STRENGTH 0.60, SILVER_LIFT 1.45, SILVER_LUMA_LO 0.48
  nb_contrast: smoothstep(0.25, 0.40, lc - min_nb)
  foliage_s: smoothstep(0.15, 0.30) — excludes rocks/concrete
  silver tint: float3(lc*0.97, lc*1.00, lc*1.05) — cool blue-white
  Hard ceiling: result = min(result, float3(0.97, 0.95, 0.92))
  Shadow rim: SHADOW_RIM_STRENGTH 0.35, SHADOW_RIM_LUMA_HI 0.52, SHADOW_RIM_CONTRAST 0.10
  NVG gate: smoothstep(0.05, 0.18, col.b)

### halation
  HALATION_SIGMA (BUFFER_WIDTH*0.00469), HALATION_TAPS 20
  HALATION_THRESH 0.82, HALATION_KNEE 0.18
  HALATION_STRENGTH 0.16, HALATION_GREEN 0.18, HALATION_BLUE 0.02
  Quadratic ramp (ramp*ramp) — hottest pixels produce most halation.
  Scalar energy normalization, saturation gate smoothstep(0.08, 0.20), foliage exclusion gate.
  sat_gate floor 0.08 (raised from 0.04) — prevents warm-white sunlit buildings from triggering halation.
  NVG immune (red-weighted luma).

### promist
  EXTRACT_POWER 2.20, SCATTER_SPREAD (BUFFER_WIDTH*0.00176 ≈4.50px), SCATTER_STRENGTH 0.46
  DIFFUSE_RADIUS 0.010, DIFFUSE_STRENGTH 0.185
  DIFFUSE_LUMA_LO 0.50 — raised from 0.45, reduces bloom on bright neutral surfaces
  DIFFUSE_LUMA_CAP 0.88 — fade out above here
  NVG gate: smoothstep(0.05, 0.18) on scatter extraction and diffuse blend.
  WARM_R 1.10, WARM_G 1.02, WARM_B 0.80

### veil
  VEIL_STRENGTH 0.17, VEIL_RADIUS (BUFFER_WIDTH*0.001465)
  VEIL_TINT R1.02/G1.00/B0.97 (luma-preserving) — neutral green, eased blue suppression
  VEIL_LUMA_CAP 0.82 — white gate, prevents glow on buildings/concrete
  Sky exclusion gate: smoothstep via (col.b - max(col.r,col.g)) * 8.0 — sky pixels skip veil entirely
  NVG gate: smoothstep(0.05, 0.18, col.b)

### olofssonian_zone_contrast
  CURVE_STRENGTH 0.25, LERP_SPEED 0.08
  Three-way median blend: dark(25th)→mid(50th)→bright(75th), quadratic outer weight preserves shadow depth
  Frame-jittered Halton: kHalton[256] table, 128 samples/frame, window slides by FRAME_COUNT%128, ≈1600 effective samples over smoothing window
  TOE_STRENGTH 0.37, TOE_RANGE 0.35 (cubic rolloff for darkening)
  TOE_TINT_R -0.028, TOE_TINT_G -0.014, TOE_TINT_B 0.040
  TOE_TINT: linear bell (decoupled from cubic), peaks luma ≈0.175 (TOE_RANGE/2)
  TOE_TINT: saturation gate smoothstep(0.12–0.22) — skips neutral surfaces
  SHOULDER_STRENGTH 0.10 (cubic rolloff)
  BLACK_LIFT: R0.008, G0.025, B0.035
  SHADOW_TINT: R+0.005, G+0.008, B+0.050, SHADOW_RANGE 0.18 — saturation-gated (smoothstep 0.12–0.22)
  HIGHLIGHT_TINT: R0.18, G0.06, B-0.08, HIGHLIGHT_START 0.65 (quadratic luma-weighted)
  GRADE_R 0.996, GRADE_G 1.015, GRADE_B 1.00

### color_grade
  General-purpose film-stock grade. Foliage-specific work moved to gzw_foliage_pass.fx.

  Shader lives at: /general/color-grade/olofssonian_color_grade.fx
  GZW-specific tuning (defaults in shader are more conservative):
    SAT_GREEN 1.30 (default 1.15), SAT_SKY 1.30 (default 1.15)
    BLACK_POINT 0.035 (default 0.020), SAT_BLEND 0.18 (default 0.15)

  Active preset: Kodak Vision3 500T
  WHITE_R 0.97, WHITE_G 0.95, WHITE_B 0.93
  FILM_RG 0.057, FILM_RB 0.013, FILM_GR 0.031, FILM_GB 0.043, FILM_BR 0.013, FILM_BG 0.068

  SAT_GREEN 1.30, SAT_SKY 1.30 — luma-weighted (sat_luma), SAT_SENS 3.0
  SKY_LUMA_LO 0.25, SKY_LUMA_HI 0.65 — sky saturation active in mid-luma range only
  BLACK_POINT 0.035
  SAT_MAX 0.85, SAT_BLEND 0.18
  Film matrix gate: smoothstep(0.10, 0.25, chroma) * smoothstep(0.08, 0.28, luma) — neutral/dark surfaces skip matrix

  ---

  Film presets and cinematic reference:

  Kodak Vision3 500T (active — default)
    Warm shadows, golden highlights, slightly desaturated mids. The modern film look.
    → No Country for Old Men, Blade Runner 2049, 1917, The Revenant, Dunkirk

  Kodak Vision3 200T
    Cleaner, less pushed, cooler overall. Same stock family, less character.
    → La La Land, The Grand Budapest Hotel, Moonrise Kingdom

  Fuji Eterna 500
    Cooler, green-leaning mids, flatter contrast, neutral shadows. The quiet/literary look.
    → Lost in Translation, Marie Antoinette, Babel, The Assassination of Jesse James

  Kodak 5219 (Vision3 500T pushed)
    High contrast, punchy, deep warm blacks. Deakins' thriller aesthetic.
    → Sicario, Prisoners, True Grit, Road to Perdition

  Fuji Velvia 50
    Very saturated, cool neutral shadows, high contrast. Slide film — not a cinema stock.
    Nature/landscape photography aesthetic: National Geographic, Baraka, Koyaanisqatsi.
    Use for hyper-real or stylised looks only.

### sharpen
  SHARPEN_STRENGTH 0.28, SHARPEN_LUMA_LO 0.18
  CONTRAST_LO 0.05, CONTRAST_HI 0.15
  Three gates: luma_w (quadratic), contrast_w (diffuse-aware), sat_w (smoothstep 0.08–0.22)
  Position: after veil, before ca

### ca
  CA_STRENGTH 0.0024 — radial, luma-weighted (quadratic), corners only

### vignette
  STRENGTH 0.22, INNER 0.20, SMOOTHNESS 0.6

---

## olofssonian_zone_contrast — Technique Uniqueness Research (2026-04-16)

### What exists in the literature

- **Reinhard 2002**: Derives a global "key value" from log-average luminance, scales the whole scene. Single global value — no percentile pivots, no per-pixel curve blending.
- **UE5 / Unity auto-exposure**: Histogram percentile range (UE5: 10th–90th) determines a single global exposure multiplier. Shifts the whole image uniformly — not per-pixel, not two S-curve pivots.
- **ReShade CLAHE**: Local adaptive histogram equalization per screen neighborhood — completely different architecture.
- **Bart Wronski localized tonemapping**: Laplacian pyramid spatial decomposition — different technique entirely.
- **Exposure Fusion**: Blends multiple exposures by local quality metrics — conceptually related (per-pixel content-based blending) but different implementation.

### What olofssonian_zone_contrast does that nothing else documented does

The specific composition that doesn't appear in game graphics literature:

1. **Sparse quasi-random scene sampling** — 64 Halton(2,3) points cover the screen without a histogram pass or compute shader
2. **In-shader bitonic sort** — actual percentile extraction inside a pixel shader, no readback, no multi-pass histogram
3. **Two S-curves pivoted at scene-derived percentile values** — dark pivot at 25th percentile, bright pivot at 75th
4. **Per-pixel blend between the two curves** — `smoothstep(dark_pivot, bright_pivot, pixel_luma)` — each pixel self-selects its correction by where it sits in the scene's own IQR
5. **Adaptive strength via IQR width** — compressed scenes (narrow IQR) get more boost, wide-range scenes get less — decoupled from the percentile values

### Author background — relevant for paper framing

Peter Olofsson — amateur photographer, photojournalist, avid film fan. The stack's aesthetic decisions (Kodak Vision3 halation, filmic toe, ivory white point, warm/cool foliage split, indigo shadow tint) are photographer's decisions, not shader programmer defaults. The technique was designed by someone who understands how film actually looks — this is a different starting point than most graphics research, and worth stating in any introduction.

### Origin — the video that started it

**"The Wrong Way to Add Contrast (and What to Do Instead)"**
Todd Dominey — https://www.youtube.com/watch?v=BTe0JLe5g2Y
This video introduced the concept of using the image's median/midpoint as a pivot for contrast curves rather than a fixed value. It was the conceptual seed for Olofssonian Zone Contrast — the insight that the pivot should be derived from the scene's own tonal distribution, not a universal constant.

### Closest prior art — Quartile Sigmoid Function (QSF)
**Source:** "Adaptive Quartile Sigmoid Function Operator for Color", IS&T Color Imaging Conference (CIC), 9th edition.

QSF uses Q1/Q3 quartile pivots with two curves meeting at Q2 (median). Key differences from Olofssonian Zone Contrast:

| | QSF | Olofssonian Zone Contrast |
|---|---|---|
| Pivot extraction | Full histogram accumulation | Direct Halton sampling + in-shader bitonic sort |
| Transition at median | Hard switch | Continuous per-pixel blend |
| Color handling | Per-channel RGB (hue-shifting) | Luma-only (hue-preserving) |
| Runtime | Offline / batch | Per-frame fragment shader |
| Temporal coherence | None | Lerp on percentile values |

QSF was derived from psychophysical experiments — confirming that Q1/Q3 pivots align with human perceptual contrast sensitivity, not just mathematical convenience. This independently validates our choice of 25th/75th percentiles as pivots.

**What we do better than QSF:**
1. Per-pixel continuous blend vs. hard switch — no tonal discontinuity at the median
2. Luma-only operation — no hue shifts (QSF per-channel RGB changes hue)
3. Real-time single-pass — no histogram buffer or multi-pass accumulation
4. Temporal smoothing — no frame flicker on scene cuts

**Metric to consider for write-up:** AMBE (Absolute Mean Brightness Error) — QSW was optimized for this. Running AMBE comparison vs. fixed-pivot and QSF would strengthen any formal submission.

### Verdict

The per-pixel blend between two scene-derived percentile-pivoted S-curves is genuinely novel in real-time graphics. The pieces exist individually (histogram percentiles in auto-exposure, S-curves in tone mapping), but this specific composition — using the scene's IQR as the per-pixel blend axis — is not documented anywhere in game shader literature or ReShade repositories. The bitonic sort inside a pixel shader is also unusual; the standard approach is a compute pass.

QSF (IS&T CIC) is the closest published prior art — uses quartile pivots but hard-switches at median, operates offline, and processes per-channel. Cite as prior art in any formal write-up.

Closest real-time work: Reinhard 2002 auto key + UE5 histogram auto-exposure. Neither does per-pixel pivot blending.

In published game engine work: possibly being done inside closed engines (Frostbite, id Tech) without publication.

---

## Current chain
```
olofssonian_zone_contrast → color_grade → halation → foliage_light → promist → veil → sharpen → ca → vignette
```
Shelved (not in chain): gzw_rolloff.fx
Removed: gzw_grain.fx, gzw_atmosphere.fx, gzw_pseudo_depth.fx
