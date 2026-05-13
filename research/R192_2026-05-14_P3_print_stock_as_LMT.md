# R192 — Session Plan: PRINT_STOCK/BLEACH_BYPASS as Post-Grade LMT (P3)

**Date:** 2026-05-14
**Status:** Plan only — not yet implemented. Implement in a dedicated session.

---

## Background

R191 identified three pipeline mismatches vs. industry standard. P1 and P2 were implemented
2026-05-14:

- **P1 done** — Retinex now fires before zone S-curve in ApplyTonal
- **P2 done** — Apply3WayCC now fires before ApplyPrintStock in ApplyCorrective

**P3** is the largest remaining mismatch: PRINT_STOCK and BLEACH_BYPASS currently run inside
ApplyCorrective, before all tonal and chroma work. Research says print emulation is a Look
Modification Transform — it should run after all grade (after ApplyChroma), before optical
finishing (diffusion, grain).

---

## Current state (post P1+P2)

ApplyCorrective firing order:
```
EXPOSURE → DIR couplers → Halation (pre-curve) → FilmCurve
→ Apply3WayCC
→ ApplyPrintStock → ApplyMaskingCoupler → ApplyDyeMatrix → ApplyBleachBypass
```

ColorTransformPS call order:
```
ApplyCorrective → ApplyTonal → ApplyChroma → dither → return
```

---

## Target state

ApplyCorrective firing order:
```
EXPOSURE → DIR couplers → Halation (pre-curve) → FilmCurve → Apply3WayCC
```

New ApplyLook function (called post-ApplyChroma):
```
ApplyPrintStock → ApplyMaskingCoupler → ApplyDyeMatrix → ApplyBleachBypass
```

ColorTransformPS call order:
```
ApplyCorrective → ApplyTonal → ApplyChroma → ApplyLook → dither → return
```

---

## Implementation steps

### Step 1 — Remove print stock chain from ApplyCorrective

In `ApplyCorrective` (grade.fx ~line 433), delete:
```hlsl
    // ── R51: print stock + R110: masking coupler + R130: dye matrix + bleach ──
    out_lin = ApplyPrintStock(out_lin, ctx.fc_knee_toe, ctx.fc_knee, PRINT_STOCK,
                              ctx.eff_p25, ctx.eff_p75);
    out_lin = ApplyMaskingCoupler(out_lin, PRINT_STOCK);
    out_lin = ApplyDyeMatrix(out_lin);
    out_lin = ApplyBleachBypass(out_lin, BLEACH_BYPASS);
```

ApplyCorrective then ends after Apply3WayCC:
```hlsl
    out_lin = Apply3WayCC(out_lin,
                          SHADOW_TEMP, SHADOW_TINT,
                          MID_TEMP, MID_TINT,
                          HIGHLIGHT_TEMP, HIGHLIGHT_TINT);
    return out_lin;
```

### Step 2 — Add ApplyLook function

Insert before ColorTransformPS (after ApplyChroma in the file):

```hlsl
float3 ApplyLook(float3 lin, SceneCtx ctx)
{
    float3 out_lin = lin;
    out_lin = ApplyPrintStock(out_lin, ctx.fc_knee_toe, ctx.fc_knee, PRINT_STOCK,
                              ctx.eff_p25, ctx.eff_p75);
    out_lin = ApplyMaskingCoupler(out_lin, PRINT_STOCK);
    out_lin = ApplyDyeMatrix(out_lin);
    out_lin = ApplyBleachBypass(out_lin, BLEACH_BYPASS);
    return out_lin;
}
```

### Step 3 — Call ApplyLook from ColorTransformPS

In ColorTransformPS (~line 737), change:
```hlsl
    float3 result  = ApplyChroma(tonal.lin, tonal.new_luma, tonal.local_var, lf_mip2_tex, ctx);
```
to:
```hlsl
    float3 result  = ApplyChroma(tonal.lin, tonal.new_luma, tonal.local_var, lf_mip2_tex, ctx);
    result = ApplyLook(result, ctx);
```

### Step 4 — ctx field availability

All fields ApplyLook needs are already in ctx (computed in BuildSceneCtx, passed through):
| Field | Used by | Status |
|-------|---------|--------|
| `ctx.fc_knee_toe` | ApplyPrintStock | ✓ in ctx |
| `ctx.fc_knee` | ApplyPrintStock | ✓ in ctx |
| `ctx.eff_p25` | ApplyPrintStock | ✓ in ctx |
| `ctx.eff_p75` | ApplyPrintStock | ✓ in ctx |
| `PRINT_STOCK` | ApplyPrintStock, ApplyMaskingCoupler | ✓ scalar define |
| `BLEACH_BYPASS` | ApplyBleachBypass | ✓ scalar define |

No new textures, no new passes, no new ctx fields needed.

### Step 5 — Update creative_values.fx comments (both profiles)

PRINT_STOCK and BLEACH_BYPASS comments currently say "on top of FilmCurve". Update to reflect
that they fire after all chroma work:

```
// Kodak 2383 print emulsion — applied as a look after all grading and chroma work.
// ...
#define PRINT_STOCK  0.35
// Skip the bleach step during print development ...
// Applied as a look after print emulation.
#define BLEACH_BYPASS  0.05
```

Also update the firing-order section headers in creative_values.fx. Currently PRINT_STOCK is
under CORRECTIVE. After P3 it fires after CHROMA — move it to its own OUTPUT or LOOK section,
or insert it between CHROMA and OUTPUT in both files.

---

## Calibration expectations

### PRINT_STOCK

Currently: fires before VIBRANCE, SAT_*, SATURATION, Purkinje, hue rotation, Munsell rolloff.
After P3: fires after all of those.

PRINT_STOCK desaturates mids ~15% and adds a warm shadow bow. When it fired first, VIBRANCE
and SAT_* were boosting back into a pre-desaturated signal. After P3, VIBRANCE/SAT work on
the full-chroma grade, then print stock desaturates on top.

**Expected direction of change:**
- Image will appear more desaturated overall at the same PRINT_STOCK value
- Warm shadow bow will be more visible and less compensated by subsequent chroma work
- VIBRANCE may need to come down slightly (currently fighting print stock)
- PRINT_STOCK strength may feel stronger — consider dialing from 0.35 toward 0.25–0.30 first

### BLEACH_BYPASS

Currently: steepens midtone contrast and crushes shadow saturation before zone S-curve,
Retinex, shadow lift. Those operations were partially compensating.
After P3: runs on the fully graded, tonal-lifted signal. Shadow desaturation will be
denser. Midtone contrast steepening will ride on top of zone S-curve result.

**Expected direction of change:**
- Shadow desaturation more pronounced — reduce BLEACH_BYPASS first (try 0.03 from 0.05)
- The "grit" character will be more visible and not softened by Retinex

### 3-way CC (SHADOW_TEMP/TINT)

After P2 (already done), CC fires before print stock. The warm shadow cast from PRINT_STOCK
will hit after CC. Existing SHADOW_TEMP = −5 was partly compensating for print stock's warm
cast — after P2+P3 together that compensation is no longer fighting print stock's output.
**SHADOW_TEMP will likely want to move closer to 0** once P3 is evaluated.

---

## Halation note

Halation pre-curve position is physically correct regardless of where print stock sits.
Halation is a camera-negative phenomenon; print stock is a printing phenomenon. After P3,
the physical order in code becomes:
```
camera negative (halation) → FilmCurve (negative response) → 3-way CC → ... → print stock
```
This is the most physically correct model yet — halation before negative curve, CC before
print, print last.

---

## Risk assessment

**Low risk for correctness.** No new math, no new algorithm. Pure reordering of existing
function calls. All ctx fields available at the call site.

**Medium risk for calibration.** Both profiles will need re-tuning. The chroma knobs
(VIBRANCE, SAT_*, SATURATION) are currently calibrated against a pre-desaturated signal.
After P3 they work on the full-chroma image and print stock desaturates at the end.
Recommend starting with `PRINT_STOCK 0.30`, `BLEACH_BYPASS 0.03`, then recalibrate
VIBRANCE and SAT_* from their current values downward.

**No GPU cost change.** Same function calls, same passes. ApplyLook is a pure inline
function reorder with zero ALU overhead vs. current.

---

## Files to touch

| File | Change |
|------|--------|
| `general/grade/grade.fx` | Remove 4 lines from ApplyCorrective; add ApplyLook function; add 1 call line in ColorTransformPS |
| `gamespecific/arc_raiders/shaders/creative_values.fx` | Move PRINT_STOCK/BLEACH_BYPASS to new LOOK section after CHROMA; update comments |
| `gamespecific/gzw/shaders/creative_values.fx` | Same as above |
| `HANDOFF.md` | Document P3 implementation |
| `CHANGELOG.md` | R192 entry |
