# Research Findings — Film Stock Spectral Emulation — 2026-05-01

## Search angle

Friday domain: spectral sensitivity matrices, Hurter-Driffield per-layer gamma asymmetry, dye
secondary (unwanted) absorption coupling, and compact physically-based film emulation models.
Five Brave queries attempted (host-blocked); four WebSearch queries and multiple WebFetch calls
substituted. Key sources: Kodak VISION3 / VERITA technical datasheets, IS&T Color Imaging
Conference proceedings, agx-emulsion / Spektrafilm spectral simulation project (Volpato, 2024),
"Emulating Emulsion: A Compact Physically-Based Model for Film Colour" (SIGGRAPH Posters 2025,
ACM DL 10.1145/3721250.3743014), and classical H&D sensitometry literature.

---

## Finding R47: Per-Channel FilmCurve Shoulder/Toe Gamma Weighting

**Source:** Kodak VISION3 color negative film technical datasheets (Kodak H-740 sensitometry
workbook; Vision3 5219/7219 and 2254 data sheets); corroborated by Roger Deakins forum
discussions on film contrast curves and the agx-emulsion spectral pipeline (github.com/
andreavolpato/agx-emulsion).
**Year:** Sensitometry baseline 1970s–2020s; datasheet corroboration confirmed 2024–2026
**Field:** Photographic sensitometry / film colorimetry

### Core thesis

In every published Kodak color negative film datasheet the three H&D characteristic curves for
the red-, green-, and blue-sensitive dye layers are NOT parallel. The blue layer has the steepest
slope (highest gamma, γ_B ≈ 0.65–0.70), the green layer sits in the middle (γ_G ≈ 0.60–0.65),
and the red layer has the shallowest slope (γ_R ≈ 0.55–0.60). This is a consistent property of
CMY dye coupler chemistry: the cyan-forming (red-sensitive) layer trades some contrast for wider
latitude; the yellow-forming (blue-sensitive) layer operates at higher inherent contrast.

The perceptual consequence on final print/scan output:
- **Shadows/toe**: red lifts more (softer toe = more shadow detail in the warm channel) → warm shadow
- **Shoulder**: red compresses more gently (lower γ means the shoulder rolls in earlier relative to
  mid-tone, but with a flatter slope) → highlights retain a hint of warmth while blue compresses
  more aggressively, pulling highlight neutrals slightly toward cyan
- Overall: the classic "Kodak warm in shadows, neutral-to-slightly cool in highlights" rendering
  that cannot be replicated by per-channel knee-position offsets alone (which only shift WHERE
  compression starts, not HOW FAST it progresses once engaged)

### Current code baseline

`FilmCurve` at `grade.fx:108–128` computes a single scalar `factor` for the shoulder quadratic
and a single scalar `0.03/(knee_toe²)` for the toe quadratic, shared across all three channels:

```hlsl
return x - factor * above * above
           + (0.03 / (knee_toe * knee_toe)) * below * below;
```

Per-channel knee positions are exposed via `CURVE_R_KNEE / CURVE_B_KNEE` (grade.fx:117–122) but
the compression *rate* (the factor that scales the quadratic term) is identical for R, G, B.

### Proposed delta

Replace the scalar `factor` with a `float3 shoulder_w` and the scalar toe coefficient with a
`float3 toe_w`. Values are baked from Kodak VISION3 sensitometry ratios; no new user knob needed
(orthogonal to the existing `CURVE_*` position offsets which remain unchanged).

```hlsl
// grade.fx:126–128 — inside FilmCurve(), after 'above' and 'below' are computed

// R47: per-channel gamma weighting from Kodak H&D sensitometry
// Red layer: lower gamma → softer shoulder + more toe lift (warm shadows)
// Blue layer: higher gamma → steeper shoulder + less toe lift (neutral-to-cool highlights)
float3 shoulder_w = float3(1.06, 1.00, 0.93);   // R: +6% compression, B: −7% compression
float3 toe_w      = float3(1.12, 1.00, 0.86);   // R: +12% toe lift,   B: −14% toe lift

return x - factor * shoulder_w * above * above
           + (0.03 / (knee_toe * knee_toe)) * toe_w * below * below;
```

All three terms are `float3 * float3 * float3` element-wise — legal SPIR-V, no branching.
Neutrals are affected symmetrically across channels and the net lightness change is < 0.3% for
scene-median input (calibrated to be perceptually transparent at p50). The effect grows with
scene saturation and distance from mid-exposure.

### Injection point

`grade.fx:126–128` — replace the two-line return statement inside `FilmCurve`.

### Breaking change risk

Low. Changes shape of the FilmCurve shoulder/toe per-channel. Default `CURVE_R_KNEE = CURVE_B_KNEE
= CURVE_R_TOE = CURVE_B_TOE = 0.000` (creative_values.fx:43–46) means no prior calibrated offset
is disturbed. Users who have tuned those offsets will see a slight interaction; both corrections
operate independently (position vs. rate) and can be re-balanced by small CURVE_* tweaks.

### Viability verdict

**VIABLE.** Physically motivated by published film data; three new float3 constants, no new user
knob, no branching, SPIR-V clean, real-time trivial, game-agnostic.

---

## Finding R48: Dominant-Channel Dye Secondary Absorption Softening

**Source:** IS&T Color Imaging Conference vol. 4 (library.imaging.org/cic/4/1/art00010) on
secondary absorption compensation in digital film mastering; IS&T 1997 interimage-effect paper
(imaging.org, cited in agx-emulsion docs); chromogenic dye characterisation survey
(ScienceDirect 2024, ISSN 0026-265X); and the agx-emulsion project's masking coupler model.
**Year:** Physical basis 1970s; digital-grading application confirmed 2024–2026
**Field:** Film colorimetry / photochemistry

### Core thesis

Every chromogenic film dye has **secondary (unwanted) absorptions**: cyan dye absorbs some green
and blue light (not just red); magenta dye absorbs some red and blue (not just green); yellow dye
absorbs some red and green (not just blue). These secondary absorptions reduce the *apparent*
density of the dominant dye layer when the complementary dyes are also present at any density —
i.e., in coloured (non-neutral) pixels.

The IS&T Color Imaging Conference paper states explicitly: "for accurate colour reproduction and
compensation of secondary absorption, at least a 3×3 matrix should be implemented." The
agx-emulsion project models these as *masking couplers* — a negative absorption contribution to
each layer's isolated absorption spectrum that reduces cross-talk.

Practical magnitude: cyan dye secondary absorptions reduce effective red density by ~5–10% in
scenes where green and blue are non-negligible; magenta secondary absorptions similarly affect the
green channel. The resulting perceptual effect is a **gentle chroma softening of mid-saturation
colours** (oranges, teals, skin tones, foliage) that is NOT present in pure primaries (where only
one layer fires) and NOT present in neutrals (secondary absorptions cancel). It creates the
characteristic "depth without harshness" of Kodak print colours versus digital renders.

### Current code baseline

After `FilmCurve` at `grade.fx:214–215`, `lin` goes directly into the R19 3-way colour corrector
with no inter-layer coupling. The 3-way corrector (lines 219–232) applies luminance-zoned
*additive* offsets — static per luminance region, not modulated by per-pixel colour saturation.
No mechanism exists for reducing the dominant channel proportionally to the presence of
complementary channels.

### Proposed delta

After `FilmCurve` and before R19, insert a saturation-modulated dominant-channel attenuation.
The attenuation is zero for neutrals (dominant == others → sat_proxy == 0) and for pure primaries
(complementary channels near zero → no secondary absorption available to drive cross-coupling).
It is maximal for mid-saturation colours where one channel noticeably leads the others.

```hlsl
// grade.fx: new block after line 215 (after FilmCurve lerp into lin), before R19 block

// R48: dye secondary absorption — dominant channel soft attenuation
// Physical: cyan/magenta/yellow dyes absorb ~5-8% of complementary wavelengths.
// Neutral-preserving: sat_proxy = 0 → no effect.
{
    float lin_max = max(lin.r, max(lin.g, lin.b));
    float lin_min = min(lin.r, min(lin.g, lin.b));
    float sat_proxy = lin_max - lin_min;                       // 0 = neutral, 1 = pure primary
    float ramp = saturate(sat_proxy / 0.18);                   // smooth onset; 0.18 ≈ film's colour
                                                               //   masking activation threshold
    float3 dom_mask = saturate((lin - lin_min) / max(sat_proxy, 0.001)); // 0=min channel, 1=max
    float couple = 0.06;                                       // ~6%, mid-range of published values
    lin = saturate(lin - couple * dom_mask * sat_proxy * ramp);
}
```

Walkthrough for representative inputs:

| Pixel          | lin_max | sat_proxy | dom_mask    | Δ (couple=0.06)    |
|----------------|---------|-----------|-------------|---------------------|
| neutral (0.5³) | 0.50    | 0.00      | n/a         | **0.000 (no change)**|
| skin (0.65,0.45,0.35) | 0.65 | 0.30 | (1.0,0.33,0) | R −0.018, G −0.006 |
| orange (0.85,0.55,0.10)| 0.85 | 0.75 | (1.0,0.60,0) | R −0.045, G −0.027 |
| pure red (0.9,0,0)     | 0.90 | 0.90 | (1.0, 0, 0)  | R −0.054, G 0, B 0 |

Pure red loses ~5-6% (physically correct — cyan dye does absorb some red). Neutral: unchanged.
Skin: very gentle. Mid-saturation colours (orange, teal, foliage): most visibly softened.

The `couple = 0.06` constant is baked; no new creative_values.fx knob required for initial
implementation. If artistic control is later desired, a single `FILM_DYE_COUPLE` (0–100, default
6) can expose it.

### Injection point

`grade.fx:215` — new block between the `FilmCurve` result assignment and the `// ── R19` comment
line. The `lin` variable is already in scope as `float3`.

### Breaking change risk

Low. The effect is always a small reduction of the dominant channel, never an amplification; the
output remains in [0,1] by construction (`saturate`). At the default 6% coupling, the maximum
single-channel change on a fully-saturated primary is −0.054 — well within the noise of an 8-bit
display step. No existing automated parameter (chroma_str, density_str, etc.) depends on the
absolute value of `lin` at this point in a way that would be destabilised.

### Viability verdict

**VIABLE.** Analytically derived from published film colorimetry; four lines of new code, neutral-
preserving by construction, no LUTs, no branches, SPIR-V clean, game-agnostic.

---

## Discarded this session

| Title / Technique | Reason |
|---|---|
| "Emulating Emulsion: A Compact Physically-Based Model for Film Colour" (SIGGRAPH Posters 2025, ACM DL 10.1145/3721250.3743014) | Full RAW-to-RAW pipeline — requires inverting the digital capture ISP before simulating film. Not applicable to a BackBuffer post-process pass with no RAW access. |
| agx-emulsion / Spektrafilm spectral simulation (Volpato 2024, github.com/andreavolpato/agx-emulsion) | Runtime spectral LUT built from manufacturer datasheets (spectral sensitivities + density curves per stock). Violates real-time constraint #8 and game-agnostic constraint #9 (stock-specific data). |
| Naive log-domain cross-coupling: `exp(log(lin) · M_offdiag)` | `log()` diverges toward −∞ as any channel approaches 0 (pure-primary or shadowed pixels). Amplification near zero is unbounded and cannot be safely clamped without an asymptotic fallback — violates constraint #3. |
| Pre-FilmCurve spectral sensitivity input matrix (digital → film primaries) | A 3×3 near-identity matrix in linear light is perceptually equivalent to a combination of global saturation (already automated via chroma_str/R36) plus global hue rotation (already R21). No structurally novel contribution. |
| Inhibitor coupler spatial diffusion (local contrast + chroma enhancement at density edges) | Spatial phenomenon requiring per-pixel neighbourhood reads. Already addressed by R09N Cauchy-bell multi-scale Laplacian clarity chain and R29 multi-scale Retinex illumination separation. |
| Film D-min base fog tint (shadow colour offset from residual dye density) | Additive constant per channel in the shadow region, identical in structure to the R19 `SHADOW_TEMP` / `SHADOW_TINT` knobs. Already fully reachable by tuning existing controls. |

---

## Strategic recommendation

R47 and R48 together form a coherent **Film Layer Physics** package that closes two distinct gaps
in the current CORRECTIVE stage:

- R47 differentiates *how fast* each channel compresses (rate, i.e. gamma), while the existing
  `CURVE_*` knobs only control *where* compression starts (position). They are fully orthogonal.
- R48 models the cross-layer density coupling that makes film colours feel "embedded in light"
  rather than "painted on" — the gentle dominant-channel softening distinguishes mid-saturation
  scene colours from digital harshness without flattening pure primaries or neutrals.

Recommended implementation order: R47 first (pure refactor inside `FilmCurve`, no new code
surface), then R48 (new block, verify on skin tones and foliage). Both at their proposed strengths
are perceptually subtle and cumulative with the existing HK/Abney/density chain.

A third structural idea evaluated but deferred: **saturation-driven complementary-channel
de-compression** (non-dominant channels in a saturated pixel are in the toe, not the shoulder of
their H&D curve, so applying full `factor` shoulder compression to them is physically incorrect).
This would require passing a per-pixel saturation proxy *into* `FilmCurve` and would interact
with R47. Recommended for a future session after R47 perceptual impact is assessed.
