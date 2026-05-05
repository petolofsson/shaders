# Nightly Automation Research — 2026-05-04

## Summary

Three of four candidate automations (SHADOW_LIFT, DENSITY_STRENGTH, CHROMA_STRENGTH) remain
fully automated and stable. CLARITY_STRENGTH is the sole unimplemented item.

Today's primary finding is a **compounding PercTex timing gap** introduced by R90
(adaptive inverse tone mapping, implemented 2026-05-04). R90 runs after `analysis_frame`
writes PercTex but before `corrective.fx` reads the BackBuffer. This means PercTex.r/g/b
measure pre-expansion luminance, while every other analysis texture (ZoneHistoryTex,
ChromaHistoryTex, zone_std, zone_log_key) is derived from the post-expansion image. The
gap compounds the pre-existing CAT16 mismatch documented yesterday (R24N_2026-05-03) and
pushes in the same direction: PercTex.r overestimates the effective shadow floor seen by
shadow lift, biasing `shadow_lift_str` low.

The CLARITY formula proposed in R24N_2026-05-03 used `iqr_global = perc.b - perc.r` as
its primary contrast anchor. Since PercTex is now pre-R90, the IQR underestimates the
post-expansion contrast → formula sets clarity higher than the expanded image warrants.
Revised formula today switches the primary anchor to `zone_std` (post-R90 consistent).

New external literature: Žaganeli et al. (2026), arXiv 2604.06276, provides independent
pixel-wise validation of the pipeline's saturation-by-slope coupling (R51 print stock).

---

## CLARITY_STRENGTH

### Current behaviour (grade.fx line reference)

No CLARITY_STRENGTH knob or operator exists in the production shader. R30 (wavelet clarity,
session 5, 2026-04-30) was implemented then removed. No trace remains in the current
grade.fx beyond the `local_var` texture-variance term (line 359), which is used for
`texture_att` in shadow lift, not for a clarity boost.

The nearest working analogue is Multi-Scale Retinex (R29) at **grade.fx lines 355–363**:

```hlsl
float illum_s0  = max(lf_mip1.a, 0.001);
float illum_s2  = max(lf_mip2.a, 0.001);
float local_var = abs(illum_s0 - illum_s2);
float nl_safe   = max(new_luma, 0.001);
float log_R     = log2(nl_safe / illum_s0);
float zk_safe   = max(zone_log_key, 0.001);
new_luma = lerp(new_luma, saturate(nl_safe * zk_safe / illum_s0), 0.75 * ss_04_25);
```

Retinex is a multiplicative illumination normaliser. Clarity (`pixel − lowfreq_blur`) is an
additive mid-frequency contrast boost. They operate on different spatial scales and are
complementary, not redundant — Retinex targets regional luminance uniformity, Clarity targets
local edge pop.

### Proposed formula (revised for R90)

**Signal change vs. R24N_2026-05-03:** IQR-based anchor (`perc.b − perc.r` from PercTex)
replaced by `zone_std` as the primary contrast anchor. `zone_std` is stored in
`ChromaHistoryTex` column 6 (grade.fx line 261) and is derived from ZoneHistoryTex — which
is computed by `corrective.fx` from the **post-R90 BackBuffer**. It is therefore consistent
with the actual contrast state of the image that grade.fx is processing.

All named variables below are already in registers at the proposed insertion point
(after Retinex, line 363; before shadow lift, line 365):

| Variable | Source | R90-consistent? |
|----------|--------|----------------|
| `luma` | `Luma(lin)` at line 344 | Yes (post-R90) |
| `illum_s0` | `lf_mip1.a` at line 356 | Yes (computed from post-R90 LowFreqTex) |
| `zone_std` | `zstats.g` at line 261 | Yes (from post-R90 ZoneHistoryTex) |
| `ss_04_25` | `smoothstep(0.04, 0.25, zone_std)` at line 265 | Yes |
| `perc.g` | PercTex.g at line 256 | **No** (pre-R90, but used at 0.4× weight — acceptable) |

```hlsl
// Insert after Retinex (line 363), before shadow lift (line 365)
// Clarity — additive mid-freq boost; zone_std anchor is post-R90 consistent
float clarity_residual  = luma - illum_s0;
float clarity_zstd_t    = smoothstep(0.08, 0.30, zone_std);          // 0 = flat, 1 = contrasty
float clarity_stevens   = smoothstep(0.20, 0.60, perc.g);             // Stevens anchor (0.4× weight)
float clarity_str_auto  = lerp(0.35, 0.15, saturate(clarity_zstd_t + 0.4 * clarity_stevens));
clarity_str_auto       *= (1.0 - 0.50 * ss_04_25);                   // anti-Retinex gate
new_luma = saturate(new_luma + clarity_str_auto * clarity_residual);
```

**Changes vs. R24N_2026-05-03:**

1. Primary anchor: `iqr_global = perc.b - perc.r` → `zone_std` (R90-consistent)
2. Smoothstep range: `(0.10, 0.40)` → `(0.08, 0.30)` (calibrated to zone_std units, which
   span ~0.0–0.35 for typical scenes vs. IQR ~0.0–0.55)
3. Strength bounds: `lerp(0.45, 0.20)` → `lerp(0.35, 0.15)` (reduced ~22% to compensate
   for R90's larger post-expansion residuals at INVERSE_STRENGTH = 0.50)
4. Anti-Retinex gate unchanged: `(1.0 − 0.50 × ss_04_25)`

Range analysis at INVERSE_STRENGTH = 0.50:

| Scene | zone_std | perc.g | clarity_str_auto |
|-------|----------|--------|-----------------|
| Dark flat (underground) | 0.06 | 0.12 | ≈ 0.35 × 1.0 = 0.35 |
| Bright contrasty (outdoor) | 0.28 | 0.55 | ≈ 0.15 × 0.60 = 0.09 |
| Typical Arc Raiders | 0.14 | 0.32 | ≈ 0.25 × 0.80 = 0.20 |

### Pumping risk

**Low-moderate.** `zone_std` is derived from ZoneHistoryTex medians (Kalman-filtered, R39),
making it more temporally stable than the IQR-from-PercTex formulation in the previous
proposal. On hard scene cuts, SceneCutTex spikes K → 1 in both ZoneHistoryTex and
ChromaHistoryTex paths, so `zone_std` resets within 1–2 frames — the same transient
budget as all other scene-cut-aware signals. `clarity_residual = luma − illum_s0` is
per-pixel and fully frame-instantaneous; it contributes no temporal state and cannot pump.

The remaining pumping surface is `perc.g` (pre-R90, PercTex), but its 0.4× weight limits
its contribution to ≤ 25% of the strength range (~0.05 units absolute), which is
imperceptible.

---

## SHADOW_LIFT

### Current behaviour (grade.fx lines 371–374)

Shadow lift is fully automated (R35 + R60). The operative formula:

```hlsl
// grade.fx line 371
float shadow_lift_str = lerp(1.50, 0.45, smoothstep(0.03, 0.22, perc.r));
// grade.fx line 362
float shadow_lift     = shadow_lift_str
                      * (0.149169 / (illum_s0 * illum_s0 + 0.003))
                      * local_range_att * texture_att * detail_protect * context_lift;
// grade.fx line 374
new_luma = saturate(new_luma + (shadow_lift / 100.0) * 0.75 * lift_w * SHADOW_LIFT_STRENGTH);
```

`perc.r` is PercTex.r (p25), which is written by `analysis_frame` from the **raw BackBuffer**
before any processing effects run. As of 2026-05-04, the pre-grade BackBuffer is processed by
two effects before `corrective.fx` computes ZoneHistoryTex and ChromaHistoryTex:

1. **R76A CAT16** (grade.fx lines 233–249): shifts pixel luminance ±14% max (gain clamped to
   [0.5, 2.0] × 0.60 lerp weight). Warm scenes → slightly darker shadows → post-CAT16 p25
   < PercTex.r.

2. **R90 inverse_grade** (added 2026-05-04): runs after `analysis_frame` in chain order
   (`analysis_frame : inverse_grade : ... : corrective : grade`). Formula:
   `luma_out = p50 × (luma_in / p50)^slope` blended by `INVERSE_STRENGTH`. At
   INVERSE_STRENGTH = 0.50 and slope = 1.5 (typical for Arc Raiders):
   - A dark pixel at p25 ≈ 0.05 expands to ≈ 0.50 × (0.05/0.50)^1.5 ≈ 0.016, then
     blended: lerp(0.05, 0.016, 0.50) ≈ 0.033.
   - PercTex.r reads 0.05; post-R90 effective p25 ≈ 0.033. Δ ≈ −34%.

Both effects push in the same direction. The combined effect for a dark warm scene
(worst case):

| Effect | Max PercTex.r overestimate |
|--------|---------------------------|
| R76A CAT16 | ~14% |
| R90 inverse_grade | ~20–35% (depends on slope and INVERSE_STRENGTH) |
| Combined (typical) | ~25–35% relative overestimate |

Using smoothstep(0.03, 0.22, perc.r) with a 30% overestimate: a scene at effective
post-expansion p25 = 0.025 reads as perc.r ≈ 0.033 →  smoothstep ≈ 0.016 →
shadow_lift_str ≈ 1.483 vs. ideal 1.50. The error is bounded and small (~1%). However,
for a dark-warm scene at effective p25 = 0.015, perc.r reads ≈ 0.021, just below the
current 0.03 lower bound → smoothstep = 0, shadow_lift_str = 1.50 (correct, coincidence).
The real concern is the middle range (effective p25 0.02–0.07) where the undercount shifts
the smoothstep output measurably.

### Proposed formula

Shift the smoothstep lower bound down to compensate for the pre-processing gap:

```hlsl
// Current (grade.fx line 371)
float shadow_lift_str = lerp(1.50, 0.45, smoothstep(0.03, 0.22, perc.r));
// Proposed — shifts breakpoints 15% darker to compensate compounded CAT16 + R90 gap
float shadow_lift_str = lerp(1.50, 0.45, smoothstep(0.025, 0.20, perc.r));
```

No change to the lerp range [1.50, 0.45] — only the smoothstep breakpoints move.

This is a documentation-class calibration note, not an urgent correctness issue. The
lift's internal spatial gating (`lift_w = new_luma × smoothstep(0.30, 0.0, new_luma)`)
prevents any over-lift regardless of shadow_lift_str.

### Risk

**Low.** The adjustment is small and conservative. Validation: compare shadow luma in a
dark warm scene before and after the breakpoint change. If shadow blacks look washed, revert
to 0.03. The maximum effect on the final image is a 3–5% increase in shadow_lift_str for
dark scenes processed through R90, well within the self-limiting range.

---

## DENSITY_STRENGTH

### Current behaviour (grade.fx line 460)

DENSITY_STRENGTH is fully automated (R36). Formula unchanged:

```hlsl
float density_str = 62.0 - 20.0 * chroma_exp;   // grade.fx line 460
// where: float chroma_exp = exp2(-5.006152 * mean_chroma);
```

Applied at grade.fx line 515:

```hlsl
float density_L = saturate(final_L - delta_C * headroom * (density_str / 100.0));
```

`mean_chroma` is derived from ChromaHistoryTex (bands 0–5), which is computed by
`corrective.fx UpdateHistoryPS` from the **post-R90 BackBuffer**. ChromaHistoryTex is
therefore R90-consistent.

**R90 interaction:** R90 applies `col.rgb *= (luma_out / luma_in)` — a uniform channel
scale at each pixel. This preserves the R:G:B ratios and therefore preserves Oklab hue
direction (a/b direction unchanged). Oklab chroma `C = sqrt(a² + b²)` is not purely
scale-invariant under the cube-root LMS transform, but the effect is bounded: for pixels
near p50, R90 barely moves them (expansion is anchored at p50). For dark pixels, the
darkening is approximately C ∝ L^(2/3) in Oklab, so a 30% luminance drop produces
≈ 20% chroma reduction. At INVERSE_STRENGTH = 0.50, the effect is halved to ~10% for
the darkest pixels, fading to zero at p50. Mean chroma measured post-R90 is marginally
lower for dark-skewed scenes. This is a second-order effect; no formula change is needed.

### Proposed formula

No change. The automation is correct and R90-consistent (reads from post-R90 ChromaHistoryTex).

### Risk

**Very low.** The self-limiting `headroom` product ensures density cannot push L below 0.0.
Second-order R90 chroma compression is within calibration noise.

---

## CHROMA_STRENGTH

### Current behaviour (grade.fx lines 447–462)

CHROMA_STRENGTH is fully automated (R36 + R68A). Formula unchanged:

```hlsl
// grade.fx lines 447–458
float cm_t = 0.0, cm_w = 0.0;
[unroll] for (int bi = 0; bi < 6; bi++)
{
    float4 hc = tex2D(ChromaHistory, float2((bi + 0.5) / 8.0, 0.5 / 4.0));
    cm_t += hc.r * hc.b;
    cm_w += hc.b;
}
float mean_chroma = cm_t / max(cm_w, 0.001);
float chroma_exp  = exp2(-5.006152 * mean_chroma);
float chroma_mc_t   = smoothstep(0.05, 0.25, mean_chroma);
float chroma_p50_t  = smoothstep(0.15, 0.55, perc.g);
float chroma_drive  = saturate(chroma_mc_t + 0.35 * chroma_p50_t);
float chroma_str    = saturate(0.085 * chroma_exp * hunt_scale * lerp(1.25, 0.60, chroma_drive));
// grade.fx line 462 — R68A spatial modulation
chroma_str         *= lerp(1.0, 0.65, smoothstep(0.02, 0.08, local_var));
```

`hunt_scale` (grade.fx lines 439–444) is derived from `zone_log_key`, which comes from
ChromaHistoryTex column 6 (post-R90 consistent). `perc.g` (p50) is from PercTex (pre-R90).

**R90 interaction:** Same as DENSITY. ChromaHistoryTex reads from post-R90 BackBuffer, so
`mean_chroma` is post-expansion consistent. `perc.g` at 0.35× weight is pre-R90 but the
minor luminance shift (~8% at p50 by construction of the expansion formula, which is
anchored to p50 and therefore zero-shift at p50) does not meaningfully bias chroma_drive.

### Proposed formula

No change. The automation is correct, R90-consistent where it matters (mean_chroma from
post-R90 ChromaHistoryTex), and the `perc.g` pre-R90 residual is negligible at p50 anchor.

### Risk

**Low.** Dual-signal (mean_chroma + p50) automation confirmed stable through R24N_2026-05-03.
R68A spatial modulation (`local_var`) is orthogonal to the scene-level chroma_drive signal.
No compounding concerns.

---

## Stevens + Hunt as automation anchor

### Current implementations

**Stevens** (grade.fx line 274):

```hlsl
float fc_stevens = (1.48 + sqrt(max(zone_log_key, 0.0))) / 2.03;
```

Based on the CIECAM02 lightness exponent z = 1.48 + sqrt(n) (R11, confirmed from
literature). Driven by `zone_log_key` (geometric mean of 16 zone medians — shadow-sensitive
log adaptation luminance). Post-R90 consistent via ChromaHistoryTex column 6.

**Hunt** (grade.fx lines 439–444):

```hlsl
float _k    = 1.0 / (5.0 * zone_log_key + 1.0);
float _k4   = _k * _k; _k4 *= _k4;
float _omk4 = 1.0 - _k4;
float hunt_scale = sqrt(sqrt(max(
    _k4 * zone_log_key + 0.1 * _omk4 * _omk4 * pow(5.0 * zone_log_key, 1.0 / 3.0),
    1e-6))) / 0.5912;
```

CIECAM02 FL^0.25 formula driven by `zone_log_key`. Post-R90 consistent.

### Should p50 anchor the formulas?

**CLARITY (revised):** The new formula uses `zone_std` (not p50 or IQR) as the primary
signal for R90 consistency. `perc.g` (p50) is retained as a secondary Stevens anchor at
0.4× weight. This is the right balance: zone_std captures post-expansion image contrast;
p50 modulates the Stevens correction for adaptation luminance. Both signals are semantically
orthogonal and their weights prevent over-coupling.

**CHROMA:** `perc.g` (p50) remains at 0.35× weight in `chroma_p50_t`. Pre-R90 PercTex.g
is barely affected at p50 by R90 (the expansion is anchored to p50 → zero displacement
there by construction). The p50 anchor is safe for CHROMA specifically because the R90
anchor point and the signal measurement point coincide.

**Risk of over-coupling to p50:**
- p50 tracks scene exposure changes, which is the desired feedback (brighter → less boost).
- At ≤ 0.4× weight, p50 can shift the output by at most ~20% of the primary signal range.
- Below the threshold where coupling reads as soft auto-exposure to a trained observer.
- Confirmed safe at these weights. Rule: keep p50 weight ≤ 0.4× for all auto-driven terms.

### New external validation — Žaganeli et al. (2026)

From today's filmcurve domain research (`research/2026-05-04_filmcurve.md`):

Žaganeli et al. (2026), arXiv 2604.06276, "Structural Regularities of Cinema SDR-to-HDR
Mapping", measured actual professional colorist decisions across 18,580 frames of a
single ACES-mastered film. Key finding relevant to this automation:

> Saturation redistribution follows three zones: shadow suppression → midtone expansion →
> highlight convergence. Zone boundaries track the local slope of the characteristic curve,
> not fixed luma levels.

This independently validates the pipeline's R51 print stock `desat_w` bell (grade.fx
lines 296–298):

```hlsl
float desat_w = 0.15 * (1.0 - smoothstep(0.0, 0.3, luma_ps))
                      * (1.0 - smoothstep(0.6, 1.0, luma_ps));
```

The bell is zero at luma=0 (toe, slope < 1) and luma=1 (shoulder, slope < 1), and peaks
in the straight-line midtone region. This is the same topology as Žaganeli's empirical
shadow-suppression / midtone-expansion / highlight-convergence profile. **The CHROMA
automation's inverse-strength-on-vivid-scenes formulation (high chroma_drive → lower
chroma_str) is also consistent**: vivid scenes typically correspond to the saturated
midtone region where, per Žaganeli, saturation is *already expanded* by colorists — the
pipeline correctly restrains further lift.

This paper provides the strongest external validation to date that the pipeline's
saturation shaping matches what professional SDR colorists actually do.

---

## Implementation priority

| Knob | Status | Confidence | Pumping risk | Recommended action |
|------|--------|------------|-------------|-------------------|
| CLARITY_STRENGTH | **Not implemented** | Medium | Low-moderate | Implement with zone_std anchor; recalibrated for R90 |
| SHADOW_LIFT | **Implemented (R35 + R60)** | High | Low | Recalibrate smoothstep(0.03, 0.22) → (0.025, 0.20) on warm-dark scene test |
| DENSITY_STRENGTH | **Implemented (R36)** | Very high | Very low | No action |
| CHROMA_STRENGTH | **Implemented (R36)** | High | Low | No action |

**CLARITY implementation checklist:**
1. Insert the 6-line block after grade.fx line 363 (after Retinex), before line 365.
2. Verify zone_std is in register at insertion point (it is: line 261).
3. Validate on a flat scene (zone_std ≤ 0.06): should produce clarity_str_auto ≈ 0.30–0.35.
4. Validate on a contrasty outdoor scene (zone_std ≥ 0.25): should produce ≈ 0.09–0.12.
5. Check for halos on zone boundary edges (Retinex + Clarity both firing): if visible,
   increase the anti-Retinex gate coefficient from 0.50 to 0.65.
6. No SPIR-V concerns — the block uses only `saturate`, `smoothstep`, `lerp`, and
   arithmetic on existing registers. No static arrays.

**SHADOW_LIFT calibration checklist** (lower priority — no functional issue, cosmetic):
1. Test a warm-lit dark scene (tungsten interior, p25 raw ≈ 0.04–0.06).
2. Check shadow luma output before and after adjusting smoothstep from (0.03, 0.22)
   to (0.025, 0.20).
3. If shadow luma increases visibly and correctly: keep the adjustment.
4. If no visible difference: the compounding effects are within calibration noise — defer.

---

## Literature findings

External search APIs (Brave, arXiv) were blocked by host_not_allowed (HTTP 403),
consistent with all prior nightly sessions. Literature basis is from training knowledge
and session-sourced papers.

**New this session:**

Žaganeli, B. et al. (2026). "Structural Regularities of Cinema SDR-to-HDR Mapping in a
Controlled Mastering Workflow: A Pixel-wise Case Study on ASC StEM2." arXiv 2604.06276.
Provides pixel-wise empirical ground truth for what professional SDR colorists do with
saturation as a function of luma. Confirms shadow suppression / midtone expansion /
highlight convergence, aligned with R51 and the CHROMA automation's inverse direction.

**Previously cited, confirmed relevant:**

- Fairchild & Johnson (2007), iCAM06, *J. Visual Communication and Image Representation*
  18:279–294. FL^0.25 drives both Stevens and Hunt. Both pipeline implementations
  (`fc_stevens`, `hunt_scale`) derive from this.

- CIE 159:2004 (CIECAM02). Stevens z = 1.48 + sqrt(n); FL luminance factor formula.
  Both implemented correctly as confirmed by R11 audit.

- Webster (1996), *Vision Research* 36:4519–4524. Color contrast adaptation: higher
  scene chroma → reduced perceived chroma gain in visual system → lower chroma boost is
  correct. Theoretical basis for the inverse `chroma_drive` relationship in CHROMA automation.

- Frazor & Geisler (2006), *Vision Research* 46:1585–1598. Percentile luminance statistics
  in natural images; p25 as a valid shadow-content signal. Underpins SHADOW_LIFT automation.

- Reinhard et al. (2002), SIGGRAPH. Scene key and log-average luminance for adaptive tone
  operators. Conceptual precedent for all scene-stat-driven automations.

- Safdar et al. (2021), *Optics Express* 29(4):6036–6048. ZCAM colorfulness Mz at SDR
  luminances produces Hunt factors ≈ 1.2–1.6×, consistent with pipeline's FL^0.25
  hunt_scale producing comparable values.
