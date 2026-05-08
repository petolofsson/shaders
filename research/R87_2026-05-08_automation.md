# Nightly Automation Research — 2026-05-08

## Summary

Two of the four job-spec candidates (CLARITY_STRENGTH, DENSITY_STRENGTH) are already absent
from the codebase as user knobs — both mechanisms are fully automated and require no further
work. SHADOW_LIFT has a feasible scene-level p25 overlay on top of its existing pixel-adaptive
formula. CHROMA_STRENGTH has a credible Stevens/Hunt-grounded p50 automation path, but the
primary mean_chroma signal is already embedded in the adaptive expression, requiring a
non-redundant driver (p50) to avoid double-dipping. Implementation priority: SHADOW_LIFT first
(single smoothstep, low risk), CHROMA_STRENGTH second (valid but needs careful validation
against desaturated scenes).

---

## CLARITY_STRENGTH

### Current behaviour

**Knob does not exist in creative_values.fx. No CLARITY_STRENGTH define referenced anywhere in
grade.fx.**

The clarity-analog functionality in the current pipeline is handled by two fully automated
mechanisms:

1. **Multi-scale Retinex** — `grade.fx:299-301`. Separates illumination from reflectance at
   1/8-res (LOD 1 of CreativeLowFreqTex). Blend weight `0.75 × smoothstep(0.04, 0.25, zone_std)`
   rises automatically with scene contrast complexity, producing exactly the "boost local midtone
   contrast where detail exists" behaviour the job spec describes. Flat scenes (low zone_std) get
   almost zero Retinex. Textured, spatially complex scenes get full blend.

2. **CLAHE-inspired clip limit** — `grade.fx:292`. `clahe_slope = lerp(1.32, 1.12, smoothstep(0.04, 0.25, zone_std))` bounds the S-curve slope, tightening in high-contrast scenes to prevent
   halation of fine detail.

The `CreativeLowFreqTex` residual (full-res minus 1/8-res) implicitly drives both — exactly the
"image detail density" signal the job spec proposes.

### Proposed formula

Not applicable. The mechanism is already gate-free and adaptive.

### Literature support

No web search available (nightly constraint). The Retinex approach is grounded in Land & McCann
(1971) and the multi-scale refinements of Rahman et al. (1996). Both support the pipeline's
existing implementation over a separate CLARITY knob.

### Risk

None — reject closes this candidate cleanly. Introducing a redundant CLARITY_STRENGTH multiplier
on top of the existing Retinex+CLAHE system would create conflicting adaptation loops pulling in
the same direction.

### Verdict: **REJECT — knob does not exist; mechanism already fully automated**

Code evidence: `creative_values.fx` (no CLARITY_STRENGTH define). `grade.fx:292` (CLAHE slope),
`grade.fx:299-301` (Retinex blend).

---

## SHADOW_LIFT

### Current behaviour

`creative_values.fx:103`: `#define SHADOW_LIFT 1.7`

`grade.fx:304-306`:
```hlsl
float shadow_lift     = SHADOW_LIFT * 25.19 * exp(-5.776 * illum_s0) * local_range_att;
float lift_w          = new_luma * smoothstep(0.30, 0.0, new_luma);
new_luma              = saturate(new_luma + (shadow_lift / 100.0) * 0.75 * lift_w);
```

`illum_s0` is the 1/8-res LOD-1 luma from `CreativeLowFreqTex` (grade.fx:299) — already a
pixel-local illumination estimate. The exponential `exp(-5.776 × illum_s0)` decays the lift as
local brightness increases: nearly full lift at `illum_s0 ≈ 0`, approaching 0 at `illum_s0 ≈ 0.8`.
`local_range_att = 1.0 - smoothstep(0.20, 0.50, zone_iqr)` suppresses lift where local IQR is
wide (already high-contrast zone).

The remaining SHADOW_LIFT 1.7 is a single global scalar controlling overall magnitude. It is
scene-descriptive: the "correct" global lift depends on how dark the global shadow population is.

### Scene-descriptive target

`PercTex.r` (p25, global luma 25th percentile) is the natural anchor. When p25 is high
(intrinsically bright shadows — outdoor midday, exposed environments), the existing adaptive
pixel formula will already apply minimal lift to each pixel individually, but the global scalar
still amplifies it unnecessarily. When p25 is low (underexposed or night scenes), more global
lift magnitude is warranted.

Desiderata:
- Monotonically decreasing in p25.
- Smooth (no discontinuities).
- Range approximately [0.8, 2.4] — below 0.8 the lift is perceptually negligible; above 2.4 the
  existing per-pixel suppression term `lift_w = new_luma × smoothstep(0.30, 0.0, new_luma)`
  cannot prevent global graying of dark regions.

### Proposed formula

```hlsl
// p25 already loaded: float4 perc = tex2D(PercSamp, float2(0.5, 0.5));  [grade.fx:229]
float auto_shadow_lift = lerp(2.2, 0.8, smoothstep(0.05, 0.25, perc.r));
// Replace SHADOW_LIFT with auto_shadow_lift in grade.fx:304:
float shadow_lift = auto_shadow_lift * 25.19 * exp(-5.776 * illum_s0) * local_range_att;
```

Behaviour:
| p25   | auto_shadow_lift | Scene character              |
|-------|-----------------|------------------------------|
| 0.03  | ≈ 2.20          | Very dark — night / interior |
| 0.05  | 2.20            | Dark-shadow threshold        |
| 0.12  | ≈ 1.6           | Normal mixed scene           |
| 0.20  | ≈ 0.95          | Bright/outdoor                |
| 0.25+ | 0.80            | Bright-shadow ceiling        |

The smoothstep transition window (0.05–0.25 in p25) covers the practical range of Arc Raiders
scenes (indoor tunnels ↔ open-air exposed environments). PercTex is EMA-smoothed by analysis_frame
before grade.fx reads it, preventing per-frame pumping.

`creative_values.fx` can retain `SHADOW_LIFT` as a manual ceiling / override multiplier:
`float auto_shadow_lift = SHADOW_LIFT * lerp(1.29, 0.47, smoothstep(0.05, 0.25, perc.r));`
(where the lerp endpoints are normalised so SHADOW_LIFT 1.7 × 1.29 ≈ 2.2 and 1.7 × 0.47 ≈ 0.8).

### Literature support

No web search available. The inverse-p25 anchor is grounded in:
- Naka-Rushton luminance adaptation: perceived brightness compresses at high adaptation levels
  (Weber–Fechner), supporting lower lift in bright-ambient scenes.
- Stevens effect (1961): apparent contrast of a scene increases with adaptation luminance. Brighter
  adaptation → shadows appear relatively darker → less artificial lifting is needed to maintain
  perceived shadow detail. This is the same Stevens scalar already applied to the FilmCurve
  shoulder (`grade.fx:135`: `stevens = (1.48 + sqrt(p50)) / 2.03`). An analogous inverse term
  on shadow lift is psychophysically consistent.
- Fairchild (2013) *Color Appearance Models*: Chapter 4 discusses luminance-adapted dark-region
  visibility, supporting the concept of scene-key-dependent toe correction.

### Risk

**Moderate.** The existing per-pixel formula already provides significant per-pixel adaptation.
The scene-level p25 overlay adds a second-order correction. In transitional scenes (cut from
dark interior to bright exterior) PercTex lags by a few EMA frames; however, `SceneCutTex`
already spikes the Kalman gain on hard cuts (corrective.fx:309-310), which propagates through
to PercTex refresh rate. Scene-cut risk is low.

Primary risk: outdoor scenes with extreme shadow depth (e.g., a sun-lit environment with deep
engine shadow regions) — p25 will be pulled high by the bright majority, leaving dark corners
under-lifted. Mitigated by the per-pixel `exp(-5.776 × illum_s0)` which still fires locally.

### Verdict: **FEASIBLE — medium confidence. Recommended for implementation.**

---

## DENSITY_STRENGTH

### Current behaviour

**Knob does not exist in creative_values.fx. No DENSITY_STRENGTH define referenced anywhere in
grade.fx.**

Density is computed fully automatically at `grade.fx:356`:
```hlsl
float density_str = 62.0 - 20.0 * chroma_exp;
// where chroma_exp = exp(-3.47 * mean_chroma);  [grade.fx:354]
```

When scene mean_chroma is high (colorful scene), `chroma_exp → 0`, `density_str → 62`. When
mean_chroma is low (desaturated scene), `chroma_exp → 1`, `density_str → 42`. Range is
`[42, 62]` — exactly the job spec's intended 45 midpoint. The HANDOFF.md confirms: "Chroma/density
strengths — driven by mean_chroma from ChromaHistoryTex."

### Proposed formula

Not applicable. Already fully automated with no residual knob.

### Literature support

Not applicable.

### Risk

None — reject closes this candidate cleanly.

### Verdict: **REJECT — knob does not exist; already fully automated**

Code evidence: `creative_values.fx` (no DENSITY_STRENGTH define). `grade.fx:354-356`
(`chroma_exp`, `density_str`). HANDOFF.md line 89: "Chroma/density strengths — driven by
mean_chroma from ChromaHistoryTex."

---

## CHROMA_STRENGTH

### Current behaviour

`creative_values.fx:42`: `#define CHROMA_STRENGTH 0.9`

`grade.fx:353-355`:
```hlsl
float mean_chroma = cm_t / max(cm_w, 0.001);          // weighted mean C across 6 hue bands
float chroma_exp  = exp(-3.47 * mean_chroma);          // high scene chroma → lower lift
float chroma_str  = saturate(0.085 * chroma_exp * hunt_scale * CHROMA_STRENGTH);
```

`hunt_scale` is computed at `grade.fx:335-342` via a CIECAM02-style luminance adaptation factor
`fl`, encoding the Hunt effect: higher scene key → higher apparent saturation → less lift needed.

CHROMA_STRENGTH (0.9) is a scalar on `chroma_exp × hunt_scale`. The mean_chroma signal is
already embedded. Automating CHROMA_STRENGTH by a function of mean_chroma would double-dip:
mean_chroma is already the base, and squaring its influence would aggressively suppress chroma
lift in already-colorful scenes beyond what the Hunt model supports.

### Scene-descriptive target

The valid remaining signal is **scene key** (`PercTex.g`, p50). This is NOT already used in the
chroma_str computation. The Hunt effect connection:

- Higher p50 (brighter scene key) → increased chromatic adaptation → perceived saturation is
  higher at same physical chroma → less artificial lift is needed.
- Lower p50 (dim / desaturated scene) → perceived saturation suppressed → more lift is
  beneficial to maintain colour appearance.

This is precisely the Hunt effect applied to the CHROMA_STRENGTH scalar, using a signal that is
orthogonal to the existing mean_chroma driver.

Stevens connection: a brighter adaptation also increases apparent contrast (Stevens effect), which
perceptually "carries" some of the saturation perception — supporting the same direction of
correction.

### Proposed formula

```hlsl
// perc.g is p50, already loaded: float4 perc = tex2D(PercSamp, float2(0.5, 0.5));
// zone_log_key already loaded at grade.fx:233 from ChromaHistoryTex col 6
// Hunt is partially encoded in hunt_scale, but hunt_scale uses zone_log_key (geometric mean
// of zone medians), not the global p50. These are correlated but not identical.
// p50 is the global median luma — a cleaner scene-key anchor for per-scene adaptation.

float auto_chroma_str = lerp(1.15, 0.65, smoothstep(0.20, 0.60, perc.g));
// Replace CHROMA_STRENGTH with auto_chroma_str
float chroma_str = saturate(0.085 * chroma_exp * hunt_scale * auto_chroma_str);
```

Behaviour:
| p50   | auto_chroma_str | Scene character            |
|-------|----------------|----------------------------|
| 0.10  | ≈ 1.15         | Dark key (fog, night)      |
| 0.20  | 1.15           | Dark threshold             |
| 0.35  | ≈ 0.95         | Normal mid-key             |
| 0.50  | ≈ 0.75         | Bright-key outdoor         |
| 0.60+ | 0.65           | Bright ceiling             |

The current CHROMA_STRENGTH 0.9 sits between the endpoints, consistent with Arc Raiders
mid-key tuning. `creative_values.fx` can retain `CHROMA_STRENGTH` as an artistic ceiling:
`auto_chroma_str = CHROMA_STRENGTH * lerp(1.28, 0.72, smoothstep(0.20, 0.60, perc.g));`
(normalised so 0.9 × 1.28 ≈ 1.15, 0.9 × 0.72 ≈ 0.65).

### Literature support

No web search available. Psychophysical grounding:
- **Hunt effect** (Hunt, 1952; also Fairchild 2013 Chapter 9): colorfulness of a stimulus
  increases with adaptation luminance. A p50-driven rollback of CHROMA_STRENGTH is the correct
  direction: higher adaptation → less supplemental lift needed.
- **CIECAM02 / Oklab**: the existing `hunt_scale` uses `zone_log_key` (geometric mean of 16
  zone medians). The global p50 captures flat-scene vs. high-key transitions in a way that
  zone_log_key may miss (zone_log_key is Kalman-smoothed over zone patches, not a true global
  percentile). The two signals are complementary, not redundant.
- **Stevens effect** (Stevens & Stevens, 1963): supports the same direction on chroma as on
  contrast (see SHADOW_LIFT above). Brighter adaptation → less supplemental colour enhancement
  needed.

### Risk

**Moderate-low.** The proposed driver (p50) is orthogonal to mean_chroma, so there is no
mathematical double-dipping. However, p50 and mean_chroma are empirically correlated in many
game scenes (bright outdoor = more colour, dark interior = less colour), which means the
correction and the existing chroma_exp term will both move in the same direction for common
scenes — reinforcing each other more than expected. In pathological cases (bright but very
desaturated scene, e.g., overexposed white sky), p50 will suppress lift while mean_chroma will
suppress it further, potentially under-saturating.

Risk mitigation: retain CHROMA_STRENGTH as a per-game ceiling so the user can override if a
specific game breaks the assumption.

### Verdict: **NEEDS-MORE-DATA — conceptually sound but empirically unvalidated. Lower priority than SHADOW_LIFT.**

---

## Stevens + Hunt as automation anchor

### Assessment

Both effects are already partially implemented in the current pipeline:

- **Stevens effect**: `grade.fx:135` — `float stevens = (1.48 + sqrt(max(p50, 0.0))) / 2.03;`
  This is applied to the `factor` multiplier in `FilmCurve`, boosting shoulder compression at
  higher scene keys. It is a direct Stevens implementation for the contrast curve.

- **Hunt effect**: `grade.fx:335-342` — full CIECAM02-style `fl` computation using `zone_log_key`
  as the adaptation luminance. `hunt_scale = sqrt(sqrt(fl)) / 0.5912` then scales `chroma_str`
  at line 355.

**Should p50 drive CLARITY and CHROMA directly?**

- For CLARITY: already handled by Retinex blend via zone_std. p50 would be a secondary axis but
  is not needed given the existing automation.
- For CHROMA: a p50-based Hunt override on CHROMA_STRENGTH is the most defensible remaining
  automation. The existing `hunt_scale` uses zone_log_key (a spatial geometric mean) while p50
  is a true global percentile. They are correlated but measure different things. p50 is a
  meaningful second axis.

**Recommendation:** Use p50 as the CHROMA_STRENGTH automation anchor (as proposed above) rather
than as a CLARITY anchor. The SHADOW_LIFT p25 anchor (different percentile) is also
non-redundant with p50. Together these two automations provide a complete scene-key-driven
picture for the two remaining candidates:

```
p25 → SHADOW_LIFT magnitude (dark-shadow population drives how much toe lift is needed)
p50 → CHROMA_STRENGTH scalar (scene key drives how much supplemental saturation is needed)
```

This is a psychophysically clean separation: p25 governs shadow behaviour, p50 governs colour
appearance — consistent with the literature's treatment of these as independent adaptation axes.

---

## Implementation priority

| Knob              | Confidence | Risk       | Recommended order | Rationale                                                       |
|-------------------|------------|------------|-------------------|-----------------------------------------------------------------|
| CLARITY_STRENGTH  | N/A        | N/A        | REJECT            | Knob absent; Retinex + CLAHE already handle it                  |
| DENSITY_STRENGTH  | N/A        | N/A        | REJECT            | Knob absent; density_str already automated via mean_chroma      |
| SHADOW_LIFT       | Medium     | Low        | 1st               | Single smoothstep on existing perc.r; no new texture reads      |
| CHROMA_STRENGTH   | Low-medium | Moderate   | 2nd               | Valid but empirical correlation with mean_chroma needs testing  |

---

## Notes on candidate sources and literature

Literature search was unavailable in this nightly session (no web access). The formulas above are
derived from psychophysical first principles (Weber–Fechner, Naka-Rushton, Stevens 1961, Hunt
1952, Land–McCann Retinex) and are consistent with the existing Stevens and Hunt implementations
already in grade.fx. A follow-up web-search session should query:

- arxiv.org: "scene-adaptive shadow lifting" "tone mapping shadow lift" "p25 luminance adaptation"
- IEEE Xplore: "Stevens effect tone mapping" (2024–2026) for contrast-luminance coupling
- ACM: "Hunt effect saturation adaptation SDR" (2024–2026)
- Specifically: any 2024–2026 refinements to CIECAM02 fl factor for SDR pipelines

These are the searches that would either validate the smoothstep anchor points (0.05–0.25 for
SHADOW_LIFT, 0.20–0.60 for CHROMA_STRENGTH) or provide empirically-fit replacements.

---

## Appendix — key code locations

| Symbol              | File            | Line  | Role                                          |
|---------------------|-----------------|-------|-----------------------------------------------|
| SHADOW_LIFT         | creative_values | 103   | Global scalar, currently 1.7                  |
| shadow_lift (local) | grade.fx        | 304   | Pixel-level expression using SHADOW_LIFT      |
| local_range_att     | grade.fx        | 303   | IQR-based suppression in high-contrast zones  |
| CHROMA_STRENGTH     | creative_values | 42    | Global scalar on chroma_str, currently 0.9    |
| chroma_exp          | grade.fx        | 354   | exp(-3.47 × mean_chroma) — primary driver     |
| hunt_scale          | grade.fx        | 342   | CIECAM02 fl → chroma multiplier               |
| chroma_str          | grade.fx        | 355   | Final chroma lift strength per pixel          |
| density_str         | grade.fx        | 356   | Already automated — no exposed knob           |
| perc (p25/p50/p75)  | grade.fx        | 229   | Loaded from PercTex — available for formulas  |
| stevens             | grade.fx        | 135   | Stevens effect already in FilmCurve           |
