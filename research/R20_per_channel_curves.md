**Role:** Technical Research Lead & Shader Architect (AI Agent Mode)
**Task:** Use the **Brave Search MCP** to research per-channel curve differences in real film stocks from sensitometric data, and design a minimal per-channel curve offset system that adds cross-channel tonal contrast to the existing `FilmCurve` in `grade.fx`.

---

### 1. Contextual Audit (Internal)

**Scan files:** `general/grade/grade.fx`, `gamespecific/arc_raiders/shaders/creative_values.fx`

**Current FilmCurve (grade.fx, Stage 1):**
```hlsl
float3 FilmCurve(float3 x, float p25, float p50, float p75, float spread_scale)
{
    float knee     = lerp(0.90, 0.80, saturate((p75 - 0.60) / 0.30));
    float width    = 1.0 - knee;
    float stevens  = (1.48 + sqrt(max(p50, 0.0))) / 2.03;
    float factor   = 0.05 / (width * width) * stevens * spread_scale;
    float knee_toe = lerp(0.15, 0.25, saturate((0.40 - p25) / 0.30));
    float3 above   = max(x - knee,     0.0);
    float3 below   = max(knee_toe - x, 0.0);
    return x - factor * above * above
               + (0.03 / (knee_toe * knee_toe)) * below * below;
}
```
Called with identical R, G, B values in `x`. The function returns a float3 but applies the **same knee, toe, and factor** to all three channels. The cross-channel contrast that characterises real film stocks — where the red layer compresses differently from the blue at the shoulder — is absent.

**Current film presets (creative_values.fx):**
Each preset defines `WHITE_*`, `FILM_*`, `TOE_TINT_*`, `SHADOW_TINT_*`, `HIGHLIGHT_TINT_*` via `#define`. These apply additive tints at the grade stage (Stage 4) but do not alter the FilmCurve shape per channel.

**Gap:** A Kodak Vision3 frame has its cyan layer (red channel) compressing earlier in the shoulder than the magenta/yellow layers. This creates warm highlights and cool shadows — the cross-over. Today's pipeline fakes this via additive tints (R17) but does not model it as a curve difference, which is what it physically is.

**Proposed approach:** Add per-preset, per-channel curve offsets that shift the `knee` and `knee_toe` positions independently for R and B (G is the reference). Small deltas — on the order of ±0.03 to ±0.06 — are enough to produce visible cross-channel contrast.

```
// Per-preset channel curve offsets (hardcoded in creative_values.fx per preset block)
CURVE_R_KNEE_OFFSET   // shifts R shoulder earlier (<0) or later (>0) than G
CURVE_B_KNEE_OFFSET   // shifts B shoulder
CURVE_R_TOE_OFFSET    // shifts R toe
CURVE_B_TOE_OFFSET    // shifts B toe
```
G channel remains the FilmCurve reference. These are internal to the preset, not user-facing knobs.

**Philosophy:** SDR, linear light. No new passes. No gates. Offsets must keep `knee` and `knee_toe` in valid ranges.

---

### 2. Autonomous Brave Search (The Hunt)

Search `kodak.com`, `scientifico-research.com`, `filmscanner.info`, `arxiv.org`, `cinematography.net` for:

- **Kodak Vision3 500T characteristic curves:** Per-layer (cyan/magenta/yellow) D-log E curves. Target: the gamma differences between layers in the straight-line region and the relative shoulder position of the cyan vs. magenta/yellow layers. Kodak publication H-1 or equivalent sensitometric spec sheets.
- **Fuji Eterna / Fuji 500T per-layer data:** Same — looking for the magnitude of inter-layer gamma difference and whether Fuji's cross-over is subdued relative to Kodak (industry consensus says yes).
- **ARRI LogC channel balance:** Any published data on ARRI sensor's per-channel response in the ALEXA log space. Is the cross-channel contrast in ARRI footage primarily from the sensor or from grading?
- **Sony Venice color science:** Published Venice color gamut/matrix documentation. Per-channel curve characteristics vs. Vision3.
- **Cross-over magnitude in SDR:** Search "film cross-over knee offset SDR" and "per-channel tone curve film emulation 2022–2026". Any shader implementation that derives per-channel knee positions from sensitometric data rather than additive tints?

---

### 3. Documentation

Output findings to `research/R20_per_channel_curves_findings.md`. Address:

- **Sensitometric data:** For each of the 4 film presets (Vision3, Eterna, ARRI, Venice), provide the best available estimate of the per-layer gamma difference (Δγ between red and blue layers) and the relative shoulder position offset (how many stops earlier/later the cyan layer compresses vs. magenta).
- **Knee offset derivation:** Convert Δγ and shoulder offset from sensitometric space to our `knee` parameter space (0.80–0.90 range). Provide a concrete CURVE_R_KNEE_OFFSET and CURVE_B_KNEE_OFFSET value for each preset.
- **Interaction with R17 tints:** Per-channel curve offsets and additive tints both produce warm-highlight / cool-shadow effects. Quantify the overlap — will enabling per-channel curves require reducing TINT_ADAPT_SCALE to avoid double-application of the cross-over?
- **Injection point:** Modified `FilmCurve` signature and call site in `ColorTransformPS`.
- **SPIR-V viability:** PASS/FAIL — confirm knee clamping keeps output bounded, no static arrays.
- **Confidence level:** Sensitometric PDFs may be binary-encoded (noted in R17 research). Document what data was accessible and what was estimated from community sources.

---

### 4. Strategic Recommendation

Minimum viable implementation:
1. Modify `FilmCurve` to accept `float r_knee_off, float b_knee_off, float r_toe_off, float b_toe_off`
2. Apply channel-specific knee and toe: `float knee_r = clamp(knee + r_knee_off, 0.70, 0.95)`
3. Compute `above` / `below` per-channel using their respective knee/toe values
4. Preset blocks in `creative_values.fx` define the 4 offsets as `#define` constants — not user-facing

If sensitometric data is inaccessible, fallback: derive offsets by matching against known reference images for each stock (e.g. Kodak's published sample reels), using the cross-over colour temperature as the calibration target.

**Constraint:** G channel is always the unmodified reference. R and B offsets must be symmetric enough that a neutral grey input still outputs neutral grey (equal R=G=B in → equal R=G=B out). Verify this algebraically before implementing.
