# R116 — Color Pipeline Audit — 2026-05-06

## Scope

Full audit of statistics, compression stacking, and adaptive logic across the color
pipeline. Covers analysis_frame.fx, corrective.fx, grade.fx. All findings verified
against actual code — several automated-analysis claims were wrong and excluded.

Excluded (agent claim, code disproves):
- "PrintStock desaturation fires in midtones" — formula fires only below fc_knee_toe
  (deep shadows). Product of two smoothstep terms kills it above ~0.20 luma.
- "texture_att is inverted" — `1 - smoothstep(0.005, 0.030, |illum_s0 - illum_s2|)`
  correctly reduces shadow lift where Mip1 and Mip2 diverge (textured/detailed areas).

---

## Issue 1 — Arithmetic mean for chroma pivot (HIGH)

**Location:** `analysis_frame.fx` MeanChromaPS, lines 411–443

**What it does:** Computes arithmetic mean of Oklab C across all pixels with C > 0.05.
This mean drives the chroma slope calculation in `inverse_grade.fx` (HWY_MEAN_CHROMA,
x=198), which scales how aggressively R90 expands chroma.

```hlsl
sum_C += C * in_b;    // in_b = step(0.05, C)
...
float mean_C = lerp(0.10, sum_C * inv_count, valid);
```

**Why it's wrong:** Arithmetic mean of a right-skewed distribution (chroma) is biased
toward the tail. A single neon sign, fire effect, or saturated UI element with C=0.30
in a scene where 95% of pixels have C ≤ 0.08 pulls the mean to ~0.12 — 50% above the
scene's actual median chroma. This is the value that the inverse grade uses as its
"scene chroma reference"; a high mean makes the scene appear more saturated than it is,
causing R90 to expand chroma more aggressively than intended.

**Consequence:** In scenes with isolated saturated objects (explosions, neon, status
indicators), chroma expansion fires too hard on the full frame, pushing neutrals and
pastels away from grey toward the dominant outlier hue.

---

## Issue 2 — Zone log key is geometric mean of zone medians (MEDIUM)

**Location:** `corrective.fx` UpdateHistoryPS band_idx==6, lines 313–328

```hlsl
float lk = 0.0;
for each of 16 zones: lk += log2(max(zm, 0.001));
return float4(exp2(lk * 0.0625), ...);   // geometric mean of zone medians
```

**What it does:** `zone_log_key` is the geometric mean of the 16 zone medians. It
drives: FilmCurve knee position, zone contrast strength attenuation, shadow lift
strength, H-K exponent, Pro-Mist key scale, and more.

**The structural concern:** Geometric mean in log space is appropriate when the quantity
is multiplicative (exposure, gain). Zone medians are not multiplicative — they are
luminance values in linear light. Using geometric mean gives disproportionate weight to
dark zones. In a split scene (dark interior + bright window), the bright window might be
zone_median=0.85 and the 15 interior zones median=0.08. Geometric mean: `exp2((15 *
log2(0.08) + log2(0.85)) / 16) = exp2(-3.67) ≈ 0.077`. Arithmetic mean: `(15*0.08 +
0.85)/16 ≈ 0.128`. The geometric mean reads the scene as darker than it is.

**Consequence:** zone_log_key underestimates scene key in high-contrast scenes → zone
contrast fires at higher strength than intended, shadow lift fires harder, H-K exponent
biased toward dark-scene mode. The interior of the split scene gets over-treated.

---

## Issue 3 — zone_std from zone medians, not per-pixel variance (MEDIUM)

**Location:** `corrective.fx` lines 320–327

```hlsl
m2 += zm * zm;
float zavg = m * 0.0625;
float zone_std = sqrt(max(m2 * 0.0625 - zavg * zavg, 0.0));
```

**What it does:** `zone_std` is the standard deviation of the 16 zone median values —
how spread apart the zone medians are spatially. This drives zone contrast strength via
`zone_str = ZONE_STRENGTH * lerp(0.14, 0.24, zone_std_norm)`.

**The problem:** zone_std measures tonal *separation between zones*, not per-pixel
contrast within zones. Consider two scenes:

- Scene A: 16 zones with medians ranging 0.05–0.90 (bright sky, dark foreground, varied
  mid). High zone_std → high zone contrast.
- Scene B: 16 zones all with median=0.5, but each zone contains sharp black/white
  edges (highly textured). Low zone_std → low zone contrast.

Scene B has more actual pixel-level contrast but gets less zone contrast boost. Scene A
gets aggressive contrast even if its zones are internally smooth.

**Consequence:** Zone contrast adapts to spatial tonal distribution (interesting for
cinema-style scene adaptation), but not to local detail or texture. Scenes that are flat
overall but texture-rich get under-treated; scenes that are tonally varied but smooth
get over-treated.

---

## Issue 4 — eff_p25 / eff_p75 blend incompatible statistics (MEDIUM)

**Location:** `grade.fx` lines 258–259

```hlsl
float eff_p25 = lerp(perc.r, zstats.b, 0.4);   // global p25, zone zmin
float eff_p75 = lerp(perc.b, zstats.a, 0.4);   // global p75, zone zmax
```

**What it does:** FilmCurve knee and toe positions are derived from eff_p25 and eff_p75.
These blend global percentiles (p25, p75 from PercTex) with the minimum and maximum
zone medians (zmin, zmax from ChromaHistoryTex col 6).

**The mismatch:** `perc.r` is the p25 of the full downsampled frame histogram — the
luminance at which 25% of all pixels are darker. `zstats.b` is the minimum *zone median*
— the darkest zone's median luminance. These answer different questions:
- Global p25 represents per-pixel tonal distribution
- Zone zmin represents the darkest spatial region's central tendency

In a scene with a large dark foreground (zmin ≈ 0.05) but bright sky dominating the
histogram (global p25 ≈ 0.30), eff_p25 = lerp(0.30, 0.05, 0.4) = 0.20. The resulting
fc_knee_toe shifts to ~0.25, changing the FilmCurve toe shape based on where the
darkest zone is, not where most dark pixels are.

**Consequence:** In scenes where large dark zones exist but are not the dominant content,
FilmCurve toe moves without corresponding histogram justification. The curve floats in a
way that's spatially-motivated but tonally inconsistent frame to frame.

---

## Issue 5 — CAT16 illuminant estimated from frame-average spatial blur (MEDIUM)

**Location:** `grade.fx` lines 238–246

```hlsl
float3 illum_rgb  = lf_mip0.rgb;   // CreativeLowFreqTex mip0 — 1/8-res box blur
float3 illum_norm = illum_rgb / max(Luma(illum_rgb), 0.001);
...
col.rgb = lerp(col.rgb, saturate(cat16), 0.60);
```

**The problem:** The illuminant estimate is a single frame-average 1/8-res blur of the
scene. Two failure modes:

1. **Isolated bright source in a dark room.** A white lamp covering 2% of the frame
   surrounded by dark walls: lf_mip0 ≈ 0.9 * dark + 0.1 * lamp = mostly dark.
   illum_norm divides by a dark luma, amplifying the lamp's hue. The illuminant over-
   tilts toward the lamp color, driving the adaptation in the wrong direction.

2. **Mixed lighting.** A scene with warm (tungsten) and cool (daylight) regions mixed
   equally: lf_mip0 is near-neutral, illum_norm ≈ white. CAT16 does nothing, even
   though both regions individually have strong casts.

**The 60% blend** (line 246) is a partial safety valve against these cases, but it
also means correct illuminants are only 60% corrected — a deliberate strong colour cast
is suppressed to 60% of what CAT16 would give.

**Consequence:** CAT16 over-corrects in high-contrast scenes (bright-in-dark) and
under-corrects in mixed-lighting scenes. The 60% blend makes it safe but perpetually
partial.

---

## Issue 6 — Triple highlight compression stacking (HIGH)

**Location:** `grade.fx` lines 289–325

Three compression operations apply to highlights in sequence:

1. **FilmCurve shoulder** (line 289): quadratic rolloff above fc_knee (~0.80–0.90).
   Compresses highlights by pulling them down a curve.

2. **PrintStock shoulder** (lines 296–299): `shoulder = 1.0 - (1.0 - ps)^2 * 1.8`.
   Applied to already-compressed FilmCurve output. At ps=0.90 post-FilmCurve,
   PrintStock shoulder pushes it further: `1.0 - 0.1^2 * 1.8 = 0.982`. Subtle, but
   at ps=0.95: `1.0 - 0.05^2 * 1.8 = 0.9955`. The shoulder actually flattens.
   Combined with the lerp blend at PRINT_STOCK=0.50, highlights are compressed by
   both curves.

3. **Gamut density darkening** (lines 518–525): L darkened when chroma was lifted
   (`delta_C = max(final_C - C, 0.0)`), via `density_L = lab.x / hk_boost`. This
   darkens highlights that were already chroma-lifted.

**The cascade:** A highlight at linear 0.92 (above FilmCurve knee) passes through:
FilmCurve → pushed down → PrintStock → pushed down slightly more → gamut density →
may darken if chroma was present. None of these stages knows the others exist.

**Consequence:** Specular highlights, sky gradients, and near-white regions with any
saturation lose fine separation. Blown highlights and near-blown highlights compress
into the same narrow range. Not obviously visible as clipping, but reduces dynamic range
headroom above midtones.

---

## Issue 7 — Quadruple black lift stacking (HIGH)

**Location:** `grade.fx` lines 248–409

Four black-lifting operations fire in sequence:

1. **FILM_FLOOR pedestal** (line 250): `col.rgb * (FILM_CEILING - cfilm_floor) + cfilm_floor`.
   Raises true black from 0 to ~0.01 (tinted by illuminant via lms_illum_norm).

2. **PrintStock toe** (lines 296–297): `ps = lin * (1.0 - 0.025) + 0.025` — explicit
   0.025 black lift before the toe curve. Then `toe = ps^2 * 3.2` which still curves
   up from 0.025.

3. **Shadow lift / Retinex** (lines 382–386): adaptive shadow boost driven by
   `(0.149169 / (illum_s0^2 + 0.003))` — can add significant lift in dark areas with
   bright neighbours.

4. **Ambient shadow tint** (lines 400–408): injects illum_s2 hue into achromatic
   shadows, modifying ab while leaving L unchanged, but the Oklab→RGB conversion
   implicitly raises R/G/B for achromatic shadows that gain chroma.

**Combined lift at true black (0.0 input):** Rough estimation at FILM_FLOOR=0.01,
PRINT_STOCK=0.50, SHADOW_LIFT=1.30, typical MIST_STRENGTH=2.0 scene:
- After FILM_FLOOR: ~0.01
- After PrintStock: ~0.027 (toe curve + 0.025 base)
- After shadow lift: depends on scene, but lift_w = new_luma * smoothstep(0.30, 0, new_luma)
  peaks at low luma — can add 0.02–0.06 in dark scenes
- After ambient tint: color shift only, no luma change

True black reaches ~0.04–0.08 in linear light after all four. In sRGB display code that
is ~20–30% code value. Shadow detail and perceived black level are significantly lifted.

**Note:** This may be intentional — film blacks are lifted. The concern is the
*stacking* without inter-stage awareness, not that any single stage is wrong.

---

## Issue 8 — Chroma ceiling applied post-vibrance (MEDIUM)

**Location:** `grade.fx` lines 473–481

```hlsl
float vib_mask = saturate(1.0 - C / 0.22);
float vib_C    = C + max(lifted_C - C, 0.0) * vib_mask;   // vibrance-gated lift
float C_ceil   = hw_o0 * 0.28 + hw_o1 * 0.24 + ...;       // per-band ceiling
float final_C  = min(vib_C, max(C_ceil, C));               // ceiling applied post-vib
```

**The issue:** Vibrance attenuates the lift delta for already-saturated pixels (`vib_mask`
→ 0 when C > 0.22). The ceiling then clamps `vib_C`. The ceiling is a *maximum output*
guarantee, but it's applied to the vibrance-modified value. A pixel that was at C=0.20
before lift, lifted to C=0.26, vibrance-masked down to C=0.23 (mask≈0.09), can still
hit a ceiling at 0.21 — and will be clamped back below where vibrance left it.

`max(C_ceil, C)` prevents clamping below the *original* C, so the ceiling never
reduces below input — that's correct. But the ceiling interacts with the vibrance-
modified intermediate, not the input. The effective ceiling is path-dependent.

**Consequence:** Mid-saturation pixels (~0.18–0.22) near the vibrance threshold have
an effective ceiling that floats depending on how much lift was applied and how much
vibrance masked it. Not a hard-clamp artifact, but the ceiling's intended "never exceed
this hue's maximum" guarantee is weaker than it appears.

---

## Issue 9 — HWY_SLOPE decoded as 1.0 on uninitialised frames (LOW)

**Location:** `analysis_frame.fx` line 298–299, `inverse_grade.fx` line 76–77,
`highway.fxh` line 24

```hlsl
// encode: (slope - 1.0) / 1.5    slope clamped [1.15, 1.8] → encoded [0.10, 0.53]
// decode: slope_enc * 1.5 + 1.0
```

**The issue:** The highway is an 8-bit UNORM texture. Before the first frame writes
x=197, the value is 0.0. Decoded: `0.0 * 1.5 + 1.0 = 1.0`. The valid encoded range is
[0.10, 0.53]; an encoded value of 0.0 is below the minimum valid slope.

`slope = 1.0` means the inverse grade multiplier is 1.0 — no expansion. The first frame
sees no inverse grade, which is a safe fallback (identity), but it's a one-frame pulse
away from the calibrated minimum (1.15). On a scene cut that clears the analysis state,
this could briefly produce no inverse grade before the Kalman filter converges.

**Consequence:** One-frame partial inverse grade miss on startup and potentially on
very-clean cuts. Minor but diagnosable if a flash is seen on the first frame.

---

## Summary table

| # | Issue | Location | Severity | Type |
|---|-------|----------|----------|------|
| 1 | Arithmetic mean chroma pivot — outlier bias | analysis_frame.fx ~420 | HIGH | Statistic |
| 2 | Zone log key = geometric mean — dark bias | corrective.fx ~326 | MEDIUM | Statistic |
| 3 | zone_std from zone medians, not pixels | corrective.fx ~327 | MEDIUM | Statistic |
| 4 | eff_p25/p75 blends global percentile with zone min/max | grade.fx 258–259 | MEDIUM | Statistic |
| 5 | CAT16 illuminant from frame-average blur | grade.fx 238–246 | MEDIUM | Algorithm |
| 6 | Triple highlight compression stacking | grade.fx 289–325 | HIGH | Stacking |
| 7 | Quadruple black lift stacking | grade.fx 248–409 | HIGH | Stacking |
| 8 | Chroma ceiling applied post-vibrance | grade.fx 473–481 | MEDIUM | Interaction |
| 9 | HWY_SLOPE decoded 1.0 on init | analysis_frame ~299 | LOW | Edge case |
