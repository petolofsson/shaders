# R22 — Saturation by Luminance: Findings

**Date:** 2026-04-29
**Status:** Research complete — implementation ready

---

## 1. Internal Audit

**Current saturation-adjacent controls in Stage 3 (`grade.fx` lines 547–607):**

```hlsl
// Hunt-scaled chroma strength — scene-global luminance adaptation only
float la         = max(perc.g, 0.001);          // global scene median (p50)
float k          = 1.0 / (5.0 * la + 1.0);
float k4         = k * k * k * k;
float fl         = 0.2 * k4 * (5.0 * la) + 0.1 * (1.0 - k4) * (1.0 - k4) * pow(5.0 * la, 0.333);
float hunt_scale = pow(max(fl, 1e-6), 0.25) / 0.5912;
float chroma_str = saturate(CHROMA_STRENGTH / 100.0 * hunt_scale);

// Density — lightness reduction proportional to chroma gain above baseline
float delta_C   = max(final_C - C, 0.0);
float headroom  = saturate(1.0 - rmax_probe);
float density_L = saturate(final_L - delta_C * headroom * (DENSITY_STRENGTH / 100.0));
```

Three observations:

1. **`hunt_scale`** adjusts CHROMA_STRENGTH based on `perc.g` (global scene median luminance). This is a **scene-level** adaptation — every pixel receives the same scaling regardless of its individual luminance.

2. **`DENSITY_STRENGTH`** reduces lightness in proportion to chroma *gain over baseline*, weighted by available gamut headroom. This is not a chroma multiplier; it does not respond to the pixel's luminance level.

3. **`CHROMA_STRENGTH`** is a uniform per-hue saturation bend via `PivotedSCurve`. Luminance-agnostic.

**Gap:** A pixel in a deep shadow and a pixel in a midtone with identical linear-light chroma values receive identical treatment from all three systems. No mechanism reduces chroma in the toe or shoulder relative to midtones.

---

## 2. Literature & Physical Basis

### 2.1 Munsell Chroma Limits by Value

**Source:** Newhall, Judd & Nickerson 1943 renotation data (JOSA); `munsellinterpol` R package documentation (CRAN); Aurélien Pierre 2022 "Color saturation control for the 21st century" (eng.aurelienpierre.com); Wikipedia Munsell color system.

The Munsell renotation assigns each color a Value (V, 0–10, perceptual lightness) and Chroma (C, purity from 0). The maximum achievable Munsell chroma at each value level, for typical pigment hues within the sRGB gamut, is:

| Munsell V | Linear Y (approx) | Oklab L (approx) | Max Munsell C (typical) |
|-----------|-------------------|------------------|-------------------------|
| 1 | 0.011 | 0.22 | 2–6 |
| 2 | 0.030 | 0.31 | 6–10 |
| 3 | 0.067 | 0.41 | 8–14 |
| 4–6 | 0.13–0.33 | 0.51–0.69 | 10–18 (peak) |
| 7 | 0.46 | 0.77 | 10–16 |
| 8 | 0.59 | 0.84 | 8–14 |
| 9 | 0.74 | 0.91 | 4–10 |

*(Oklab L is cube-root of Y; Munsell V is non-linear: Y ≈ (V/10)^2.218)*

The curve is **right-skewed**: the shadow falloff is steeper than the highlight falloff. At V=1 (near-black, L_oklab ≈ 0.22), maximum chroma is less than 40% of the V=5 peak. The highlight falloff is gentler and is partly a gamut-boundary effect (sRGB cannot represent highly saturated near-white colors).

**Implication for threshold values:**
- Shadow rolloff begins meaningfully below V≈3, corresponding to Oklab L ≈ 0.40. The spec's linear ramp from L=0.25 targets only the deepest shadow region — conservative but correct for game footage (well-exposed content rarely has significant chroma below L≈0.25).
- Highlight rolloff begins around V≈7–8, corresponding to Oklab L ≈ 0.77–0.84. The spec's threshold of L=0.75 is appropriate.

**Rolloff shape:** The Munsell chroma limit near V=1 drops more steeply than linearly in Value. A `pow(saturate(1 - L/threshold), 2.0)` quadratic rolloff would more closely match the physical curve than the linear `saturate()`. However, for an explicitly controlled creative knob where the user sets magnitude directly, the linear form is sufficient. The difference between linear and quadratic is masked by the SHADOW_ROLLOFF knob itself.

### 2.2 Film Toe/Shoulder Chroma Behaviour

**Source:** AnalogCommunity Reddit discussion (density = log(exposure)); Darktable filmic RGB issue discussion; general film sensitometry literature.

In colour negative film, the characteristic curve of each dye layer (cyan, magenta, yellow) is a sigmoid with a toe (underexposure) and shoulder (overexposure). In the **toe**:
- Dye density is at minimum (D_min) — the base tint of the film base
- All three dye layers are at minimum together for pure black
- Underexposed scenes: fine shadow colour information compresses onto the toe, reducing colour differentiation

In the **shoulder**:
- All three dye layers approach maximum density together for overexposed whites
- The saturation of highlights collapses because the sigmoid for all three channels converges at the top

This is the physical origin of the film look: a gradual, luminance-dependent desaturation at both extremes, with maximum chroma in the midtones. The effect is continuous (not a hard threshold) and asymmetric (toe collapse is steeper than shoulder collapse for typical negative film).

### 2.3 Hunt Effect and Low-Luminance Chroma

**Source:** CIECAM02 (Luo & Li, cielab.xyz); Fairchild PAP45 (Hellwig 2022); Colorfulness (Wikipedia); ResearchGate CIECAM02 Hunt effect diagram.

The Hunt effect: colourfulness (M) increases with adapting luminance (LA). In CIECAM02:
```
FL = 0.2·k⁴·(5·LA) + 0.1·(1−k⁴)²·(5·LA)^(1/3)   where k = 1/(5·LA+1)
M  ∝ C·FL^0.25
```

At low LA (dim surround, as in deep shadow regions): FL is small → M is small → perceived colourfulness drops substantially relative to the stimulus chroma. From the CIECAM02 model at five chroma levels, ResearchGate Fig. 16 shows colourfulness predictions dropping roughly 3–5× as luminance falls from 100 cd/m² to 1 cd/m².

**Critical distinction:** Our pipeline already applies a GLOBAL Hunt correction via `hunt_scale = pow(FL, 0.25) / 0.5912`, which adjusts CHROMA_STRENGTH based on the scene's median luminance (`perc.g`). This is a scene-level correction — it sets the overall saturation depth for a given scene key. **R22 adds the per-pixel complement:** within any given scene, pixels in deep shadow receive a luminance-appropriate chroma reduction, independent of the scene's global key.

These are orthogonal: a bright scene (high global `hunt_scale`) with dark shadow regions needs R22 just as much as a dark scene.

### 2.4 ACES 2.0 Chroma Compression

**Source:** ACES documentation (draftdocs.acescentral.com/system-components/output-transforms/technical-details/chroma-compression/); CubiColor ACES 2.0 overview.

ACES 2.0 Output Transform performs chroma compression as a separate stage (after tonescale) in Hellwig JMh space:
1. **Compression** applies a toe function to all M values: suppresses chroma everywhere
2. **Expansion** re-expands shadows and midtones but **not highlights** — `c₁ = saturation·(1 − Jₜ/J_max)`, so the expansion coefficient approaches zero as J approaches J_max (highlight)

This is the industry consensus implementation of luminance-dependent chroma: keep shadow/midtone chroma, compress highlight chroma. R22 models this with two explicit knobs rather than a single coupled compression/expansion cycle, giving the user direct control over each region independently.

**Functional form:** The ACES expansion uses `c₂ = sqrt((Jₜ/J_max)² + threshold)` — essentially a smoothed absolute value that rounds the corner at zero. This is softer than the linear `saturate()` in the spec. However, for an SDR pipeline with an explicit magnitude knob, the simpler linear form is adequate.

---

## 3. Proposed Implementation

### Finding 1 — Two knobs in `creative_values.fx` [PASS]

```hlsl
// ── SATURATION BY LUMINANCE ───────────────────────────────────────────────────
// Rolls off chroma at the toe (shadows) and shoulder (highlights) in Oklab L space.
// Matches film dye-layer collapse: chroma is maximum in midtones, reduced at extremes.
// Both default 0 = no effect. Range 0–100.
// Shadow rolloff: full effect at L=0, fades to zero at L=0.25 (linear luma ≈0.016).
// Highlight rolloff: begins at L=0.75 (linear luma ≈0.42), full at L=1.0.
#define SAT_SHADOW_ROLLOFF     0
#define SAT_HIGHLIGHT_ROLLOFF  0
```

Recommended starting values after install: SAT_SHADOW_ROLLOFF=20, SAT_HIGHLIGHT_ROLLOFF=25. These produce a subtle effect visible on a grey ramp but nearly imperceptible on typical midtone game content.

### Finding 2 — Injection point in `ColorTransformPS`, Stage 3 [PASS]

**Exact location:** After `float h = OklabHueNorm(lab.y, lab.z);` (grade.fx line 550), before the FL/hunt_scale computation (line 552).

```hlsl
// R22: saturation by luminance — chroma rolloff at toe and shoulder
{
    float r22_sh = SAT_SHADOW_ROLLOFF    / 100.0 * saturate(1.0 - lab.x / 0.25);
    float r22_hl = SAT_HIGHLIGHT_ROLLOFF / 100.0 * saturate((lab.x - 0.75) / 0.25);
    C *= saturate(1.0 - r22_sh - r22_hl);
}
```

`lab.x` is the Oklab L component (`lab = RGBtoOklab(lin)`, line 548). It ranges [0,1] in perceptually linear space.

**Passthrough verification:** When both knobs = 0:
- `r22_sh = 0.0 / 100.0 * anything = 0.0`
- `r22_hl = 0.0 / 100.0 * anything = 0.0`
- `C *= saturate(1.0 - 0.0 - 0.0) = C *= 1.0`

C unchanged. Bitwise-identical passthrough. ✓

**Why before FL/hunt_scale:** Placing R22 here means all downstream operations — chroma lift `PivotedSCurve(C, ...)`, final_C computation, Abney, H-K, density — receive the luminance-adjusted C. This is correct: shadow chroma should be reduced before the pipeline decides how much to lift or correct it further.

### Finding 3 — Rolloff shape recommendation

**Linear is adequate for a creative knob.** If Munsell-accuracy is desired, replace the shadow term with:
```hlsl
float r22_sh = SAT_SHADOW_ROLLOFF / 100.0 * pow(saturate(1.0 - lab.x / 0.25), 2.0);
```
This matches the steeper Munsell V=1–2 drop more faithfully. Both forms are gate-free and SPIR-V-safe. The quadratic form's effective range is narrower (the peak magnitude is the same but it accelerates near L=0), so the same knob value produces a more concentrated effect in the very darkest pixels.

**Recommendation:** Start with linear. If the shadow rolloff feels too gradual on extreme darks, switch to quadratic — this can be decided during A/B testing rather than at implementation time.

---

## 4. SPIR-V Compliance

| Check | Result |
|-------|--------|
| No `static const float[]` | PASS — no arrays |
| No `static const float3` | PASS |
| No `out` as variable name | PASS — variables named `r22_sh`, `r22_hl` |
| No branches on pixel values | PASS — all `saturate()`, no `if` |
| `saturate()` as hard clamp | PASS — correct usage; `C *= saturate(...)` bounds C at original value |

---

## 5. Strategic Assessment

| Aspect | Assessment |
|--------|-----------|
| Physical basis | Munsell chroma limits (empirical), film dye-layer sigmoid toe/shoulder, Hunt effect (CIECAM02 FL^0.25) |
| Redundancy with DENSITY_STRENGTH | Orthogonal: density reduces L proportional to chroma GAIN weighted by gamut headroom; R22 directly multiplies C before any gain. Stacking both at typical values is not a problem at defaults (SAT_*_ROLLOFF=0). |
| Redundancy with hunt_scale | Complementary: hunt_scale is scene-global (based on perc.g); R22 is per-pixel within the scene. Neither subsumes the other. |
| HK interaction | Correct and desired: R22 reduces C → H-K boost (∝ C^0.587) automatically shrinks → no spurious brightening of near-black chromatic pixels |
| Chroma lift interaction | Reduced C entering PivotedSCurve pivots the saturation bend from a lower baseline. At very low C (deep shadows), the bend effect approaches zero anyway — natural, not an artefact |
| ACES precedent | ACES 2.0 confirms luminance-dependent chroma compression is industry-standard for complete display transforms. R22 is the SDR-pipeline equivalent with explicit user control. |
| New passes | None |
| New texture reads | None |
| Cost | 2 saturate + 1 multiply + 2 MAD — negligible |
| Gate-free | PASS |
| Thresholds (0.25 shadow, 0.75 highlight) | Supported by Munsell V=3 (L≈0.41 upper shadow limit) and V=7 (L≈0.77 highlight onset). Conservative: only the extremes are affected at default knob values. |
| Default passthrough | Algebraically verified: both knobs 0 → C unchanged |
