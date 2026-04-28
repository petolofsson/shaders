**Role:** Technical Research Lead & Shader Architect (AI Agent Mode)
**Task:** Use the **Brave Search MCP** to research luminance-dependent saturation behaviour in real film and human vision, and design a luma-driven saturation curve that complements the existing density and chroma systems in `grade.fx` without redundancy.

---

### 1. Contextual Audit (Internal)

**Scan files:** `general/grade/grade.fx`, `gamespecific/arc_raiders/shaders/creative_values.fx`

**Current saturation controls (Stage 3):**
```hlsl
// Density — uniform desaturation (subtractive dye, all luma levels equally)
float density = 1.0 - DENSITY_STRENGTH / 100.0 * density_curve;

// Chroma lift — per-hue saturation bend (independent of luminance)
float chroma_str = CHROMA_STRENGTH / 100.0;

// HK — saturation-driven lightness correction (not a saturation control per se)
float hk_boost = 1.0 + (HK_STRENGTH / 100.0) * f_hk * pow(final_C, 0.587);
```

None of these respond to the pixel's own luminance. A near-black pixel and a near-white pixel at the same chroma value receive identical treatment from all three systems.

**Gap:** Real film does not saturate at the extremes:
- In the toe (near-black): dye density approaches minimum — colours in deep shadow collapse toward neutral
- In the shoulder (near-white): all three dye layers converge at maximum density — highlights bleach toward white
- Midtones retain the most chroma

Human vision exhibits the same behaviour (Helmholtz-Kohlrausch and Hunt effects are midtone phenomena). The current pipeline's `saturate()` clamp at [0,1] hard-clips highlight chroma but does not soft-roll it off.

**Proposed mechanism:**
A luma-driven saturation multiplier applied to `C` before chroma operations:

```hlsl
// R22: saturation by luminance — roll off chroma at toe and shoulder
float luma_sat_scale = 1.0
    - SAT_SHADOW_ROLLOFF / 100.0 * saturate(1.0 - luma / 0.25)   // toe rolloff
    - SAT_HIGHLIGHT_ROLLOFF / 100.0 * saturate((luma - 0.75) / 0.25); // shoulder rolloff
C *= luma_sat_scale;
```

Two new knobs:
```
SAT_SHADOW_ROLLOFF    20   // 0–100; how much to desaturate near-black
SAT_HIGHLIGHT_ROLLOFF 25   // 0–100; how much to desaturate near-white
```

These operate on the `C` value in Oklab before density, chroma lift, and HK — so all three downstream operations see reduced chroma in the extremes automatically.

**Philosophy:** SDR, linear light. Gate-free — `saturate()` only, no conditionals. Monotone in luma (rolloff only increases with distance from midtone).

---

### 2. Autonomous Brave Search (The Hunt)

Search `colour.readthedocs.io`, `arxiv.org`, `journals.plos.org`, `cie.co.at`, `onlinelibrary.wiley.com` for:

- **Munsell chroma vs. value data:** The Munsell Book of Color provides empirical chroma limits at each value level. At value 1 (near-black) maximum chroma is ~2; at value 9 (near-white) it drops again. Find either the tabulated data or a polynomial fit to Munsell chroma limit as a function of value. This would provide ground-truth rolloff shape and magnitude.
- **Film toe/shoulder chroma collapse:** Any sensitometric paper characterising the chroma behaviour of negative film stocks in the toe and shoulder regions. Specifically: at what exposure level (stops below/above normal) does the cross-over saturation collapse begin, and is it symmetric?
- **Hunt effect luma dependency:** The Hunt effect states that colourfulness increases with luminance. This is the opposite of the shadow rolloff — at low luminance, perceived chroma drops. Find the quantitative Hunt model (FL exponent from CIECAM, or Nayatani 1995) and its predictions for shadow-region chroma correction in SDR display conditions.
- **Highlight chroma rolloff in display pipelines:** Any ACES or OpenColorIO documentation on how the Reference Rendering Transform (RRT) handles chroma compression in the shoulder. The RRT is known to desaturate highlights as part of its gamut compression — find the functional form.

---

### 3. Documentation

Output findings to `research/R22_saturation_by_luminance_findings.md`. Address:

- **Munsell chroma limits:** Provide the chroma limit as a function of Munsell value. Convert to approximate Oklab (L, C_max) coordinates. Does the data support a linear rolloff, a quadratic, or something steeper?
- **Rolloff shape:** Based on Munsell data and/or film sensitometry, what is the right functional form for the shadow and highlight rolloff? Is `saturate(1 - luma / threshold)` adequate, or does a smoothstep or power curve better match the data?
- **Threshold values:** At what luma level (in linear light, Oklab L) does the rolloff meaningfully begin in the shadows (toe) and highlights (shoulder)? Propose concrete threshold values for the `SAT_SHADOW_ROLLOFF` and `SAT_HIGHLIGHT_ROLLOFF` masks.
- **Redundancy with density:** `DENSITY_STRENGTH` desaturates uniformly. R22 desaturates at the extremes only. At default knob values, is there measurable overlap? If so, should default `DENSITY_STRENGTH` be lowered to compensate?
- **Redundancy with HK:** HK increases perceived brightness from chroma — at the shadow toe where chroma is now reduced, HK correction also diminishes automatically. Is this interaction correct (desired) or does it over-darken near-black chromatic regions?
- **Injection point:** Exact location in `ColorTransformPS` Stage 3, with line numbers.
- **SPIR-V viability:** PASS/FAIL — `saturate()` only, no static arrays, no conditionals.

---

### 4. Strategic Recommendation

Minimum viable implementation:
1. Add `SAT_SHADOW_ROLLOFF` and `SAT_HIGHLIGHT_ROLLOFF` to `creative_values.fx`
2. Compute `luma_sat_scale` from the pixel's pre-chroma luma (already available as `L = lab.x`)
3. Multiply `C` by `luma_sat_scale` before the density, chroma lift, and HK operations
4. Default values (20 shadow, 25 highlight) should produce a subtle effect comparable to viewing a calibrated monitor — noticeable on a grey ramp, invisible on typical midtone game content

If Munsell data confirms a steeper-than-linear rolloff, replace the linear `saturate()` mask with `pow(saturate(...), 2.0)` — still gate-free and SPIR-V safe.

**Constraint:** At default knob values (SAT_SHADOW_ROLLOFF = 0, SAT_HIGHLIGHT_ROLLOFF = 0), output must be bitwise-identical to current shader. The `luma_sat_scale` must equal exactly 1.0 when both knobs are zero — verify algebraically.
