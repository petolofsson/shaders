**Role:** Technical Research Lead & Shader Architect (AI Agent Mode)
**Task:** Use the **Brave Search MCP** to research the ASC CDL standard and per-channel primary grade implementations, then design a 3-way color corrector (Lift / Gamma / Gain per channel) that integrates cleanly into the existing `grade.fx` pipeline.

---

### 1. Contextual Audit (Internal)

**Scan files:** `general/grade/grade.fx`, `gamespecific/arc_raiders/shaders/creative_values.fx`

**Current primary controls:**
```hlsl
// Stage 1 — CORRECTIVE
float3 lin = FilmCurve(pow(max(col.rgb, 0.0), EXPOSURE), eff_p25, zone_log_key, eff_p75);
```
`EXPOSURE` is a single gamma applied identically to R, G, B before FilmCurve. No per-channel control.

```hlsl
// Stage 2 — TONAL (shadow lift, creative_values.fx)
#define SHADOW_LIFT 16  // raises all channels equally
```
Global lift. No per-channel color balance in shadows.

**Gap:** There is no mechanism to independently control color balance at shadows, midtones, or highlights. Warming highlights requires equally warming shadows. Cooling blacks tints the whole image.

**Proposed knob surface (temp/tint axes, 6 new knobs + 1):**
```
SHADOW_TEMP     0   // warm/cool shadows: +100=warm (R up, B down), -100=cool
SHADOW_TINT     0   // green/magenta shadows: +100=magenta, -100=green
MID_TEMP        0   // warm/cool midtones
MID_TINT        0   // green/magenta midtones
HIGHLIGHT_TEMP  0   // warm/cool highlights
HIGHLIGHT_TINT  0   // green/magenta highlights
HIGHLIGHT_GAIN  100 // master highlight level (100=neutral; complements EXPOSURE)
```

Temperature axis: R + δ, B − δ (and inverse). Tint axis: G + δ, (R+B) − δ/2.
These are the standard two-axis decomposition of a 3-channel gain/offset used in DaVinci Resolve's color wheels.

**Pipeline insertion point:** Stage 1, immediately before `FilmCurve`, operating on the post-`pow(rgb, EXPOSURE)` linear signal. Primary correction precedes tone curves in all professional pipelines.

**Luminance masks for region isolation:**
- Shadows mask: `saturate(1.0 - luma / 0.35)` — full weight at black, zero at 0.35
- Highlights mask: `saturate((luma - 0.65) / 0.35)` — full weight at white, zero at 0.65
- Midtones mask: `1.0 - shadow_mask - highlight_mask`

These must be smooth, monotone, and gate-free (no conditionals).

**Philosophy:** SDR, linear light, vkBasalt post-process. Output must remain [0,1]. No gates on pixel properties. EXPOSURE and SHADOW_LIFT remain as master-level controls; new knobs add color balance only.

---

### 2. Autonomous Brave Search (The Hunt)

Search `acescentral.com`, `github.com/ampas/aces-dev`, `docs.acescentral.com`, `colour.readthedocs.io` for:

- **ASC CDL specification:** Slope / Offset / Power formulation. Is `(x * Slope + Offset)^Power` the canonical form? How does it relate to Lift/Gamma/Gain? What are the standard range constraints on each parameter?
- **Temp/tint decomposition:** How does DaVinci Resolve internally decompose color wheel XY position into per-channel lift/gamma/gain? Is there a published or reverse-engineered formula? Any 2020–2026 paper or technical note on the two-axis parameterization.
- **Region mask shape:** Are there published luminance mask shapes for shadow/mid/highlight isolation that avoid halos or abrupt transitions? Search "primary grade luminance mask shape sigmoid" and "tonal zone masking color grading 2022–2026".
- **Oklab vs. linear RGB primary grade:** Any 2022–2026 work on whether primary corrections should be applied in linear RGB or a perceptual space (Oklab, IPT) for better hue stability. Specifically: does a temperature shift in linear RGB produce a hue shift at high saturation, and does Oklab avoid this?

---

### 3. Documentation

Output findings to `research/R19_3way_color_corrector_findings.md`. Address:

- **ASC CDL delta:** Is Slope/Offset/Power the right formulation, or is an additive offset + power model (Lift/Gamma/Gain) better for our SDR context? Define the exact per-channel math.
- **Temp/tint formula:** Provide the RGB delta expressions for a unit temperature step and a unit tint step. Confirm they are hue-stable in linear light at sRGB primaries.
- **Mask shapes:** Propose the shadow/mid/highlight luminance mask functions. Verify they sum to 1.0 at every luma value (partition of unity) to prevent brightness shift from the corrector itself.
- **Oklab question:** Should the correction be applied in linear RGB (before Oklab conversion) or in Oklab LCh (in the chroma stage)? Assess hue shift risk in linear RGB.
- **Injection point:** Exact location in `ColorTransformPS` (line numbers in current `grade.fx`).
- **Knob defaults and ranges:** Confirm ±100 for temp/tint, 0–200 for HIGHLIGHT_GAIN. Are the default-zero temp/tint values truly neutral (no output change)?
- **SPIR-V viability:** PASS/FAIL — no `static const float[]`, no reserved keywords, no branches on pixel values.

---

### 4. Strategic Recommendation

Minimum viable implementation:
1. Add 6 temp/tint knobs to `creative_values.fx` (default 0 = passthrough)
2. Compute per-channel delta from temp/tint values: `float3 col_delta = float3(temp - tint*0.5, tint, -temp - tint*0.5) * strength`
3. Apply masked: `lin += shadow_delta * shadow_mask + mid_delta * mid_mask + hl_delta * hl_mask`
4. `saturate()` after application — no values can escape [0,1] if deltas are bounded

HIGHLIGHT_GAIN deferred to a second pass — assess whether EXPOSURE already covers this sufficiently.

**Constraint:** All 6 new knobs must default to exactly neutral (zero output change). The corrector must be a strict passthrough when all knobs are at default. No new texture reads or passes.
