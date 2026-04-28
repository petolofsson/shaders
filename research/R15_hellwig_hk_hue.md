**Role:** Technical Research Lead & Shader Architect (AI Agent Mode)
**Task:** Use the **Brave Search MCP** to research the Hellwig 2022 Helmholtz–Kohlrausch formula and produce a drop-in upgrade for the HK block in `grade.fx`.

---

### 1. Contextual Audit (Internal)

**Scan files:** `general/grade/grade.fx`, `gamespecific/arc_raiders/shaders/creative_values.fx`

**Current HK implementation** (`grade.fx`, Stage 3, Seong & Kwak 2025 model from R08N):
```hlsl
float hk_boost = 1.0 + (HK_STRENGTH / 100.0) * final_C;
float final_L  = saturate(lab.x / lerp(1.0, hk_boost, smoothstep(0.0, 0.35, lab.x)));
```
Reduces perceived lightness of saturated colors by dividing L by `(1 + k*C)`. Hue-agnostic. No exponent on C.

**Hellwig 2022 H-K formula** (colour-science implementation):
```python
J_HK = J + hue_angle_dependency_Hellwig2022(h) * spow(C, 0.587)
f(h) = -0.160*cos(h_r) + 0.132*cos(2*h_r) - 0.405*sin(h_r) + 0.080*sin(2*h_r) + 0.792
```
Key differences from current shader:
1. `C^0.587` exponent vs. linear in C
2. Hue-dependent gain f(h) ∈ [~0.3, ~1.3] — blue gets more correction than red
3. Formula is an **addition** to J (not a divisor) — same direction as current (chromatic → brighter percept → needs lightness reduction), but different implementation shape

**The hue mapping problem:** `h_r` in Hellwig 2022 is the CIECAM hue angle in radians. Our shader uses `OklabHueNorm` which gives a normalized [0,1] value. The coordinate systems are related but not equal: Oklab and CIECAM use different opponent-channel matrices. A calibration mapping is needed.

**Philosophy:** SDR, linear light, Oklab. Gate-free. Output bounded. No new passes.

---

### 2. Autonomous Brave Search (The Hunt)

Search `arxiv.org`, `colour.readthedocs.io`, `cie.co.at`, `onlinelibrary.wiley.com` for:

- **Oklab-to-CIECAM hue mapping:** Has anyone published a polynomial or piecewise mapping from Oklab hue angle to CIECAM hue angle? The Oklab primaries (R, G, B, Y, C, M) have known CIECAM hue angles — a 6-point calibration could be derived.
- **Hellwig 2022 full paper:** "Brightness, lightness, colorfulness, and chroma in CIECAM02 and CAM16" *Color Research & Application* 47(5):1083–1095. Find the exact f(h) formula and coefficient values (are they the same as the colour-science implementation: -0.160, 0.132, -0.405, 0.080, 0.792?).
- **H-K effect in SDR shaders:** Any practical implementation of hue-dependent H-K correction in display post-processing 2022–2026. Is C^0.587 well-validated for sRGB/display-referred content?
- **Hellwig 2024 "Brightness of chromatic stimuli"** (follow-on paper, Wiley 2024) — does it refine the f(h) formula or change the C exponent?

---

### 3. Documentation

Output findings to `research/R15_hellwig_hk_hue_findings.md`. Address:

- **f(h) coefficients:** Confirm or correct the 5 coefficients from colour-science. What is the range of f(h) across sRGB primary hues?
- **C exponent:** Is 0.587 correct for linear light? (CIECAM operates on adapted, non-linear cone responses — the exponent may differ for linear-light Oklab chroma.)
- **Hue calibration:** Provide a 6-point lookup table mapping Oklab normalized hue (0–1) → CIECAM hue (radians) for the 6 primary hue angles. Or propose a closed-form approximation.
- **Injection point:** The `hk_boost` / `final_L` block in `grade.fx` Stage 3 (lines ~464–466).
- **Knob impact:** Does this change the meaning of `HK_STRENGTH`? The Hellwig formula has no explicit strength knob — `HK_STRENGTH` would scale the f(h)*C^0.587 term.
- **Viability verdict:** PASS/FAIL for SPIR-V — no `static const float[]`, no reserved keywords.

---

### 4. Strategic Recommendation

The minimum viable Hellwig upgrade:
1. Replace `final_C` exponent from linear to `pow(final_C, 0.587)`
2. Add hue-dependent weighting f(h) using the Oklab hue `h` (with or without the full CIECAM calibration)
3. Keep `HK_STRENGTH` as the global strength knob

Assess whether the hue calibration is necessary for the correction to be perceptually meaningful, or whether the hue-agnostic C^0.587 exponent alone is a worthwhile improvement over the current linear model.

**Constraint:** If the full f(h) Fourier function requires the CIECAM hue mapping and that mapping is not available with ≥90% accuracy, the fallback is C^0.587 without hue weighting — still an improvement over the linear model.
