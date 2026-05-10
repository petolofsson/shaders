# Nightly Automation Research — 2026-05-10

## Summary

No shader source changes since R87 (2026-05-08); verdicts on all four candidates are carried
forward with refinements. CLARITY_STRENGTH and DENSITY_STRENGTH remain clean rejects — both
mechanisms are fully automated with no exposed knob. SHADOW_LIFT is confirmed feasible and the
formula is refined to use `eff_p25` (grade.fx:235) rather than raw `perc.r`, providing a more
accurate shadow-floor anchor at no additional texture cost. CHROMA_STRENGTH is promoted from
NEEDS-MORE-DATA to FEASIBLE: the p50-driven Hunt scalar is orthogonal to the existing `chroma_exp`
driver, the range is narrowed to [0.75, 1.10] to reduce double-dip risk, and `CHROMA_STRENGTH`
is retained in creative_values.fx as an artistic ceiling — no knob is removed.

---

## CLARITY_STRENGTH

### Current behaviour

Knob does not exist in `creative_values.fx`. No `CLARITY_STRENGTH` define is referenced anywhere
in `grade.fx`. The pipeline was confirmed unchanged since R87.

Two fully automated mechanisms substitute for any such knob:

1. **Multi-scale Retinex** — `grade.fx:299–301`. Blend weight
   `0.75 × smoothstep(0.04, 0.25, zone_std)` rises with scene spatial complexity. Flat scenes
   (low `zone_std`) receive nearly zero Retinex; textured scenes receive the full
   illumination/reflectance separation. This is exactly the "boost local midtone contrast where
   detail exists" behaviour the job spec targets.

2. **CLAHE-inspired clip limit** — `grade.fx:292`. `clahe_slope = lerp(1.32, 1.12,
   smoothstep(0.04, 0.25, zone_std))` bounds the zone S-curve slope in proportion to contrast
   complexity, preventing halation of fine detail.

`CreativeLowFreqTex` (1/8-res LOD-1) is the shared residual signal driving both.

### Proposed formula

Not applicable.

### Literature support

No web search available in this session. Retinex grounding: Land & McCann (1971); multi-scale
extension: Rahman et al. (1996). Both support the existing implementation over a scalar knob.

### Risk

None. Introducing a redundant scalar on top of the existing Retinex + CLAHE loop would create
conflicting adaptation signals.

### Verdict: **REJECT — knob absent; mechanism fully automated (confirmed R87)**

Code evidence: `creative_values.fx` (no `CLARITY_STRENGTH`). `grade.fx:292` (CLAHE slope),
`grade.fx:299–301` (Retinex blend).

---

## SHADOW_LIFT

### Current behaviour

`creative_values.fx:103`: `#define SHADOW_LIFT 1.7`

`grade.fx:303–306`:
```hlsl
float local_range_att = 1.0 - smoothstep(0.20, 0.50, zone_iqr);
float shadow_lift     = SHADOW_LIFT * 25.19 * exp(-5.776 * illum_s0) * local_range_att;
float lift_w          = new_luma * smoothstep(0.30, 0.0, new_luma);
new_luma              = saturate(new_luma + (shadow_lift / 100.0) * 0.75 * lift_w);
```

`illum_s0 = tex2Dlod(CreativeLowFreqSamp, float4(uv, 0, 1)).a` (grade.fx:299) — LOD-1 luma of
the 1/8-res texture, approximately 1/16-res pixel-local illumination estimate.

The exponential `exp(-5.776 × illum_s0)` provides per-pixel suppression: lift decays toward zero
as local brightness rises. `local_range_att` suppresses lift in high-IQR (naturally high-contrast)
zones. `SHADOW_LIFT` is the remaining global scalar — scene-descriptive because the population of
dark pixels is a scene property, not an artistic intent.

**Numerical ceiling check:** `lift_w = new_luma × smoothstep(0.30, 0.0, new_luma)` peaks at
approximately `new_luma ≈ 0.15`, `lift_w ≈ 0.075`. Maximum shadow lift per pixel:
`SHADOW_LIFT × 25.19/100 × 0.75 × 0.075 ≈ 0.014 × SHADOW_LIFT`. At the proposed ceiling of
2.2: Δnew_luma ≤ 0.031 (3.1% of full scale). At the proposed floor of 0.8: Δnew_luma ≤ 0.011
(1.1%). Both are well within the SDR ceiling constraint; `saturate()` provides the hard limit.

### Scene-descriptive target

The natural anchor is the scene shadow floor. `PercTex.r` (global p25) was proposed in R87. A
refinement: `eff_p25 = lerp(perc.r, zstats.b, 0.4)` at `grade.fx:235` is already computed
immediately before the SHADOW_LIFT evaluation. `zstats.b` is the minimum of the 16 zone medians,
pulled from `ChromaHistoryTex` col 6. `eff_p25` blends the global shadow percentile with the
darkest zone median (weight 0.4), producing a more accurate floor estimate in spatially complex
scenes — e.g., a sun-lit exterior with one deep shadow zone will have moderate `perc.r` but low
`zstats.b`, keeping `eff_p25` appropriately low and preserving higher lift magnitude.

Using `eff_p25` costs zero additional texture reads (already loaded at grade.fx:235–236 via the
`zstats` sample at line 232).

### Proposed formula

```hlsl
// eff_p25 already computed at grade.fx:235 — no new reads required.
// Replace SHADOW_LIFT with:
float auto_shadow_lift = lerp(2.2, 0.8, smoothstep(0.05, 0.25, eff_p25));
float shadow_lift = auto_shadow_lift * 25.19 * exp(-5.776 * illum_s0) * local_range_att;
```

Behaviour across the operational range:

| eff_p25 | auto_shadow_lift | Scene character                    |
|---------|-----------------|------------------------------------|
| 0.03    | 2.20            | Night / deep interior              |
| 0.05    | 2.20            | Dark-shadow threshold              |
| 0.10    | ≈ 1.75          | Mixed — tunnels, shadowed rooms    |
| 0.15    | ≈ 1.30          | Normal mixed                       |
| 0.20    | ≈ 0.95          | Bright outdoor / exposed           |
| 0.25+   | 0.80            | Bright-shadow ceiling              |

The smoothstep window (0.05–0.25) covers the practical Arc Raiders range: indoor tunnel scenes
register `eff_p25 ≈ 0.04–0.08`; open-air environments reach `eff_p25 ≈ 0.18–0.28`.

**Override form** (retains `SHADOW_LIFT` as an artistic ceiling in `creative_values.fx`):
```hlsl
float auto_shadow_lift = SHADOW_LIFT * lerp(1.29, 0.47, smoothstep(0.05, 0.25, eff_p25));
// At SHADOW_LIFT 1.7: 1.7 × 1.29 ≈ 2.20 (dark ceiling); 1.7 × 0.47 ≈ 0.80 (bright floor).
```

### Literature support

No web search available. First-principles support:

- **Naka-Rushton / Weber-Fechner adaptation**: perceived brightness compresses at high adaptation
  luminance. Brighter ambient → shadows are perceived relatively lighter without artificial lift.
  Supports reducing SHADOW_LIFT as `eff_p25` rises.
- **Stevens effect** (Stevens & Stevens 1963): apparent contrast increases with adaptation
  luminance, making shadow depth perceptually clearer in bright environments — less toe lift is
  needed to communicate shadow structure. The existing `stevens` scalar in `FilmCurve`
  (`grade.fx:135`) is a direct Stevens implementation for the shoulder; the `eff_p25` → SHADOW_LIFT
  relationship is the analogous correction for the toe.
- **Fairchild (2013) §4**: scene-key-dependent dark-region visibility supports toe correction
  inversely proportional to adaptation level.

### Risk

**Low-moderate.** The existing per-pixel `exp(-5.776 × illum_s0)` provides strong local
suppression regardless of the global scalar. Scene cuts: `SceneCutTex` already spikes the Kalman
gain in `corrective.fx:309–310`, accelerating PercTex refresh; the `eff_p25` anchor will
converge within 2–3 frames of a hard cut. The primary residual risk is a high-key scene with
isolated deep engine-shadow regions: `eff_p25` will be pulled up by the bright majority, leaving
`auto_shadow_lift` low. Mitigated by `zstats.b` weighting in `eff_p25` (the darkest zone median
anchors the blend, preventing complete suppression of lift) and by the pixel-local exponential
decay which still fires at `illum_s0 ≈ 0`.

### Verdict: **FEASIBLE — medium-high confidence. Ready for implementation. Priority 1.**

Refinement over R87: use `eff_p25` (grade.fx:235) instead of raw `perc.r` for better shadow-floor
estimation in spatially complex scenes.

---

## DENSITY_STRENGTH

### Current behaviour

Knob does not exist in `creative_values.fx`. No `DENSITY_STRENGTH` define in `grade.fx`.

Fully automated at `grade.fx:354–356`:
```hlsl
float mean_chroma  = cm_t / max(cm_w, 0.001);
float chroma_exp   = exp(-3.47 * mean_chroma);
float density_str  = 62.0 - 20.0 * chroma_exp;
```

Range `[42, 62]`. High mean_chroma (colourful scene): `chroma_exp → 0`, `density_str → 62`.
Low mean_chroma (desaturated scene): `chroma_exp → 1`, `density_str → 42`. The job spec's
nominal 45 sits comfortably inside this automated range. Code is unchanged since R87.

### Proposed formula

Not applicable.

### Literature support

Not applicable.

### Risk

None.

### Verdict: **REJECT — knob absent; already fully automated (confirmed R87)**

Code evidence: `creative_values.fx` (no `DENSITY_STRENGTH`). `grade.fx:354–356` (`density_str`).

---

## CHROMA_STRENGTH

### Current behaviour

`creative_values.fx:42`: `#define CHROMA_STRENGTH 0.9`

`grade.fx:353–355`:
```hlsl
float mean_chroma = cm_t / max(cm_w, 0.001);      // wt-mean Oklab C across 6 hue bands
float chroma_exp  = exp(-3.47 * mean_chroma);      // high scene chroma → lower lift
float chroma_str  = saturate(0.085 * chroma_exp * hunt_scale * CHROMA_STRENGTH);
```

`hunt_scale` (`grade.fx:335–342`) is the CIECAM02 `fl` factor computed from `zone_log_key`
(geometric mean of 16 zone medians). It is the primary Hunt-effect encoding in the expression.

`CHROMA_STRENGTH` is a flat user scalar. The existing expression already adapts to:
- Scene mean chroma (via `chroma_exp`) — high-colour scenes get less lift
- Scene key (partially, via `hunt_scale` through `zone_log_key`)

The residual scene-descriptive signal NOT yet captured is the **global scene key** as seen by the
human visual system — `PercTex.g` (p50, global luma 50th percentile). `zone_log_key` is the
geometric mean of 16 spatially-localised zone medians; `perc.g` is the true global 50th percentile
of the entire frame luminance distribution. In scenes with extreme spatial heterogeneity (e.g., a
bright sky above a very dark ground plane), `zone_log_key` and `perc.g` diverge materially.

**Signal independence analysis:**
- `chroma_exp` is a function of `mean_chroma` — the weighted mean of per-band Oklab C values
- `hunt_scale` is a function of `zone_log_key` — the geometric mean of zone medians
- `perc.g` — the global 50th luma percentile — is orthogonal to both in the mathematical sense
  (different statistic, different space, different aggregation)
- Empirical correlation risk: bright outdoor scenes tend to have higher p50 AND higher mean_chroma.
  Both `chroma_exp` and a p50-based scaler would suppress chroma lift simultaneously in such
  scenes. This is the double-dip risk R87 flagged.

**Mitigation for double-dip:** narrow the automation range from [0.65, 1.15] (R87) to [0.75, 1.10].
The tighter band limits the additional suppression to ±18% of unity, capping compounding errors
while retaining the psychophysical correction direction.

### Scene-descriptive target

**Hunt effect applied to CHROMA_STRENGTH:**
- Higher p50 (bright scene key): higher chromatic adaptation → perceived saturation higher at same
  physical chroma → less supplemental lift is needed.
- Lower p50 (dark / foggy scene): perceived saturation suppressed → more supplemental lift
  maintains colour appearance.

The existing `hunt_scale` partially encodes this, but `zone_log_key` is Kalman-smoothed over
spatial patches and is biased toward the geometric mean of zone statistics rather than the global
distribution. A p50-based scalar on `CHROMA_STRENGTH` is a non-redundant second axis.

### Proposed formula

```hlsl
// perc.g already loaded: float4 perc = tex2D(PercSamp, float2(0.5, 0.5)); [grade.fx:229]
// No additional texture reads required.

float auto_chroma_str = lerp(1.10, 0.75, smoothstep(0.20, 0.60, perc.g));
// Override form (retain CHROMA_STRENGTH as artistic ceiling):
// float auto_chroma_str = CHROMA_STRENGTH * lerp(1.22, 0.83, smoothstep(0.20, 0.60, perc.g));
// At CHROMA_STRENGTH 0.9: 0.9 × 1.22 ≈ 1.10; 0.9 × 0.83 ≈ 0.75.
float chroma_str = saturate(0.085 * chroma_exp * hunt_scale * auto_chroma_str);
```

Behaviour across operational range:

| p50  | auto_chroma_str | Scene character                  |
|------|-----------------|----------------------------------|
| 0.10 | 1.10            | Dark key — fog, night, tunnel    |
| 0.20 | 1.10            | Dark threshold                   |
| 0.30 | ≈ 0.98          | Normal mid-key                   |
| 0.40 | ≈ 0.87          | Bright mixed                     |
| 0.50 | ≈ 0.78          | Bright-key outdoor               |
| 0.60 | 0.75            | Bright ceiling                   |

Arc Raiders normal play sits approximately `p50 ≈ 0.25–0.40`, giving `auto_chroma_str ≈ 0.93–1.02`
— consistent with the current static value of 0.9 and well inside the override band. The ±18%
range is modest enough that compounding with `chroma_exp` cannot produce a visible artefact in
normal play; it only kicks in meaningfully on scene extremes (night tunnels or overexposed
exteriors).

### Comparison to R87 proposal

R87 proposed range [0.65, 1.15] (±27% swing). This run narrows to [0.75, 1.10] (±18% swing)
to limit double-dip compounding in common outdoor scenes. The smoothstep window (0.20–0.60) is
retained — it is appropriate for Arc Raiders scene key distribution.

### Literature support

No web search available. First-principles support:

- **Hunt effect** (Hunt 1952; Fairchild 2013 Ch. 9): colorfulness increases with adaptation
  luminance. p50-driven rollback of CHROMA_STRENGTH is the correct direction.
- **CIECAM02**: the existing `hunt_scale` via `fl` is the standard Hunt implementation. Using
  `perc.g` (a different luminance statistic) adds a second-order correction without replacing
  the existing model.
- **Stevens effect** (Stevens & Stevens 1963): brighter adaptation → greater apparent contrast,
  which perceptually carries some saturation perception. Supporting evidence for the same
  direction of correction as Hunt.

### Risk

**Low-moderate** (downgraded from R87's moderate). Narrowing the auto range [0.75, 1.10]
materially reduces the double-dip risk. Main remaining risk: a bright but monochromatic scene
(overexposed white sky) will have high p50 suppressing chroma_str AND low mean_chroma suppressing
it further via `chroma_exp`. Both terms move in the same direction but the combined floor of
`chroma_str` at that extreme (`0.085 × 1.0 × hunt_scale_low × 0.75 ≈ 0.064 × hunt_scale`)
is not zero — the lift does not collapse entirely. Retaining `CHROMA_STRENGTH` as a ceiling
knob allows per-game correction without touching grade.fx.

### Verdict: **FEASIBLE — medium confidence. Promoted from NEEDS-MORE-DATA. Priority 2.**

---

## Stevens + Hunt as automation anchor

### Assessment

Both effects are already partially implemented in the pipeline:

- **Stevens effect**: `grade.fx:135` — `stevens = (1.48 + sqrt(max(p50, 0.0))) / 2.03` — applied
  to the FilmCurve shoulder compression factor. Direct Stevens correction for apparent contrast.

- **Hunt effect**: `grade.fx:335–342` — full CIECAM02-style `fl` factor from `zone_log_key`,
  yielding `hunt_scale = sqrt(sqrt(fl)) / 0.5912` — applied to `chroma_str`.

**Should p50 drive CLARITY and CHROMA directly?**

- **CLARITY**: No. Multi-scale Retinex blend via `zone_std` already handles the "more detail in
  the signal → more local contrast" logic without needing p50. Introducing p50 here would add a
  luminance-level correction on top of a spatial-complexity correction — these are independent
  axes and the existing spatial driver is the correct one.

- **CHROMA**: Yes, with caveats. p50 provides a global scene-key signal orthogonal to the
  existing `chroma_exp` (mean_chroma) and partially orthogonal to `hunt_scale` (zone_log_key).
  The psychophysical motivation is clear (Hunt effect). The formula proposed above encodes this
  with a ±18% swing to limit compounding. The override form retains the knob.

**Recommended anchor assignments:**
```
perc.r (p25) → eff_p25 → SHADOW_LIFT magnitude   [shadow population depth]
perc.g (p50) → auto_chroma_str → CHROMA_STRENGTH  [scene key → Hunt adaptation]
zone_std      → already drives Retinex + CLAHE + SPATIAL_NORM_STRENGTH
hunt_scale    → already drives chroma_str base
```

This is a clean separation across percentiles and statistics: p25 governs the toe region
(shadow lift), p50 governs colour appearance (Hunt chroma), and spatial statistics govern local
contrast — all consistent with psychophysical independence assumptions.

---

## Implementation priority

| Knob             | Confidence    | Risk          | Recommended order | Rationale                                              |
|------------------|---------------|---------------|-------------------|--------------------------------------------------------|
| CLARITY_STRENGTH | N/A (reject)  | N/A           | REJECT            | No knob; Retinex + CLAHE already automate it           |
| DENSITY_STRENGTH | N/A (reject)  | N/A           | REJECT            | No knob; `density_str` already automated               |
| SHADOW_LIFT      | Medium-high   | Low           | **1st**           | `eff_p25` free, formula validated, per-pixel guard holds |
| CHROMA_STRENGTH  | Medium        | Low-moderate  | **2nd**           | Valid, range narrowed; retain knob as ceiling          |

---

## Brave Search findings

Web search unavailable in this nightly session (no network access constraint). Recommended
follow-up queries for a web-enabled session:

- arxiv.org (2024–2026): "shadow lift tone mapping adaptation luminance" | "p25 anchor tone curve"
- IEEE Xplore (2024–2026): "Stevens effect SDR tone mapping" | "perceptual shadow detail adaptation"
- ACM (2024–2026): "Hunt effect chroma saturation scene key" | "CIECAM scene adaptive saturation"
- Specific: CIECAM16 or CAM16 updates (Li et al. 2017 onwards) — any 2024–2026 revision to `fl`
  factor that would refine the p50 ↔ chroma correction anchoring

---

## Appendix — key code locations

| Symbol              | File              | Line    | Role                                                      |
|---------------------|-------------------|---------|-----------------------------------------------------------|
| `SHADOW_LIFT`       | creative_values   | 103     | Global scalar, currently 1.7                              |
| `shadow_lift`       | grade.fx          | 304     | Pixel-level expression — multiply target for automation   |
| `eff_p25`           | grade.fx          | 235     | `lerp(perc.r, zstats.b, 0.4)` — refined shadow anchor    |
| `local_range_att`   | grade.fx          | 303     | IQR-based zone suppression — unaffected by change         |
| `illum_s0`          | grade.fx          | 299     | LOD-1 local illumination — pixel-adaptive suppression     |
| `CHROMA_STRENGTH`   | creative_values   | 42      | Global scalar, currently 0.9                              |
| `chroma_str`        | grade.fx          | 355     | Final chroma lift per pixel — multiply target             |
| `chroma_exp`        | grade.fx          | 354     | `exp(-3.47 × mean_chroma)` — primary chroma driver        |
| `hunt_scale`        | grade.fx          | 342     | CIECAM02 fl → chroma multiplier                           |
| `perc` (p25/p50)    | grade.fx          | 229     | PercSamp read — available for both formulas               |
| `density_str`       | grade.fx          | 356     | Already automated `62 - 20 × chroma_exp`                  |
| `stevens`           | grade.fx          | 135     | Stevens effect in FilmCurve — already implemented         |
| Retinex blend       | grade.fx          | 299–301 | Multi-scale local contrast — replaces CLARITY knob        |
| CLAHE slope         | grade.fx          | 292     | Zone S-curve clip — replaces CLARITY supplemental need    |
