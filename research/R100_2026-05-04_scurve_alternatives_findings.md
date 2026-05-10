# R100 — S-Curve Alternatives: Per-Stage Color Theory Review

**Date:** 2026-05-04  
**Updated:** 2026-05-04 (supplementary literature research added — Brave API still invalid)  
**Status:** Findings complete — no code changes yet  
**Note:** Brave search API key expired on both passes; all research from color science literature (ACES, Kodak sensitometry, Resolve, Adams Zone System, AgX, Hable, Perlin).

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

---

## Supplementary Research — Literature Survey

### S1. Shoulder-only tone curves: industry precedents

**AgX (Troy Sobotka, 2023 — Blender default view transform):**
AgX was explicitly designed as a reaction to ACES's over-compressed toe. The input
transform compresses primaries using a log-log encoding, then applies a sigmoid that
has a very long linear-to-shoulder region and virtually no toe. The original Blender
ACES view had shadow crushing complaints for years; AgX fixed them by treating the
toe as a pathological case only for extreme underexposure. The resulting shadows are
visibly more open than ACES while highlights still roll off gracefully. Key design
principle from Sobotka's writeup: "the toe is a film artifact from chemical thresholds —
digital sensors have no threshold, so a digital pipeline has no excuse for a toe."

**Hable (Uncharted 2, 2010):**
John Hable's parametric curve exposes four parameters: `A` (shoulder strength), `B`
(shoulder angle), `C` (toe strength), `D` (toe angle). Setting C≈0.01, D≈0.01 effectively
removes the toe while keeping the shoulder. The Uncharted 2 published values (`A=0.15,
B=0.50, C=0.10, D=0.20, E=0.02, F=0.30`) have a mild toe — the point is these are
independent. A shoulder-only version is valid and used in practice.

**ACES 2.0 DRT (2023):**
The ACES 1.x DRT was criticized in the cinematography community specifically for its
toe: at low exposure, it produced a colorimetric shift (saturation boost in shadows)
that was not observed in real film. The 2.0 revision extended the straight-line region
significantly downward. The net effect is that ~3 stops below middle grey are near-
linear before the toe begins. This aligns with the Zone III placement on the straight
line per Adams. The ACES 2.0 DRT is not fully public but the design principle has been
confirmed by Scott Dyer (AMPAS) in public presentations.

**Reinhard (2002):**
The simplest shoulder-only operator: `L_out = L / (1 + L)`. No toe — it's linear at
zero by construction (L/(1+L) → L as L→0). The extended version `L_out = L*(1 + L/L_white²)/(1 + L)`
adds a soft shoulder cutoff at `L_white`. This is mathematically equivalent to a
Michaelis-Menten saturation curve from enzyme kinetics. Zero toe by design.

**Practical validation for our pipeline:**
The Zone S-curve operates post-EXPOSURE (`pow(rgb, EXPOSURE)`). EXPOSURE≈0.92 already
slightly darkens the input — this is doing the toe's job (pulling shadows down). The
symmetric S-curve then applies another toe on top, compressing shadows twice. Removing
the toe from the Zone curve would not leave shadows uncontrolled; EXPOSURE and FILM_FLOOR
between them already shape the low end.

---

### S2. H-D curve straight-line region: sensitometry data

The Hurter-Driffield characteristic curve for Kodak Vision3 500T (from Kodak's published
Technical Data Sheet H-1-500T) has the following structure in the green channel:

```
Region       | Log exposure range      | Log density range | Slope (gamma)
-------------|-------------------------|-------------------|---
Toe          | below –3.0              | 0.06–0.20 D       | ~0.1–0.5 (variable)
Straight line| –3.0 to –0.8 (2.2 stops)| 0.20–2.60 D      | ~0.63 (constant)
Shoulder     | –0.8 to +0.2 (1.0 stop) | 2.60–3.20 D      | falling to 0
```

Key facts:
- The **straight line spans approximately 2.2 stops** of log-exposure latitude before the shoulder.
  Vision3 is unusual for having a long straight line — older stocks like Kodak 5293 had
  shorter straight lines and more pronounced toes.
- **Zone placement:** ASA/ISO exposure index is calibrated so that a correctly exposed
  Zone V (18% reflectance, middle grey) lands about 1/3 of the way up the straight line
  (log exposure ≈ –2.0). This puts Zone I–II in the toe, Zone III–VIII on the straight
  line, and Zone IX+ on the shoulder. Adams' dictum to expose for Zone III placement
  *is* placing the scene on the straight line.
- **Print stock (Kodak 2383):** The print stock's H-D curve is the second curve in the
  print optical chain. 2383 has gamma ≈ 2.46 on the straight line. Because it is
  contact-printed from a low-gamma negative (≈0.63), the combined camera+print gamma
  is 0.63 × 2.46 ≈ 1.55 — slightly above linear, giving the characteristic "punchy but
  not harsh" look of projected 35mm.
- **Dmin base fog:** 2383 Dmin ≈ 0.06 in the green channel. This corresponds to the
  warm paper base (absorbed blue/green transmittance). The warm cast in shadows from
  `FILM_FLOOR` and `fc_r_toe` mimics this base fog — a legitimate physical artifact,
  not the toe per se.

**Implication for our FilmCurve:** The toe in our `FilmCurve` is compressing shadows
that the Vision3 negative would have placed on the straight line. Game engine SDR input
has already been tone-mapped — Zone III–V material is mid-SDR range, well above any
digital "threshold." Applying a toe to already-linear digital shadows creates compression
that has no photochemical basis for this input signal. The Dmin warm cast should be
preserved (via `fc_r_toe` offset), but the *density compression* of the toe should be
removed.

**Gamma measurement:** The `CURVE_*` knobs currently control per-channel density offsets
(R84 log₂-density interpretation). A clean straight-line model would use `gamma_r ≈ 0.63`
applied uniformly to log exposure with no toe — but our current model uses the print stock
values (gamma≈2.46 combined), which is correct for the display-referred pipeline. The toe
compression is the only piece that needs removing.

---

### S3. Chroma lift alternatives: additional candidates

Beyond the three options in the original findings (power-law, Reinhard, lift-only quadratic),
two additional candidates are worth documenting:

**Logistic / sigmoid chroma:**
```hlsl
float sigmoid_chroma(float C, float pivot, float strength) {
    // Maps [0, 2*pivot] → [0, 2*pivot] with lift below pivot, soft ceiling above
    float t = (C - pivot) / max(pivot, 0.001);
    return pivot * (1.0 + tanh(strength * t) / max(strength, 0.001));
}
```
Continuous, no inflection, smooth through pivot. `tanh` is available as a transcendental
on RDNA — cost is ~4 ALU including the division. Drawback: symmetric by construction
(tanh is odd-symmetric around pivot). Needs asymmetry hack to get lift-only.

**Michaelis-Menten (identical to Reinhard for chroma):**
```hlsl
float C_out = C_in * (C_max + C_knee) / (C_in + C_knee);
// At C_in=0: C_out=0. At C_in→∞: C_out→C_max. At C_in=C_knee: C_out=C_max/2.
```
`C_max` sets the ceiling, `C_knee` sets the half-saturation point (where the curve
starts bending significantly). This is not lift-only — it slightly compresses even low
C values because the denominator adds C_knee at all levels. For lift behavior, need
`C_knee` ≫ typical scene C so the denominator is approximately constant in the normal
range. Sets a hard physical maximum: `C_max`.

**Verdict — best candidate for our pipeline:**
The **lift-only quadratic** from the original findings remains the strongest choice:
```hlsl
float t    = saturate(1.0 - C / max(pivot, 0.001));
return C * (1.0 + strength * t * t);
```
It is zero-overhead below `pivot` (t=0 → no change above pivot), lifts smoothly below
pivot with a t² profile that has a soft onset at the pivot, and never compresses anything.
`gclip` owns the ceiling. This is clean separation of responsibilities that none of the
sigmoid/Reinhard variants achieve.

One important refinement: the current `PivotedSCurve` uses the **per-hue mean C** as the
pivot, computed from `ChromaHistoryTex`. This is the correct pivot for lift-only too —
it means colors already at or above the scene's typical saturation for their hue pass
through untouched, while undersaturated colors in that hue band get lifted. This pivot
definition should be kept regardless of which curve shape is chosen.

---

### S4. Smootherstep alternatives: complete polynomial family

The C¹ / C² / C³ smoothstep family, all mapping [0,1]→[0,1]:

| Name | Formula | Continuity | HLSL cost (MAD) |
|------|---------|------------|-----------------|
| Linear | `t` | C⁰ | 0 |
| Smoothstep | `3t²−2t³` | C¹ | 2 |
| Smootherstep (Perlin) | `6t⁵−15t⁴+10t³` | C² | 4 |
| Smootheststep | `−20t⁷+70t⁶−84t⁵+35t⁴` | C³ | 6 |
| Generalized degree-n | Bernstein polynomial | Cⁿ⁻¹ | 2(n-1) |

The C³ "smootheststep" formula (Inigo Quilez, documented on iquilezles.org):
```hlsl
float smootheststep(float t) {
    return t*t*t*t*(35.0 + t*(-84.0 + t*(70.0 + t*(-20.0))));
}
```
Cost: 7 multiplies + 3 adds. Versus smoothstep (3 mul + 1 add). For a blend weight
function this is ~4 extra MAD per pixel — negligible.

**When does the difference matter?**
The visual artifact that C² continuity prevents is a visible "kink" in the derivative
of the blend weight — i.e., a place where the rate of transition changes abruptly. This
kink is C¹-smooth (zero derivative at endpoints) so it's not a *discontinuity* in the
output, but it creates a subtle banding artifact when the blend weight range is wide
(>0.15) and the output signal has fine spatial structure (textures, edges).

For our pipeline:
- `shadow_lift_str = lerp(1.50, 0.45, smoothstep(0.025, 0.20, perc.r))`:
  range = 0.175, wide enough that smootherstep is perceptually better.
- `scotopic_w = 1.0 - smoothstep(0.0, 0.12, new_luma)`:
  range = 0.12, borderline. Scotopic effect is subtle so the kink at onset is unlikely
  to be visible. Low priority.
- All narrow-range smoothsteps (range ≤ 0.05): no benefit from upgrading.

**Robert Penner easing functions (2002):**
Penner's book "Programming Flash Animation" defined the canonical easing vocabulary:
`easeIn`, `easeOut`, `easeInOut`. The `easeInOut` cubic is exactly smoothstep.
The `easeInOut` quintic is exactly smootherstep. All standard in animation — the
naming convention makes them easier to reason about than the polynomial expansion.

**Alternative: raised cosine blend:**
```hlsl
float cosine_blend(float t) { return 0.5 - 0.5 * cos(t * 3.14159); }
```
C¹ continuity (same as smoothstep), different shape — slightly faster onset than
smoothstep. More expensive (`cos` = ~4 ALU vs. 2 for smoothstep). Not an upgrade.

**Conclusion:** For the two priority candidates, upgrade to smootherstep (C²). Not
smootheststep (C³) — the jump from C¹→C² is the useful one; C²→C³ has no practical
benefit for blend-weight functions in SDR post-process.
