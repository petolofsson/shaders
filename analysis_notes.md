# GZW Shader Stack — Scene Analysis Notes
# Last updated 2026-04-17 — v0.10

## Known Limitations
- **Night vision**: Blue-channel gate (`smoothstep(0.05, 0.18, col.b)`) on foliage_pass, promist scatter, promist diffuse blend, and veil lerp. Halation naturally immune (red-weighted luma, NVG R≈0 → luma_w far below thresh). Clean.
- **Scatter on overcast**: No bright highlights to trigger promist scatter. Diffuse still active. By design.
- **Flickering**: Watch on high-contrast night scenes (LERP_SPEED 0.08).
- **HDR**: Stack is SDR [0–1]. DXVK_HDR/PROTON_ENABLE_HDR removed from launch command. Do not re-enable without full rewrite.

---

## Shader values — current

### olofssonian_zone_contrast
Lives at: `~/code/shaders/general/olofssonian-zone-contrast/olofssonian_zone_contrast.fx`

  CURVE_STRENGTH 0.25, LERP_SPEED 0.08
  Three-way median blend: dark(25th)→mid(50th)→bright(75th)
  TOE_STRENGTH 0.35, TOE_RANGE 0.30 (darkest 30% of scene)
  TOE_TINT_R -0.028, TOE_TINT_G -0.014, TOE_TINT_B 0.033
  TOE_TINT: saturation gate smoothstep(0.14, 0.27) — skips neutral surfaces
  SHOULDER_STRENGTH 0.10, SHOULDER_RANGE 0.80 (brightest 20%)
  BLACK_LIFT: R0.008, G0.025, B0.035
  BLACK_POINT 0.035, WHITE_POINT 0.97 — OZC self-contained, no color_grade required
  SHADOW_TINT: R+0.005, G+0.008, B+0.050, SHADOW_RANGE 0.18
  HIGHLIGHT_TINT: R0.18, G0.06, B-0.08, HIGHLIGHT_START 0.65
  GRADE_R 0.996, GRADE_G 1.015, GRADE_B 1.00

### color_grade
Lives at: `~/code/shaders/general/color-grade/olofssonian_color_grade.fx`

  Active preset: Kodak Vision3 500T
  WHITE_R 0.97, WHITE_G 0.95, WHITE_B 0.93
  FILM_RG 0.057, FILM_RB 0.013, FILM_GR 0.031, FILM_GB 0.043, FILM_BR 0.013, FILM_BG 0.068
  SAT_GREEN 1.30, SAT_SKY 1.30, SAT_SENS 3.0
  SKY_LUMA_LO 0.25, SKY_LUMA_HI 0.65
  BLACK_POINT 0.035, SAT_MAX 0.85, SAT_BLEND 0.15
  Film matrix gate: smoothstep(0.10, 0.25, chroma) * smoothstep(0.08, 0.28, luma)

  Film presets:
  - Kodak Vision3 500T (active) — warm shadows, golden highlights, slightly desaturated mids → Blade Runner 2049, 1917
  - Kodak Vision3 200T — cleaner, cooler, less pushed → La La Land, Grand Budapest Hotel
  - Fuji Eterna 500 — cooler, green-leaning mids, flatter → Lost in Translation, Babel
  - Kodak 5219 (500T pushed) — punchy, deep warm blacks → Sicario, Prisoners
  - Fuji Velvia 50 — very saturated, high contrast (slide film, use sparingly)

### halation
  HALATION_SIGMA (BUFFER_WIDTH*0.0120), HALATION_TAPS 20
  HALATION_THRESH 0.72, HALATION_KNEE 0.18
  HALATION_STRENGTH 0.30, HALATION_GREEN 0.18, HALATION_BLUE 0.02
  Quadratic ramp (ramp*ramp). Foliage exclusion gate. Energy normalization.
  NVG immune (red-weighted luma).

### foliage_pass
  NVG gate: smoothstep(0.05, 0.18, col.b)

### promist
  EXTRACT_POWER 2.20, SCATTER_SPREAD (BUFFER_WIDTH*0.00176 ≈4.50px), SCATTER_STRENGTH 0.46
  DIFFUSE_RADIUS 0.010, DIFFUSE_STRENGTH 0.185
  DIFFUSE_LUMA_LO 0.50, DIFFUSE_LUMA_CAP 0.88
  NVG gate: smoothstep(0.05, 0.18) on scatter extraction and diffuse blend.
  WARM_R 1.10, WARM_G 1.02, WARM_B 0.80

### veil
  VEIL_STRENGTH 0.17, VEIL_RADIUS (BUFFER_WIDTH*0.001465)
  VEIL_TINT R1.02/G1.00/B0.97
  VEIL_LUMA_CAP 0.82 — white gate
  Sky exclusion gate: (col.b - max(col.r,col.g)) * 8.0
  NVG gate: smoothstep(0.05, 0.18, col.b)

### sharpen
  SHARPEN_STRENGTH 0.28, SHARPEN_LUMA_LO 0.18
  CONTRAST_LO 0.05, CONTRAST_HI 0.15
  Three gates: luma_w (quadratic), contrast_w (diffuse-aware), sat_w (smoothstep 0.08–0.22)

### ca
  CA_STRENGTH 0.0024 — radial, luma-weighted (quadratic), corners only

### vignette
  STRENGTH 0.22, INNER 0.20, SMOOTHNESS 0.6

---

## Current chain
```
olofssonian_zone_contrast → color_grade → halation → foliage_pass → promist → veil → sharpen → ca → vignette
```
Currently active in gzw.conf: `olofssonian_zone_contrast` only (tuning in progress)

---

## olofssonian_zone_contrast — Technique Uniqueness Research (2026-04-16)

### What exists in the literature

- **Reinhard 2002**: Derives a global "key value" from log-average luminance, scales the whole scene. Single global value — no percentile pivots, no per-pixel curve blending.
- **UE5 / Unity auto-exposure**: Histogram percentile range (UE5: 10th–90th) determines a single global exposure multiplier. Shifts the whole image uniformly — not per-pixel, not two S-curve pivots.
- **ReShade CLAHE**: Local adaptive histogram equalization per screen neighborhood — completely different architecture.
- **Bart Wronski localized tonemapping**: Laplacian pyramid spatial decomposition — different technique entirely.
- **Exposure Fusion**: Blends multiple exposures by local quality metrics — conceptually related but different implementation.

### What olofssonian_zone_contrast does that nothing else documented does

1. **Sparse quasi-random scene sampling** — 128 Halton(2,3) points, no histogram pass or compute shader
2. **In-shader bitonic sort** — percentile extraction inside a pixel shader, no readback
3. **Two S-curves pivoted at scene-derived percentile values** — dark pivot at 25th, bright pivot at 75th
4. **Per-pixel blend between the two curves** — each pixel self-selects its correction by where it sits in the scene's own IQR
5. **Adaptive strength via IQR width** — compressed scenes get more boost, wide-range scenes get less

### Closest prior art — Quartile Sigmoid Function (QSF)
**Source:** "Adaptive Quartile Sigmoid Function Operator for Color", IS&T Color Imaging Conference (CIC), 9th edition.

| | QSF | Olofssonian Zone Contrast |
|---|---|---|
| Pivot extraction | Full histogram accumulation | Direct Halton sampling + in-shader bitonic sort |
| Transition at median | Hard switch | Continuous per-pixel blend |
| Color handling | Per-channel RGB (hue-shifting) | Luma-only (hue-preserving) |
| Runtime | Offline / batch | Per-frame fragment shader |
| Temporal coherence | None | Lerp on percentile values |

**Metric for write-up:** AMBE (Absolute Mean Brightness Error) — QSF was optimized for this. Running AMBE comparison vs. fixed-pivot and QSF would strengthen any formal submission.

**Origin:** Todd Dominey — "The Wrong Way to Add Contrast (and What to Do Instead)" https://www.youtube.com/watch?v=BTe0JLe5g2Y
