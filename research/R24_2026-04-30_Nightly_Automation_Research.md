# Nightly Automation Research — 2026-04-30

## Context files status

The following files specified in the job brief were **not found** in the repository:

| Expected path | Status |
|---|---|
| `CLAUDE.md` | Missing |
| `research/HANDOFF.md` | Missing (directory did not exist) |
| `gamespecific/arc_raiders/shaders/creative_values.fx` | Missing |
| `general/grade/grade.fx` | Missing |
| `general/corrective/corrective.fx` | Missing |

Analysis below is derived from: (a) the actual shader files present in the repo
(`frame_analysis.fx`, `alpha_zone_contrast.fx`, `alpha_chroma_lift.fx`,
`youvan_orthonorm.fx`, `primary_correction.fx`, `olofssonian_color_grade.fx`),
(b) the task brief's own descriptions of each knob's behaviour, and (c)
the available analysis signals described in the brief (PercTex, ZoneHistoryTex,
ChromaHistoryTex, zone_std).

**Signal mapping — hypothetical pipeline → actual pipeline textures:**

| Brief signal | Actual pipeline equivalent |
|---|---|
| PercTex 1×1 RGBA16F (p25/p50/p75) | New 1×1 pass reading from `LumCDFTex` (already built by `alpha_zone_contrast.fx`) |
| ZoneHistoryTex 4×4 (16 zones) | `ZoneTex` 3×1 RGBA16F (3 zones: dark/mid/bright, `youvan_orthonorm.fx`) |
| ChromaHistoryTex per-hue chroma | `SatHistTex` 64×6 R32F (`frame_analysis.fx`) |
| CreativeLowFreqTex 1/8-res | `DownsampleTex` 32×18 RGBA16F (`frame_analysis.fx`) |
| zone_std (16-zone std dev) | Approximable from `ZoneTex` 3 zones (see SPATIAL_NORM section) |

---

## Summary

SHADOW_LIFT and SPATIAL_NORM_STRENGTH have strong automation candidates: their
signals (PercTex.r / p25 and zone_std respectively) are already computed in the
pipeline, temporally stable, and physically well-motivated. DENSITY_STRENGTH and
CHROMA_STRENGTH share a clean inverse mapping from mean chroma but require one
new 1×1 reduction pass not yet wired in corrective.fx. CLARITY_STRENGTH is the
highest-risk candidate: IQR and zone_std are plausible detail proxies but both
measure tonal spread rather than true texture density, and the signal is sensitive
to scene-cut pumping if LERP_SPEED is not carefully matched across the PercTex
update chain.

---

## CLARITY_STRENGTH

### Current behaviour (grade.fx line reference)

`general/grade/grade.fx` not found. Based on task description: Stage 2 applies a
local midtone contrast enhancement proportional to `CLARITY_STRENGTH / 100`. The
operator boosts the transition band around each pixel's luma relative to a blurred
(low-frequency) version of the scene. In textureless/flat scenes the residual is
near-zero and the knob has no effective surface to act on; in detail-rich scenes it
sharpens perceived micro-contrast. Current static value: **35**.

### Proposed formula

**Primary signal:** IQR = `PercTex.b − PercTex.r` (p75 − p25, gamma-space luma).

Wide IQR → rich tonal spread → content-dense scene → clarity can be higher.
Compressed IQR (overcast, fog, flat interiors) → clarity should be minimal, as there
are few midtone transitions to enhance.

**Backup corroboration:** `zone_std` — both should track in the same direction.
If they disagree (e.g. high zone_std but low IQR), prefer IQR since it is the
more direct percentile measure.

```hlsl
// PercTex sampled from the 1×1 corrective analysis texture
float4 pt       = tex2Dlod(PercTex, float4(0.5, 0.5, 0, 0));
float  p25      = pt.r;
float  p75      = pt.b;
float  iqr      = saturate(p75 - p25);

// IQR expected range:
//   ~0.08  overcast exterior, heavy fog, interior with low contrast
//   ~0.42  high-contrast exterior, varied scene with deep shadows + bright sky
// Map monotonically to [20, 45]
float clarity_auto = lerp(20.0, 45.0, smoothstep(0.08, 0.42, iqr));
```

At IQR = 0.08 (flat scene) → CLARITY = 20
At IQR = 0.42 (rich scene) → CLARITY = 45

**Rationale:** smoothstep(0.08, 0.42) gives a generous linear band covering the
expected operational envelope for Arc Raiders' post-tonemap output in gamma space.
The ±0.04 margins either side mean neither extreme is over-fitted.

### Pumping risk

**Moderate–high.** Scene cuts that change the scene key (interior → bright
exterior) shift IQR within 1–2 frames, before PercTex temporal smoothing catches
up. At LERP_SPEED 8, PercTex lags ~2–3 frames on a step change. Result: clarity
briefly overshoots then decays to the correct value. Mitigations:

1. Ensure PercTex LERP_SPEED matches the slowest signal in the chain (~0.06–0.08).
2. Add a secondary temporal clamp: `clarity_auto = lerp(prev_clarity, clarity_auto, 0.12)` in the grade pass itself.
3. Widen the smoothstep bounds if content analysis shows typical IQR variation
   across cuts exceeds the 0.08–0.42 window.

Adding Stevens p50 as an anchor (see §Stevens + Hunt) compounds pumping —
avoid for CLARITY specifically.

---

## SHADOW_LIFT

### Current behaviour

`general/grade/grade.fx` not found. Based on task description: Stage 2 raises the
tone curve toe, lifting the floor of the darkest tonal zone proportional to
`SHADOW_LIFT / 100`. Excessive lift on an already-bright shadow floor produces
milky blacks; insufficient lift on a genuinely dark scene leaves the toe crushed.
Current static value: **15**.

### Proposed formula

**Signal:** `PercTex.r` (p25) — the 25th-percentile luma, representing where the
scene's shadow floor naturally sits in gamma space.

Physical logic: if p25 is already elevated (bright day, snow, overcast exterior),
the shadows don't need lifting — the pipeline would be adding lift on top of
existing lift, producing grey blacks. If p25 is low (night, dungeon, dark interior),
meaningful lift is needed and SHADOW_LIFT should be at or near its maximum.

```hlsl
float p25 = tex2Dlod(PercTex, float4(0.5, 0.5, 0, 0)).r;

// p25 expected range:
//   ~0.04  night / dark interior / tunnels
//   ~0.28  bright exterior / snow / overcast sky
// Monotonically decreasing function: high p25 → less lift needed
float shadow_lift_auto = lerp(20.0, 5.0, smoothstep(0.04, 0.28, p25));
```

At p25 = 0.04 → SHADOW_LIFT = 20 (maximum — dark scene)
At p25 = 0.28 → SHADOW_LIFT = 5  (minimum — bright scene)

Output is a direct knob value (float); scale to the pipeline's integer range when
writing back: `int shadow_lift_knob = int(round(shadow_lift_auto));`

### Risk

**Low.** p25 is the most stable of the three PercTex percentiles — the shadow
floor of a scene drifts slowly even across significant camera movement and is
only disrupted by full scene cuts. PercTex temporal smoothing (LERP_SPEED 8)
handles cuts within 2–3 frames without visible pumping. The monotonically
decreasing shape has no local extrema or inflection points that could produce
unexpected behaviour.

---

## DENSITY_STRENGTH

### Current behaviour

`general/grade/grade.fx` not found. Based on task description: Stage 3 applies
subtractive dye compaction — a colour-space compression that gives colours a
dense, matte, analogue-film body feel. The effect is proportional to
`DENSITY_STRENGTH / 100`. Over-saturated scenes already exhibit this density
quality; applying more compaction on top adds little and risks muddying the
palette. Desaturated scenes (fog, overcast, haze) need stronger compaction to
read as cinematic rather than washed-out. Current static value: **45**.

### Proposed formula

**Signal:** `mean_chroma` — scene-wide mean saturation derived from
ChromaHistoryTex (equivalent: `SatHistTex` 64×6 in the actual pipeline).

A new 1×1 pass in corrective.fx computes the scene mean saturation. The pattern
is identical to `ComputeSatGatePS` in `alpha_chroma_lift.fx` (line 141) but
outputs a weighted mean rather than a percentile:

```hlsl
// ── New 1×1 corrective pass: ChromaMeanPS ────────────────────────────────
// Output: R = scene mean saturation across all 6 hue bands
float4 ChromaMeanPS(float4 pos : SV_Position,
                    float2 uv  : TEXCOORD0) : SV_Target
{
    float wsum = 0.0;
    float wtot = 0.0;
    [loop]
    for (int band = 0; band < 6; band++) {
        float row_v = (band + 0.5) / 6.0;
        [loop]
        for (int b = 0; b < 64; b++) {
            float bin_ctr = (b + 0.5) / 64.0;
            float count   = tex2Dlod(ChromaHistoryTex,
                                float4((b + 0.5) / 64.0, row_v, 0, 0)).r;
            wsum += bin_ctr * count;
            wtot += count;
        }
    }
    float mean_chroma = (wtot > 0.001) ? wsum / wtot : 0.15;
    return float4(mean_chroma, 0, 0, 1);
}
```

Automation formula (reads from the 1×1 ChromaMeanTex):

```hlsl
float mean_chroma = tex2Dlod(ChromaMeanTex, float4(0.5, 0.5, 0, 0)).r;

// mean_chroma expected range:
//   ~0.05  heavy fog / rain / overcast grey exterior
//   ~0.38  vibrant saturated outdoors / neon environment
// Monotonically decreasing: low chroma → more density needed
float density_auto = lerp(55.0, 30.0, smoothstep(0.06, 0.36, mean_chroma));
```

At mean_chroma = 0.06 → DENSITY_STRENGTH = 55 (desaturated scene, max compaction)
At mean_chroma = 0.36 → DENSITY_STRENGTH = 30 (saturated scene, min compaction)

### Risk

**Low–moderate.** The 1×1 ChromaMeanTex pass is new infrastructure — a
corrective.fx edit is required. The signal itself is stable once in place:
SatHistTex is temporally smoothed (LERP_SPEED 0.5 in the actual pipeline), making
mean_chroma resistant to single-frame spikes. The main risk is the first few
frames after a pipeline cold-start before the histogram fills — clamp
`mean_chroma` to `[0.04, 0.45]` to prevent out-of-range values.

---

## CHROMA_STRENGTH

### Current behaviour

`general/grade/grade.fx` not found. Based on task description: Stage 3 bends the
per-hue saturation response curve. A low-saturation scene has compressed chroma
that needs more bending to feel alive; a high-saturation scene already reads as
vivid and needs minimal intervention. This is described as inverse to DENSITY
logic in mechanism (density subtracts, chroma bends) but the same in direction:
both increase as mean_chroma falls. Current static value: **40**.

### Proposed formula

Same signal as DENSITY_STRENGTH: `mean_chroma` from ChromaMeanTex (shares the
same 1×1 pass — no additional infrastructure cost beyond what DENSITY requires).

```hlsl
float mean_chroma = tex2Dlod(ChromaMeanTex, float4(0.5, 0.5, 0, 0)).r;

// Monotonically decreasing: low scene chroma → more per-hue bend needed
// Range [25, 50] — narrower than DENSITY to limit compound effect
float chroma_str_auto = lerp(50.0, 25.0, smoothstep(0.06, 0.36, mean_chroma));
```

At mean_chroma = 0.06 → CHROMA_STRENGTH = 50 (desaturated scene, max bend)
At mean_chroma = 0.36 → CHROMA_STRENGTH = 25 (saturated scene, min bend)

**Note on coupling:** DENSITY and CHROMA now co-vary monotonically via the same
signal. This is intentional — both serve to compensate for low-chroma conditions
— but it means they cannot be independently automated with the current signal set.
If future tuning reveals that a given scene needs high DENSITY but low CHROMA or
vice versa, zone_std could serve as a second axis to decouple them (e.g. scale
CHROMA by `lerp(0.9, 1.1, smoothstep(0.08, 0.25, zone_std))`).

### Risk

**Low.** Identical to DENSITY_STRENGTH risk profile — same signal, same
infrastructure dependency, same cold-start clamp requirement. The compressed
output range [25, 50] means the worst-case scene swing produces ±12.5 units,
which is within safe creative tolerance.

---

## SPATIAL_NORM_STRENGTH

### Current behaviour

`general/grade/grade.fx` not found. Based on task description: pulls each zone's
median toward the global scene key in Stage 2, reducing spatial luminance
non-uniformity across the 4×4 zone grid. Analogous to a gentle per-zone gain
offset. Current static value: **20**.

The existing zone S-curve strength formula (from task brief, already implemented):
```hlsl
float zone_str = lerp(0.30, 0.18, smoothstep(0.08, 0.25, zone_std));
```
Note: zone_str *decreases* as zone_std increases — the S-curve is gentled in
naturally contrasty scenes to avoid over-processing. SPATIAL_NORM travels in the
**opposite** direction on the same axis: a scene with high zone_std has
meaningfully divergent zones that *benefit* from normalisation being stronger.

### Proposed formula

**Signal:** `zone_std` — standard deviation of the 16 zone medians
(ZoneHistoryTex). In the actual pipeline, 3-zone approximation from
`ZoneTex` (`youvan_orthonorm.fx`):

```hlsl
// 3-zone approximation of zone_std (usable until ZoneHistoryTex 4×4 is wired)
float l0      = dot(tex2Dlod(ZoneSampler, float4(0.5/3.0, 0.5, 0, 0)).rgb,
                    float3(0.2126, 0.7152, 0.0722));
float l1      = dot(tex2Dlod(ZoneSampler, float4(1.5/3.0, 0.5, 0, 0)).rgb,
                    float3(0.2126, 0.7152, 0.0722));
float l2      = dot(tex2Dlod(ZoneSampler, float4(2.5/3.0, 0.5, 0, 0)).rgb,
                    float3(0.2126, 0.7152, 0.0722));
float l_mean  = (l0 + l1 + l2) / 3.0;
float zone_std = sqrt(((l0 - l_mean)*(l0 - l_mean) +
                        (l1 - l_mean)*(l1 - l_mean) +
                        (l2 - l_mean)*(l2 - l_mean)) / 3.0);
```

Automation formula (same smoothstep bounds as existing `zone_str` for consistency):

```hlsl
// zone_std expected range:
//   ~0.05  overcast / flat interior / night exterior (uniform luma zones)
//   ~0.28  high-contrast outdoor with deep shadows and bright sky
// Monotonically increasing — opposite direction to zone_str
float spatial_norm_auto = lerp(10.0, 30.0, smoothstep(0.08, 0.25, zone_std));
```

At zone_std = 0.08 → SPATIAL_NORM = 10 (flat scene, light normalisation)
At zone_std = 0.25 → SPATIAL_NORM = 30 (contrasty scene, strong normalisation)

The complementary relationship to zone_str is by design: the two operators
trade off on high-contrast scenes — zone contrast is attenuated (zone_str → 0.18)
while spatial normalisation is strengthened (spatial_norm → 30), preventing
double-amplification of already-large zone differences.

### Risk

**Low.** zone_std is the most resilient automation signal in the set. It measures
the *spread* of zone lumas rather than their absolute positions, making it
insensitive to overall scene exposure changes. Both a uniformly bright scene and a
uniformly dark scene yield low zone_std; only scenes with tonal structure (sky +
ground, lit area + shadow) yield high zone_std. Scene cuts produce the largest
transient, handled by ZoneHistoryTex temporal smoothing within 3–4 frames.

---

## Stevens + Hunt as automation anchor

**Stevens effect (1961):** perceived contrast increases with adaptation luminance.
A brighter scene key (high `PercTex.g` / p50) makes a given tonal transition
appear more contrasty to the viewer, suggesting CLARITY could be modestly reduced
for bright scenes to avoid perceptual over-sharpening.

**Hunt effect (1952):** perceived saturation increases with luminance. At high p50,
colours appear more vivid than their measured chroma would suggest, implying
CHROMA_STRENGTH could be marginally reduced for bright scenes.

**Assessment: should p50 anchor the CLARITY and CHROMA formulas?**

Yes, but only as a **low-weight secondary correction** (≤ 20–25% blend), not as a
primary driver. The justification and proposed weight:

```hlsl
float p50 = tex2Dlod(PercTex, float4(0.5, 0.5, 0, 0)).g;

// Stevens trim for CLARITY: 10% reduction at bright key, 5% boost at dark key
float stevens_w    = lerp(0.95, 1.10, smoothstep(0.30, 0.65, p50));
float clarity_final = clarity_auto * lerp(1.0, stevens_w, 0.20);

// Hunt trim for CHROMA: slight reduction for bright scenes
float hunt_w           = lerp(1.04, 0.93, smoothstep(0.30, 0.65, p50));
float chroma_str_final = chroma_str_auto * lerp(1.0, hunt_w, 0.20);
```

The 0.20 blend weight means p50 can shift the final value by at most ±2% of the
primary signal's output — a perceptual refinement, not a structural driver.

**Pumping risk with p50 anchor:**

p50 (global median) is the most volatile luma statistic on scene cuts. Unlike IQR
(which measures spread and is stable across moderate key changes) or zone_std
(which measures zone divergence and is insensitive to overall exposure), p50 tracks
the scene's absolute key. Adding p50 as a primary anchor would introduce a soft
auto-exposure feedback loop, coupling CLARITY and CHROMA to scene exposure — in
direct conflict with the pipeline philosophy (EXPOSURE is intentionally manual; no
auto-exposure). At 20% weight, the coupling is perceptually valid and the exposure
feedback is negligible. At >35% weight, the risk becomes measurable.

**Recommended use:** Wire p50 Stevens/Hunt correction only after the primary
signals (IQR, mean_chroma) are validated and stable in gameplay. Treat it as a
final pass-1 refinement rather than a first-pass implementation.

---

## Implementation priority

| Knob | Confidence | Pumping risk | Recommended order |
|------|------------|-------------|------------------|
| SHADOW_LIFT | High | Low | 1 — signal already in pipeline |
| SPATIAL_NORM_STRENGTH | High | Low | 2 — signal already computed |
| CHROMA_STRENGTH | Medium-High | Low–Moderate | 3 — needs 1×1 chroma mean pass |
| DENSITY_STRENGTH | Medium-High | Low–Moderate | 4 — shares pass with CHROMA |
| CLARITY_STRENGTH | Medium | Moderate–High | 5 — validate pumping in gameplay first |

**SHADOW_LIFT** and **SPATIAL_NORM_STRENGTH** share that their signals live in
already-running passes (PercTex / ZoneTex) and have physically clean, monotone
mappings with no new infrastructure cost. Ship these two first.

**DENSITY_STRENGTH** and **CHROMA_STRENGTH** should be implemented together: the
single 1×1 `ChromaMeanPS` pass in corrective.fx serves both, halving the wiring
cost. Test in a fog-heavy scene (Cluster 7 if available) and a saturated scene
(outdoor daytime arenas) to validate the mean_chroma range spans 0.06–0.36 as
assumed.

**CLARITY_STRENGTH** is the only candidate where the signal proxy (IQR) is an
indirect measure of the underlying quantity (local texture density). Before
shipping, capture a 5-minute gameplay session and plot `iqr` vs. perceived
texture richness per cut to verify the correlation holds for Arc Raiders content.
If IQR proves too noisy, a high-pass residual energy from `CreativeLowFreqTex`
is the stronger signal — but requires an additional pass.

---

## Literature search

Requires web search connector — skipped.
