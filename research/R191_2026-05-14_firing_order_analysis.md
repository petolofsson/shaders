# R191 — Code Analysis: Firing Order & Filmic Workflow

**Date:** 2026-05-14
**Status:** Analysis complete — proposed changes listed at end, pending implementation decision

---

## 1. Research summary — industry standard ordering

Sources: ACESCentral, Dehancer, Noam Kroll, Lowepost, Cullen Kelly Genesis, Blackmagic forum,
PixelTools Film/Emulsion, Boris FX, Epic UE5 docs.

**Professional DI consensus (Resolve / ACES / film finish):**

```
1.  Input normalization          black/white point, exposure
2.  Film curve / negative        negative stock emulation
3.  Primary CC                   exposure trim, white balance
4.  Tonal shaping                zone/S-curve contrast, shadow lift, highlights
5.  Local spatial redistribution Retinex / local tone mapping (before global S-curve)
6.  Secondary CC                 3-way CC, hue rotation
7.  Chroma                       saturation, vibrance, per-hue adjustments
8.  Look transform / print LMT   print stock, bleach bypass (ACES LMT position)
9.  Optical artifacts             halation, lens diffusion
10. Grain                        always last — universally
```

**Key principles from sources:**

- "Technically correct before creatively expressive" (Noam Kroll, Lowepost, color.io)
- ACES explicitly: "the grade modifies the image first, followed by process emulation via LMT"
  (ACESCentral). Print stock / look transforms sit after CC, not before.
- Bleach bypass: "balance the image first, then apply" (Boris FX, Resolve forums). It is a look
  modification, not a correction — digital DI treats it post-grade.
- Local tone mapping: "spatial redistribution before global S-curve" (UE5 docs, academic Retinex
  literature). UE5 local exposure runs before tone mapping and before color grading. The S-curve
  should shape the spatially normalized signal, not the raw uneven one.
- Grain: universally last, no exceptions found.

**Film vs. games — SDR-to-SDR specific:**

- Games (UE5, Unity): local exposure / adaptive luminance before tone curve and CC. Grain last.
  The game pipeline is shorter and more compressed but follows the same macro-order.
- Film scanning / DI: full node chain as above. Print stock is a Look Transform applied after
  primary and secondary CC, not interspersed within it.
- SDR-to-SDR note: in HDR-to-SDR workflows, print/LMT sits before the Output Transform (ODT).
  In SDR-to-SDR there is no ODT — the equivalent position is after all tonal/chroma work and
  before optical finishing (halation, diffusion, grain). This is the natural mapping.

---

## 2. Our current pipeline order

```
CORRECTIVE (ApplyCorrective)
  BLACKS / WHITES                 input remap
  EXPOSURE                        gain
  HAL_STRENGTH / HAL_GAMMA        halation (pre-curve — moved R190)
  FilmCurve                       CURVE_R/B KNEE/TOE
  PRINT_STOCK                     print emulsion
  BLEACH_BYPASS                   silver retention
  3-way CC                        SHADOW/MID/HIGHLIGHT TEMP/TINT

TONAL (ApplyTonal)
  LOCAL_TONE / CLARITY            guided filter redistribution
  CONTRAST                        zone S-curve
  Retinex                         local illuminant normalization
  SHADOWS                         shadow lift
  HIGHLIGHTS                      luma push/pull

CHROMA (ApplyChroma)
  SHADOW_CAST                     pre-flash warm
  Purkinje                        PURKINJE_STRENGTH
  R22 sat-by-luma                 shadow desaturation
  R133 Munsell rolloff            highlight chroma
  ROT_*                           hue rotation
  VIBRANCE                        chroma lift
  SAT_*                           per-band chroma scale
  SATURATION                      global
  HK / Abney / density / gclip    perceptual corrections

OUTPUT (DiffusionPS)
  DIFFUSION_STRENGTH              lens diffusion / bloom
  GRAIN_STRENGTH                  film grain
```

---

## 3. Mismatches against research findings

### Mismatch A — 3-way CC fires after PRINT_STOCK and BLEACH_BYPASS

**Current:** FilmCurve → PRINT_STOCK → BLEACH_BYPASS → 3-way CC
**Research says:** FilmCurve → 3-way CC → PRINT_STOCK → BLEACH_BYPASS

ACES is explicit: the grade adjusts the signal that goes INTO the print emulation. 3-way CC is
primary color correction — it should set up the colors that the print stock then transforms.
Having CC after print stock means you are correcting the combined negative+print response, which
mixes the look transform's color character into the correction. You are tuning the output of the
print emulsion rather than tuning the input to it.

Practical consequence: SHADOW_TEMP/TINT currently corrects the shadow cast that PRINT_STOCK has
already added. Those knobs are fighting the look rather than setting up the scene for it.

**Fix:** Move 3-way CC block before PRINT_STOCK in ApplyCorrective. One function call reorder.

---

### Mismatch B — Retinex fires after zone S-curve

**Current:** LOCAL_TONE → CONTRAST (zone S-curve) → Retinex → SHADOWS
**Research says:** LOCAL_TONE → Retinex → CONTRAST → SHADOWS

Both LOCAL_TONE and Retinex are spatial illumination operators. The research finding (UE5 docs,
academic Retinex literature) is clear: spatial redistribution should precede global tonal
shaping. The S-curve should operate on the spatially normalized signal.

Currently Retinex runs on the post-S-curve `new_luma` — it is trying to remove local illuminant
variation from a signal that already has contrast applied. This is backwards: the S-curve
amplifies the illumination variation that Retinex is then trying to undo.

However: LOCAL_TONE is correctly before CONTRAST, which is the larger-scale spatial operator.
Retinex at 1/16-res is finer-scale than LOCAL_TONE at 1/8-res. A fully correct ordering would
be finest-scale-first: Retinex (1/16-res) → LOCAL_TONE (1/8-res) → CONTRAST (global). This is
the inverse of the current scale ordering.

That said: Retinex is a multiplicative illuminant correction (weak effect, blended at 75% ×
ss_04_25), while LOCAL_TONE is the primary redistribution tool. Swapping them would change the
perceptual weight. The minimum correct fix is Retinex before CONTRAST.

**Fix:** In ApplyTonal, move the Retinex block to execute before the zone S-curve block.

---

### Mismatch C — PRINT_STOCK and BLEACH_BYPASS position relative to TONAL and CHROMA

**Current:** PRINT_STOCK/BLEACH_BYPASS fire inside ApplyCorrective, before all of TONAL and CHROMA.
**Research says:** Print emulation is a Look Transform — it should come after the grade (after CC,
tonal, and chroma), before optical artifacts.

This is the most significant architectural mismatch. PRINT_STOCK desaturates mids ~15% before
VIBRANCE and SAT_* run. BLEACH_BYPASS steepens contrast and crushes shadow saturation before
the zone S-curve, shadow lift, and Retinex run. Everything downstream is compensating for
compression that happened too early.

The correct SDR-to-SDR position: after ApplyChroma (after all tonal and chroma work), before
DiffusionPS (which has halation and grain already). This would require a new function
ApplyLook(out_lin, uv, ctx) inserted between ApplyChroma and the Diffusion passes.

**Architectural impact:** Medium. PRINT_STOCK and BLEACH_BYPASS are currently computed inside
ApplyCorrective which receives `lin` (pre-corrective) and has access to ctx (knees, percentiles).
ApplyPrintStock uses ctx.fc_knee_toe, ctx.fc_knee, ctx.eff_p25, ctx.eff_p75.
ApplyBleachBypass uses only BLEACH_BYPASS scalar.
Moving them requires passing the needed ctx fields to a later-stage function — all already
available in ctx, which is passed through to ApplyChroma and returned to ColorTransformPS.

---

### Mismatch D — Halation placement (noted, not a definitive error)

**Current:** Pre-curve (we moved it in this session — physically: camera negative model)
**Research says:** Dehancer, Genesis, PixelTools all place halation post-print, in the "finishing"
tier. Physical rationale: halation scatter is baked into the negative before printing, so the
print emulsion sees the halo-containing negative — halation comes before print in the physical
chain, but after it in the visual evaluation chain.

For SDR-to-SDR this is genuinely ambiguous:
- Physical model → pre-curve (where we have it now)
- Professional tools / visual evaluation → post-print

The pre-curve fix we made this session was motivated by signal consistency (lf_mip1 and pixel
both pre-corrective = accurate ring detection). That argument holds regardless of where print
stock sits. If PRINT_STOCK moves after CHROMA (Mismatch C fix), halation would be physically
between negative and print, which is actually more correct than the old post-FilmCurve position
even if it's before print in the code order.

**Decision:** Leave halation pre-curve for now. Revisit if Mismatch C is implemented.

---

## 4. Summary table

| # | Operation | Current position | Research position | Mismatch? |
|---|-----------|-----------------|-------------------|-----------|
| BLACKS/WHITES/EXPOSURE | Input normalization | First | First | ✓ |
| FilmCurve | Negative emulation | After exposure | After exposure | ✓ |
| HAL | Halation | Pre-curve | Post-print (ambiguous) | ⚠ minor |
| 3-way CC | Primary CC | After print stock | Before print stock | ✗ |
| PRINT_STOCK | Print emulation LMT | Mid-corrective | After all grading | ✗ |
| BLEACH_BYPASS | Silver retention | Mid-corrective | After all grading | ✗ |
| LOCAL_TONE | Local TMO | Before S-curve | Before S-curve | ✓ |
| Retinex | Local illuminant | After S-curve | Before S-curve | ✗ |
| CONTRAST | Zone S-curve | After LOCAL_TONE | After spatial ops | ✓ |
| SHADOWS/HIGHLIGHTS | Tonal | After Retinex | After contrast | ✓ |
| ROT_* | Hue rotation | After PURKINJE | After tonal | ✓ |
| VIBRANCE/SAT | Chroma | After ROT | After tonal | ✓ |
| PURKINJE | Scotopic | Before ROT | After tonal | ⚠ minor |
| DIFFUSION | Lens diffusion | Last pass | After look LMT | ✓ |
| GRAIN | Film grain | Last in Diffusion | Last | ✓ |

---

## 5. Proposed changes — priority order

### P1 — Retinex before zone S-curve (low risk, clear win)

In `ApplyTonal`, swap the execution order: Retinex block before the zone S-curve block.
Retinex currently reads `new_luma` post-S-curve. After the fix it reads `luma` pre-S-curve,
and the S-curve then shapes the Retinex-normalized signal. Single block reorder, no new textures.

Calibration: CONTRAST and SHADOWS values may need slight recalibration (S-curve now sees a
different input distribution). Expect minor adjustments.

### P2 — 3-way CC before PRINT_STOCK/BLEACH_BYPASS (low risk, clear win)

In `ApplyCorrective`, move the `Apply3WayCC` call to before `ApplyPrintStock`. One line move.
No new textures, no new passes. CC now shapes the negative before print emulation receives it.

Calibration: SHADOW_TEMP/TINT values will need recalibration — they are currently compensating
for PRINT_STOCK's shadow cast, which will now be applied after CC. Expect the existing values
to overpower once they're no longer fighting the print stock.

### P3 — PRINT_STOCK and BLEACH_BYPASS after CHROMA (medium risk, architectural)

Extract PRINT_STOCK/BLEACH_BYPASS from ApplyCorrective. Add an ApplyLook function called from
ColorTransformPS after ApplyChroma returns, before the Diffusion passes. Pass the necessary
ctx fields (fc_knee_toe, fc_knee, eff_p25, eff_p75) through.

Calibration: significant. VIBRANCE/SAT/SATURATION currently work on the pre-print signal;
after this fix they work on the full saturated image and the print stock desaturates on top.
BLEACH_BYPASS shadow contrast will be more visible (not attenuated by subsequent Retinex/lift).
Expect recalibration of VIBRANCE, SAT_*, PRINT_STOCK, BLEACH_BYPASS.

---

## 6. SDR-to-SDR specific notes

In HDR-to-SDR, print/LMT precedes the ODT which handles range compression. In SDR-to-SDR
there is no range compression pass — the signal is already in display range. This makes the
"print stock last" position even more correct for us: with no ODT to catch gamut/range issues,
running print stock on the fully graded signal (P3) means the final saturate() at the end of
ApplyChroma has already handled clipping before print stock adds its density. Print stock
getting saturate()'d is the correct behavior — it mirrors what happens on real print emulsion
when highlights clip to paper-white.

---

## 7. Recommendation

Implement P1 and P2 together in one session — both are small code reorders with clear
research backing and low implementation risk. Calibrate creative_values.fx after.

P3 is a larger change. Evaluate after P1+P2 are stable. The visual improvement (print stock
no longer fighting chroma adjustments, bleach bypass not suppressing shadow lift) is real,
but requires a full recalibration pass on both profiles.
