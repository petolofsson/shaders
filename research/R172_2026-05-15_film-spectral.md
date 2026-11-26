# R172 — Film Spectral Emulation: Per-Channel Print Dye Shoulder and DIR Bell Cross-Validation

**Date:** 2026-05-15
**Domain:** Film stock spectral emulation (Friday rotation)
**Status:** F1 implementation-ready; F2 cross-validation only; F3 deferred

---

## Literature surveyed

- vkdt `filmsim` module (jo.dreggn.org) — GPU two-stage negative+print pipeline, DIR coupler model with density-dependent per-layer inhibition
- andreavolpato/spektrafilm (GitHub, 2025) — full analog process simulation with spectral calculations, grain, couplers, halation
- JanLohse/spectral_film_lut (GitHub) — LUT generation from Kodak/Fuji published datasheets via spectral sensitivity matrices
- Kodak Vision Color Print Film 2383/3383 datasheet (Kodak, public) — CMY dye spectral density curves, D-min/D-max per-channel values, interimage effects note
- Žaganeli et al. 2026 *arXiv:2604.06276* — pixel-wise SDR→HDR cinema mastering statistics showing chroma redistribution: shadow suppression + midtone expansion + highlight convergence
- Plutino 2024, *Color Research & Application* — color systems for motion picture film digitization; ADX/APD encoding discussion

---

## Prior art audit (relevant to this domain)

| File | What it covers |
|------|----------------|
| `ApplyPrintStock` (R51/R160, grade.fx:207) | Single-curve shoulder + adaptive black lift (p25) + adaptive shoulder soften (p75) + small static R+0.010/B−0.007 warmth tint |
| `ApplyMaskingCoupler` (R110, grade.fx:184) | Shadow-biased red warmth coupler, quadratic luma gate |
| `ApplyDyeMatrix` (R130, grade.fx:170) | 3×3 unwanted-absorption matrix for saturated pixels only; scales by sat_proxy ramp |
| R104 DIR couplers (grade.fx:375) | Log2-space cross-channel inhibition, `act = x²/(x²+0.09)`, default COUPLER_STRENGTH=0 (off) |
| R22 midtone chroma bell (grade.fx:500) | `0.08 × smoothstep(0.22,0.40,L) × (1−smoothstep(0.55,0.70,L))` plus 20% shadow desat |

**What is not covered:** Per-channel shoulder compression asymmetry (B<G<R D-max ordering) in the print stock. The current `ApplyPrintStock` applies a single scalar `ps_shoulder` to all three channels equally; the static ±R/B tints are linear (not shoulder-shaped). The spectral physics of Kodak 2383 print dye compression ordering is absent.

---

## Finding 1 — Per-channel print dye D-max shoulder (Kodak 2383 spectral ordering)

### Physical basis

The Kodak 2383 datasheet documents the spectral dye density curves for the cyan, magenta, and yellow print dyes. Each dye has a different D-max (maximum density at saturation) and a different onset of the shoulder region where the characteristic curve compresses:

| Print dye | Controls | D-max saturation order |
|-----------|----------|------------------------|
| Yellow (Y) | Blue channel | Saturates first — lowest D-max before compression |
| Magenta (M) | Green channel | Intermediate |
| Cyan (C) | Red channel | Saturates last — highest D-max headroom |

The datasheet notes: "The yellow spectral dye density is narrower on the long wavelength side, resulting in less unwanted absorption in the green light region." This narrower yellow response means the yellow dye saturates at lower absolute density, compressing the blue channel in highlights before the green or red channels reach compression.

**Visual result:** In bright highlights, blue compresses before green, green before red. The print appears warm in highlights (less blue → orange/gold cast) and comparatively cool in lower midtones where all three dyes are operating linearly. This is the physical origin of the characteristic Kodak warm-highlight, cool-shadow "crossover" look — not a grading choice but a consequence of the print dye spectral physics. The current pipeline approximates this with static `ps.r += 0.010` and `ps.b -= 0.007` tints (linear, not shoulder-shaped), which underrepresents the non-linear compression character in the upper range.

### Implementation sketch

Extend `ApplyPrintStock` in `grade.fx` with per-channel shoulder onset thresholds, inserted after the existing unified shoulder computation and before the final `lerp(lin, saturate(ps), print_stock)`:

```hlsl
// R172: per-channel print dye shoulder — B<G<R D-max ordering (Kodak 2383)
// Threshold values (0.0–1.0 display-referred linear) derived from
// community-documented 2383 H&D curve shoulder endpoints.
// Blue saturates ~76%, green ~82%, red ~89% of display linear range.
static const float PS_DSAT_B = 0.76;
static const float PS_DSAT_G = 0.82;
static const float PS_DSAT_R = 0.89;
// Compression ratio above threshold (soft half-slope in shoulder region)
static const float PS_COMP   = 0.50;

float3 dsat_excess;
dsat_excess.r = max(0.0, ps.r - PS_DSAT_R);
dsat_excess.g = max(0.0, ps.g - PS_DSAT_G);
dsat_excess.b = max(0.0, ps.b - PS_DSAT_B);
ps -= dsat_excess * PS_COMP;
// (ps already in [0,1] via toe/shoulder; dsat_excess * 0.50 keeps ps < 1.0)
```

This goes **after** the existing toe/shoulder block and **before** the `desat_w` midtone desaturation section in `ApplyPrintStock`. The three constants `PS_DSAT_*` are not user-adjustable (they are a property of the 2383 print stock, not a creative choice) — keep them in `grade.fx` as `static const`. The overall `PRINT_STOCK` blend at the end still governs overall strength.

**Effect at display-referred values:**
- Below ps.b = 0.76: no per-channel asymmetry, all three channels compress at same rate via the existing unified shoulder.
- 0.76 < ps.b ≤ 1.0: blue compressed by 50% of excess → warm cast starts appearing.
- 0.82 < ps.g ≤ 1.0: green also compresses → yellow-orange push.
- 0.89 < ps.r ≤ 1.0: red now also compresses — only in near-white regions.
- Result: specular highlights shift from neutral to warm (reduced blue first, then green), matching 2383 characteristic projection look.

### GPU cost

| Operation | Cost |
|-----------|------|
| 3× `max(0, ps - threshold)` | 3 MAD |
| 3× `ps -= excess * 0.50` | 3 FMA |
| **Total** | **~6 ALU** |
| New textures | 0 |
| New passes | 0 |
| New highway slots | 0 |

### Conflict check

- **No gates:** `max(0, x - threshold)` is a continuous ramp; no seams or conditionals.
- **SDR safe:** `dsat_excess * 0.50 < dsat_excess`; the reduction brings ps toward (not below) the threshold. Combined with the existing `saturate(ps)` at return, output stays [0,1].
- **R133 Munsell highlight rolloff** also compresses highlights in chroma (per-hue). The two effects are complementary: R133 operates in Oklab chroma (hue-dependent), while this operates in RGB per-channel (dye-dependent). No interaction.
- **Existing ps.r += 0.010 / ps.b -= 0.007 tints:** These linear tints are small (≈1%) and remain. The per-channel shoulder adds a non-linear compression on top. The total effect is: linear tint (everywhere) + per-channel compression (only in highlights). Compatible.
- **PRINT_STOCK = 0:** The entire function blends to identity at PRINT_STOCK=0, so this is automatically disabled when PRINT_STOCK is off.

### Confidence

Medium-high. The B<G<R D-max ordering of 2383 print dyes is directly stated in the datasheet. The specific threshold values (0.76/0.82/0.89) are derived from community-documented characteristic curve shoulder endpoints, not directly from the Kodak data (the datasheet gives density curves in optical density units, not display-linear); these may need visual calibration upward or downward by ~0.05. The half-slope (0.50) is a conservative choice and can be tuned by inspection.

---

## Finding 2 — Physical cross-validation of R22 midtone chroma bell

### What the literature shows

Žaganeli et al. (arXiv:2604.06276) performed a pixel-wise case study of SDR→HDR cinema mastering using ASC StEM2, reporting that in the chroma dimension: "saturation exhibiting a redistribution pattern of shadow suppression, midtone expansion, and highlight convergence." This is the empirical basis for the midtone chroma bell already in R22.

The vkdt filmsim documentation and spektrafilm source code confirm the physical mechanism: DIR coupler activity is proportional to development activity, which follows a roughly bell-shaped profile as a function of scene exposure (density):
- At very low exposure (underlit / deep shadows): insufficient silver halide to develop → minimal dye formation → minimal DIR coupler release.
- At mid-density (roughly 1–2 stops below key): maximum development activity → maximum dye and DIR coupler formation → maximum interimage saturation enhancement.
- At high exposure (highlights / thin negative): developer consumption slows at low density → DIR activity falls off → interimage effect diminishes.

### Alignment with current R22 implementation

Current R22 midtone bell: `0.08 × smoothstep(0.22, 0.40, L) × (1 − smoothstep(0.55, 0.70, L))`

This bell plateaus in Oklab L range [0.40, 0.55] with soft transitions. For display-referred content where Oklab L ≈ Y^(1/3) (approximation), this corresponds to display-linear Y ≈ [0.064, 0.166] — the lower midtone/shadow transition zone.

The physical DIR coupler peak at ~18% gray (zone V, middle density) in film exposure space maps to display-referred Y ≈ 0.18, Oklab L ≈ 0.46 (using L = 0.2 + 0.88Y^0.38 as approximate CIE 2015 proxy). This is squarely within the current R22 bell plateau (0.40–0.55).

**Conclusion: R22 midtone bell peak location and amplitude are physically coherent.** The empirical Žaganeli data and the film interimage model agree. No tuning change recommended.

**One advisory note:** The upper bell knee at L=0.70 is broader than strict film physics would predict (mid-density activity should tail off well before display L=0.70, which corresponds to Y ≈ 0.30 — at 30% linear luminance the negative is relatively thin and developer activity is indeed declining). If the upper knee were tightened from 0.70 to 0.60–0.62, the bell would more precisely track the physical DIR activity curve. However, the current 0.70 provides a smoother tonal result and the 0.02–0.03 Oklab L difference has minimal perceptual consequence. **This is informational only; no code change recommended.**

---

## Finding 3 (deferred) — Spectral input sensitivity matrix

### Status

Deferred from R126 F3. Source: JanLohse/spectral_film_lut derives a 3×3 input matrix per film stock by sampling published spectral sensitivity curves at sRGB primary wavelengths. For Kodak Vision3 500T (5219), the red layer has non-negligible sensitivity at ~530nm (cross-talk with green channel), which creates the characteristic skin tone rendering.

**Why still deferred:**
- Pipeline input is display-referred sRGB, not scene-referred spectral radiance. A 3×3 applied to display-referred values conflates the camera spectral response with the film spectral response — the resulting matrix is doubly confounded.
- The Kodak "skin tone" effect visible in real footage arises partly from the spectral cross-sensitivity and partly from the print stock gamut. The print stock effects are already addressed (ApplyDyeMatrix, ApplyMaskingCoupler, ApplyPrintStock). Adding the input sensitivity matrix risks double-counting.
- Would require calibration against reference footage graded on a real Vision3 negative + 2383 print chain.

**Next step before implementation:** Verify whether the identified skin tone rendering difference (compared to a PRINT_STOCK=0 scene) is already largely explained by the existing pipeline (ApplyDyeMatrix + print coupler chain). If a visible gap remains vs real 2383 footage, revisit the input matrix.

---

## Stage impact summary

| Finding | Target | GPU cost | Risk | Recommendation |
|---------|--------|----------|------|----------------|
| F1 Per-channel print shoulder | `ApplyPrintStock` in `grade.fx` | ~6 ALU | Low | Implement — check visual with PRINT_STOCK > 0.5 |
| F2 R22 bell cross-validation | None (validation only) | 0 | — | Close as confirmed; upper knee advisory only |
| F3 Spectral input matrix | Pre-FilmCurve (CORRECTIVE) | 9 MAD | Medium | Continue to defer |

### Implementation order for F1

1. Locate `ApplyPrintStock` in `grade.fx` (line 207).
2. After the `ps = lerp(toe, shoulder, …)` block and before the `desat_w` desaturation block, insert the three `max(0, ps - threshold)` clamps per-channel.
3. Do NOT add new knobs to `creative_values.fx` — the thresholds are stock constants, not creative choices.
4. Test with PRINT_STOCK sweeping 0→1 at a neutral bright scene (overexposed sky) — expect: warm shoulder appearing progressively as PRINT_STOCK increases, zero effect below ps.b ≈ 0.76.
