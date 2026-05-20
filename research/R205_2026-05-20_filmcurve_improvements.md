# R205 — Film Curve Improvement Audit

**Date:** 2026-05-20
**Question:** Can FilmCurveApply be improved? What does literature say about its three components?

---

## Current anatomy

```hlsl
float3 FilmCurveApply(float3 x, knee_r, knee_g, knee_b, ktoe_r, ktoe_g, ktoe_b)
{
    float3 above   = max(x - knee, 0.0);
    float3 below   = max(ktoe - x, 0.0);
    float3 headroom = max(1.0 - knee, 0.001);
    float3 xs      = saturate(x);
    float3 xw      = xs * (1.0 - xs);
    float3 body_s  = max(0.0, xw * xw * (2.0 * xs - 1.0)) * 0.65;  // one-sided upper-mid lift
    float3 sh_comp = above * above / (headroom + above);             // rational shoulder
    float3 tc_comp = (0.06 / ktoe) * below * below / (ktoe + below); // rational toe
    return x + body_s - sh_comp + tc_comp;
}
```

Applied in `ApplyCorrective` with `fc_w = lerp(1.0, 0.5, sh_w)` half-strength blend at shoulder.
fc_knee: scene-adaptive from p75/bowley (range 0.80–0.90).
fc_knee_toe: scene-adaptive from p25/mode (range 0.15–0.25).

---

## Finding 1 — tc_comp: remove (R204 conclusion, not yet implemented)

**Status: clear verdict, awaiting implementation.**

R204 already established this. Summary for completeness:
- tc_comp models a print stock toe in display-referred linear space. The ACES OT has already handled
  the scene-to-display mapping including shadow compression. Applying a second toe on the output
  compresses shadows that have no photochemical basis for further compression.
- `ApplyPrintStock` (post-chroma, `pow(ps, 1.15)`) already owns shadow density treatment.
- `BLACKS` knob owns shadow lift.
- Removing tc_comp makes the curve: `x + body_s − sh_comp`. Clean, two-component.

**Expected change:** Shadows open slightly when CORRECTIVE_STRENGTH > 0 and knobs are neutral.
Intentional shadow treatment remains fully available via PRINT_STOCK and BLACKS.

---

## Finding 2 — body_s: physically real, peak position not anchored to fc_knee

### Physical basis (confirmed)

Sensitometric literature confirms: "The straight-line portion [of the H-D curve] is not truly
straight, but slightly continues the trend of the toe." The upper straight-line region of real
film has slight super-linearity before the shoulder begins. body_s models this correctly.

Hable's piecewise power curve framework (filmicworlds.com, 2017) makes this explicit: the tone
curve has three distinct regions — toe, **linear section**, shoulder — and the linear section
carries its own slope parameter above 1.0. This is the "midtone body" or "presence" that
distinguishes filmic curves from simple Reinhard. Our body_s is an implicit version of that
linear-section slope boost, applied only to the upper half of the linear section.

The 1.2% peak lift (+0.012 at x≈0.724) is modest, but it is in a perceptually sensitive zone
(upper midtones, L≈0.72 ≈ where skin tones and lit surfaces live). A small positive slope bias
here creates forward presence without altering blacks or whites.

### The peak anchoring problem

body_s peaks at x≈0.724 — a fixed absolute value. fc_knee is scene-adaptive (0.80–0.90).

- **Dark scene** (fc_knee = 0.90): peak at 0.724, gap to knee = 0.176. body_s has decayed to
  ~0.2% by the time the shoulder begins. Fine.
- **Bright scene** (fc_knee = 0.80): peak at 0.724, gap to knee = 0.076. body_s is still +0.7%
  at the knee boundary — it's interacting with sh_comp in the transition zone. body_s and
  sh_comp are both non-zero in [0.724, 0.80]. They partially cancel (body_s lifts, sh_comp
  compresses). The net effect is unpredictable and not by design.

**The principled fix:** body_s should be parameterized relative to fc_knee (the upper boundary
of the linear section), not as an absolute x=0.724. In Hable's framework, the linear section
runs from x0 (toe end) to x1 = fc_knee. The upper-body lift should peak at some fraction of the
way through [0.5, fc_knee], not at a fixed absolute value.

### Proposed reparameterization

Instead of the current fixed polynomial, normalize x into [0, 1] over the linear section:

```hlsl
float t = saturate((xs - 0.5) / max(fc_knee_g - 0.5, 0.001));  // 0 at x=0.5, 1 at x=fc_knee
float body_s_scalar = t * t * (1.0 - t) * (1.0 - t) * (2.0*t - 1.0);  // same shape, now relative
body_s_scalar = max(0.0, body_s_scalar) * 0.65;
```

Wait — this would need to be applied per-channel since fc_knee varies per channel. The current
formula uses `xs = saturate(x)` (per-channel float3 already). The reparameterization is:

```hlsl
float3 knee_rgb = float3(knee_r, knee_g, knee_b);
float3 t_norm   = saturate((xs - 0.5) / max(knee_rgb - 0.5, 0.001));
float3 body_s   = max(0.0, t_norm * t_norm * (1.0 - t_norm) * (1.0 - t_norm)
                         * (2.0 * t_norm - 1.0)) * 0.65;
```

Peak of the normalized formula: same polynomial shape, peak at t≈0.724 in [0,1] space, which
maps to x = 0.5 + 0.724 × (fc_knee − 0.5).

At fc_knee = 0.85: peak at x ≈ 0.5 + 0.724 × 0.35 ≈ 0.753 (vs. fixed 0.724 — slight shift up)
At fc_knee = 0.80: peak at x ≈ 0.5 + 0.724 × 0.30 ≈ 0.717 (shifts down with the knee)
At fc_knee = 0.90: peak at x ≈ 0.5 + 0.724 × 0.40 ≈ 0.790 (shifts up with the knee)

**Key property:** body_s always reaches zero exactly at fc_knee (by construction — t=1 → factor
contains (1−t)² = 0). No overlap with sh_comp. The interaction bug at bright scenes disappears.

### Risk

body_s peak shifts slightly from current positions. Interaction with existing knob values: minor.
The 0.65 amplitude stays the same. This is a structural correctness fix, not a magnitude change.
One-frame delay via fc_knee reconstructed from highway: same R198 precedent.

---

## Finding 3 — sh_comp + fc_w: the half-strength blend is redundant

`fc_w = lerp(1.0, 0.5, sh_w)` was added to prevent over-compression at the shoulder transition.
But sh_comp is already C1 at fc_knee — the derivative is continuous. There is no discontinuity
to smooth. The fc_w blend simply halves the shoulder's effectiveness in the knee zone, which is
an empirical correction layered on top of a principled formula.

With the FILM_CURVE knob now gating the whole function (`lerp(lin_e, fc_out, fc_w * FILM_CURVE)`),
fc_w is a secondary blend inside a primary blend. At FILM_CURVE = 1.0: fc_w halves sh_comp near
the knee, giving a softer shoulder onset. This may be the intended artistic behavior — but if so,
it should be explicit, not an unnamed scalar.

**Options:**
- Remove fc_w: shoulder fires at full rational strength. Slightly more compression at the knee.
- Keep fc_w but name it (document that it's intentional shoulder softening, not a safety clamp).
- Replace with a clean C2 transition (smootherstep into the shoulder zone instead of hard lerp).

**Verdict:** Audit whether the current shoulder behavior at fc_knee is intentional. A/B with
fc_w removed is cheap. If the shoulder felt too harsh before fc_w was added, keep it and document it.

---

## Finding 4 — FILM_CURVE knob: correct addition, one gap

FILM_CURVE = 0 → passthrough, FILM_CURVE = 1 → full curve. Clean. One issue: the blend applies
to `fc_out - lin_e`, but `fc_out` already incorporates fc_w. So the actual blend is:

```
out = lin_e + fc_w * FILM_CURVE * (fc_out - lin_e)
```

At FILM_CURVE = 1 and sh_w = 1 (deep shoulder): fc_w = 0.5 → shoulder at 50%.
At FILM_CURVE = 0.5 and sh_w = 1: fc_w = 0.5 × 0.5 = 0.25 → shoulder at 25%.
At FILM_CURVE = 1 and sh_w = 0 (midtone): fc_w = 1.0 → body_s and tc_comp at 100%.

The knob scales unevenly across tonal zones — body_s scales linearly with FILM_CURVE, shoulder
scales at FILM_CURVE × 0.5. Not wrong, but worth being aware of when calibrating.

---

## Summary table

| Component | Status | Recommendation |
|-----------|--------|----------------|
| tc_comp (toe) | Unjustified (R204) | **Remove** — PRINT_STOCK owns shadows |
| body_s (upper-mid lift) | Physically real, fixed peak | **Reparameterize** relative to fc_knee |
| sh_comp (shoulder) | Principled, C1 | Keep — audit fc_w |
| fc_w half-strength | Empirical hack or soft feature | **A/B** with and without |
| FILM_CURVE knob | Good addition | Keep |

## Recommended implementation order

1. **Remove tc_comp** — 1 line, zero risk, R204 justification is complete.
2. **Reparameterize body_s** relative to fc_knee — fixes the bright-scene interaction bug,
   keeps amplitude identical, self-contained change.
3. **Audit fc_w** — A/B comparison, decide keep-and-document vs. remove.
