**Role:** Technical Research Lead & Shader Architect (AI Agent Mode)
**Task:** Use the **Brave Search MCP** to find measured Abney hue shift data for all 6 primary hue bands and replace the current hardcoded 3-band approximation in `grade.fx` with a data-driven model.

---

### 1. Contextual Audit (Internal)

**Scan files:** `general/grade/grade.fx`

**Current implementation** (`grade.fx`, Stage 3, Abney block):
```hlsl
float abney = (-HueBandWeight(h, BAND_BLUE)   * 0.08
              - HueBandWeight(h, BAND_CYAN)    * 0.05
              + HueBandWeight(h, BAND_YELLOW)  * 0.05) * final_C;
float dtheta = -(GREEN_HUE_COOL * 2.0 * 3.14159265) * green_w * final_C + abney;
```

Problems:
- Only 3 of 6 hue bands have Abney coefficients. Red, green, magenta are assumed zero.
- Coefficients (0.08, 0.05, 0.05) have no citation.
- Abney shift direction is unsigned (all negative or positive). Real data shows bidirectional shifts that vary with saturation level, not just hue.
- The `dtheta` rotation is in Oklab (a,b) space using a small-angle approximation — verify this remains valid for corrected coefficients.

**Philosophy:** SDR, linear light, Oklab. Gate-free. Output bounded. No new texture reads.

---

### 2. Autonomous Brave Search (The Hunt)

Search `arxiv.org`, `onlinelibrary.wiley.com`, `cie.co.at`, `opticsinfobase.org` for:

- "Abney effect hue shift" measured data 2020–2026. Target: a table or formula giving hue rotation angle (degrees or radians) as a function of hue angle θ and saturation s for sRGB or similar display primaries.
- Pridmore 2007 / Mizokami et al. Abney effect measurements — find if newer replications exist.
- "Abney hue shift" CIECAM OR CIECAM16 OR CAM16 2022–2026 — does the current CAM already encode Abney? If so, what coefficients does it use?
- SIGGRAPH Asia 2024 "Hue Distortion Cage" paper — was previously inaccessible (ACM paywall). Check if a preprint is now available on arxiv or the authors' pages.

---

### 3. Documentation

Output findings to `research/2026-XX-XX_abney.md`. For each band (red, yellow, green, cyan, blue, magenta):

- **Measured shift:** Rotation direction and magnitude (radians per unit Oklab chroma)
- **Mathematical delta:** Current coefficient → proposed coefficient
- **Cross-pollination:** Does the literature suggest the shift should be modulated by lightness as well as saturation?
- **Injection point:** The `abney` float computation in `grade.fx` Stage 3
- **Viability verdict:** PASS/FAIL

---

### 4. Strategic Recommendation

If full 6-band data is found, propose a complete replacement of the 3-term `abney` expression with a 6-band weighted sum using data-derived coefficients. Assess whether the shift magnitude warrants exposing a single `ABNEY_STRENGTH` knob in `creative_values.fx` (currently no knob exists — the effect is always-on at hardcoded magnitude).

**Constraint:** The small-angle approximation for `cos(dtheta)/sin(dtheta)` was validated for `|dtheta| < 0.10 rad`. If corrected Abney coefficients push `dtheta` above this bound, the approximation must be revisited.
