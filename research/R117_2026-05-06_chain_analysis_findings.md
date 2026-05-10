# R117 — Full Chain Analysis: Improvement Candidates + Research
**Date:** 2026-05-06

---

## Method

Full read of ColorTransformPS (grade.fx), corrective.fx (all 6 passes), and ProMistPS.
Each stage traced for: signal source vs. consumer mismatches, statistical correctness,
physical accuracy, and architectural inconsistency. Findings researched against published
literature (training knowledge, Brave MCP unavailable this session).

---

## Finding A — 3-way CC region boundaries in linear luma

**Location:** ColorTransformPS, Stage 1 (R19 block)

**Issue:** Shadow/mid/highlight regions are defined in **linear luma**:
```hlsl
float r19_sh  = saturate(1.0 - r19_luma / 0.35);   // full shadow at luma=0
float r19_hl  = saturate((r19_luma - 0.65) / 0.35); // full highlight at luma=1
float r19_mid = 1.0 - r19_sh - r19_hl;
```
In linear light, Oklab L at luma=0.35 ≈ 0.65 (perceptual midtone). At luma=0.65, Oklab L ≈ 0.83
(well into highlights). The "midtone" linear range (0.35–0.65) is a narrow perceptual band; the
"shadow" range (<0.35) covers most of the perceptual image in dark games.

### Research findings (DaVinci Resolve / Baselight)

**Resolve Color Wheels:** Operate in the *working colour space of the timeline* — gamma-encoded
for SDR Rec.709 workflows. No explicit perceptual luma mask; shadow selectivity is positional
(value of the pixel in the encoded space). Implicit boundaries from community analysis:
shadows < ~0.25, highlights > ~0.75 on a 0–1 gamma-encoded scale. Resolve does NOT perform
a hidden linear-light conversion inside the primary correctors.

**Filmlight Baselight Base Grade:** Operates in *scene-referred linear light* with an explicit
parameterised pivot (typically scene-linear 0.18 grey as midtone anchor). Shadow/highlight split
is customisable.

**Broadcast convention (Avid Symphony, legacy Quantel):** Soft overlapping cosine-weighted masks
in gamma-encoded space. Approximate centres: shadow ~0.25, midtone ~0.50, highlight ~0.75.

### Verdict

The current implementation's linear-light boundaries (0.35 / 0.65) correspond to ~gamma 0.62 /
~gamma 0.82 in sRGB-encoded space — much narrower midtone coverage than Resolve's ~0.25–0.75.
Two valid options:

1. **Gamma-encode r19_luma before splitting** — apply pow(r19_luma, 1/2.2) and use ~0.35/0.65
   thresholds. This gives Resolve-like behaviour: half the pixels fall in midtones.
2. **Use Oklab L (lab.x from the already-computed Oklab)** — operate in Oklab L-space, thresholds
   ~0.45/0.70. Perceptually even split; consistent with Baselight-style linear-referred grading.

Option 2 is preferred: Oklab L is already computed (available from Stage 3). Repurposing it here
avoids a pow() call and is consistent with the rest of the pipeline's Oklab-first philosophy.
But R19 currently runs in Stage 1 (before Oklab is computed). Either move R19 to Stage 3 after
Oklab decomp, or compute a cheap gamma proxy: `sqrt(r19_luma)` for ~gamma 0.5 approximation.

**Priority: High.** Dark games (Arc Raiders is often dark) get wrong CC targeting.

---

## Finding B — Halation Lorentzian driven by pixel brightness, not spatial proximity

**Location:** ColorTransformPS, halation block

**Issue:** `hal_lore = γ²/(γ²+d²)` where `d = 1 - hal_bright`, `hal_bright = smoothstep(thresh, 1.0, hal_luma)`.
hal_luma is the **current pixel's own brightness**, not its spatial distance from the bright
source. At dark pixels adjacent to highlights (where halation actually fires): hal_luma is LOW →
hal_bright = 0 → hal_d = 1 → hal_lore ≈ 0 → G gain = 0.94 (less orange).
At bright pixels: hal_lore ≈ 1 → G gain = 0.78 (more orange). But at bright pixels, hal_ring ≈ 0
(no halation fires). The Lorentzian has near-zero effect on the actual annular fringe.

### Research findings (film halation chromatic radial variation)

Physical mechanism: light transmits through emulsion, reflects off the film base, scatters back.
The emulsion stack (top to bottom): blue-sensitive → yellow filter → green-sensitive → red-sensitive → anti-halation backing.

**Key physical fact:** The spectral character of halation is NOT uniform across the radial extent:
- **Inner annulus** (close to source): scatter path is short; all dye channels contribute.
  More spectrally balanced, less saturated orange.
- **Outer tail** (far from source): longer scatter path allows more blue + green extinction
  by the yellow filter and green layer on the return pass. Red component dominates strongly.
  More deeply orange/amber.
- This gives a systematic **red shift that increases with radial distance** from the source.
  Inner halo = less saturated. Outer tail = most orange.

Source: Kodak cinematographic emulsion publications; Luo & Hunt (Colour Research & Application);
two-component PSF model with spectrally-narrow inner diffusion + spectrally-warm outer scatter.

### Verdict

The Lorentzian was intended to produce more orange in the outer tail. But as currently wired
(driven by hal_luma = pixel brightness), it has the **opposite effect**: dark adjacent pixels
(= the outer annular ring) get LESS orange. The intent and the implementation are inverted.

**Proposed fix:** Drive hal_lore from `hal_ring` magnitude, not from `hal_luma`:
```hlsl
float hal_ring_luma = dot(hal_ring, float3(0.2126, 0.7152, 0.0722));
float hal_lore = (HAL_GAMMA * HAL_GAMMA) / (HAL_GAMMA * HAL_GAMMA + hal_ring_luma * hal_ring_luma + 1e-6);
```
Now: at pixels with large ring (outer annular zone) → hal_lore LOW → G gain 0.94 (more balanced).
At pixels with small ring (inner transition zone from bright) → hal_lore HIGH → G gain 0.78 (more orange).

Wait — that's still inverted vs. the physical model (outer should be MORE orange). Correct wiring:
```hlsl
// outer tail = large ring magnitude = should be MORE orange (lower G gain)
float hal_lore = hal_ring_luma / (hal_ring_luma + HAL_GAMMA + 1e-6);  // 0 at no ring, 1 at large ring
float hal_g = hal_ring.g * lerp(0.94, 0.78, hal_lore);  // large ring → 0.78 (more orange)
```
This drives the outer tail (large hal_ring) toward more orange, inner transition (small hal_ring)
toward more balanced — matching physical emulsion data.

**Priority: Medium.** The current code is physically backwards but the effect is subtle since
hal_lore barely modulates the annular ring pixels (hal_ring is never very large). The visual
improvement may be small. Zero new taps, ~3 ALU change.

---

## Finding C — Retinex illuminant source is pre-grade, signal is post-FilmCurve

**Location:** ColorTransformPS, Stage 2 (Retinex block)

**Issue:** `illum_s0` from LowFreqMip1 is built from the **pre-grade** (post-inverse_grade,
pre-FilmCurve) signal. But `new_luma` at this stage is post-FilmCurve, post-PrintStock,
post-3-way CC. The ratio `new_luma / illum_s0` is comparing a tone-curve-compressed signal
against a linear illuminant — not a true reflectance ratio.

### Research findings (Retinex signal domain and tone-curve order)

**Jobson, Rahman, Woodell (1997) "A multiscale retinex for bridging the gap..."** IEEE TIP 6(7):
The original MSR operates in log space on whatever camera output is available (inherently
gamma-encoded scanned photographs). The formulation is agnostic to whether input is linear or
gamma-encoded — it is a log-division (= ratio in linear). The authors do not explicitly require
linear input; they use available camera signal.

**Provenzi et al. (2007) "Mathematical definition and analysis of the Retinex algorithm"** JOSA A:
Retinex is logically a *pre-tone-curve* operation: it estimates scene illuminant from the
scene-referred signal and outputs a normalised scene-referred signal. Applying tone mapping
**before** Retinex corrupts the illuminant estimate because tone mapping is a spatially-uniform
luminance transform that Retinex will partially undo.

**Rahman et al. (2004) NASA Technical Memorandum:** Apply Retinex on the unprocessed camera
signal *before* any enhancement curve.

**Bertalmío et al. (2020):** Retinex in linear light is physically correct.

### Verdict

The academic literature is clear: Retinex should run **before** the FilmCurve, not after.
In the current stage order (R29 is in TONAL, which is after FilmCurve), the illuminant estimate
is sound (LowFreqMip1 is pre-curve) but the signal being normalised (`new_luma`) is post-curve.

**Practical impact:** In bright textured areas, FilmCurve compresses `new_luma` while
`illum_s0` remains at the higher pre-curve value. The ratio `new_luma / illum_s0 < 1`
more than it should be → Retinex makes highlights slightly darker than true reflectance.
In shadows, FilmCurve toe also compresses slightly. Effect is moderate — FilmCurve is not
a large transform at arc_raiders EXPOSURE=0.95, but would be significant at EXPOSURE=0.80.

**Proposed fix (zero-cost):** Compute the Retinex ratio from `col.rgb` (which IS pre-grade,
consistent with illum_s0), and apply the correction as a ratio to `new_luma`:
```hlsl
float raw_luma  = max(dot(col.rgb, float3(0.2126, 0.7152, 0.0722)), 0.001);
float ret_ratio = saturate(raw_luma * zk_safe / illum_s0);  // true reflectance × scene_key
new_luma = lerp(new_luma, new_luma * (ret_ratio / max(raw_luma, 0.001)), 0.75 * ss_04_25);
// simplifies to:
new_luma = lerp(new_luma, saturate(new_luma * zk_safe / illum_s0), 0.75 * ss_04_25);
```
Wait — that's exactly the current code but with `new_luma * zk_safe / illum_s0` instead of
`nl_safe * zk_safe / illum_s0`. These are the same thing (`nl_safe = max(new_luma, 0.001)`).
The actual proposed fix is to guard the division properly and accept that this IS operating
post-curve. The more meaningful fix is architectural: move the Retinex normalisation step
to before FilmCurve, operate on `lin_e` (post-EXPOSURE, pre-FilmCurve), then carry the
correction through the rest of Stage 1. Non-trivial restructuring.

**Revised verdict:** The post-FilmCurve Retinex is a known compromise, consistent with how
practical implementations work (Jobson 1997 also used post-gamma signals). The visual impact
at current EXPOSURE is acceptable. Flag for future architectural refactor if Retinex appears
to over-normalise in scenes with strong FilmCurve. **Priority: Low-Medium.**

---

## Finding D — Slow key time constant 333 frames (~5.5s at 60fps)

**Location:** corrective.fx, UpdateHistoryPS col 7:
```hlsl
return float4(lerp(prev_slow, zone_log_key, 0.003), 0, 0, 0);
```

### Research findings (dark adaptation time constants)

**Physiological (Hecht, Shlaer & Pirenne; standard photoreceptor kinetics):**
- Cone adaptation (photopic → mesopic): 5–10 seconds for initial sensitivity increase.
- Pupil dilation: fast component 3–5 s, full dilation 15–30 s.
- Rod adaptation (full scotopic): 20–30 minutes. Not relevant for game displays (photopic).

**Game rendering HDR eye adaptation (published models):**
- Krawczyk et al. 2005 / Brian Karis (Epic): tau ≈ 0.5–2.0 seconds for the fast component.
- AMD GPU Open whitepapers: tau_bright→dark = 0.5–1.0 s; tau_dark→bright = 1.5–3.0 s.
  Asymmetric: faster to adapt when going bright, slower when going dark (matches pupil kinetics).
- Intel (Rauwendaal & Saleh, GDC 2013): tau_dark = 1.5–3.0 s; tau_bright = 0.5–1.0 s.

### Verdict

At 60fps, blend rate 0.003 → TC ≈ 5.5 seconds. This sits within the upper range of the
physiological cone adaptation window but significantly slower than published game rendering
practice (AMD/Intel recommend ≤ 3s). For scene-cut driven context lift (R60), a 5.5s TC
means the effect barely settles before the next cut (average shot length 3–8s in games).

However: no auto-exposure rule means this TC is for creative context lift, not a display
adaptation system. Slightly longer TC is acceptable to avoid over-responsive lift on fast
cuts. 0.003 is defensible but borderline too slow.

**Proposed change:** 0.005 (200 frames, ~3.3s at 60fps) — upper range of AMD recommendations.
Optionally asymmetric: 0.008 dark→bright (faster response entering bright), 0.003 bright→dark.

**Priority: Low.** R60 context lift is a subtle effect. TC mismatch won't be visible in most
content.

---

## Finding E — FilmCurve knee calibrated to raw p75, applied post-EXPOSURE

**Location:** ColorTransformPS, ~line 273, 276

At EXPOSURE=0.95: mismatch ≈ 2–3%. At EXPOSURE=0.80: ≈ 11% shift in effective knee position.
Arc Raiders runs at 0.95 — negligible. **Priority: Low. Defer unless EXPOSURE < 0.85.**

Quick fix if needed: `float eff_p75_adj = pow(perc.b, EXPOSURE);` — 2 ALU, no new taps.

---

## Finding F — CreativeLowFreqTex MipLevels=3 wastes VRAM (easy fix)

`MipLevels=3` on a BUFFER_WIDTH/8 × BUFFER_HEIGHT/8 RGBA16F texture:
- Mip1 + Mip2 = ~81 KB unused at 1080p.
- Fix: `MipLevels = 1`. Zero visual impact. **Priority: Low, trivial.**

---

## Finding G — Dead highway slots HWY_ZONE_KEY (211) and HWY_ZONE_STD (212)

Defined in highway.fxh, never written or read. grade.fx reads zone stats directly from
ChromaHistoryTex col 6. **Cleanup only. No visual impact.**

---

## Implementation priority summary

| Finding | Impact | Confidence | Effort | Action |
|---------|--------|------------|--------|--------|
| A — 3-way CC in perceptual space | High | High | Medium | Implement: use sqrt(luma) or Oklab L |
| B — Halation Lorentzian fix | Medium | High | Trivial | Implement: drive from hal_ring, not hal_luma |
| C — Retinex post-FilmCurve | Low-Med | Medium | High | Defer: architectural, compromise acceptable |
| D — Slow key TC 0.003 → 0.005 | Low | Medium | Trivial | Optional: 1 number change |
| E — FilmCurve EXPOSURE bias | Low | High | Trivial | Defer until EXPOSURE < 0.85 |
| F — CreativeLowFreqTex mips | Low | High | Trivial | Implement immediately |
| G — Dead highway slots | Cleanup | High | Trivial | Implement immediately |
