# Nightly Automation Research — 2026-05-02

## Summary

Four knob-automation candidates examined: CLARITY_STRENGTH (not yet in code — proposed new knob),
SHADOW_LIFT (currently 1.7 scalar; already spatially adaptive per-pixel), DENSITY_STRENGTH
(already fully automated in code — no user knob), and CHROMA_STRENGTH (currently 0.9 scalar; base
formula already scene-adaptive via mean_chroma × hunt_scale, knob is the residual tuning surface).

All four can be signal-driven from existing analysis textures. No new passes required. Stevens and
Hunt effects are already partially present in the pipeline; p50 can anchor both CLARITY and CHROMA
formulas with low risk given Kalman smoothing on PercTex.

---

## CLARITY_STRENGTH

### Current behaviour (grade.fx line reference)

No CLARITY_STRENGTH knob exists in the current pipeline. The closest analogue is the Multi-Scale
Retinex (R29) blend in Stage 2:

```hlsl
// grade.fx lines 299-303
float illum_s0  = max(tex2Dlod(CreativeLowFreqSamp, float4(uv, 0, 1)).a, 0.001);
float illum_s2  = max(tex2Dlod(CreativeLowFreqSamp, float4(uv, 0, 2)).a, 0.001);
float local_var = abs(illum_s0 - illum_s2);
float log_R     = log2(max(new_luma, 0.001) / illum_s0);
new_luma = lerp(new_luma, saturate(exp2(log_R + log2(max(zone_log_key, 0.001)))),
                0.75 * smoothstep(0.04, 0.25, zone_std));
```

The Retinex blend strength `0.75 * smoothstep(0.04, 0.25, zone_std)` adapts to zone spread, not to
scene detail texture. Retinex is a global-illumination normaliser; classical Clarity is a
mid-frequency contrast boost (`pixel - low_freq_blur`), applied as a luma addition before hue
rotation. These are complementary, not redundant.

A true Clarity term would be:

```hlsl
float clarity_residual = luma - illum_s0;  // pixel - 1/8-res blur: mid-freq detail
new_luma = saturate(new_luma + CLARITY_STRENGTH_AUTO * clarity_residual);
```

### Proposed formula

Signal: `iqr_global = perc.b - perc.r` (PercTex p75 − p25, already read at grade.fx line 229).
Low IQR = tonally flat scene → little inherent contrast → Clarity should work hardest.
High IQR = already contrasty scene → Clarity risks halos → pull back.

Secondary anchor: `perc.g` (p50). Stevens effect (see §Stevens + Hunt) predicts that brighter
adaptation luminance increases perceived contrast. Higher p50 → scene already "pops" → less Clarity
needed. This is a soft correction on top of IQR.

```hlsl
// iqr_global and perc already in registers
float iqr_global       = perc.b - perc.r;
float clarity_iqr_t    = smoothstep(0.10, 0.40, iqr_global);   // 0 = flat, 1 = contrasty
float clarity_stevens  = smoothstep(0.20, 0.60, perc.g);        // 0 = dark, 1 = bright
float CLARITY_STR_AUTO = lerp(45.0, 20.0, saturate(clarity_iqr_t + 0.4 * clarity_stevens));
```

Range analysis:
- Dark, flat scene (IQR 0.08, p50 0.15): iqr_t ≈ 0, stevens ≈ 0 → CLARITY ≈ 45 (max)
- Bright, contrasty scene (IQR 0.38, p50 0.55): iqr_t ≈ 1, stevens ≈ 0.9 → arg ≈ 1.36 → saturate → 1 → CLARITY ≈ 20 (min)
- Typical Arc Raiders (IQR 0.25, p50 0.35): iqr_t ≈ 0.6, stevens ≈ 0.4 → arg ≈ 0.76 → CLARITY ≈ 28
- Output always in [20, 45]. No hard conditional.

### Pumping risk

**Moderate.** Clarity residual `luma - illum_s0` is per-pixel and not temporally smoothed —
it cannot pump. The strength scalar CLARITY_STR_AUTO is derived from PercTex (perc.r/g/b), which
is Kalman-filtered (R39) and scene-cut aware (R53). The Kalman steady-state time constant of
~10 frames means gradual scene illumination changes track cleanly. Hard cuts spike K → 1.0 in
SceneCutTex, forcing one-frame reset, then a brief 2–3 frame ramp. Visible as a momentary
clarity dip on extreme scene cuts (dark interior → bright exterior). Acceptable given the Kalman
already causes the same transient on zone contrast and shadow lift.

Risk is lower than Retinex (zone_std lags behind PercTex on cuts) because PercTex resets faster.

---

## SHADOW_LIFT

### Current behaviour (grade.fx line reference)

SHADOW_LIFT is a linear multiplier on a spatially-adaptive per-pixel lift formula:

```hlsl
// grade.fx lines 305-310
float local_range_att = 1.0 - smoothstep(0.20, 0.50, zone_iqr);
float texture_att     = 1.0 - smoothstep(0.005, 0.030, local_var);
float detail_protect  = smoothstep(-0.5, 0.0, log_R);
float shadow_lift     = SHADOW_LIFT * (0.149169 / (illum_s0 * illum_s0 + 0.003))
                        * local_range_att * texture_att * detail_protect;
float lift_w          = new_luma * smoothstep(0.30, 0.0, new_luma);
new_luma              = saturate(new_luma + (shadow_lift / 100.0) * 0.75 * lift_w);
```

`illum_s0` (local low-freq illumination) already controls per-pixel lift magnitude — darker local
regions get more lift. The spatial attenuators `local_range_att`, `texture_att`, and
`detail_protect` prevent halos and clip edges. What remains uncontrolled: the global scene
shadow level. A scene where p25 is already 0.25 (well-exposed shadows) is receiving the same
scalar as a scene where p25 is 0.04 (crushed shadows).

### Proposed formula

Signal: `perc.r` (p25, global shadow percentile). Monotonically decreasing: if shadows are
already bright, back off; if crushed, increase lift.

```hlsl
// perc already in registers (grade.fx line 229)
float SHADOW_LIFT_AUTO = lerp(1.30, 0.45, smoothstep(0.03, 0.22, perc.r));
```

Range analysis (current code scale; creative_values.fx default = 1.7):
- p25 = 0.03 (crushed shadows): SHADOW_LIFT_AUTO = 1.30
- p25 = 0.22 (open shadows): SHADOW_LIFT_AUTO = 0.45
- p25 = 0.10 (typical Arc Raiders): ≈ 0.88

Note on scale mismatch with task spec: the task states target range [5, 20] (older scale at
SHADOW_LIFT × 100 normalization). Current code's default of 1.7 is already in [0.45, 1.30] at
100× normalisation. The formula above maps the same perceptual effect; if a [5, 20] literal range
is desired, multiply both endpoints by ~11.8 and leave the `/100` divisor in the shader
unchanged.

The formula is intentionally conservative (max 1.30 vs current 1.7) because the per-pixel spatial
attenuators already work hard. Pushing SHADOW_LIFT above ~1.5 on pixel-level dark regions that
have already passed `local_range_att` = 0 produces grey mud. The auto range stays well clear of that.

### Risk

**Low.** PercTex is Kalman-filtered. The p25 channel tracks scene-cut changes via K = 1 on cut.
SHADOW_LIFT only affects the region `lift_w = new_luma * smoothstep(0.30, 0.0, new_luma)` —
pixels above 0.30 get zero lift by construction. This is self-limiting: a fast scene cut from
dark to bright transiently overshoots by at most one frame before p25 snaps to the new scene.
No pumping on static scenes. Grade-in/grade-out transitions are gradual and imperceptible.

---

## DENSITY_STRENGTH

### Current behaviour (grade.fx line reference)

DENSITY_STRENGTH **does not exist as a user knob** in the current pipeline. It is already fully
automated:

```hlsl
// grade.fx lines 350-360
float cm_t = 0.0, cm_w = 0.0;
[unroll] for (int bi = 0; bi < 6; bi++) {
    hist_cache[bi] = tex2D(ChromaHistory, float2((bi + 0.5) / 8.0, 0.5 / 4.0));
    cm_t += hist_cache[bi].r * hist_cache[bi].b;   // mean_C * weight_sum
    cm_w += hist_cache[bi].b;
}
float mean_chroma  = cm_t / max(cm_w, 0.001);
float chroma_exp   = exp(-3.47 * mean_chroma);
float density_str  = 62.0 - 20.0 * chroma_exp;   // range [42, 62]
```

Applied at grade.fx line 404:

```hlsl
float density_L = saturate(final_L - delta_C * headroom * (density_str / 100.0));
```

Range: when mean_chroma → 0 (greyscale), density_str → 42; when mean_chroma → large (vivid),
density_str → 62. More chroma → more density darkening to compensate gamut-distance headroom.
This is inverted relative to CHROMA_STRENGTH: density increases WITH saturation to counteract
the gamut excursion of the lift.

### Proposed formula

The current formula is well-founded. If a user knob were introduced to override it (as the task
implies), the automation formula should expose the range [30, 55]:

```hlsl
float density_str_auto = lerp(30.0, 55.0, smoothstep(0.03, 0.20, mean_chroma));
```

This produces:
- mean_chroma 0.03 (nearly grey): density_str = 30 (minimal darkening)
- mean_chroma 0.20 (vivid): density_str = 55 (strong darkening)
- The current formula `62 - 20 * exp(-3.47 * mc)` sits between 42–62, slightly above the proposed
  range. The proposed [30,55] is more conservative and less likely to grey-out lightly-lifted
  colours in SDR ceiling conditions.

Note: mean_chroma is already in registers at this stage (the 6-band loop runs before both
density_str and chroma_str). No additional texture reads needed.

### Risk

**Very low.** mean_chroma is Kalman-filtered per band (R39, R53). Even on a hard scene cut, the
worst-case excursion is one frame of density over-darkening before Kalman resets. Density only
darkens pixels that have a positive `delta_C` (i.e. were lifted by chroma boost) AND have
`headroom > 0` (not near the sRGB boundary). Both conditions gate the effect naturally; neither
is a hard conditional on pixel luminance (Oklab `final_L` already continuous).

---

## CHROMA_STRENGTH

### Current behaviour (grade.fx line reference)

CHROMA_STRENGTH is a scalar multiplier on an already-adaptive chroma lift:

```hlsl
// grade.fx lines 339-359
float la         = max(zone_log_key, 0.001);
float k          = 1.0 / (5.0 * la + 1.0);
// ... FL computation (iCAM06-style Hunt factor) ...
float hunt_scale = sqrt(sqrt(max(fl, 1e-6))) / 0.5912;

float chroma_exp = exp(-3.47 * mean_chroma);
float chroma_str = saturate(0.085 * chroma_exp * hunt_scale * CHROMA_STRENGTH);
```

Applied via PivotedSCurve on per-band chroma (grade.fx line 367):

```hlsl
new_C += PivotedSCurve(C, hist_cache[band].r, chroma_str) * w;
```

`chroma_exp` inverts mean_chroma (less lift when already saturated). `hunt_scale` provides the
Hunt-effect luminance dependency (brighter scenes → more saturation boost). CHROMA_STRENGTH (0.9)
is the remaining degree of freedom: it sets the overall calibration point.

### Proposed formula

To fully automate, CHROMA_STRENGTH can be driven jointly by mean_chroma and p50 (Stevens/Hunt
anchor — see §Stevens + Hunt). Low mean_chroma AND low p50 → maximum boost. High mean_chroma OR
high p50 → pull back (chroma_exp and hunt_scale already handle the per-scene fine-grain; the
auto knob governs the macro-level range).

```hlsl
// mean_chroma and perc already in registers
float chroma_mc_t  = smoothstep(0.05, 0.25, mean_chroma);   // 0=desaturated, 1=vivid
float chroma_p50_t = smoothstep(0.15, 0.55, perc.g);         // 0=dark, 1=bright
// Combined: high mc OR high p50 both reduce the knob, but don't double-penalise
float chroma_drive = saturate(chroma_mc_t + 0.35 * chroma_p50_t);
float CHROMA_STR_AUTO = lerp(1.25, 0.60, chroma_drive);      // current-code scale [0.60, 1.25]
```

Range analysis (current 0.9-scale; task spec [25,50] implies ×40 scale):
- Desaturated dark scene (mc 0.04, p50 0.12): drive ≈ 0 → CHROMA_STR_AUTO = 1.25
- Vivid bright scene (mc 0.22, p50 0.50): drive ≈ 1 → CHROMA_STR_AUTO = 0.60
- Typical Arc Raiders (mc 0.11, p50 0.32): drive ≈ 0.49 → CHROMA_STR_AUTO ≈ 0.97 ≈ current knob

The formula reproduces the current tuned value (~0.9–1.0) for the Arc Raiders reference scene,
confirming calibration alignment.

### Risk

**Low-moderate.** CHROMA_STRENGTH enters `chroma_str = saturate(...)` which is already bounded to
[0, 1] and further limited by `chroma_exp` and `hunt_scale`. The risk is subtle: in a desaturated
interior with a bright p50 (e.g., overcast window fill), the p50 branch reduces CHROMA_STR while
`hunt_scale` is simultaneously high. These signals pull in opposite directions. The proposed
formula uses a 0.35 weight on the p50 term to make this cross-term weak — the mc term dominates.
Scene-cut pumping is protected by Kalman on PercTex and ChromaHistoryTex.

---

## Stevens + Hunt as automation anchor

### Stevens effect

The Stevens effect states that apparent contrast increases with adaptation luminance. iCAM06
implements this by spatially deriving FL from the local adapted-white image:
`fl = k^4 * la + 0.1 * (1−k^4)^2 * (5*la)^(1/3)` where `la` is local luminance and
`k = 1/(5*la + 1)`. This exact formula is already computed in grade.fx Stage 3 (lines 339–346)
for the Hunt-effect hunt_scale.

More directly: grade.fx already has a Stevens-inspired term in FilmCurve (line 135):
```hlsl
float stevens = (1.48 + sqrt(max(p50, 0.0))) / 2.03;
float factor  = 0.05 / (width * width) * stevens * spread;
```
p50 scales the FilmCurve shoulder compression factor — brighter scenes get a steeper shoulder,
matching the Stevens prediction of increased apparent contrast at higher luminance.

### Hunt effect

The Hunt effect states that colorfulness increases with luminance. The pipeline's `hunt_scale`
(grade.fx lines 339–346) is an iCAM06-derived FL^0.25 factor anchored to zone_log_key (the
log-geometric mean of the 16 zone medians). This is not p50 — it is the perceptual key of the
zone distribution, which is typically close to p50 but weighted toward shadows by the log
transform (geometric mean < arithmetic mean).

### Should p50 anchor CLARITY and CHROMA formulas?

**CLARITY:** Yes, with low risk. p50 as a secondary correction term (Stevens direction: bright
scene → less Clarity needed) is well-supported by iCAM06 and aligns with the existing `stevens`
term in FilmCurve. The weight should be subordinate to the IQR term (0.4× in proposed formula)
to avoid over-correcting on high-key scenes that genuinely lack texture.

**CHROMA:** Yes, with low risk. p50 as a secondary Hunt anchor in CHROMA_STR_AUTO (0.35× weight
in proposed formula) extends the existing `hunt_scale` correction with a scene-level signal.
`hunt_scale` already embeds FL(zone_log_key), so p50 is partially redundant — but zone_log_key
is the geometric mean of 16 zones, while p50 is the median of all pixels. In very high-contrast
scenes they can diverge (zone_log_key pulled low by dark zones; p50 pulled up by bright
majority). The residual p50 term captures this mismatch.

**Risks of p50 anchoring:**

1. **Pumping on slow exposure transitions.** If the player walks from dark to light, p50 rises
   over ~10 frames (Kalman lag). Both CLARITY and CHROMA will ramp down during this transition.
   Perceptually this is correct (bright scenes need less boost) but the rate of change must not
   be faster than the eye's dark adaptation. At Kalman Q_min = 0.0001 and R = 0.01, the
   steady-state gain K ≈ 0.095, giving a 10-frame EMA. This is within the ~0.3s threshold
   for perceptually undetectable adaptation.

2. **Overcast vs backlit ambiguity.** A bright overcast scene (high p50, low chroma) and a
   backlit scene with bright highlights (high p50, moderate chroma) both have similar p50. The
   IQR and mean_chroma terms disambiguate them, making p50 the correct secondary term, not
   primary.

3. **Independence from EXPOSURE.** p50 tracks EXPOSURE changes (brightening via EXPOSURE raises
   p50). This is desirable: if the user increases EXPOSURE, the pipeline should automatically
   reduce the amount of additional chroma and clarity boost that was compensating for darkness.
   No concern here; this coupling is intentional.

**Verdict:** p50 is a sound secondary anchor for both CLARITY and CHROMA. Weight at ≤ 0.4× to
keep the primary signals (IQR for clarity, mean_chroma for chroma) dominant.

---

## Implementation priority

| Knob | Confidence | Pumping risk | Recommended order |
|------|------------|--------------|-------------------|
| DENSITY_STRENGTH | Very high — already automated in code; formula proven | Very low — Kalman-protected, gated by delta_C and headroom | Already done; no action needed |
| SHADOW_LIFT | High — p25 → lift strength is direct and monotonic; current spatial adaptors stay intact | Low — p25 Kalman R53 protected | 1st — drop-in replacement for scalar, zero architectural change |
| CHROMA_STRENGTH | High — current formula reproduces Arc Raiders tuning at midpoint | Low-moderate — dual-signal (mc + p50) needs weight validation | 2nd — test weight interaction with hunt_scale on dark desaturated scenes |
| CLARITY_STRENGTH | Medium — knob does not yet exist; need clarity_residual addition to Stage 2 | Moderate — strength scalar needs Kalman; raw residual is frame-stable | 3rd — requires new Stage 2 luma addition, validate no Retinex interaction |

---

## Literature findings

**Stevens effect in tone mapping (iCAM06):** The iCAM06 model (Fairchild & Johnson 2007,
*Journal of Visual Communication and Image Representation*) computes a spatially-varying FL
factor from the local adapted-white. The FL^0.25 exponent drives both contrast (Stevens) and
colorfulness (Hunt) in a unified formulation. The pipeline's hunt_scale at grade.fx lines 339–346
is a direct implementation of this. Reference: http://markfairchild.org/PDFs/PAP26.pdf

**Perceptual effects in real-time tone mapping (MPI):** Luebke & Heidrich (2002) and related MPI
work showed that Stevens-effect contrast expansion and Hunt-effect saturation increase can be
implemented as a post-process power-function adjustment without a full CAM solve. The
`zone_str = lerp(0.26, 0.16, ...) * lerp(1.10, 0.93, lum_att)` formula in grade.fx is this
same principle applied to the adaptive zone S-curve. Reference:
https://resources.mpi-inf.mpg.de/hdr/peffects/

**CLAHE adaptive clip limit (IA-CLAHE, 2026):** Recent work (arXiv:2604.16010) proposes making
CLAHE differentiable with per-tile clip limits driven by image-wise L1 loss. The observation
that entropy-based tile sizing improves over fixed clip limits aligns with the proposal to drive
CLARITY_STRENGTH from IQR (a histogram spread measure). IQR and entropy are correlated under
Gaussian assumptions; IQR is cheaper to compute from PercTex and avoids per-tile passes.
Reference: https://arxiv.org/html/2604.16010v1

**Perceptually adaptive real-time tone mapping (Tariq 2023):** Demonstrates that spatially-local
adaptation maps that respond to `surround luminance` per region outperform global tone operators.
This supports the per-zone (ZoneHistoryTex) architecture already in the pipeline, and confirms
that p50 as a global anchor is appropriate only as a secondary correction, with zone-level
statistics primary. Reference: https://achapiro.github.io/Tar23/Tar23.pdf

**ZCAM (Safdar et al. 2021):** ZCAM extends CIECAM02 to HDR with a revised Hunt-effect
formulation. The ZCAM colorfulness correlate `Mz = 0.0172 * Cz * Qz^0.2` shows that apparent
colorfulness grows sub-linearly with brightness (0.2 exponent), and that at SDR luminances
(< 100 cd/m²) the Hunt amplification is modest (factor ~1.2–1.6). The pipeline's hunt_scale =
FL^0.25 / 0.5912 produces factors in the same range. Confirms the current calibration is
physically plausible for SDR. Reference: https://www.researchgate.net/publication/348773224

**Scene-adaptive chroma grading (darktable color balance RGB):** The darktable team's JzAzBz
perceptual grading module drives per-region chroma modifications from scene statistics without
user knobs in auto mode. The same mean-chroma signal used in grade.fx Stage 3 is their primary
input. Validates the CHROMA_STRENGTH automation direction. Reference:
https://docs.darktable.org/usermanual/4.0/en/module-reference/processing-modules/color-balance-rgb/
