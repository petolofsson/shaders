**Role:** Technical Research Lead & Shader Architect (AI Agent Mode)
**Task:** Use the **Brave Search MCP** to research per-band hue rotation in Oklab space and design a gate-free hue rotation system that integrates into the existing chroma stage of `grade.fx` without introducing hue discontinuities at band boundaries.

---

### 1. Contextual Audit (Internal)

**Scan files:** `general/grade/grade.fx`, `gamespecific/arc_raiders/shaders/creative_values.fx`

**Current chroma stage (grade.fx, Stage 3):**
The shader operates in Oklab LCh space: `L = lab.x`, `C = sqrt(lab.y*lab.y + lab.z*lab.z)`, `h = atan2(lab.z, lab.y) / 6.28318` (normalised 0–1).

Six hue bands are defined (Red, Yellow, Green, Cyan, Blue, Magenta). Per-band saturation bending is applied via smooth bell weights. The hue angle `h` is read and used for band weighting and H-K correction, but `h` is never **modified** — the output always carries the original hue angle.

**Gap:** There is no mechanism to rotate hues. Skintones in Arc Raiders sit at approximately h≈0.08 (red-orange). To shift them warmer or cooler requires rotating the hue angle in that band. Foliage (h≈0.38–0.42) and sky (h≈0.55–0.65) are similarly fixed.

**Proposed mechanism:**
For each of the 6 hue bands, define a rotation offset `ROT_x` in normalised hue units (0–1, where 1.0 = full 360° rotation). Apply via a weighted sum of per-band rotations using the existing bell-weight system:

```hlsl
float h_delta = ROT_RED   * w_red
              + ROT_YELLOW * w_yellow
              + ROT_GREEN  * w_green
              + ROT_CYAN   * w_cyan
              + ROT_BLUE   * w_blue
              + ROT_MAG    * w_mag;
float h_out = frac(h + h_delta);  // frac handles wraparound at 0/1
// Reconstruct lab.yz from new hue:
float angle_out = h_out * 6.28318;
lab.y = C * cos(angle_out);
lab.z = C * sin(angle_out);
```

The bell weights already ensure smooth, overlapping band boundaries — no discontinuities. `frac()` handles the red wraparound (hue 0 = hue 1).

**Knob count:** 6 new knobs (one per band), all default 0.0. Range ±0.10 covers all practical grading use — a full 36° rotation per band.

**Philosophy:** SDR, linear light. No new passes. Gate-free — bell weights are smooth by construction.

---

### 2. Autonomous Brave Search (The Hunt)

Search `colour.readthedocs.io`, `arxiv.org`, `opencolorio.org`, `acescentral.com` for:

- **Oklab hue rotation stability:** Any 2022–2026 paper or technical note on hue manipulation in Oklab space. Does rotating the a/b vector while holding C constant produce perceptually uniform hue shifts, or does it introduce lightness or chroma artefacts at hue extremes? Compare to HSV hue rotation.
- **Hue vs. Hue curves in Oklab:** DaVinci Resolve and Baselight implement Hue vs. Hue curves in a perceptual space. Has any published work characterised which colour space gives the most predictable hue rotation (least secondary colour contamination)?
- **Bell weight normalisation:** The existing chroma bell weights may not sum to 1.0 across all hues (they are independent Gaussian-like weights, not a partition of unity). If a pixel sits between two bands, its `h_delta` could be a weighted average of two non-zero rotations, or it could be under-weighted. Search "hue band partition of unity colorimetry" for any established normalisation practice.
- **Red wraparound artefacts:** Search "hue rotation wraparound artefact HLSL" — is `frac(h + delta)` sufficient for the 0/1 boundary, or does the cos/sin reconstruction require special handling near h=0?

---

### 3. Documentation

Output findings to `research/R21_hue_rotation_findings.md`. Address:

- **Oklab hue rotation quality:** Is rotating the a/b vector by angle δ while holding C fixed a perceptually clean operation? What secondary effects (L, C change) occur, if any?
- **Bell weight normalisation:** Do the existing band weights need to be normalised (divided by their sum) before applying h_delta, to ensure a pixel fully inside one band gets exactly that band's rotation and a pixel at the boundary gets a blend? Provide the normalised weight formula.
- **Wraparound:** Confirm `frac()` is sufficient, or propose a safer reconstruction.
- **Interaction with H-K:** The H-K correction uses `h` to compute `f(h)`. Should H-K read the original or the rotated hue? Answer with reference to what H-K is modelling (perceived brightness of the stimulus colour vs. the stimulus as displayed).
- **Interaction with Abney correction:** Abney correction modifies hue at the hue-shift bands (Cyan↑/Blue↓ etc.). Does applying hue rotation before or after Abney matter? Which order is more predictable?
- **Injection point:** Exact location in `ColorTransformPS` Stage 3. Before or after chroma lift? Before or after H-K?
- **Range recommendation:** What ±rotation range (in normalised hue units) covers practical grading without risk of hue bleeding into adjacent bands?
- **SPIR-V viability:** PASS/FAIL — `frac()`, `cos()`, `sin()` are standard intrinsics. No static arrays.

---

### 4. Strategic Recommendation

Minimum viable implementation:
1. Add 6 `ROT_*` knobs to `creative_values.fx`, default 0.0
2. After existing band weight computation, sum `h_delta = Σ ROT_x * w_x`
3. Apply `h_out = frac(h + h_delta * ROTATION_SCALE)` where `ROTATION_SCALE = 0.10` keeps range sane
4. Reconstruct `lab.yz` from `h_out` and existing `C`
5. All downstream operations (H-K, Abney, density) use the rotated hue

If bell weight normalisation is required, add a `float w_sum = w_red + w_yellow + ... + w_mag` and divide each weight before accumulating h_delta.

**Constraint:** Default-zero knobs must produce bitwise-identical output to the current shader (h_delta = 0 → cos/sin unchanged → lab.yz unchanged). Verify algebraically.
