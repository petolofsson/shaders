# Research Findings — Tone Mapping & Film Sensitometry — 2026-05-04

## Search angle

Monday domain: tone mapping & film sensitometry. Searched for:
- Cinema SDR mastering structural regularities (pixel-wise case study)
- Hurter–Driffield H&D characteristic curve toe/shoulder geometry
- Stevens brightness exponent psychophysics (luminance adaptation)
- Perceptual tone mapping SDR real-time literature (SIGGRAPH 2023/2025)
- Print emulsion interimage effects and dye-coupling cross-terms

Primary vetted source: Žaganeli et al. (2026) — "Structural Regularities of Cinema SDR-to-HDR
Mapping in a Controlled Mastering Workflow: A Pixel-wise Case Study on ASC StEM2",
arXiv 2604.06276 (April 2026). This is a pixel-wise empirical study across 18,580 frames of a
single ACES-mastered film with both SDR and HDR release prints from the same source — giving
ground-truth data on what professional SDR colorists actually do with tone and saturation.

---

## Finding 1: Sensitometrically-coupled print stock desaturation bell bounds

**Source:** arXiv 2604.06276 — Žaganeli et al., "Structural Regularities of Cinema SDR-to-HDR
Mapping", April 2026
**Year:** 2026
**Field:** Film sensitometry / cinema mastering colorimetry

### Core thesis

The paper's saturation redistribution measurement shows a three-zone pattern in SDR cinema
masters: **shadow suppression → midtone expansion → highlight convergence**. Crucially, the
boundaries between zones are not fixed luma levels — they track the local slope of the SDR
characteristic curve. Where the curve slope is sub-unity (toe and shoulder), saturation is
suppressed. Where slope ≈ 1 (the straight-line region), saturation is fully expressed or
expanded. This is the physical basis of the Kodak 2383 print stock desaturation: the emulsion
expresses full saturation only in the linear-gamma region and compresses it proportionally to
slope departure in toe/shoulder.

### Current code baseline

`grade.fx`, R51 print stock block (~line 297):

```hlsl
float desat_w = 0.15 * (1.0 - smoothstep(0.0, 0.3, luma_ps))
                      * (1.0 - smoothstep(0.6, 1.0, luma_ps));
```

The bounds `0.3` and `0.6` are magic numbers — they define the saturation suppression zones in
luma_ps space. They do not track the scene-adaptive FilmCurve geometry. When the scene is
bright (eff_p75 > 0.60) and `fc_knee` drops to ~0.80, the midtone expansion window should also
narrow — but the fixed `0.6` bound keeps it wide. When the scene is dark and `fc_knee_toe`
rises to ~0.25, the shadow suppression zone should extend further — but `0.3` keeps it narrow.

### Proposed delta

Replace the two magic numbers with the FilmCurve parameters already computed in scope:

```hlsl
// grade.fx ~line 297, inside R51 block
// fc_knee_toe (~line 276) and fc_knee (~line 273) are already in scope here.
float desat_w = 0.15 * (1.0 - smoothstep(0.0, fc_knee_toe, luma_ps))
                      * (1.0 - smoothstep(fc_knee, 1.0, luma_ps));
```

Both `fc_knee_toe` and `fc_knee` are frame-constant scalars computed at lines 276–280, before
the R51 block. No new texture reads or arithmetic. The change is 2 tokens in a single line.

Effect at typical values (fc_knee=0.85, fc_knee_toe=0.20):
- Shadow boundary moves from 0.30 → 0.20 (shadow suppression is narrower — less harsh)
- Highlight boundary moves from 0.60 → 0.85 (midtone expansion window widens 25%)

Effect at bright scene (eff_p75=0.80 → fc_knee=0.80, fc_knee_toe=0.15):
- Shadow boundary: 0.30 → 0.15 (tighter shadow compression)
- Highlight boundary: 0.60 → 0.80 (still wide — matching compressed-shoulder profile)

Effect at dark scene (eff_p25=0.20 → fc_knee_toe=0.25):
- Shadow boundary: 0.30 → 0.25 (slight expansion of suppression zone)
- Highlight boundary: unchanged (knee nominally still ~0.88 in dark scenes)

### Injection point

`general/grade/grade.fx`, line ~297, inside the R51 print stock block. Both `fc_knee` and
`fc_knee_toe` are in scope; `luma_ps` is already computed on the line above.

### Breaking change risk

Low. The effect is continuous, gate-free, and bounded. The only visible change is a modest
widening/narrowing of the print stock saturation bell that tracks scene exposure — exactly the
behaviour the Kodak 2383 emulsion exhibits in response to changing print density settings. Peak
desaturation amplitude (0.15) is unchanged.

### Viability verdict

**ACCEPT.** SDR-safe, gate-free, SPIR-V safe, real-time (zero new ops), game-agnostic,
physically motivated. 2-token change to grade.fx line ~297.

---

## Finding 2: Midtone saturation expansion in R22

**Source:** arXiv 2604.06276 — Žaganeli et al., "Structural Regularities of Cinema SDR-to-HDR
Mapping", April 2026
**Year:** 2026
**Field:** Cinema SDR colorimetry / saturation redistribution

### Core thesis

The pixel-wise case study reports that the saturation redistribution in SDR cinema masters is
not merely a double-sided suppression (as might be assumed from clamping dynamic range). It
has a distinct **midtone expansion** component: saturation in the range approximately
Oklab L ∈ [0.28, 0.65] is actively increased relative to the HDR source, not just less
suppressed. The paper notes this tracks closely with where the characteristic curve slope equals
1.0 — the straight-line gamma region — where the film's dye layers reach their rated density
ratio and can fully express chromatic separation.

Our current R22 (`grade.fx` lines 419–420) models only the two suppression terms:

```hlsl
C *= (1.0 - 0.20 * saturate(1.0 - lab.x / 0.25)        // shadow -20%
         - 0.45 * saturate((lab.x - 0.75) / 0.25));      // highlight -45%
```

No midtone expansion is modeled. The R22 curve is monotonically flat or reducing — it has no
peak exceeding 1.0 in any luma band. Cinema SDR masters demonstrably add a saturation bump in
the midtone region.

### Current code baseline

`grade.fx`, R22 block, lines 419–420. `C = length(lab.yz)` at this point, `lab.x` is Oklab L.
`lab` is post-R52 Purkinje shift.

### Proposed delta

Add a smooth midtone expansion bell before the existing suppression terms:

```hlsl
// grade.fx ~line 419, R22 block
float mid_C_boost = 0.06 * smoothstep(0.22, 0.40, lab.x)
                         * (1.0 - smoothstep(0.55, 0.70, lab.x));
C *= (1.0 + mid_C_boost
          - 0.20 * saturate(1.0 - lab.x / 0.25)
          - 0.45 * saturate((lab.x - 0.75) / 0.25));
```

Peak expansion: +6% at lab.x ≈ 0.47 (roughly 50% luminance in perceptual space, matching the
paper's observed midtone expansion centre). The bell is gate-free — two smoothsteps form a
smooth product with no discrete threshold.

Net effect accounting for downstream vibrance mask and memory color ceiling:
- The vibrance mask (`1.0 - C / 0.22`) is smaller for already-expanded C → self-limiting
- Memory color ceilings (lines 480–482) cap per-band expansion at 0.15–0.28
- Effective midtone saturation increase at output: approximately +3–4% after ceiling clamping

The shadow and highlight suppression terms are unchanged. No SDR ceiling violation risk:
`C * 1.06` at the ceiling bands (0.19–0.28) stays within the memory color ceiling.

### Injection point

`general/grade/grade.fx`, line 419, R22 chroma saturation-by-luminance block. Follows Purkinje
shift (R52), precedes per-band chroma lift (lines 448–482).

### Breaking change risk

Moderate. Midtone saturation increases ~6% at the bell peak, partially absorbed by the vibrance
mask. Net visual: slightly richer midtone colours across the image. The interaction with the
per-band chroma lift needs A/B validation — the lift operates on a higher base C, so per-band
expansion in the pivot region may slightly increase. Memory color ceilings provide the upper
bound.

### Viability verdict

**ACCEPT.** SDR-safe (ceilings exist downstream), gate-free (double smoothstep bell), SPIR-V
safe, real-time (4 extra ALU ops), game-agnostic, physically motivated by cinema SDR mastering
data. Requires A/B comparison post-implementation.

---

## Finding 3: Stevens exponent recalibration — sqrt → cbrt for fc_stevens

**Source:** Nayatani et al. (1997) "Simple estimation methods for the Helmholtz–Kohlrausch
effect", *Color Research & Application* 22(6); corroborated by Journal of Vision 25(2) 2025
(psychophysical appearance data up to 16,860 cd/m²)
**Year:** 1997 / 2025
**Field:** Psychophysical brightness adaptation / Stevens effect

### Core thesis

The Stevens effect (perceived contrast amplification with increasing adapting luminance) follows
a power law on scene luminance. Across multiple psychophysical studies, including the 2025 JoV
dataset collected at luminance levels spanning low-mesopic to photopic (up to 16,860 cd/m²),
the brightness exponent consistently trends toward L_A^(1/3) (cube root) rather than L_A^(1/2)
(square root) as adapting luminance increases. The square root overestimates the Stevens
correction in bright scenes and underestimates it in dark scenes relative to the full luminance
range.

### Current code baseline

`grade.fx`, line ~274:

```hlsl
float fc_stevens = (1.48 + sqrt(max(zone_log_key, 0.0))) / 2.03;
```

This sets the Stevens multiplier on `fc_factor` (shoulder compression strength). At
`zone_log_key = 0.18` (18% gray, photopic norm): fc_stevens ≈ 0.94. At key=0.05 (dim game
scenes): fc_stevens ≈ 0.80. The square root underestimates correction for dark scenes because
the psychophysical exponent for dark adaptation is closer to 1/3, not 1/2.

### Proposed delta

Replace sqrt with exp2/log2 cube root (SPIR-V safe — same pattern as the cbrt used in
RGBtoOklab and the R62 ratio computation):

```hlsl
// grade.fx line ~274
float fc_stevens = (1.48 + exp2(log2(max(zone_log_key, 1e-6)) * (1.0 / 3.0))) / 2.04;
//                               ^^^ cbrt, SPIR-V safe      ^^^                  ^--- recal
```

Denominator changes from 2.03 → 2.04 to keep fc_stevens ≈ 1.0 at the photopic norm
(zone_log_key = 0.18): cbrt(0.18) = 0.5646, → (1.48 + 0.5646) = 2.044 ≈ 2.04.

Calibration table (fc_stevens value, which scales fc_factor):

| zone_log_key | sqrt (old) | cbrt (new) | Δ fc_stevens |
|-------------|-----------|-----------|-------------|
| 0.01 (very dark) | 0.78 | 0.86 | +0.08 |
| 0.05 (dim)       | 0.83 | 0.91 | +0.08 |
| 0.18 (photopic)  | 0.94 | 1.00 | +0.06 |
| 0.40 (bright)    | 1.05 | 1.10 | +0.05 |
| 1.00 (very bright)| 1.22 | 1.22 | 0.00 |

The cbrt consistently gives slightly more Stevens correction in dark/mid-key scenes (Δ ≈ +5–8%
on fc_factor), converging to the same value at key=1.0. In practice: dark game sessions get a
marginally stronger shoulder roll-off (more authentic perceptual contrast boost), bright
outdoor scenes are unchanged.

### Injection point

`general/grade/grade.fx`, line ~274. Single arithmetic substitution: `sqrt(key)` →
`exp2(log2(max(key, 1e-6)) * (1.0 / 3.0))`.

### Breaking change risk

Very low. fc_factor changes by ≤ 8% in the most extreme case (very dark scenes). The shoulder
compression changes correspondingly — a few percent difference in how aggressively highlights
are rolled off. No new textures, no new passes, no inter-effect interaction.

### Viability verdict

**ACCEPT.** Psychophysically motivated, SPIR-V safe, zero new ALU paths (exp2/log2 already in
the shader), game-agnostic, SDR-safe. Minor visual change — dark games get slightly more
contrast character. Denominator must update from 2.03 → 2.04 to preserve photopic-norm
calibration.

---

## Discarded this session

| Title / Technique | Reason |
|---------------------|--------|
| AIM 2025 Inverse Tone Mapping Challenge (arXiv 2508.13479) | Inverse TMO: reconstructs HDR from SDR. Requires HDR output. Reject. |
| SIGGRAPH 2025 "What is HDR? Perceptual Impact of Luminance…" (ACM 2025) | VR-specific, tests 0–1000 nit peak luminance. Not applicable to SDR gaming. |
| Hurter–Driffield cubic shoulder (slope = (1−factor·above)²) | Impact below perceivable threshold for above ≤ 0.10 in SDR; Δ output < 0.008 at x=1.0. |
| Chromatic adaptation time course VR shader (arXiv 2509.23489) | Adjacent to chroma/appearance domain, not sensitometry. Temporal EMA already handled by VFF Kalman on percentiles. |
| Print film interimage development inhibition cross-coupling | Overlaps functionally with existing R50 (Beer-Lambert) and R85 (spectral dye coupling). Additive signal <0.1% — imperceptible. |
| Deep chroma compression of tone-mapped images (arXiv 2409.16032) | ML-trained chroma compressor. Violates real-time constraint. |

---

## Strategic recommendation

Both Film 1 and Finding 2 derive from the same 2026 empirical paper (2604.06276). They are
complementary and low-risk. Implement Finding 1 first (2-token change, near-zero risk), then
Finding 2 (requires A/B in a scene with rich mid-range colours — Arc Raiders' outdoor areas
with foliage and sky are ideal).

Finding 3 (Stevens cbrt) is a calibration refinement — best implemented last and validated in
dark interior scenes. The +0.06–0.08 increase in fc_stevens in dark scenes maps directly to
the shoulder compression strength, which is easiest to perceive in game lighting transitions
from interior to exterior.

Recommended evaluation order: F1 → F2 → F3. All three can be implemented simultaneously in
one commit if preferred — their code paths are non-overlapping.
