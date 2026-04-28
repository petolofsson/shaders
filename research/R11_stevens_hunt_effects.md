**Role:** Technical Research Lead & Shader Architect (AI Agent Mode)
**Task:** Use the **Brave Search MCP** to audit the Stevens and Hunt effect implementations in `grade.fx` against 2024–2026 psychophysical literature and propose mathematically grounded replacements.

---

### 1. Contextual Audit (Internal)

**Scan files:** `general/grade/grade.fx`, `gamespecific/arc_raiders/shaders/creative_values.fx`

**Current Stevens implementation** (`grade.fx`, FilmCurve call):
```hlsl
float stevens = lerp(0.85, 1.15, saturate((p50 - 0.10) / 0.50));
float factor  = 0.05 / (width * width) * stevens;
```
A linear ramp on scene median (p50). No adaptation luminance. No non-linearity. Coefficient range [0.85, 1.15] is empirical with no citation.

**Current Hunt implementation** (`grade.fx`, Stage 3):
```hlsl
float hunt_scale = lerp(0.7, 1.3, saturate((perc.g - 0.15) / 0.50));
float chroma_str = saturate(CHROMA_STRENGTH / 100.0 * hunt_scale);
```
A linear ramp on p50. No luminance-to-chroma model. Range [0.7, 1.3] is empirical.

**Philosophy:** SDR, linear light, vkBasalt post-process. Output must remain [0,1]. No gates on pixel properties. Game-agnostic.

---

### 2. Autonomous Brave Search (The Hunt)

Search `arxiv.org`, `doi.org`, `cie.co.at`, `onlinelibrary.wiley.com` for:

- **Stevens effect:** "Stevens effect" contrast luminance adaptation SDR 2022–2026. Target: CIECAM16 or CAM16 formulation of the Stevens exponent as a function of adaptation luminance La. Find the mathematical relationship between scene luminance and contrast exponent.
- **Hunt effect:** "Hunt effect" chromatic adaptation saturation luminance 2022–2026. Target: the J_HK or equivalent lightness-chroma scaling in CIECAM16, Nayatani, or Hellwig 2022 CAM. Find the coefficient k(La) that maps luminance to chroma amplification.
- Cross-reference: Hellwig & Fairchild 2022 "Brightness, lightness, colorfulness, and chroma in CIECAM16" — this paper reformulated both effects in a unified framework.

---

### 3. Documentation

Output findings to `research/2026-XX-XX_stevens_hunt.md`. For each effect:

- **Core thesis:** What does the literature say the correct mathematical model is?
- **Mathematical delta:** Current lerp vs. proposed formula (with coefficients from the paper)
- **Injection point:** Exact lines in `grade.fx` to modify
- **Knob impact:** Does this change the meaning of existing knobs (CHROMA_STRENGTH, CLARITY_STRENGTH)?
- **Viability verdict:** PASS/FAIL — SPIR-V safe, gate-free, bounded output

---

### 4. Strategic Recommendation

Both effects share a dependency on adaptation luminance La. If the literature provides a unified La → (contrast_exponent, chroma_scale) model, a single scene-median → La mapping would feed both corrections, replacing two independent lerps with one physically-grounded lookup. Assess whether this unification is possible and whether it improves or complicates the knob surface.

**Constraint:** SDR only. La should be derived from PercTex (already available). No new passes.
