# Nightly Automation Research — 2026-04-30

## Summary

Two knobs remain in `creative_values.fx` as user-facing `#define`s: `CLARITY_STRENGTH`
(35) and `HALATION_STR` (0.18). `SHADOW_LIFT`, `DENSITY_STRENGTH`, and `CHROMA_STRENGTH`
have already been automated (confirmed in grade.fx and creative_values.fx). This report
derives automation formulas for both remaining candidates, reviews Stevens + Hunt effects
as psychophysical anchors for clarity, and assigns implementation priority.

---

## CLARITY_STRENGTH

### Current behaviour

`CLARITY_STRENGTH` appears in two places in `grade.fx`:

1. **Luma detail injection** (Stage 2, Tonal):
   ```hlsl
   new_luma = saturate(new_luma + detail * (CLARITY_STRENGTH / 100.0) * bell * clarity_mask);
   ```
   `detail` is the wavelet D1 band (pixel − mip0 low-freq). `bell` is a Lorentzian
   suppressor (`1 / (1 + detail² / 0.0144)`) that limits over-sharpening on coarse
   edges. `clarity_mask` is a midtone window `smoothstep(0.0, 0.2, luma) * (1 − smoothstep(0.6, 0.9, luma))`.

2. **Chroma detail boost** (Stage 3, Chroma):
   ```hlsl
   float final_C = max(lifted_C, C) * (1.0 + abs(detail) * (CLARITY_STRENGTH / 100.0) * 0.25);
   ```
   Adds 25% of the luma detail signal to chroma amplitude — keeps colour texture
   consistent with luma texture after the clarity lift.

The effect is a local midtone contrast / microcontrast tool analogous to "clarity" in
Lightroom or Davinci's softness. At CLARITY_STRENGTH = 35 it is film-like; above 50 it
reads as digital sharpening.

### Proposed formula

**Driver:** `iqr = perc.a` (global luma IQR, already available from PercTex) combined
with `zone_std` (already in registers at Stage 2 from ChromaHistoryTex col 6). Both
describe scene contrast spread.

The Stevens effect states that apparent contrast grows with adaptation luminance (p50).
Scenes with a high p50 already appear contrasty to the HVS; injecting additional clarity
would over-sharpen them. Scenes with a depressed p50 (indoor, night) need more support.

```hlsl
// Proposed auto-clarity — computed once at the top of ColorTransformPS
float p50         = perc.g;                          // global median luma
float iqr         = perc.a;                          // interquartile range
// Stevens anchor: bright scenes need less clarity (HVS already perceives more contrast)
float stevens_att = smoothstep(0.35, 0.65, p50);     // 0 = dark scene, 1 = bright scene
// Contrast spread: flat scenes need less clarity (no detail to amplify)
float spread_att  = smoothstep(0.04, 0.20, iqr);     // 0 = flat, 1 = full-range
// Base target [20..42]: dark + contrasty → 42, bright or flat → 20
float auto_clarity = lerp(42.0, 20.0, saturate(stevens_att * 0.6 + (1.0 - spread_att) * 0.4));
```

The blend weights (0.6 / 0.4) express that p50-via-Stevens is the stronger predictor of
over-sharpening risk; IQR is a secondary guard for near-empty-histogram flat scenes.

Range stays within [20, 42] — comfortably inside the "film-like" zone. The knob `CLARITY_STRENGTH`
is removed from `creative_values.fx` and replaced by `auto_clarity` at the usage sites.

**Scene-cut safety:** Both p50 and IQR are Kalman-smoothed upstream (VFF Kalman in
`SmoothZoneLevelsPS` and `UpdateHistoryPS`). Scene-cut `Q_vff` rises to 0.10 and K
approaches 0.91, so auto_clarity tracks within ~2 frames on hard cuts — negligible.

### Literature support

- **Stevens + Hunt (Wanat & Mantiuk, 2014, Cambridge):** Formalise that both Stevens
  (contrast up with luminance) and Hunt (chroma up with luminance) are surround-dependent.
  The paper demonstrates retargeting via CIECAM02 forward/inverse at different Yabs.
  Directly supports using p50 as an adaptation luminance proxy for scaling perceptual
  clarity demand.

- **Aurelien Pierre 2022 / CIECAM16 exposition:** The Stevens exponent is encoded in the
  `cz` term of CIECAM16 lightness. Under typical SDR viewing conditions `cz ≈ 1` (neutral),
  but the framework shows that any deviation of background relative luminance from 0.20
  shifts perceived contrast — i.e., dark-biased scenes (p50 < 0.35) have `n < 0.2`,
  pushing `cz > 1` and increasing apparent contrast demand. Supporting the lower boundary
  of the auto-clarity formula.

- **MSACE (JISEM 2024):** Multi-Scale Adaptive Contrast Enhancement. Demonstrates that
  adaptive contrast strength tied to local luminance statistics outperforms fixed-strength
  methods on diverse scenes. Confirms that a single user-set constant underperforms
  scene-adaptive scaling.

- **MDPI Mathematics 2025 (Optica AO-64-13-3502):** Adaptive histogram gamma correction
  that preserves mean luminance while scaling local contrast — methodology analogous to
  using IQR as a spread signal to gate clarity injection.

### Risk

1. **Pumping on scene cuts:** Mitigated by VFF Kalman (K_inf ≈ 0.095 steady-state; K rises
   on cut). Watch for 2–3 frame clarity surge after abrupt light-to-dark transitions.
2. **Over-attenuation on dark cinematic sequences:** If p50 stays low for extended periods
   (caves, cutscenes), auto-clarity may park at 42 and feel over-sharpened on textureless
   dark surfaces. Mitigation: the `bell` Lorentzian in grade.fx is the true edge brake;
   auto_clarity is the global amplitude knob. The Lorentzian provides a per-pixel
   safety net independent of the global value.
3. **Two-site usage:** Both luma and chroma clarity uses must be updated. The chroma site
   scales at 0.25 of the luma strength — this ratio is internal and not exposed, so no
   change needed there.
4. **IQR proxy quality:** PercTex `.a` is stored as IQR = p75 − p25, computed in
   `analysis_frame.fx`. If analysis_frame is on a separate EMA (not VFF Kalman), IQR may
   lag on cuts slightly differently than p50. Verify EMA vs Kalman status in
   `analysis_frame.fx` before implementing.

---

## HALATION_STR

### Current behaviour

`HALATION_STR` is defined as `0.18` in `creative_values.fx` and listed under the CHROMA
section with the comment: "warm glow from bright highlights (film emulsion scatter). Red
scatters widest, blue narrowest — warm orange bloom by construction. 0.0 = off,
0.18 = subtle film look, 0.35 = pronounced."

The knob exists in `creative_values.fx` but `HALATION_STR` is **not yet referenced in
`grade.fx`**. The HANDOFF notes "Halation — not yet built." This means the knob is a
forward declaration with no implementation. It cannot be automated until it is implemented.
However, the automation formula can be designed now so that both implementation and
automation land in a single commit.

### Physical basis

Film halation is caused by light penetrating the anti-halation layer at the film base,
reflecting back through the red-sensitive layer (red scatters furthest). Strength is
proportional to highlight luminance — more photons above the exposure threshold reach the
base layer. Colour (warm orange) is fixed by physics, not scene content. The appropriate
driver is therefore: **how many pixels are in the highlight zone** and **how bright they
are on average** — both available from zone stats.

### Proposed formula

```hlsl
// Auto halation strength — computed once at top of ColorTransformPS
// zmax = brightest zone median (ChromaHistoryTex col 6, .a)
// eff_p75 = lerp(perc.b, zstats.a, 0.4) — already in registers
float highlight_load = smoothstep(0.55, 0.85, eff_p75);   // how bright are highlights
float auto_hal = lerp(0.0, 0.22, highlight_load);
// Flat/dark scenes: no halation (nothing to scatter)
// Bright scenes: up to 0.22, slightly above the default 0.18 to preserve intent
```

Why `eff_p75` rather than `zmax`? `zmax` is the max zone median — it can spike on a single
bright zone (e.g., a sunlit window) and cause halation to suddenly ramp. `eff_p75` is a
global 75th-percentile luma blended with zone max, smoother and more representative of
overall highlight energy across the frame.

Alternative: use a highlight pixel fraction derived from the zone histogram. Bins 24–31
of `CreativeZoneHistTex` sum to give fraction of pixels above ~75% luma. This is a more
direct physical correlate (more highlight pixels = more photons hitting base layer) but
requires 8 extra taps per frame in `ColorTransformPS`. Given the GPU budget constraint,
`eff_p75` (already in registers) is strongly preferred.

**Implementation note:** When halation is implemented in `grade.fx`, it will likely be a
per-pixel operation using `CreativeLowFreqTex` (mip 1 or 2) to approximate the scatter
blur. The auto strength simply replaces the constant `HALATION_STR` in that path with
`auto_hal`.

### Literature support

- **Digital Production / Dehancer (Jan 2024):** Confirms that halation strength is
  physically tied to how much light penetrates above the anti-halation layer — i.e., it
  is a function of highlight intensity, not a creative constant. Supports the highlight_load
  formula above.

- **Color Finale Blog (Nov 2024):** Notes that scatter is a function of light quantity
  reaching the base — implicitly a luminance threshold effect. Higher scene exposure = more
  visible halation.

- **Neural Bloom (arxiv 2409.05963, Karp 2024):** Proposes a brightness mask for real-time
  bloom (structurally related to halation) that is scene-adaptive. The mask is derived from
  a neural network but the signal is identical: highlight pixel luminance distribution.
  Validates the perceptual legitimacy of scene-adaptive bloom/halation strength.

- **Pixls.us Spektrafilm (andreavolpato/agx-emulsion):** Physically modelled halation
  distinguishes halation_size and halation_strength as independent parameters per channel.
  The strength is calibrated to film sensitivity — in our SDR context, sensitivity is
  fixed, so the only variable driver is highlight luminance energy.

### Risk

1. **Not yet implemented:** The knob exists but the halation pass does not. Risk of
   designing the automation formula for an implementation that does not yet exist. Mitigated
   by the fact that the formula is purely a scalar drive signal — independent of the
   implementation architecture.
2. **eff_p75 cross-talk with density_str:** `eff_p75` already drives the `chroma_adapt`
   path indirectly (through `mean_chroma`). A sudden bright scene will push both halation
   and chroma_str — desired, since bright scenes need both. No conflict.
3. **Dark-scene floor:** The `smoothstep(0.55, 0.85, eff_p75)` returns 0.0 for p75 < 0.55.
   In the darkest Arc Raiders scenes (interiors), halation goes to zero — correct physically,
   but may read as the effect being "off." Setting a small floor (0.03) could preserve a
   ghost of the effect for artistic continuity. Defer to Peter's call.
4. **GPU cost:** Auto_hal is a single `smoothstep` on a value already in registers. Zero
   additional taps. Negligible cost.

---

## Stevens + Hunt as automation anchors

### Stevens effect

Stevens (1961) demonstrated that the exponent of the brightness power function (perceived
brightness = k × luminance^β) increases with adaptation luminance. The practical
consequence: **scenes with high p50 appear more contrasty to the observer than their
linear values suggest** — so the pipeline need not apply as much additional clarity or
zone contrast to reach the same subjective result.

The pipeline already uses a Stevens correction inside `FilmCurve`:
```hlsl
float stevens = (1.48 + sqrt(max(p50, 0.0))) / 2.03;
float factor  = 0.05 / (width * width) * stevens * spread;
```
This modulates FilmCurve shoulder aggressiveness. Stevens is therefore already active
in Stage 1 as a contrast-scaling term.

**For CLARITY automation:** The same p50 → Stevens reasoning applies. A bright-adapted
scene (high p50) has more perceived contrast from the FilmCurve; adding full clarity
strength (35) on top over-delivers. The `auto_clarity` formula above attenuates by
`smoothstep(0.35, 0.65, p50)` — a direct implementation of Stevens-informed rolloff.

**Confidence:** High. Stevens effect is well-established (power law β ≈ 0.33 for
brightness). The existing FilmCurve usage demonstrates that the pipeline already accepts
Stevens as a design principle.

### Hunt effect

Hunt (1952) showed that perceived colorfulness increases with luminance. CIECAM02 and
CIECAM16 encode this via the `F_L` factor (luminance-dependent chromatic adaptation).

The pipeline implements the Hunt effect explicitly in Stage 3:
```hlsl
float la         = max(perc.g, 0.001);   // adaptation luminance = p50
float k          = 1.0 / (5.0 * la + 1.0);
float fl         = 0.2 * k4 * (5.0 * la) + 0.1 * (1 - k4)^2 * (5*la)^0.333;
float hunt_scale = pow(max(fl, 1e-6), 0.25) / 0.5912;
```
`hunt_scale` modulates `chroma_str`. This is a textbook `F_L` implementation.

**For CLARITY automation:** The Hunt effect is less directly relevant to clarity
(a luma-domain tool) than Stevens. However, Wanat & Mantiuk (2014) show that both
effects interact — bright-scene clarity boosts would compound the HVS's naturally elevated
chroma perception and risk an over-saturated, over-sharpened combined look. The dual
attenuation (clarity down + chroma auto-managed by Hunt/mean_chroma) is therefore
coherent: both knobs ease off in bright saturated scenes, reinforcing each other rather
than fighting.

**Recommended role:** Stevens as primary driver of `auto_clarity` amplitude (weight 0.6),
Hunt as a secondary cross-check — if `hunt_scale > 1.0` (bright adaptation), auto_clarity
could further attenuate by an additional `lerp(1.0, 0.85, saturate(hunt_scale - 1.0))`.
This is a refinement, not a requirement for the initial implementation.

---

## Implementation priority

| Knob | Status | Confidence | Risk | Recommended order |
|------|--------|-----------|------|-------------------|
| CLARITY_STRENGTH | Exists, implemented | High | Low-Med (IQR lag, audit analysis_frame EMA) | 1st |
| HALATION_STR | Exists, NOT implemented | Med | Med (needs halation pass first) | 2nd — implement halation pass + automation together |

**Recommended next commit sequence:**
1. Audit `analysis_frame.fx` — confirm IQR (PercTex.a) is Kalman or EMA, document lag.
2. Implement `auto_clarity` in `grade.fx`. Remove `CLARITY_STRENGTH` from `creative_values.fx`.
3. Design and implement the halation pass (single-pass, mip-based scatter using
   `CreativeLowFreqTex` mip 1). Wire `auto_hal` as the strength signal.

---

## Searches run

1. `Stevens power law apparent contrast adaptation luminance psychophysics 2024 2025`
2. `Hunt effect chroma adaptation luminance color appearance model 2024 2025`
3. `adaptive clarity local contrast enhancement scene luminance automatic real-time shader 2024 2025`
4. `halation film emulsion scatter simulation automatic strength HDR SDR tone mapping 2024 2025`
5. `Stevens Hunt effect color appearance model luminance adaptation automatic saturation clarity video games 2024`
6. `halation bloom highlight luminance threshold automatic pixel shader post-process perceptual 2024 2025`
