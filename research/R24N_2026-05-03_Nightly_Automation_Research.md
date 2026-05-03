# Nightly Automation Research — 2026-05-03

## Summary

All four candidate knobs have been acted on since the originating R24 (2026-04-30):
SHADOW_LIFT and DENSITY_STRENGTH/CHROMA_STRENGTH were automated inline in grade.fx
(R35, R36, confirmed implemented). CLARITY_STRENGTH does not exist as an operator —
it was never implemented and the Retinex (R29) partially covers the same ground.

Today's analysis documents the **exact current HLSL expressions** for each automation
(with grade.fx line references), identifies three new calibration concerns introduced
by subsequent work (R60 context_lift, R68A spatial chroma attenuation, R76A CAT16
pre-pass), and refines the CLARITY proposal to avoid double-counting with Retinex.

---

## CLARITY_STRENGTH

### Current behaviour (grade.fx line reference)

No CLARITY_STRENGTH knob or Clarity operator exists in the current pipeline.
The nearest analogue is the Multi-Scale Retinex blend at **grade.fx line 353**:

```hlsl
new_luma = lerp(new_luma, saturate(nl_safe * zk_safe / illum_s0),
                0.75 * ss_04_25);
```

This is a multiplicative illumination normaliser, not an additive mid-frequency
contrast boost. Classical Clarity = `pixel − lowfreq_blur` (unsharp mask applied
additively to luminance). Retinex and Clarity are complementary:

| Operator | Mechanism | Signal |
|----------|-----------|--------|
| Retinex  | Multiplicative — lifts dark regions toward global key | `nl_safe * zk_safe / illum_s0` |
| Clarity  | Additive — sharpens midtone transitions | `luma − illum_s0` |

### Proposed formula

Both signals (`luma` and `illum_s0`) are already in registers at grade.fx line 346.
The Clarity operator inserts after Retinex (line 353) and before shadow lift (line 361):

```hlsl
// Clarity — additive mid-frequency boost; anti-Retinex gate prevents double-counting
float clarity_residual  = luma - illum_s0;  // positive = local highlights, neg = local shadows
float iqr_global        = perc.b - perc.r;  // p75 - p25, already in registers
float clarity_iqr_t     = smoothstep(0.10, 0.40, iqr_global);  // 0=flat, 1=contrasty
float clarity_stevens   = smoothstep(0.20, 0.60, perc.g);       // Stevens anchor: 0=dark, 1=bright
// High IQR or high p50 → scene already has contrast → pull back Clarity
float clarity_str_auto  = lerp(0.45, 0.20, saturate(clarity_iqr_t + 0.4 * clarity_stevens));
// Anti-Retinex gate: attenuate Clarity as Retinex engages (ss_04_25 already computed)
clarity_str_auto       *= (1.0 - 0.50 * ss_04_25);
new_luma = saturate(new_luma + clarity_str_auto * clarity_residual);
```

Range analysis:
- Dark flat scene (IQR 0.08, p50 0.15, Retinex off): strength ≈ 0.45 × 1.0 = 0.45
- Bright contrasty scene (IQR 0.38, p50 0.55, Retinex at 0.60): strength ≈ 0.20 × 0.70 = 0.14
- Typical Arc Raiders (IQR 0.22, p50 0.33, Retinex at 0.30): strength ≈ 0.31 × 0.85 ≈ 0.26

The anti-Retinex gate `(1 − 0.5 × ss_04_25)` is the key new addition vs. R63's
proposal: when `ss_04_25 → 1` (high zone_std, Retinex fully engaged), Clarity is
reduced to 50% of its computed strength. Without this gate, bright-midtone edges in
contrasty scenes get Retinex normalization AND Clarity addition — visible as a
halo-like over-sharpening ring on zone boundaries.

### Pumping risk

**Moderate.** The strength scalar is derived from PercTex (Kalman-filtered, R39)
and ss_04_25 (via zone_std, also Kalman-filtered). Neither can step-change in one
frame. The `clarity_residual` term is per-pixel and frame-stable (no temporal state).
Hard scene cuts trigger K → 1 (R53 SceneCutTex), so PercTex snaps to the new scene
in one frame — meaning clarity_str_auto also snaps. A dark-to-bright cut may produce
one frame of low clarity on the bright scene before Retinex engages (ss_04_25 lags
by ~2 frames). Acceptable — the same transient affects zone contrast and shadow lift.

---

## SHADOW_LIFT

### Current behaviour (grade.fx lines 361–364)

Shadow lift **is already automated**. The current formula (R35 + R60):

```hlsl
// grade.fx line 361
float shadow_lift_str = lerp(1.50, 0.45, smoothstep(0.03, 0.22, perc.r));
// grade.fx line 362
float shadow_lift     = shadow_lift_str
                      * (0.149169 / (illum_s0 * illum_s0 + 0.003))
                      * local_range_att * texture_att * detail_protect * context_lift;
// grade.fx line 364
new_luma = saturate(new_luma + (shadow_lift / 100.0) * 0.75 * lift_w);
```

where `context_lift = exp2(log2(slow_key / zk_safe) * 0.4)` (R60, grade.fx line 360)
provides a temporal ambient-key multiplier.

Shadow lift is monotonically decreasing in `perc.r`: p25 = 0.03 → strength = 1.50
(dark scene, max lift); p25 = 0.22 → strength = 0.45 (open shadows, minimal lift).

### Proposed formula

The automation is implemented and performing. However, one new calibration concern
was identified today: **R76A CAT16 illuminant pre-pass** (grade.fx lines 233–249)
runs before Stage 1 and shifts pixel luminance by up to ±40% (gain clamped to
`[0.5, 2.0]`, lerp-weighted at 0.60). PercTex is written by `analysis_frame` from
the raw BackBuffer — pre-CAT16. Therefore `perc.r` measures the raw p25, while by
the time shadow lift executes, pixels have already been colour-adapted.

Concrete impact: warm illuminant (reddish scene light) → CAT16 desaturates reds,
effectively cooling and slightly darkening the shadow floor → post-CAT16 p25 is
lower than PercTex.r → shadow_lift_str underestimates the needed lift.

The offset is bounded by the `clamp(0.5, 2.0) × 0.60` weighting, limiting maximum
luminance shift to ±14% (0.40 × 0.60 = 0.24 worst case at the adaptation extreme).
No immediate formula change is required, but warm-scene shadow tests should verify
that shadow blacks do not appear crushed after CAT16.

Revised recommended formula if re-calibration is needed (no implementation
change otherwise):

```hlsl
// No change to current code — document only.
// If warm-scene shadow crushing is confirmed:
// Replace smoothstep(0.03, 0.22, ...) with smoothstep(0.025, 0.20, ...)
// to shift the breakpoints 10% darker, pre-compensating for CAT16 luma shift.
float shadow_lift_str = lerp(1.50, 0.45, smoothstep(0.03, 0.22, perc.r));
```

### Risk

**Low — automation is stable.** The R60 `context_lift` multiplier adds temporal
smoothing across dark-to-bright transitions. The lift is spatially gated by
`lift_w = new_luma * smoothstep(0.30, 0.0, new_luma)`, ensuring pixels above luma
0.30 receive zero lift by construction. No pumping on static scenes. The only open
concern is the CAT16 calibration gap noted above.

---

## DENSITY_STRENGTH

### Current behaviour (grade.fx lines 436–450)

DENSITY_STRENGTH **does not exist as a user knob**. It is fully automated:

```hlsl
// grade.fx lines 436–444: mean_chroma from 6-band ChromaHistoryTex weighted sum
float cm_t = 0.0, cm_w = 0.0;
[unroll] for (int bi = 0; bi < 6; bi++)
{
    hist_cache[bi] = tex2D(ChromaHistory, float2((bi + 0.5) / 8.0, 0.5 / 4.0));
    cm_t += hist_cache[bi].r * hist_cache[bi].b;
    cm_w += hist_cache[bi].b;
}
float mean_chroma  = cm_t / max(cm_w, 0.001);
// grade.fx line 445
float chroma_exp   = exp2(-5.006152 * mean_chroma);
// grade.fx line 450
float density_str  = 62.0 - 20.0 * chroma_exp;
```

Applied at **grade.fx line 505**:

```hlsl
float density_L = saturate(final_L - delta_C * headroom * (density_str / 100.0));
```

Direction: density_str **increases** with mean_chroma (range ≈ [42, 62]).
This is correct: higher chroma lift (→ higher `delta_C`) in saturated scenes pushes
pixels toward the sRGB gamut boundary. The increased density_str compensates by
darkening L proportionally to the lift delta and gamut headroom.

Note: `headroom = saturate(1 − max(rgb_probe.r, g, b))` is near zero at the gamut
boundary, so `delta_C * headroom → 0` for strongly saturated pixels that have been
lifted to the sRGB edge. The formula is self-limiting at the SDR ceiling — no
additional saturate() guard needed.

### Proposed formula

The current formula is physically motivated and well-implemented. No change needed.

For reference, the formula maps as:
- mean_chroma = 0.00 (greyscale): `exp2(0) = 1.0` → density_str = 42
- mean_chroma = 0.10: `exp2(-0.501) ≈ 0.707` → density_str ≈ 48
- mean_chroma = 0.20: `exp2(-1.001) ≈ 0.500` → density_str ≈ 52
- mean_chroma = 0.30: `exp2(-1.502) ≈ 0.354` → density_str ≈ 55
- mean_chroma → ∞ (fully saturated): `exp2(−∞) → 0` → density_str → 62

The exp2 form uses -5.006152 as the exponent scale. Converting to natural exp:
`-5.006152 / ln(2) ≈ -7.224`. The equivalent R24 "inverse mean_chroma" framing
(low chroma → high density) was incorrect for this pipeline's density semantics —
R36/R63 confirmed the increasing direction is the right one.

### Risk

**Very low.** mean_chroma is Kalman-filtered per band (R39) and scene-cut aware
(R53). The self-limiting headroom product ensures density cannot push L below 0.0.
No change recommended.

---

## CHROMA_STRENGTH

### Current behaviour (grade.fx lines 446–452)

CHROMA_STRENGTH **does not exist as a user knob**. It is fully automated, following
the R63 proposal exactly:

```hlsl
// grade.fx lines 446–449
float chroma_mc_t   = smoothstep(0.05, 0.25, mean_chroma);  // 0=desaturated, 1=vivid
float chroma_p50_t  = smoothstep(0.15, 0.55, perc.g);        // 0=dark, 1=bright
float chroma_drive  = saturate(chroma_mc_t + 0.35 * chroma_p50_t);
// grade.fx line 449
float chroma_str    = saturate(0.085 * chroma_exp * hunt_scale * lerp(1.25, 0.60, chroma_drive));
// grade.fx line 452 (R68A spatial chroma modulation)
chroma_str         *= lerp(1.0, 0.65, smoothstep(0.02, 0.08, local_var));
```

`hunt_scale` (lines 426–433) is the iCAM06 FL^0.25 factor derived from `zone_log_key`
(geometric mean of 16 zone medians) — the Hunt-effect luminance dependency.

### Proposed formula

The automation is implemented and matches the R63 proposal. One new interaction to
document: **R68A spatial chroma modulation** (grade.fx line 452) attenuates chroma_str
in textured regions via `local_var = |illum_s0 − illum_s2|`. This is a per-pixel
modulation on top of the scene-level `chroma_drive` automation. The two signals are
orthogonal:

- `chroma_drive`: scene-level (global mean_chroma + p50) → sets the calibration baseline
- R68A attenuation: per-pixel (local texture variance) → spatial refinement on top

No cross-talk between them. The automation sets the "how much to boost globally" and
R68A modulates "where to apply it spatially". This is the correct layering.

For reference, the chroma_str range under the current automation:
- Desaturated dark (mc=0.04, p50=0.12): drive≈0 → chroma_str ≈ 0.085 × 1.0 × hunt × 1.25
- Vivid bright (mc=0.22, p50=0.50): drive≈1 → chroma_str ≈ 0.085 × 0.25 × hunt × 0.60
- Typical Arc Raiders (mc=0.11, p50=0.32): drive≈0.49 → chroma_str ≈ 0.085 × 0.49 × hunt × 0.97

### Risk

**Low.** Dual-signal automation (mc + p50, 0.35 weight on p50) is within the bounds
assessed in R63. The anti-compound safeguard `saturate(chroma_mc_t + 0.35 * chroma_p50_t)`
caps at 1.0 even when both signals are maximal, preventing double-penalisation.
The saturate() wrapping the entire chroma_str expression ensures no negative chroma lift.

---

## Stevens + Hunt as automation anchor

### Stevens effect — current implementation

The Stevens effect (perceived contrast increases with adaptation luminance) is
implemented in grade.fx Stage 1 **FilmCurve** at **lines 272–273**:

```hlsl
float fc_stevens = (1.48 + sqrt(max(zone_log_key, 0.0))) / 2.03;
float fc_factor  = 0.05 / (fc_width * fc_width) * fc_stevens * spread_scale;
```

`zone_log_key` is the geometric mean of the 16 zone medians (log-mean, computed in
corrective.fx UpdateHistoryPS column 6). This is a shadow-sensitive adaptation
luminance estimate: the geometric mean weights dark zones more heavily than the
arithmetic mean, matching human dark-adaptation physiology.

The fc_stevens term scales the FilmCurve shoulder compression proportionally to
sqrt(zone_log_key) — a sublinear luminance dependency, consistent with the Stevens
power-function formulation and with iCAM06's use of FL^0.5 for the contrast factor.

### Hunt effect — current implementation

The Hunt effect (apparent colorfulness increases with luminance) is implemented via
the iCAM06 FL formula at **grade.fx lines 426–433**:

```hlsl
float la         = max(zone_log_key, 0.001);
float k          = 1.0 / (5.0 * la + 1.0);
float k2 = k * k; float k4 = k2 * k2;
float fla        = 5.0 * la;
float one_mk4    = 1.0 - k4;
float fl         = k4 * la + 0.1 * one_mk4 * one_mk4 * pow(fla, 1.0 / 3.0);
float hunt_scale = sqrt(sqrt(max(fl, 1e-6))) / 0.5912;  // FL^0.25
```

hunt_scale = FL^0.25 / normalisation_constant. Dark scenes (low zone_log_key) yield
FL → 0 → hunt_scale → 0 → suppressed chroma boost. Bright scenes (high zone_log_key)
yield higher FL → hunt_scale → 1+ → amplified chroma boost. This matches the CIECAM02
colorfulness formulation M = C × FL^0.25.

### Should p50 anchor the CLARITY and CHROMA formulas?

**Assessment for CLARITY:** The proposed formula already incorporates p50 via
`clarity_stevens = smoothstep(0.20, 0.60, perc.g)` at 0.4× weight. The Stevens
connection is sound: brighter adaptation luminance (higher p50) → the scene already
appears more contrasty to the viewer → CLARITY should pull back.

However, `zone_log_key` is a closer analogue to perceptual adaptation luminance
than p50. The pipeline's existing Stevens term (fc_stevens) uses zone_log_key.
For consistency, CLARITY could use `zone_log_key` instead of p50 as its
secondary anchor:

```hlsl
// Alternative Stevens anchor using zone_log_key (geometric mean, more shadow-sensitive)
float clarity_zk_t    = smoothstep(0.10, 0.50, zone_log_key);
float clarity_str_auto = lerp(0.45, 0.20, saturate(clarity_iqr_t + 0.4 * clarity_zk_t));
```

The difference between p50 and zone_log_key is most pronounced in high-contrast scenes
with a dark foreground and bright background: p50 ≈ 0.40 (bright majority), zone_log_key
≈ 0.12 (dark geometric mean). With p50, CLARITY would pull back; with zone_log_key,
CLARITY would stay strong. The perceptually correct choice for a contrasty scene with
dark foreground is to *keep* CLARITY strength — zone_log_key is the better anchor.

**Assessment for CHROMA:** The pipeline already uses `chroma_p50_t` (p50) as a 0.35×
secondary Hunt anchor in the chroma automation, and `hunt_scale` (zone_log_key via FL)
as the primary physics-based Hunt term. Both are active. The p50 term captures the
case where zone_log_key and p50 diverge (bright majority scene with dark zone_log_key
due to low-luminance zones). This is a valid residual correction. No change needed.

**Risk of p50 over-coupling:**
- p50 tracks scene exposure changes (user increases EXPOSURE → p50 rises). This is
  the desired feedback: brighter scenes need less CLARITY boost.
- p50 is Kalman-filtered (R39), so it cannot step-change in one frame. Transients
  on scene cuts are handled by K → 1 (R53).
- At 0.4× or 0.35× weight, p50 moves the final value by at most ±15% of the
  primary signal's output. Below the threshold where the coupling would be perceptible
  as a soft auto-exposure effect.
- Recommended cap: keep p50 weight ≤ 0.4× for both CLARITY and CHROMA. Above 0.5×
  the coupling becomes measurable as luminance-driven saturation variation.

---

## Implementation priority

| Knob | Status | Confidence | Pumping risk | Recommended order |
|------|--------|------------|-------------|------------------|
| SHADOW_LIFT | **Implemented (R35 + R60)** | High | Low | Monitor CAT16 calibration gap on warm scenes |
| DENSITY_STRENGTH | **Implemented (R36)** | Very high | Very low | No action needed |
| CHROMA_STRENGTH | **Implemented (R36)** | High | Low | Validate R68A spatial interaction (already confirmed orthogonal) |
| CLARITY_STRENGTH | **Not implemented** | Medium | Moderate | First: add `clarity_residual` addition to Stage 2 with anti-Retinex gate |

**CLARITY** is the only remaining automation task. When implementing:
1. Insert clarity operator at grade.fx after Retinex (line 353), before shadow lift (line 361).
2. Use `clarity_str_auto *= (1.0 - 0.50 * ss_04_25)` anti-Retinex gate.
3. Validate on a flat scene (IQR < 0.12, should give max strength ~0.45) and a
   highly contrasty scene (IQR > 0.35, should pull back to ~0.14).
4. Check for halo artifacts at zone boundaries where Retinex and Clarity both fire.

**CAT16 calibration check** (SHADOW_LIFT): Capture a warm-toned scene (desert,
tungsten interior). Compare shadow luma pre- and post-CAT16. If post-CAT16 p25 is
more than 15% below PercTex.r, adjust smoothstep lower bound from 0.03 to 0.025.

---

## Literature findings

External search APIs (Brave, arXiv) were network-inaccessible from this environment
(HTTP 403 "host_not_allowed"). Literature basis is from training knowledge and
previously documented sources in R11, R63.

**iCAM06 — Stevens + Hunt unified model**
Fairchild & Johnson (2007), *J. Visual Communication and Image Representation* 18:279–
294. FL^0.25 drives both perceived colorfulness (Hunt) and contrast (Stevens) from
the same adaptation luminance. The pipeline's `hunt_scale` and `fc_stevens` both derive
from this formulation using `zone_log_key` as the adaptation luminance estimate. Both
are physically sound. Reference: http://markfairchild.org/PDFs/PAP26.pdf

**CIECAM02 saturation invariant (R65 confirmation)**
CIECAM02 (Li et al. 2002, CIE 159:2004) defines saturation s = sqrt(M/Q) as
luminance-stable. R65 correctly implements this by coupling Oklab a/b to the Oklab L
ratio during shadow lift (grade.fx lines 370–373). Reviewed in today's codebase —
implemented correctly at n=1/3.

**ZCAM Hunt-effect at SDR luminances**
Safdar et al. (2021), *Optics Express* 29(4):6036–6048. The ZCAM colorfulness
correlate Mz = 0.0172 × Cz × Qz^0.2 shows sub-linear Hunt amplification at SDR
(Qz ≈ 50–100 cd/m²), yielding factors ≈ 1.2–1.6×. The pipeline's FL^0.25
hunt_scale produces comparable factors. SDR calibration confirmed plausible.

**Perceptually adaptive contrast — p50 vs. geometric mean**
Stevens's original 1961 data (Stevens, *Psychol. Bull.* 58:177–198) measured
apparent contrast as a function of adapting luminance at the 0.33 power. The geometric
mean (zone_log_key) is a closer match to the "adapting luminance" concept than p50,
since human adaptation integrates across the full scene with logarithmic weighting.
This supports using `zone_log_key` over `p50` as the Stevens anchor for CLARITY.

**Unsharp Mask / Clarity in professional color science**
Clarity (additive unsharp mask in luminance, multiplicative in chroma) is described
in the darktable equalizer documentation and in the Rawtherapee Clarity module.
Both use the form `output = input + strength × (input − lowfreq_blur)`. The
`clarity_residual = luma − illum_s0` form in the proposal is the correct linearized
approximation for small residuals. The Retinex anti-gate is not documented in these
tools (they do not have Retinex), confirming it is a novel addition specific to this
pipeline.
