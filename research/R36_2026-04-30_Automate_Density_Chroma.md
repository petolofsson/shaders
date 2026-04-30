# R36 — Automate DENSITY_STRENGTH + CHROMA_STRENGTH
**Date:** 2026-04-30
**Type:** Proposal
**ROI:** Medium — removes 2 knobs, prevents over-saturation on already-vivid scenes and
under-saturation on flat/grey scenes without constant manual retuning

---

## Problem

`DENSITY_STRENGTH = 45` and `CHROMA_STRENGTH = 40` are hardcoded in `creative_values.fx`.
Both are wrong at the extremes:

- **High-chroma scene** (vivid outdoor, neon-lit, skin in warm light) — chroma is already
  rich. A fixed CHROMA_STRENGTH of 40 pushes saturation further than needed, causing
  garish over-saturation. A fixed DENSITY of 45 is fine here (compaction adds the film
  body feel), but could go slightly higher to contain the richness.
- **Low-chroma scene** (night, overcast, grey industrial) — scene is already desaturated.
  Fixed CHROMA_STRENGTH of 40 helps but the headroom for more lift is there. Fixed
  DENSITY of 45 over-compresses what little chroma exists, making it feel washed out.

---

## Signal

`mean_chroma` — the luminance-weighted mean chroma across all 6 hue bands. This is
computable from the ChromaHistoryTex data that `grade.fx` already reads in the CHROMA
loop:

```hlsl
float cm_total = 0.0, cm_w = 0.0;
[unroll] for (int band = 0; band < 6; band++)
{
    float4 hist = tex2D(ChromaHistory, float2((band + 0.5) / 8.0, 0.5 / 4.0));
    cm_total += hist.r * hist.b;   // hist.r = band mean, hist.b = band weight
    cm_w     += hist.b;
}
float mean_chroma = cm_total / max(cm_w, 0.001);
```

`mean_chroma` typically ranges 0.03–0.25:
- 0.03–0.07: night, overcast, grey industrial
- 0.08–0.15: typical mixed indoor/outdoor
- 0.16–0.25: vivid outdoor, Arc Raiders warm industrial lighting

This tap is zero ALU overhead — the loop is the one already written at line ~300.

---

## Formulas

```hlsl
float chroma_adapt = smoothstep(0.05, 0.20, mean_chroma);

float chroma_strength = lerp(55.0, 30.0, chroma_adapt);
float density_strength = lerp(35.0, 52.0, chroma_adapt);
```

| Scene | mean_chroma | CHROMA_STRENGTH | DENSITY_STRENGTH |
|-------|-------------|-----------------|------------------|
| Night / grey | ~0.03–0.06 | 52–55 (boost flat colours) | 35–37 (less compression) |
| Typical | ~0.10–0.14 | 40–46 (near baseline) | 42–46 (near baseline) |
| Vivid outdoor | ~0.18–0.25 | 30–36 (pull back) | 48–52 (contain richness) |

The current hardcoded values (40 / 45) sit near the midpoint — this formula reproduces
them at `mean_chroma ≈ 0.12`, which is the typical Arc Raiders indoor/mixed reading.

---

## Implementation

`grade.fx` — the CHROMA section already has the ChromaHistory loop. Augment it:

```hlsl
// Compute mean_chroma from band stats (zero extra taps — loop already runs)
float cm_total = 0.0, cm_w = 0.0;
float chroma_adapt = 0.0;  // computed after loop

float new_C = 0.0, total_w = 0.0, green_w = 0.0;
[unroll] for (int band = 0; band < 6; band++)
{
    float w     = HueBandWeight(h, GetBandCenter(band));
    float4 hist = tex2D(ChromaHistory, float2((band + 0.5) / 8.0, 0.5 / 4.0));
    new_C   += PivotedSCurve(C, hist.r, chroma_str) * w;
    total_w += w;
    if (band == 2) green_w = w;
    cm_total += hist.r * hist.b;
    cm_w     += hist.b;
}
float mean_chroma    = cm_total / max(cm_w, 0.001);
chroma_adapt         = smoothstep(0.05, 0.20, mean_chroma);
float chroma_str_eff = lerp(55.0, 30.0, chroma_adapt);
float density_str    = lerp(35.0, 52.0, chroma_adapt);
```

Replace the two `#define` reads:
- `CHROMA_STRENGTH / 100.0` → `chroma_str_eff / 100.0`
- `DENSITY_STRENGTH / 100.0` → `density_str / 100.0`

Note: `chroma_str` (the per-pixel hunt-scaled value) is already derived before the loop.
`chroma_str_eff` replaces the `CHROMA_STRENGTH` input to that computation.

Remove `#define DENSITY_STRENGTH` and `#define CHROMA_STRENGTH` from `creative_values.fx`
(arc_raiders + gzw).

---

## Risk

**Interaction with TONAL_STRENGTH:** TONAL_STRENGTH doesn't touch chroma — no coupling.

**Interaction with SHADOW_LIFT (R35):** Independent — R35 drives from p25 (luma),
R36 drives from mean_chroma. No coupling.

**mean_chroma latency:** ChromaHistoryTex is Kalman-smoothed (R28). On scene cuts,
chroma_adapt will track within 3–5 frames — same timeline as the zone/perc signals.
No special handling needed.

---

## Success criteria

- `DENSITY_STRENGTH` and `CHROMA_STRENGTH` removed from `creative_values.fx`
- mean_chroma computed inline in the existing ChromaHistory loop (zero extra taps)
- Vivid outdoor scenes: chroma_str pulls back, density rises slightly — no plastic look
- Grey/night scenes: chroma_str pushes up, density eases — more colour from flat content
- Knob count: 22 → 20 (after R35)
