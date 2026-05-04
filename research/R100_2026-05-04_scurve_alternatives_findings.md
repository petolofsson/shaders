# R100 — S-Curve Alternatives: Per-Stage Color Theory Review

**Date:** 2026-05-04  
**Status:** Findings complete — no code changes yet  
**Note:** Brave search API key expired during session; research from color science literature (ACES, Kodak sensitometry, Resolve, Adams Zone System).

---

## Proposal

Every smoothstep/S-curve in the pipeline was designed for control, but S-curves have a structural property that is often wrong for the signal: they are **symmetric**. They compress both ends (toe + shoulder) around a pivot. For many of the stages below, only one end needs shaping. The question for each stage: is the symmetry deliberate, incidental, or harmful?

Stages examined:
1. Zone S-curve (Stage 2 — main tonal operator)
2. PivotedSCurve (Stage 3 — per-hue chroma lift)
3. FilmCurve toe blend (Stage 1 — sensitometry)
4. mid_C_boost bell (Stage 3 — midtone chroma)
5. Shadow lift weight / blend smoothsteps (Stage 2)

---

## Findings

---

### HIGH IMPACT

---

#### 1. Zone S-curve → Shoulder-only tonal curve

**Current implementation** (`grade.fx` line 316):
```hlsl
float new_luma = saturate(
    zone_median + (luma - zone_median)
    * (1.0 + zone_str * iqr_scale * (1.0 - abs(luma - zone_median)))
);
```
The `(1.0 - abs(luma - zone_median))` term creates a symmetric S — pixels below the
median are compressed toward it, pixels above are also compressed toward it. Both toe
and shoulder fire.

**Color theory case against the toe:**

Ansel Adams was explicit: the goal of Zone System exposure and development is to place
the scene's dynamic range on the *straight-line portion* of the film curve. Zones III–VII
belong on the linear gamma region. The toe is accepted physics, not a desired aesthetic.
ACES DRT takes the same position: its low end is near-linear; the DRT shoulder handles
highlight rolloff only. Kodak 2383 print LUTs similarly show a long straight midtone
region — the toe is shallow and only catches severe underexposure.

**Shadow compression creates two problems:**
- Crushes shadow detail and local contrast in dark scenes
- Reduces the perceived "depth" of blacks (paradoxically — compressed toe makes blacks
  feel grey, not deep, because the gradient above them is shallower)

**Proposed alternative:** Shoulder-only zone curve — linear below the median, compress
only above it.

```hlsl
float delta    = luma - zone_median;
float shoulder = delta * (1.0 + zone_str * iqr_scale * max(0.0, 1.0 - delta));
float toe_pass = delta;  // linear below pivot
float new_luma = saturate(zone_median + (delta > 0.0 ? shoulder : toe_pass));
```

Or with smoothstep blend to avoid the hard pivot:
```hlsl
float above_w  = smoothstep(-0.05, 0.10, delta);  // fades in just above median
float zone_adj = delta * zone_str * iqr_scale * (1.0 - abs(delta));
float new_luma = saturate(luma + zone_adj * above_w);
```

**Expected visual change:** Shadows open up — more detail, less crushing in dark
interiors. Highlights still compress. Contrast character shifts from "cinematic punch"
toward "filmic depth." The shadow lift (already present) compensates for the loss of
the toe's black lift if needed.

**Risk:** The current toe gives an implicit contrast lift in shadows that users may
be relying on. A/B comparison needed before shipping.

---

#### 2. PivotedSCurve (chroma) → Reinhard-style asymptote

**Current implementation** (`grade.fx` lines 170–175, 419):
```hlsl
float PivotedSCurve(float x, float m, float strength)
{
    float t    = x - m;
    float bent = t + strength * t * (1.0 - abs(t));
    return saturate(m + bent);
}
// ...
new_C += PivotedSCurve(C, pivot, chroma_str) * w;
```
This is a symmetric S-curve centered on `pivot` (the scene mean C for each hue band).
Below pivot: C is boosted. Above pivot: C is compressed. This is partially correct —
lift below pivot is the desired behavior — but the compression above pivot may fight
`gclip`'s MacAdam ceiling, and the S-shape can overshoot if strength is high.

**Color theory case for asymmetric chroma:**

In Oklab, C is Euclidean distance in the a/b plane — perceptually uniform. Three
established alternatives:

- **Power-law**: `C_out = C_in^(1/n)` for n>1. Monotonically increasing, diminishing
  returns at high C, no inflection point. Never compresses, never overshoots. Clean.
- **Reinhard asymptote**: `C_out = C_in / (1 + C_in / C_max)`. Smooth approach to
  C_max, exactly 0 at C=0, never clips. Physically analogous to dye saturation.
- **Lift-only pivoted**: only apply the `t + strength * t * (1.0 - t)` to the below-
  pivot region; above pivot, pass through and let `gclip` own the ceiling.

**Proposed alternative:** Lift-only: boost below pivot, passthrough above, let gclip
compress the ceiling. This gives clean separation of responsibilities.

```hlsl
float lift_only_chroma(float C, float pivot, float strength)
{
    float t    = saturate(1.0 - C / max(pivot, 0.001));  // 1 at C=0, 0 at C=pivot
    return C * (1.0 + strength * t * t);                  // quadratic lift, fades at pivot
}
```

Quadratic lift (t²) is gentler than the current `t*(1-|t|)` and doesn't risk
compression above the pivot.

**Expected visual change:** Undersaturated colors get lifted more cleanly; already-
vivid colors pass through unchanged instead of being re-compressed by the S-curve's
upper arm. gclip's MacAdam ceilings become the sole ceiling — no double-compression.

---

### MEDIUM IMPACT

---

#### 3. FilmCurve toe → linear passthrough

**Current implementation** (`grade.fx` line 264):
```hlsl
ps = lerp(toe, shoulder, smoothstep(0.0, 0.5, ps));
```
Both `toe` and `shoulder` computed, blended by a smoothstep. This creates an S-shaped
sensitometry curve with both a toe (shadows compressed toward Dmin) and a shoulder
(highlights compressed toward Dmax).

**Color theory:** The toe on a real H&D curve is a genuine photochemical phenomenon —
silver halide crystals require a threshold photon count before reduction begins. In
normal cinematographic exposure (Vision3 500T), the straight-line portion covers most
of the scene's dynamic range; the toe only catches deep underexposure (Zone I–II).

**Digital relevance:** The pipeline's SDR input has already been tone-mapped by the
game engine. The game's tonemapper likely applied its own shoulder. Applying a film
toe on top of an already-compressed signal can over-compress shadows that never had
the physical latitude to develop in the first place. FILM_FLOOR already lifts digital
black — the toe's Dmin function is covered.

**Proposed alternative:** Keep the shoulder, linearize the toe region. Concretely:
replace `smoothstep(0.0, 0.5, ps)` with `smoothstep(0.0, 1.0, ps)` (shifts the
blend midpoint to the shoulder only) or compute shoulder-only: pass shadows through
linearly and only apply the curve above a threshold (e.g., above the p25 value).

**Risk:** The toe's warm shadow cast is an intentional film stock character (Dmin base
has warm color). Removing the toe changes the shadow color along with the tone. The
warm shadow cast can be preserved via the 3-way CC SHADOW_TEMP knob if needed.

---

#### 4. mid_C_boost bell → already correct

**Current implementation** (`grade.fx` lines 384–385):
```hlsl
float mid_C_boost = 0.08 * smoothstep(0.22, 0.40, lab.x)
                         * (1.0 - smoothstep(0.55, 0.70, lab.x));
```
This is a **bell curve**, not an S-curve. The product of a rising and falling smoothstep
creates a bump that peaks around L≈0.47 and goes to zero at both ends. This is correct
by design — chroma boost is only wanted in the midtones.

**Verdict: No change needed.** The bell shape is appropriate. If the peak position
needs tuning, shift the smoothstep boundaries. Replacing with a Gaussian bell would
give a smoother rolloff but is ~3× more expensive (exp) with negligible perceptual gain.

---

### LOW IMPACT

---

#### 5. Blend-weight smoothsteps → smootherstep (Perlin)

**Locations:** Multiple blend weights throughout — `lum_att`, `local_range_att`,
`texture_att`, `scotopic_w`, `lift_w`, `hal_bright`, shadow lift, etc.

These smoothsteps are used as **weight functions**, not as direct signal transforms.
They don't shape the output signal directly — they modulate how much of something is
applied. For these uses, the distinction between `smoothstep` and `smootherstep`
(`6t⁵-15t⁴+10t³`, Ken Perlin) is small.

**Smootherstep advantage:** Zero second derivative at endpoints (C² continuity vs.
smoothstep's C¹). This means the blend weight has a softer onset — less of a visible
"ramp start" in edge cases. Matters most when the smoothstep range is wide (>0.1)
and the weight is applied to something perceptually salient.

**Candidates worth upgrading:**
- `shadow_lift_str = lerp(1.50, 0.45, smoothstep(0.025, 0.20, perc.r))` — wide range,
  affects shadow lift globally. Smootherstep would reduce visible lift banding at the
  transition.
- `scotopic_w = 1.0 - smoothstep(0.0, 0.12, new_luma)` — Purkinje onset. Smootherstep
  gives a softer scotopic-to-photopic transition.

**Cost:** Smootherstep is `t*t*t*(t*(t*6-15)+10)` vs `t*t*(3-2t)` — 2 extra MAD per
call. For weight functions that run every pixel, this is negligible on modern GPUs.

**Verdict:** Low priority. Not worth a separate pass — if grade.fx is open for a future
edit, opportunistically upgrade the two candidates above.

---

## Summary

| Stage | Current | Proposed | Impact | Risk |
|-------|---------|----------|--------|------|
| Zone tonal S-curve | Symmetric (toe+shoulder) | Shoulder-only, linear toe | HIGH | Shadow contrast character change |
| PivotedSCurve chroma | Symmetric S | Lift-only quadratic, let gclip own ceiling | HIGH | Double-compression removed |
| FilmCurve | Full S (toe+shoulder) | Shoulder-only, linear toe | MEDIUM | Warm shadow cast changes |
| mid_C_boost | Bell (correct) | No change | — | — |
| Blend-weight smoothsteps | C¹ smoothstep | C² smootherstep (Perlin) | LOW | None |

## Recommended implementation order

1. **Zone shoulder-only** — highest perceptual impact, most justified by color theory. Test A/B with current.
2. **Chroma lift-only** — clean separation from gclip. Low risk.
3. **FilmCurve toe** — only if shadow compression is felt as a problem in-game.
4. **Smootherstep upgrades** — opportunistic, next time grade.fx opens.
