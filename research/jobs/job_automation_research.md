## Nightly Job B — Automation & Knob Reduction Research

**Schedule:** 04:00 daily  
**Output:** `/home/pol/code/shaders/research/nightly_automation_{YYYY-MM-DD}.md`  
**Do not modify any source files.**

---

### Context — read these first

1. `/home/pol/code/shaders/CLAUDE.md` — pipeline constraints and philosophy
2. `/home/pol/code/shaders/research/HANDOFF.md` — full pipeline state, all knobs, all implemented Rx jobs
3. `/home/pol/code/shaders/gamespecific/arc_raiders/shaders/creative_values.fx` — current 24 knobs with values
4. `/home/pol/code/shaders/general/grade/grade.fx` — MegaPass: how each knob is consumed in code
5. `/home/pol/code/shaders/general/corrective/corrective.fx` — what analysis data is already computed

---

### Background

The pipeline has 24 user-facing knobs. The goal is to reduce this to ~9 **artistic** knobs (those encoding deliberate creative intent) by automating the remaining **scene-descriptive** knobs — ones whose correct value is determined by what the image looks like, not by artistic preference.

**Knobs that must stay** (artistic intent, not derivable from scene statistics):
- `EXPOSURE` — deliberate luminance placement; explicitly not auto-exposure per CLAUDE.md
- `SHADOW_TEMP`, `SHADOW_TINT`, `MID_TEMP`, `MID_TINT`, `HIGHLIGHT_TEMP`, `HIGHLIGHT_TINT` — primary color grade (6 knobs)
- `CURVE_R_KNEE`, `CURVE_B_KNEE`, `CURVE_R_TOE`, `CURVE_B_TOE` — film stock character (4 knobs)  
- `ROT_RED`, `ROT_YELLOW`, `ROT_GREEN`, `ROT_CYAN`, `ROT_BLUE`, `ROT_MAG` — hue rotation intent (6 knobs)
- `CORRECTIVE_STRENGTH`, `TONAL_STRENGTH` — stage gates, not tuning knobs

**Candidates for automation** (5 knobs, scene-descriptive):
- `CLARITY_STRENGTH 35`
- `SHADOW_LIFT 15`
- `DENSITY_STRENGTH 45`
- `CHROMA_STRENGTH 40`
- `SPATIAL_NORM_STRENGTH 20`

**Analysis data already available** (written by corrective.fx before grade.fx runs):
- `PercTex` 1×1 RGBA16F — global p25 (.r), p50 (.g), p75 (.b) of luma
- `ZoneHistoryTex` 4×4 RGBA16F — per-zone smoothed median (.r), p25 (.g), p75 (.b) — 16 zones
- `CreativeZoneHistTex` 32×16 R16F — 32-bin luma histogram per zone
- `ChromaHistoryTex` — per-hue chroma statistics
- `CreativeLowFreqTex` — 1/8-res base image (luma in .a)
- `zone_std` — standard deviation of the 16 zone medians (already computed in grade.fx Stage 2)

**Constraints from CLAUDE.md that all automation must respect:**
- No gates (hard conditionals on pixel properties) — automation target functions must be smooth
- No auto-exposure
- SDR by construction — all outputs [0,1]
- `creative_values.fx` is the only tuning surface — automation replaces a #define with a computed value; the knob may still exist as a manual override ceiling

---

### Task

For each of the 5 candidate knobs, derive a psychophysically grounded target function using the available analysis data. Then search for 2024–2026 research that either validates or improves the proposed function.

#### For each knob, produce:

1. **Current behaviour** — what the knob does in code (read from grade.fx), at what stage, on what signal
2. **Scene-descriptive target** — what value should this knob take as a function of the scene statistics? Derive from first principles (e.g., SHADOW_LIFT should decrease when p25 is already high — the shadows are already bright)
3. **Proposed formula** — concrete HLSL-compatible expression using available analysis data. Must be smooth (no hard conditionals). Must produce a value in the knob's valid range.
4. **Literature support** — use Brave Search to find 2024–2026 papers supporting or refining this formula. Search arxiv.org, acm.org, and IEEE Xplore. Prefer papers with accessible abstracts or PDFs. If no strong paper exists, note that.
5. **Risk** — what could go wrong? (e.g., does automating CLARITY cause pumping on scene cuts?)

#### Specific derivation notes per knob

**CLARITY_STRENGTH:** Clarity boosts local midtone contrast. In flat/low-detail scenes it should reduce (nothing to sharpen). In textured scenes it can be higher. The signal for "image detail density" exists in `CreativeLowFreqTex` — the residual between full-res and low-freq already drives the clarity kernel. Compute a scalar scene detail measure from this texture and map it to [20, 45].

**SHADOW_LIFT:** Raises the toe. The correct lift is inversely related to where the shadows naturally sit. Use `PercTex.r` (p25) as the anchor: if p25 is already > 0.15, the game's own shadows are bright and less lift is needed. Derive a monotonically decreasing function of p25.

**DENSITY_STRENGTH:** Subtractive density compacts chroma. Over-dense scenes (high average C from ChromaHistoryTex) need less density applied — the image already has the "film compaction body feel". Derive from mean chroma across ChromaHistoryTex.

**CHROMA_STRENGTH:** Per-hue saturation bend. High average scene saturation means less bend is needed. Low average saturation (desaturated scenes — fog, overcast) may benefit from more bend. Derive from ChromaHistoryTex mean chroma, inverse to DENSITY logic.

**SPATIAL_NORM_STRENGTH:** Pulls zone medians toward the global key. Already partially automated (zone_std drives zone S-curve strength). SPATIAL_NORM should also track zone_std: high zone_std (contrasty scene) = strong spatial normalisation needed; low zone_std (flat scene) = less useful. Derive from zone_std, same signal as existing zone_str automation.

#### Stevens + Hunt connection

R11 (Stevens + Hunt, researched but not coded) is directly relevant here. Stevens effect: apparent contrast increases with adaptation luminance — a brighter scene looks more contrasty even at the same physical contrast ratio. Hunt effect: saturation appears higher at higher luminance. These are psychophysical arguments for making CLARITY and CHROMA functions of `PercTex.g` (global p50 / scene key). Include Stevens + Hunt in the Brave Search and assess whether they should anchor the CLARITY and CHROMA automation formulas.

---

### Output format

```
# Nightly Automation Research — {YYYY-MM-DD}

## Summary
{2–3 sentences: which knobs have strong automation candidates, which are risky}

## CLARITY_STRENGTH
### Current behaviour
### Proposed formula
### Literature support
### Risk

## SHADOW_LIFT
...

## DENSITY_STRENGTH
...

## CHROMA_STRENGTH
...

## SPATIAL_NORM_STRENGTH
...

## Stevens + Hunt as automation anchor
{assessment — should p50 drive CLARITY and CHROMA? What does the literature say?}

## Implementation priority
| Knob | Confidence | Risk | Recommended order |
|------|------------|------|------------------|
...

## Brave Search findings
{list papers found, with title, authors, year, and 2-sentence relevance summary}
```
