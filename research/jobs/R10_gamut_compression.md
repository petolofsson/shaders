**Role:** Technical Research Lead & Shader Architect (AI Agent Mode)
**Task:** Use the **Brave Search MCP** to find a perceptually-principled gamut compression algorithm for SDR that replaces the current grey-point desaturation clamp in `grade.fx`.

---

### 1. Contextual Audit (Internal)

**Scan files:** `general/grade/grade.fx`

**Current implementation** (`grade.fx`, Stage 3, end of chroma section):
```hlsl
float3 chroma_rgb = OklabToRGB(float3(density_L, f_oka, f_okb));
float  rmax       = max(chroma_rgb.r, max(chroma_rgb.g, chroma_rgb.b));
if (rmax > 1.0)
{
    float L_grey = dot(chroma_rgb, float3(0.2126, 0.7152, 0.0722));
    float gclip  = (1.0 - L_grey) / max(rmax - L_grey, 0.001);
    chroma_rgb   = L_grey + gclip * (chroma_rgb - L_grey);
}
lin = saturate(chroma_rgb);
```

Problems:
- Hard conditional (`if (rmax > 1.0)`) fires only when out-of-gamut — applies no soft rolloff leading up to the boundary. Colors approaching the boundary have no compression anticipation.
- Grey-point desaturation preserves luminance but shifts hue for highly saturated colors (the grey axis is not a neutral hue anchor in Oklab).
- No rolloff: a pixel at rmax=0.999 is untouched; a pixel at rmax=1.001 is hard-compressed. This boundary is a potential seam.

**Philosophy:** SDR [0,1]. Gate-free (no hard conditionals on pixel properties per CLAUDE.md). Oklab working space. No new passes.

---

### 2. Autonomous Brave Search (The Hunt)

Search `arxiv.org`, `acm.org`, `aces-central.org`, `colour-science.org` for:

- **ACES gamut compression:** "ACES gamut compression" algorithm 2020–2026. The ACES reference gamut compression (resolve_gamut_compress.glsl) uses a smooth rolloff per-channel toward a compressed limit. Find the exact formula and assess whether it applies to our Oklab → sRGB output.
- **Oklab-native gamut mapping:** "Oklab gamut mapping" OR "Oklch gamut clipping" 2022–2026. Björn Ottosson (Oklab author) published a chroma-reduction approach in Oklch; find the latest version.
- **Perceptual gamut mapping:** "perceptual gamut mapping SDR" display 2024–2026 site:arxiv.org. Looking for any constant-hue or constant-lightness approach that works in a single pass.
- Specifically: is there a smooth monotone function f(C) → C' where f(C) = C for C below a threshold and f compresses toward the sRGB boundary for C above it, with no hard conditional?

---

### 3. Documentation

Output findings to `research/2026-XX-XX_gamut_compression.md`. For each candidate:

- **Core thesis:** What is the compression model?
- **Mathematical delta:** Current hard clamp vs. proposed smooth rolloff
- **Gate compliance:** Does the proposed formula avoid hard conditionals on pixel properties?
- **Hue linearity:** Does it preserve hue angle in Oklab (a,b) direction?
- **Injection point:** The `if (rmax > 1.0)` block in `grade.fx` Stage 3
- **Viability verdict:** PASS/FAIL

---

### 4. Strategic Recommendation

The ideal replacement is a smooth, monotone chroma rolloff in Oklch that: (a) is identity for C below ~85% of the sRGB gamut boundary, (b) compresses toward the boundary with no hard cutoff, (c) preserves the hue angle exactly (no grey-point desaturation shift), and (d) can be evaluated without a conditional branch. Rank candidates on these four criteria.

**Constraint:** Must not increase chroma for any pixel (compression only). The `saturate()` at line end is the SDR ceiling and must be preserved.
